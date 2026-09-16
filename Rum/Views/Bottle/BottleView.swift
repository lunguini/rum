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
import UniformTypeIdentifiers
import WhiskyKit

enum BottleStage {
    case config
    case programs
    case processes
    case history
}

struct BottleView: View {
    @ObservedObject var bottle: Bottle
    @State private var path = NavigationPath()
    @State private var launchingCount: Int = 0
    @State private var launchError: LaunchError?
    @State private var showWinetricksSheet: Bool = false

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]
    private static let pinnableExtensions: Set<String> = ["exe", "msi", "bat"]
    @State private var isDropTargeted: Bool = false

    private struct LaunchError: Identifiable {
        let id = UUID()
        let message: String
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var sortedHistory: [RunHistoryEntry] {
        bottle.settings.runHistory.sorted { $0.lastRun > $1.lastRun }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: gridLayout, alignment: .center) {
                    ForEach(bottle.pinnedPrograms, id: \.id) { pinnedProgram in
                        PinView(
                            bottle: bottle, program: pinnedProgram.program, pin: pinnedProgram.pin, path: $path
                        )
                    }
                    PinAddView(bottle: bottle)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(4)
                        .opacity(isDropTargeted ? 1 : 0)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                }
                if !sortedHistory.isEmpty {
                    Form {
                        Section("Run History") {
                            ForEach(sortedHistory, id: \.self) { entry in
                                let isRunning = bottle.runningPrograms.contains(entry.url)
                                let isPinned = bottle.settings.pins.contains { $0.url == entry.url }
                                HStack(spacing: 0) {
                                    HStack(spacing: 8) {
                                        if isRunning {
                                            Circle()
                                                .fill(.green)
                                                .frame(width: 8, height: 8)
                                        }
                                        Text(entry.name)
                                            .font(.body)
                                        Text(entry.url.deletingLastPathComponent().path(percentEncoded: false))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                        let timeAgo = Self.relativeFormatter
                                            .localizedString(for: entry.lastRun, relativeTo: Date())
                                        Text(timeAgo)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    ControlGroup {
                                        Button {
                                            if isPinned {
                                                unpinEntry(entry)
                                            } else {
                                                pinEntry(entry)
                                            }
                                        } label: {
                                            Image(systemName: isPinned ? "pin.slash" : "pin")
                                        }
                                        Button {
                                            let program = Program(url: entry.url, bottle: bottle)
                                            program.run()
                                        } label: {
                                            Image(systemName: "play.fill")
                                        }
                                    }
                                    .controlSize(.small)
                                }
                                .contextMenu {
                                    Button("history.remove", role: .destructive) {
                                        bottle.settings.runHistory.removeAll { $0.url == entry.url }
                                    }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                }
            }
            .bottomBar {
                HStack {
                    Button("tab.programs") {
                        path.append(BottleStage.programs)
                    }
                    Button("tab.config") {
                        path.append(BottleStage.config)
                    }
                    Spacer()
                    Button("button.cDrive") {
                        bottle.openCDrive()
                    }
                    Button("button.terminal") {
                        bottle.openTerminal()
                    }
                    Button("button.winetricks") {
                        showWinetricksSheet.toggle()
                    }
                    Button("button.run") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [UTType.exe,
                                                     UTType(exportedAs: "com.microsoft.msi-installer"),
                                                     UTType(exportedAs: "com.microsoft.bat")]
                        panel.directoryURL = bottle.url.appending(path: "drive_c")
                        panel.begin { result in
                            guard result == .OK, let url = panel.urls.first else { return }
                            launchingCount += 1
                            bottle.recordRun(url: url, name: url.lastPathComponent)
                            bottle.runningPrograms.insert(url)
                            Task(priority: .userInitiated) {
                                do {
                                    if url.pathExtension == "bat" {
                                        try await Wine.runBatchFile(url: url, bottle: bottle)
                                        await MainActor.run { decrementLaunchingCount() }
                                    } else {
                                        try await Wine.runProgram(at: url, bottle: bottle) {
                                            Task { @MainActor in
                                                decrementLaunchingCount()
                                            }
                                        }
                                    }
                                } catch {
                                    print("Failed to run program: \(error)")
                                    await MainActor.run {
                                        launchingCount = max(launchingCount - 1, 0)
                                        launchError = LaunchError(
                                            message: "\(url.lastPathComponent): \(error.localizedDescription)"
                                        )
                                    }
                                }
                                await MainActor.run { bottle.runningPrograms.remove(url) }
                                updateStartMenu()
                            }
                        }
                    }
                    .disabled(launchingCount > 0)
                    if launchingCount > 0 {
                        Spacer()
                            .frame(width: 10)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding()
            }
            .onAppear {
                updateStartMenu()
            }
            .disabled(!bottle.isAvailable)
            .navigationTitle(bottle.settings.name)
            .sheet(isPresented: $showWinetricksSheet) {
                WinetricksView(bottle: bottle)
            }
            .alert("alert.message", isPresented: Binding(
                get: { launchError != nil },
                set: { if !$0 { launchError = nil } }
            )) {
                Button("button.ok", role: .cancel) {}
            } message: {
                Text(launchError?.message ?? "")
            }
            .onChange(of: bottle.settings) { oldValue, newValue in
                guard oldValue != newValue else { return }
                BottleVM.shared.bottles = BottleVM.shared.bottles
            }
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(bottle: bottle)
                case .programs:
                    ProgramsView(
                        bottle: bottle, path: $path
                    )
                case .processes:
                    RunningProcessesView(bottle: bottle)
                case .history:
                    RunHistoryView(bottle: bottle)
                }
            }
            .navigationDestination(for: Program.self) { program in
                ProgramView(program: program)
            }
        }
    }

    @MainActor private func decrementLaunchingCount() {
        launchingCount = max(launchingCount - 1, 0)
    }
}

// MARK: - Drag-and-drop pinning
extension BottleView {
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didAccept = false
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            // Reject non-pinnable files up front using the provider's suggested filename, so the
            // drop animation doesn't report "accepted" for a file we'll silently ignore. The URL
            // load below is async, so the real extension isn't available before we must decide.
            guard let suggestedName = provider.suggestedName,
                  Self.pinnableExtensions.contains((suggestedName as NSString).pathExtension.lowercased()) else {
                continue
            }
            didAccept = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                guard Self.pinnableExtensions.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in
                    guard !bottle.settings.pins.contains(where: { $0.url == url }) else { return }
                    let name = url.deletingPathExtension().lastPathComponent
                    bottle.settings.pins.append(PinnedProgram(name: name, url: url))
                    bottle.updateInstalledPrograms()
                }
            }
        }
        return didAccept
    }

    private func pinEntry(_ entry: RunHistoryEntry) {
        let program = Program(url: entry.url, bottle: bottle)
        if !bottle.programs.contains(where: { $0.url == entry.url }) {
            bottle.programs.append(program)
        }
        program.pinned = true
    }

    private func unpinEntry(_ entry: RunHistoryEntry) {
        bottle.settings.pins.removeAll { $0.url == entry.url }
    }

    private func updateStartMenu() {
        bottle.updateInstalledPrograms()

        let startMenuPrograms = bottle.getStartMenuPrograms()
        for startMenuProgram in startMenuPrograms {
            for program in bottle.programs where
            program.url.path().caseInsensitiveCompare(startMenuProgram.url.path()) == .orderedSame {
                program.pinned = true
                guard !bottle.settings.pins.contains(where: { $0.url == program.url }) else { return }
                bottle.settings.pins.append(PinnedProgram(
                    name: program.url.deletingPathExtension().lastPathComponent,
                    url: program.url
                ))
            }
        }
    }
}
