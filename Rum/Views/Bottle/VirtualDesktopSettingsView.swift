//
//  VirtualDesktopSettingsView.swift
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

/// Toggle + resolution selector for Wine's emulated virtual desktop. State lives in the Wine registry
/// (read on appear, written on change), mirroring the Retina/DPI controls in `ConfigView`.
struct VirtualDesktopSettingsView: View {
    @ObservedObject var bottle: Bottle
    @State private var enabled: Bool = false
    @State private var resolutionSelection: String = "1280x720"
    @State private var customWidth: Int = 1280
    @State private var customHeight: Int = 720
    @State private var loadingState: LoadingState = .loading
    // The values last written to (or read from) the registry. `load()` seeds these alongside
    // `enabled`/`resolutionSelection` so the onChange handlers can tell a genuine user edit from a
    // programmatic assignment during load and skip redundant `reg add` processes.
    @State private var appliedEnabled: Bool = false
    @State private var appliedResolution: String = "1280x720"

    private static let presets = ["640x480", "800x600", "1024x768", "1280x720", "1920x1080"]

    var body: some View {
        // Whether the Wine build actually honors virtual desktop is not detected here; the toggle simply
        // writes the keys. A future runtime probe could verify support — see the design spec.
        Group {
            SettingItemView(title: "config.virtualDesktop", loadingState: loadingState) {
                Toggle("config.virtualDesktop", isOn: $enabled)
                    .onChange(of: enabled) { _, newValue in
                        guard newValue != appliedEnabled else { return }
                        appliedEnabled = newValue
                        apply()
                    }
            }
            if enabled {
                Picker("config.virtualDesktop.resolution", selection: $resolutionSelection) {
                    ForEach(Self.presets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                    Text("config.virtualDesktop.custom").tag("custom")
                }
                .onChange(of: resolutionSelection) { _, newValue in
                    guard newValue != appliedResolution else { return }
                    appliedResolution = newValue
                    apply()
                }
                if resolutionSelection == "custom" {
                    HStack {
                        TextField("config.virtualDesktop.width", value: $customWidth, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(PlainTextFieldStyle())
                            .onSubmit { apply() }
                        Text(verbatim: "×")
                        TextField("config.virtualDesktop.height", value: $customHeight, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(PlainTextFieldStyle())
                            .onSubmit { apply() }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func effectiveResolution() -> String {
        if resolutionSelection == "custom" {
            return "\(max(640, customWidth))x\(max(480, customHeight))"
        }
        return resolutionSelection
    }

    private func load() {
        Task(priority: .userInitiated) {
            do {
                let desktop = try await Wine.virtualDesktop(bottle: bottle)
                enabled = desktop.enabled
                if let resolution = desktop.resolution {
                    if Self.presets.contains(resolution) {
                        resolutionSelection = resolution
                    } else {
                        resolutionSelection = "custom"
                        let parts = resolution.split(separator: "x")
                        if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
                            customWidth = width
                            customHeight = height
                        }
                    }
                }
                // Record the loaded values so the onChange handlers treat these assignments as
                // no-ops and don't re-write the registry.
                appliedEnabled = enabled
                appliedResolution = resolutionSelection
                loadingState = .success
            } catch {
                print(error)
                // If a virtual desktop has not been configured, there will be no registry entry
                loadingState = .success
            }
        }
    }

    private func apply() {
        guard loadingState == .success else { return }
        let resolution = effectiveResolution()
        Task(priority: .userInitiated) {
            loadingState = .modifying
            do {
                try await Wine.changeVirtualDesktop(bottle: bottle, enabled: enabled, resolution: resolution)
                loadingState = .success
            } catch {
                print(error)
                loadingState = .failed
            }
        }
    }
}
