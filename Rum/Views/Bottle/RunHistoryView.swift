//
//  RunHistoryView.swift
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

struct RunHistoryView: View {
    @ObservedObject var bottle: Bottle

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var sortedHistory: [RunHistoryEntry] {
        bottle.settings.runHistory.sorted { $0.lastRun > $1.lastRun }
    }

    var body: some View {
        Form {
            if sortedHistory.isEmpty {
                Text("history.empty")
                    .foregroundStyle(.secondary)
            } else {
                Section {
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
        }
        .formStyle(.grouped)
        .navigationTitle("tab.history")
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
}
