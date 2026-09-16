//
//  RuntimeSettingsView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import WhiskyKit

struct RuntimeSettingsView: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool

    @State private var engines: [WineEngine] = []
    @State private var globalEngine: WineEngine?
    @State private var pickerSelection = Self.followGlobalID
    @State private var pendingSelection: String?
    @State private var showingConfirmation = false
    @State private var showingManager = false
    @State private var rendererFallbackMessage: String?

    private static let followGlobalID = "__rum_follow_global__"

    var body: some View {
        Section("Runtime", isExpanded: $isExpanded) {
            Picker("Wine engine", selection: $pickerSelection) {
                HStack {
                    Text(globalOptionTitle)
                    Spacer()
                    if pickerSelection == Self.followGlobalID {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .tag(Self.followGlobalID)

                ForEach(engines) { engine in
                    HStack {
                        Text(engine.displayName)
                        Text(engine.kind.displayName)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if pickerSelection == engine.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .tag(engine.id)
                    .disabled(!engine.isAvailable)
                }

                if let selectedID = bottle.settings.wineEngineID,
                   !engines.contains(where: { $0.id == selectedID }) {
                    Text("Missing engine: \(selectedID)")
                        .foregroundStyle(.red)
                        .tag(selectedID)
                }
            }

            if let selectedID = bottle.settings.wineEngineID {
                if let engine = engines.first(where: { $0.id == selectedID }), engine.isAvailable {
                    Text("Pinned to \(engine.displayName). Changes apply on the next launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "This bottle's selected engine is unavailable. Choose another engine or "
                            + "follow the global default.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            } else if let globalEngine {
                Text("Following the global default: \(globalEngine.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("No usable global Wine engine is installed.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if bottle.settings.graphicsBackend == .wineD3D, let rendererFallbackMessage {
                Label(rendererFallbackMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                showingManager = true
            } label: {
                Label("Manage Wine engines…", systemImage: "slider.horizontal.3")
            }
        }
        .onAppear {
            reload()
            pickerSelection = bottle.settings.wineEngineID ?? Self.followGlobalID
        }
        .onChange(of: pickerSelection) { _, newValue in
            guard newValue != (bottle.settings.wineEngineID ?? Self.followGlobalID),
                  !showingConfirmation else { return }
            pendingSelection = newValue
            showingConfirmation = true
        }
        .onChange(of: bottle.settings.wineEngineID) { _, newValue in
            guard !showingConfirmation else { return }
            pickerSelection = newValue ?? Self.followGlobalID
        }
        .onChange(of: bottle.url) { _, _ in
            showingConfirmation = false
            pendingSelection = nil
            rendererFallbackMessage = nil
            reload()
        }
        .confirmationDialog(
            "Change Wine engine?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Use \(pendingDisplayName)") {
                applyPendingSelection()
            }
            Button("Cancel", role: .cancel) {
                cancelPendingSelection()
            }
        } message: {
            Text(
                "The selected engine will be used for this bottle on its next launch. "
                    + "The bottle prefix is kept intact."
            )
        }
        .sheet(isPresented: $showingManager, onDismiss: reload) {
            WineManagerView()
        }
    }

    private var globalOptionTitle: String {
        if let globalEngine {
            return "Follow global default (\(globalEngine.displayName))"
        }
        return "Follow global default (not installed)"
    }

    private var pendingDisplayName: String {
        guard let pendingSelection else { return "global default" }
        if pendingSelection == Self.followGlobalID {
            return "global default"
        }
        return engines.first(where: { $0.id == pendingSelection })?.displayName ?? pendingSelection
    }

    private func applyPendingSelection() {
        guard let pendingSelection else { return }
        let engineID = pendingSelection == Self.followGlobalID ? nil : pendingSelection
        bottle.settings.wineEngineID = engineID
        reconcileRenderer(for: engineID)
        self.pendingSelection = nil
        pickerSelection = bottle.settings.wineEngineID ?? Self.followGlobalID
    }

    private func cancelPendingSelection() {
        pendingSelection = nil
        pickerSelection = bottle.settings.wineEngineID ?? Self.followGlobalID
    }

    private func reload() {
        engines = WhiskyWineInstaller.installedWineEngines()
        globalEngine = try? WhiskyWineInstaller.wineEngine(for: nil)
        guard !showingConfirmation else { return }
        pickerSelection = bottle.settings.wineEngineID ?? Self.followGlobalID
        reconcileRenderer(for: bottle.settings.wineEngineID)
    }

    private func reconcileRenderer(for engineID: String?) {
        let capabilities = WhiskyWineInstaller.wineGraphicsCapabilities(for: engineID)
        let resolution = GraphicsBackendSelectionResolver.resolve(
            current: bottle.settings.graphicsBackend,
            architecture: bottle.settings.architecture,
            capabilities: capabilities,
            dxvkInstalled: WhiskyWineInstaller.isDXVKInstalled(for: bottle.settings.architecture)
        )
        guard resolution.didFallback else {
            rendererFallbackMessage = nil
            return
        }
        bottle.settings.graphicsBackend = resolution.backend
        let reason = resolution.reason ?? "The selected engine is incompatible with the previous renderer."
        rendererFallbackMessage = "Renderer changed to WineD3D: \(reason)"
    }
}
