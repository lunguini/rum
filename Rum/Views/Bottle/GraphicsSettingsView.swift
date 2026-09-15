//
//  GraphicsSettingsView.swift
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

struct GraphicsSettingsView: View {
    @ObservedObject var bottle: Bottle
    @Binding var isExpanded: Bool
    @State private var availability: [GraphicsBackendAvailability] = []

    var body: some View {
        Section("Graphics", isExpanded: $isExpanded) {
            Picker("Renderer", selection: $bottle.settings.graphicsBackend) {
                ForEach(selectableBackends) { option in
                    Text(option.backend.displayName)
                        .tag(option.backend)
                }
            }
            Text(bottle.settings.graphicsBackend.supportedDirectXVersions)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selected = availability.first(where: { $0.backend == bottle.settings.graphicsBackend }),
               !selected.isAvailable,
               let reason = selected.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(availability.filter {
                !$0.isAvailable && $0.backend != bottle.settings.graphicsBackend
            }) { option in
                Text("\(option.backend.displayName): \(option.reason ?? "Unavailable")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $bottle.settings.dxvkAsync) {
                Text("config.dxvk.async")
            }
            .disabled(bottle.settings.graphicsBackend != .dxvk)

            Picker("config.dxvkHud", selection: $bottle.settings.dxvkHud) {
                Text("config.dxvkHud.full").tag(DXVKHUD.full)
                Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
                Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
                Text("config.dxvkHud.off").tag(DXVKHUD.off)
            }
            .disabled(bottle.settings.graphicsBackend != .dxvk)

            Picker(selection: $bottle.settings.dxvkFrameRate) {
                Text("config.dxvkFrameRate.unlimited").tag(0)
                ForEach([30, 60, 90, 120, 144, 240], id: \.self) { fps in
                    Text("\(fps) FPS").tag(fps)
                }
            } label: {
                Text("config.dxvkFrameRate")
                Text("config.dxvkFrameRate.info")
            }
            .disabled(bottle.settings.graphicsBackend != .dxvk)
        }
        .onAppear(perform: loadAvailability)
        .onChange(of: bottle.settings.wineEngineID) { _, _ in
            loadAvailability()
        }
    }

    private var selectableBackends: [GraphicsBackendAvailability] {
        guard !availability.isEmpty else {
            return [GraphicsBackendAvailability(backend: bottle.settings.graphicsBackend, isAvailable: true)]
        }
        return availability.filter {
            $0.isAvailable || $0.backend == bottle.settings.graphicsBackend
        }
    }

    private func loadAvailability() {
        availability = WhiskyWineInstaller.graphicsBackendAvailability(
            for: bottle.settings.architecture,
            engineID: bottle.settings.wineEngineID
        )
    }
}
