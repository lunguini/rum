//
//  DXMTRuntimeSection.swift
//  Rum
//
//  This file is part of Rum.
//
//  Rum is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Rum is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Rum.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import RumKit

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
            InfoHeader(
                "Graphics runtimes",
                note: "DXMT is a separate renderer payload. It works only with Wine engines "
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
        installedVersion = RumWineInstaller.installedDXMTVersion()
        release = await RumWineInstaller.fetchLatestDXMTRelease()
        loading = false
    }

    private func install(_ release: DXMTRelease) {
        installing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let (tarball, _) = try await URLSession.shared.download(from: release.downloadURL)
                await RumApp.killBottlesAndWait()
                try await RumWineInstaller.installDXMT(from: tarball, version: release.version)
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

/// An ⓘ that shows a row's full details (paths, file names) on hover, and in a popover on click,
/// where they can be read in full and selected.
struct InfoButton: View {
    let details: [String]
    /// Paths and file names read best in a fixed-width font; prose doesn't.
    var monospaced = true
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(details.joined(separator: "\n"))
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(monospaced ? .callout.monospaced() : .callout)
                        // Section headers limit their text to one line, and the popover inherits it.
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
            .padding(12)
            .frame(width: 360, alignment: .leading)
        }
    }
}

/// A section title with an ⓘ beside it holding the section's explanation, instead of a footer
/// that the list squeezes onto one cut-off line.
struct InfoHeader: View {
    let title: LocalizedStringKey
    let note: String

    init(_ title: LocalizedStringKey, note: String) {
        self.title = title
        self.note = note
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            InfoButton(details: [note], monospaced: false)
                .font(.caption)
        }
        .help(note)
    }
}
