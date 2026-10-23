//
//  LibraryRows.swift
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

/// A run-history entry: run it again, or pin it to the Library.
struct LibraryRecentRow: View {
    @ObservedObject var bottle: Bottle
    let entry: RunHistoryEntry
    let showsBottle: Bool
    let onRun: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private var isPinned: Bool {
        bottle.settings.pins.contains { $0.url == entry.url }
    }

    private var isMissing: Bool {
        !FileManager.default.fileExists(atPath: entry.url.path(percentEncoded: false))
    }

    var body: some View {
        HStack(spacing: 12) {
            ExeIconView(url: entry.url, size: 28)
                .opacity(isMissing ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if bottle.runningPrograms.contains(entry.url) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                    Text(entry.name)
                        .lineLimit(1)
                    if showsBottle {
                        Text(bottle.settings.name)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(entry.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            Text(Self.relativeFormatter.localizedString(for: entry.lastRun, relativeTo: Date()))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            HStack(spacing: 2) {
                Button {
                    togglePin()
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(isPinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 24, height: 24)
                }
                .help(isPinned ? "Remove from Library" : "Add to Library")
                Button(action: onRun) {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                }
                .disabled(isMissing)
                .help("button.run")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("button.showInFinder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
            .disabled(isMissing)
            Button("Remove from History", systemImage: "clock.badge.xmark", role: .destructive) {
                bottle.settings.runHistory.removeAll { $0.url == entry.url }
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private func togglePin() {
        if isPinned {
            bottle.settings.pins.removeAll { $0.url == entry.url }
        } else {
            let name = entry.url.deletingPathExtension().lastPathComponent
            bottle.settings.pins.append(PinnedProgram(name: name, url: entry.url))
        }
    }
}

/// A Start Menu program that isn't in the Library yet.
struct LibrarySuggestionRow: View {
    let suggestion: LibrarySuggestion
    let showsBottle: Bool
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ExeIconView(url: suggestion.url, size: 28, fallbackName: suggestion.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.name)
                    .lineLimit(1)
                Text(showsBottle
                     ? "\(suggestion.bottle.settings.name) · \(suggestion.url.lastPathComponent)"
                     : suggestion.url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Add", action: onAdd)
                .controlSize(.small)
                .help("Add to Library")
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Hide this suggestion")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct LibrarySectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Shown when there is no usable bottle yet.
struct LibraryEmptyState: View {
    let isCreating: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if isCreating {
                ProgressView()
                Text("Setting up your bottle…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("Welcome to Rum")
                    .font(.title2.bold())
                Text("Rum needs a bottle (a small Windows environment) to run games and apps in. "
                     + "One is enough for most things.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                Button(action: onCreate) {
                    Label("Create Bottle", systemImage: "plus")
                        .padding(6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Items

struct LibraryPinItem: Identifiable {
    let bottle: Bottle
    let pin: PinnedProgram
    let url: URL

    var id: String { Self.id(bottle: bottle, url: url) }

    static func id(bottle: Bottle, url: URL) -> String {
        "\(bottle.url.path)|\(url.path)"
    }
}

struct LibraryRecentItem: Identifiable {
    let bottle: Bottle
    let entry: RunHistoryEntry

    var id: String { "\(bottle.url.path)|\(entry.url.path)" }
}

struct LibrarySuggestion: Identifiable {
    let bottle: Bottle
    let name: String
    let url: URL

    var id: String { "\(bottle.url.path)|\(url.path)" }

    /// Hide uninstallers and shortcuts whose target is gone or isn't a program.
    static func isRelevant(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "exe",
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return !name.contains("uninst") && !name.hasPrefix("unins")
    }
}

struct LibraryScanKey: Hashable {
    let bottles: [URL]
    let runningCount: Int
    let activationCounter: Int
}
