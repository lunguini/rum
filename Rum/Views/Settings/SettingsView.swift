//
//  SettingsView.swift
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

struct SettingsView: View {
    @AppStorage("SUEnableAutomaticChecks") var whiskyUpdate = true
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("checkWhiskyWineUpdates") var checkWhiskyWineUpdates = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir
    @AppStorage(BottleVM.defaultBottleKey) private var defaultBottleURL: URL?
    @EnvironmentObject var bottleVM: BottleVM
    @State private var showWineManager = false
    @State private var showBottleCreation = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var activeWineVersion = WhiskyWineInstaller.installedWineVersion()
    /// The bottle whose own settings are shown in place of these; nil shows Settings.
    @Binding var managedBottleURL: URL?

    var body: some View {
        if let bottle = bottleVM.bottles.first(where: { $0.url == managedBottleURL && $0.isAvailable }) {
            BottleView(bottle: bottle, backTitle: "Settings") { managedBottleURL = nil }
                .disabled(bottle.inFlight)
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section("settings.general") {
                Toggle("settings.toggle.kill.on.terminate", isOn: $killOnTerminate)
                ActionView(
                    text: "settings.path",
                    subtitle: defaultBottleLocation.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.containerDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            defaultBottleLocation = url
                        }
                    }
                }
            }
            bottlesSection
            Section("settings.updates") {
                Toggle("settings.toggle.whisky.updates", isOn: $whiskyUpdate)
                Toggle("settings.toggle.whiskywine.updates", isOn: $checkWhiskyWineUpdates)
            }
            Section("Wine") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Wine Manager")
                        Text(activeWineVersion.map { "Global default: \($0)" } ?? "No global Wine default")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage") {
                        showWineManager = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // A page of the main window: a comfortable reading width, centred.
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .onAppear {
            refreshActiveWineVersion()
        }
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
        }
        .sheet(isPresented: $showWineManager) {
            WineManagerView()
                .onDisappear {
                    refreshActiveWineVersion()
                }
        }
    }

    /// Bottles are an advanced concept: listed here rather than in the main window.
    private var bottlesSection: some View {
        Section {
            ForEach(bottleVM.bottles.sorted()) { bottle in
                bottleRow(bottle)
            }
            Button("New Bottle…") {
                showBottleCreation = true
            }
        } header: {
            Text("Bottles")
        } footer: {
            Text("A bottle is a self-contained Windows environment. One bottle is enough for most games "
                 + "and apps; create another for 32-bit-only programs or to keep something isolated. "
                 + "Right-click a bottle to rename, move, export or remove it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func bottleRow(_ bottle: Bottle) -> some View {
        let isDefault = bottleVM.defaultBottle(preferredURL: defaultBottleURL) == bottle
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    BottleListEntry(bottle: bottle, selected: .constant(nil), refresh: .constant(false))
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.2), in: Capsule())
                    }
                }
                Text(bottleDetails(bottle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if bottle.inFlight {
                ProgressView().controlSize(.small)
            } else {
                if !isDefault {
                    Button("Make Default") {
                        defaultBottleURL = bottle.url
                    }
                    .disabled(!bottle.isAvailable)
                }
                Button("Manage…") {
                    managedBottleURL = bottle.url
                }
                .disabled(!bottle.isAvailable)
            }
        }
    }

    private func bottleDetails(_ bottle: Bottle) -> String {
        guard bottle.isAvailable else { return "Unavailable" }
        let engine = bottle.settings.wineEngineID
            .flatMap { WhiskyWineInstaller.wineEngine(withID: $0)?.displayName } ?? "Default engine"
        return "\(bottle.settings.architecture.pretty()) · \(engine)"
    }

    private func refreshActiveWineVersion() {
        activeWineVersion = WhiskyWineInstaller.installedWineVersion()
    }
}

#Preview {
    SettingsView(managedBottleURL: .constant(nil))
        .environmentObject(BottleVM.shared)
}
