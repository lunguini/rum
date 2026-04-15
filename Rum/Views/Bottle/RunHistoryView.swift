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
                        HStack(spacing: 10) {
                            if bottle.runningPrograms.contains(entry.url) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(.body)
                                Text(entry.url.path(percentEncoded: false))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                Text(Self.relativeFormatter.localizedString(for: entry.lastRun, relativeTo: Date()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                let program = Program(url: entry.url, bottle: bottle)
                                program.pinned = true
                            } label: {
                                Image(systemName: "pin")
                            }
                            .buttonStyle(.borderless)
                            .help("button.pin")
                            Button {
                                let program = Program(url: entry.url, bottle: bottle)
                                program.run()
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
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
}
