//
//  BottleView.swift
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

/// A bottle's own settings, opened from Settings. Running and pinning programs happens in the Library;
/// this is only for configuring the Windows environment they share.
struct BottleView: View {
    @ObservedObject var bottle: Bottle
    /// Where the back button returns to.
    var backTitle: LocalizedStringKey = "Back"
    let onBack: () -> Void

    @State private var sheet: BottleSheet?

    private enum BottleSheet: String, Identifiable {
        case winetricks, programs, processes
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(EdgeInsets(top: 10, leading: LibrarySidebarMetrics.margin,
                                    bottom: 0, trailing: LibrarySidebarMetrics.margin))
            ConfigView(bottle: bottle)
                .scrollContentBackground(.hidden)
                .disabled(!bottle.isAvailable)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .winetricks:
                WinetricksView(bottle: bottle)
            case .programs:
                BottleSheetContainer { path in
                    ProgramsView(bottle: bottle, path: path)
                        .navigationDestination(for: Program.self) { program in
                            ProgramView(program: program)
                        }
                }
            case .processes:
                BottleSheetContainer { _ in
                    RunningProcessesView(bottle: bottle)
                }
            }
        }
        .onChange(of: bottle.settings) { oldValue, newValue in
            guard oldValue != newValue else { return }
            BottleVM.shared.bottles = BottleVM.shared.bottles
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Label(backTitle, systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Back")
            Divider()
                .frame(height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(bottle.settings.name)
                    .font(.headline)
                Text("\(bottle.settings.windowsVersion.pretty()) · \(bottle.settings.architecture.pretty())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("button.cDrive", systemImage: "internaldrive") { bottle.openCDrive() }
            Button("button.terminal", systemImage: "terminal") { bottle.openTerminal() }
            Button("button.winetricks", systemImage: "wrench.and.screwdriver") { sheet = .winetricks }
            Menu {
                Button("tab.programs", systemImage: "app.badge") { sheet = .programs }
                Button("Running Processes", systemImage: "list.bullet.rectangle") { sheet = .processes }
                Divider()
                Button("button.showInFinder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .fixedSize()
            .help("More")
        }
        .labelStyle(.titleAndIcon)
        .disabled(!bottle.isAvailable)
    }
}

/// Wraps a sheet's content in its own navigation, with Done to close it.
private struct BottleSheetContainer<Content: View>: View {
    @ViewBuilder let content: (Binding<NavigationPath>) -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content($path)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 640, minHeight: 520)
    }
}
