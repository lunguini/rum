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
    @State private var showWinetricksSheet: Bool = false

    private let gridLayout = [GridItem(.adaptive(minimum: 100, maximum: .infinity))]

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
                                        await MainActor.run { launchingCount -= 1 }
                                    } else {
                                        try await Wine.runProgram(at: url, bottle: bottle) {
                                            Task { @MainActor in
                                                launchingCount -= 1
                                            }
                                        }
                                    }
                                } catch {
                                    print("Failed to run program: \(error)")
                                    await MainActor.run { launchingCount -= 1 }
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
