//
//  WineManagerView.swift
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

private let externalEngineLicenseNote = "External engines are used from software you installed. "
    + "Rum stores a path reference and does not copy, download, or redistribute their runtime files. "
    + "Apple's GPTK license still applies to D3DMetal."

// The manager keeps discovery, activation, and download rows together so their operation-state
// handling stays consistent.
// swiftlint:disable:next type_body_length
struct WineManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var releases: [WineRelease] = []
    @State private var sikarugirReleases: [WineRelease] = []
    @State private var installedBuilds: [InstalledWineBuild] = []
    @State private var externalEngines: [ExternalWineEngine] = []
    @State private var detectedCrossOver: ExternalWineEngine?
    @State private var detectedGamePortingToolkit: ExternalWineEngine?
    @State private var loading = true
    @State private var operationID: String?
    @State private var errorMessage: String?
    @State private var activeVersion: String?
    @State private var activeExternalEngineID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if loading {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Spacer()
            } else {
                List {
                    Section {
                        if let detectedCrossOver {
                            Button {
                                importCrossOver()
                            } label: {
                                Label("Import \(detectedCrossOver.displayName)", systemImage: "plus.circle")
                            }
                            .disabled(operationID != nil || externalEngines.contains(detectedCrossOver))
                        }
                        if let detectedGamePortingToolkit {
                            Button {
                                importGamePortingToolkit()
                            } label: {
                                Label("Import \(detectedGamePortingToolkit.displayName)", systemImage: "plus.circle")
                            }
                            .disabled(
                                operationID != nil || externalEngines.contains(detectedGamePortingToolkit)
                            )
                        }
                        Button {
                            chooseGamePortingToolkit()
                        } label: {
                            Label("Import Game Porting Toolkit…", systemImage: "folder")
                        }
                        .disabled(operationID != nil)
                        if detectedCrossOver == nil && detectedGamePortingToolkit == nil {
                            Label(
                                "No supported external Wine engine was found in /Applications",
                                systemImage: "exclamationmark.triangle"
                            )
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text(externalEngineLicenseNote)
                    }
                    if !externalEngines.isEmpty {
                        Section("External") {
                            ForEach(externalEngines) { engine in
                                externalEngineRow(engine)
                            }
                        }
                    }
                    if !installedBuilds.isEmpty {
                        Section("Managed") {
                            ForEach(installedBuilds) { build in
                                installedRow(build)
                            }
                        }
                    }
                    Section("Available Gcenx Downloads") {
                        ForEach(releases) { release in
                            releaseRow(release)
                        }
                    }
                    Section {
                        if sikarugirReleases.isEmpty {
                            Text("No Sikarugir engines are available right now.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sikarugirReleases) { release in
                                releaseRow(release)
                            }
                        }
                    } header: {
                        Text("Available Sikarugir Downloads")
                    } footer: {
                        Text(
                            "Sikarugir engines are third-party Wine builds. "
                                + "Review their licenses and compatibility before use."
                        )
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(operationID != nil)
            }
            .padding()
        }
        .frame(width: 620, height: 520)
        .task {
            await load()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wine Manager")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(activeVersion.map { "Global default: \($0)" } ?? "No global Wine default")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Wine releases")
        }
        .padding()
    }

    private func externalEngineRow(_ engine: ExternalWineEngine) -> some View {
        let isActive = activeExternalEngineID == engine.id
        return HStack {
            VStack(alignment: .leading) {
                Text(engine.displayName)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(engine.appURL.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !engine.isAvailable {
                Text("Missing")
                    .foregroundStyle(.red)
            } else if operationID == engine.id {
                ProgressView()
                    .controlSize(.small)
            } else if isActive {
                Text("Global default")
                    .foregroundStyle(.secondary)
            } else {
                Button("Activate") {
                    run(version: engine.id) {
                        try WhiskyWineInstaller.activateExternalWineEngine(engine.id)
                    }
                }
            }
        }
        .disabled(operationID != nil)
    }

    private func installedRow(_ build: InstalledWineBuild) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(build.displayName)
                    .fontWeight(build.isActive ? .semibold : .regular)
                Text(build.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(build.wineURL.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if build.isActive {
                Text("Global default")
                    .foregroundStyle(.secondary)
            } else {
                Button("Activate") {
                    run(version: build.id) {
                        try WhiskyWineInstaller.activateWineEngine(build.id)
                    }
                }
                Button("Remove") {
                    run(version: build.id) {
                        try WhiskyWineInstaller.removeWineEngine(build.id)
                    }
                }
            }
        }
        .disabled(operationID != nil)
    }

    private func releaseRow(_ release: WineRelease) -> some View {
        let installed = installedBuilds.first {
            $0.kind == release.kind && $0.version == release.version
        }
        return HStack {
            VStack(alignment: .leading) {
                Text(release.displayName)
                    .fontWeight(installed?.isActive == true ? .semibold : .regular)
                Text("\(release.assetName) - \(formatBytes(release.size))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if operationID == release.id {
                ProgressView()
                    .controlSize(.small)
            } else if installed?.isActive == true {
                Text("Global default")
                    .foregroundStyle(.secondary)
            } else if installed != nil {
                Button("Activate") {
                    run(version: installed?.id ?? release.id) {
                        try WhiskyWineInstaller.activateWineEngine(installed?.id ?? release.id)
                    }
                }
            } else {
                Button("Install") {
                    install(release)
                }
            }
        }
        .disabled(operationID != nil)
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            try WhiskyWineInstaller.migrateLegacyWineIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
        installedBuilds = WhiskyWineInstaller.installedWineBuilds()
        externalEngines = WhiskyWineInstaller.externalWineEngines()
        detectedCrossOver = WhiskyWineInstaller.defaultCrossOverEngine()
        detectedGamePortingToolkit = WhiskyWineInstaller.defaultGamePortingToolkitEngine()
        activeExternalEngineID = WhiskyWineInstaller.activeExternalWineEngine()?.id
        activeVersion = WhiskyWineInstaller.activeWineVersion() ?? WhiskyWineInstaller.installedWineVersion()
        async let gcenxReleases = WhiskyWineInstaller.fetchAvailableWineReleases()
        async let sikarugirReleases = WhiskyWineInstaller.fetchAvailableSikarugirReleases()
        releases = await gcenxReleases
        self.sikarugirReleases = await sikarugirReleases
        loading = false
    }

    private func importCrossOver() {
        guard let detectedCrossOver else { return }
        operationID = detectedCrossOver.id
        errorMessage = nil
        Task {
            do {
                try WhiskyWineInstaller.importCrossOverEngine(at: detectedCrossOver.appURL)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
            operationID = nil
        }
    }

    private func chooseGamePortingToolkit() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK, let appURL = panel.urls.first else { return }
            importGamePortingToolkit(at: appURL)
        }
    }

    private func importGamePortingToolkit() {
        guard let detectedGamePortingToolkit else { return }
        importGamePortingToolkit(at: detectedGamePortingToolkit.appURL)
    }

    private func importGamePortingToolkit(at appURL: URL) {
        operationID = "gptk:\(appURL.path)"
        errorMessage = nil
        Task {
            do {
                try WhiskyWineInstaller.importGamePortingToolkitEngine(at: appURL)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
            operationID = nil
        }
    }

    private func install(_ release: WineRelease) {
        operationID = release.id
        errorMessage = nil
        Task {
            do {
                let (tarball, _) = try await URLSession.shared.download(from: release.downloadURL)
                // Install without activating — the row's "Activate" button routes through
                // run(version:), which kills bottles before swapping the active symlink.
                try await WhiskyWineInstaller.install(
                    from: tarball,
                    version: release.version,
                    kind: release.kind,
                    activate: false
                )
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
            operationID = nil
        }
    }

    private func run(version: String, action: @escaping () throws -> Void) {
        operationID = version
        errorMessage = nil
        Task {
            do {
                await WhiskyApp.killBottlesAndWait()
                try action()
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
            operationID = nil
        }
    }
}

private func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}

#Preview {
    WineManagerView()
}
