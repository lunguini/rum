//
//  LibraryInspector.swift
//  Rum
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

enum LibraryInspectorTab: String, CaseIterable {
    case overview = "Overview"
    case settings = "Settings"
}

/// Details panel for the selected Library program: Play / Stop, where it runs, and its settings.
struct LibraryInspector: View {
    @ObservedObject var bottle: Bottle
    let item: LibraryPinItem
    let actions: LibraryItemActions
    @Binding var tab: LibraryInspectorTab

    /// The selected program's own settings. The panel is rebuilt for each selection.
    @StateObject private var program: Program
    @State private var engineName = "Default"

    init(bottle: Bottle, item: LibraryPinItem, actions: LibraryItemActions, tab: Binding<LibraryInspectorTab>) {
        self.bottle = bottle
        self.item = item
        self.actions = actions
        _tab = tab
        _program = StateObject(wrappedValue: Program(url: item.url, bottle: item.bottle))
    }

    var body: some View {
        let status = LibraryItemStatus(bottle: bottle, url: item.url)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Color.clear
                    .aspectRatio(460 / 215, contentMode: .fit)
                    .overlay { ArtworkView(url: item.url, name: item.pin.name, style: .banner) }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.pin.name)
                        .font(.title2.bold())
                        .lineLimit(2)
                    LibraryStatusLabel(status: status)
                        .font(.callout)
                }

                playControls(status: status)

                Picker("", selection: $tab) {
                    ForEach(LibraryInspectorTab.allCases, id: \.self) { tab in
                        Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.top, 4)

                switch tab {
                case .overview:
                    overview(status: status)
                case .settings:
                    LibraryProgramSettings(program: program) { actions.showAllSettings(item) }
                }
            }
            .padding(16)
        }
        .background(alignment: .top) {
            // A soft glow of the artwork's colours behind the top of the panel.
            ArtworkView(url: item.url, name: item.pin.name, style: .banner)
                .frame(height: 320)
                .blur(radius: 60)
                .opacity(0.45)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
        .clipped()
        .task(id: bottle.settings.wineEngineID) {
            // Finding the engine reads the engines folder; keep it off the main thread.
            let engineID = bottle.settings.wineEngineID
            engineName = await Task.detached(priority: .userInitiated) {
                engineID.flatMap { WhiskyWineInstaller.wineEngine(withID: $0)?.displayName } ?? "Default"
            }.value
        }
    }

    @ViewBuilder
    private func playControls(status: LibraryItemStatus) -> some View {
        HStack(spacing: 8) {
            Group {
                if status.isRunning {
                    Button { actions.stop(item) } label: {
                        Label(status.instances > 1 ? "Stop All" : "Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(RumProminentButtonStyle(role: .stop, fullWidth: true))
                } else {
                    Button { actions.run(item) } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(RumProminentButtonStyle(fullWidth: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .disabled(status == .missing)

            Menu {
                LibraryItemMenu(item: item, status: status, actions: actions)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
    }

    private func overview(status: LibraryItemStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row("shippingbox", "Bottle", bottle.settings.name)
            Divider()
            row("cpu", "Engine", engineName)
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text("Graphics")
                Spacer(minLength: 12)
                LibraryRendererPicker(program: program, bottle: bottle)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
            }
            .padding(.vertical, 5)
            Divider()
            row("macwindow", "Windows", "\(bottle.settings.windowsVersion.pretty()) · "
                + bottle.settings.architecture.pretty())
            Divider()
            row("clock", "Last played", lastPlayed(status: status))
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text("Location")
                Spacer(minLength: 12)
                Button(item.url.deletingLastPathComponent().lastPathComponent) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                .buttonStyle(.link)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.url.path(percentEncoded: false))
            }
            .padding(.vertical, 8)
        }
        .font(.callout)
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 8)
    }

    private func lastPlayed(status: LibraryItemStatus) -> String {
        guard let entry = bottle.settings.runHistory.first(where: { $0.url == item.url }) else {
            return "Never"
        }
        return entry.lastRun.formatted(.relative(presentation: .named))
    }
}

/// The settings people change most, inline; everything else is one click away.
private struct LibraryProgramSettings: View {
    @ObservedObject var program: Program
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("program.args")
                TextField("program.args", text: $program.settings.arguments)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
            }
            Picker("locale.title", selection: $program.settings.locale) {
                ForEach(Locales.allCases, id: \.self) { locale in
                    Text(locale.pretty()).tag(locale)
                }
            }
            LibraryRendererPicker(program: program, bottle: program.bottle)
            Text("The engine and Windows version are shared by everything in the "
                 + "“\(program.bottle.settings.name)” bottle.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Environment Variables & More…", action: onShowAll)
                .buttonStyle(.link)
        }
        .font(.callout)
    }
}

/// The renderer a program launches with, or its bottle's. A different one is loaded for that
/// program alone, so programs on different renderers can share a bottle and run together.
struct LibraryRendererPicker: View {
    @ObservedObject var program: Program
    @ObservedObject var bottle: Bottle
    var title: LocalizedStringKey = "Renderer"

    @State private var available: [GraphicsBackend] = []

    var body: some View {
        Picker(title, selection: $program.settings.graphicsBackend) {
            Text("Bottle Default (\(bottle.settings.graphicsBackend.displayName))")
                .tag(GraphicsBackend?.none)
            Divider()
            ForEach(choices, id: \.self) { backend in
                Text(backend.displayName)
                    .tag(GraphicsBackend?.some(backend))
            }
        }
        .help("Takes effect the next time it starts. When it differs from the bottle's, the renderer "
              + "is loaded just for this program, copying its files next to the program if needed.")
        .task(id: "\(bottle.settings.wineEngineID ?? "")|\(bottle.settings.architecture.rawValue)|"
              + bottle.settings.graphicsBackend.rawValue) {
            // Checking the engine's renderers reads the engines folder; keep it off the main thread.
            let architecture = bottle.settings.architecture
            let engineID = bottle.settings.wineEngineID
            let bottleBackend = bottle.settings.graphicsBackend
            available = await Task.detached(priority: .userInitiated) {
                WhiskyWineInstaller.graphicsBackendAvailability(for: architecture, engineID: engineID)
                    .filter(\.isAvailable)
                    .map(\.backend)
                    .filter { $0 == bottleBackend || ProgramRenderer.supportsProgramOverride($0, engineID: engineID) }
            }.value
        }
    }

    /// The renderers this bottle's engine supports, plus the chosen one if it no longer does.
    private var choices: [GraphicsBackend] {
        GraphicsBackend.allCases.filter { available.contains($0) || $0 == program.settings.graphicsBackend }
    }
}
