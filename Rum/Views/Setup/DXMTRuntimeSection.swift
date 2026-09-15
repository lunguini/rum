//
//  DXMTRuntimeSection.swift
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

struct DXMTRuntimeSection: View {
    @State private var release: DXMTRelease?
    @State private var installedVersion: String?
    @State private var loading = true
    @State private var installing = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            HStack {
                Label("DXMT", systemImage: "sparkles")
                Spacer()
                if let installedVersion {
                    Text("Installed \(installedVersion)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not installed")
                        .foregroundStyle(.secondary)
                }
            }

            if loading {
                ProgressView("Checking for the latest DXMT runtime…")
                    .controlSize(.small)
            } else if let release {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Latest \(release.version)")
                        Text("\(release.assetName) - \(formatBytes(release.size))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if installing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(installedVersion == nil ? "Install" : "Update") {
                            install(release)
                        }
                    }
                }
            } else {
                Text("The latest DXMT runtime could not be fetched.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Graphics runtimes")
        } footer: {
            Text(
                "DXMT is a separate renderer payload. It works only with Wine engines "
                    + "that expose the required macOS driver API."
            )
        }
        .task {
            await load()
        }
        .alert("Could not install DXMT", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func load() async {
        installedVersion = WhiskyWineInstaller.installedDXMTVersion()
        release = await WhiskyWineInstaller.fetchLatestDXMTRelease()
        loading = false
    }

    private func install(_ release: DXMTRelease) {
        installing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let (tarball, _) = try await URLSession.shared.download(from: release.downloadURL)
                await WhiskyApp.killBottlesAndWait()
                try await WhiskyWineInstaller.installDXMT(from: tarball, version: release.version)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
            installing = false
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

let externalEngineLicenseNote = "External engines are used from software you installed. "
    + "Rum stores a path reference and does not copy, download, or redistribute their runtime files. "
    + "Apple's GPTK license still applies to D3DMetal."

func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}
