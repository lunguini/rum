//
//  LibraryTile.swift
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

enum LibraryCardMetrics {
    static let minWidth: CGFloat = 150
    static let maxWidth: CGFloat = 200
    static let coverAspectRatio: CGFloat = 2 / 3
    static let cornerRadius: CGFloat = 10
}

/// What the Library can do with a program. Shared by cards, menus and the details panel.
struct LibraryItemActions {
    var run: (LibraryPinItem) -> Void
    var stop: (LibraryPinItem) -> Void
    /// Shows the program's settings in the details panel.
    var showSettings: (LibraryPinItem) -> Void
    /// Opens the full program settings page.
    var showAllSettings: (LibraryPinItem) -> Void
    var findArtwork: (LibraryPinItem) -> Void
    var rename: (LibraryPinItem) -> Void
}

/// A program's state, worded for the Library.
enum LibraryItemStatus: Equatable {
    case missing
    /// Rum is preparing the bottle; Wine hasn't launched the program yet.
    case starting
    case running(instances: Int, since: Date?)
    case played(Date)
    case notPlayed

    init(bottle: Bottle, url: URL) {
        let instances = bottle.runningInstances(of: url)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            self = .missing
        } else if bottle.isLaunching(url) {
            self = .starting
        } else if instances > 0 {
            self = .running(instances: instances, since: bottle.runningSince(url))
        } else if let entry = bottle.settings.runHistory.first(where: { $0.url == url }) {
            self = .played(entry.lastRun)
        } else {
            self = .notPlayed
        }
    }

    /// Starting or running: something can be stopped.
    var isRunning: Bool {
        switch self {
        case .starting, .running: true
        case .missing, .played, .notPlayed: false
        }
    }

    var instances: Int {
        if case .running(let instances, _) = self { return instances }
        return isRunning ? 1 : 0
    }

    /// Worded at `now`, so running times stay current.
    func text(at now: Date = Date()) -> String {
        switch self {
        case .missing:
            return "File not found"
        case .starting:
            return "Starting…"
        case .running(let instances, let since):
            var parts = ["Running"]
            if instances > 1 { parts.append("\(instances) open") }
            if let since, let uptime = Self.uptime(since: since, now: now) { parts.append(uptime) }
            return parts.joined(separator: " · ")
        case .played(let date):
            return "Played \(date.formatted(.relative(presentation: .named)))"
        case .notPlayed:
            return "Not played yet"
        }
    }

    /// "12 min", "1 h 5 min"; nil for the first minute.
    static func uptime(since: Date, now: Date) -> String? {
        let minutes = Int(now.timeIntervalSince(since) / 60)
        guard minutes >= 1 else { return nil }
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// A coloured dot for states worth noticing.
    var dotColor: Color? {
        switch self {
        case .missing: .orange
        case .starting: .yellow
        case .running: .green
        case .played, .notPlayed: nil
        }
    }
}

/// A Library program: cover art, name and status, with Play on hover. Click selects,
/// double-click plays.
struct LibraryCard: View {
    @ObservedObject var bottle: Bottle
    let item: LibraryPinItem
    let isSelected: Bool
    let showsBottle: Bool
    let actions: LibraryItemActions
    /// Says how often it was played ("Played 3 times last month") instead of when.
    var showsPlayCount = false
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        let status = LibraryItemStatus(bottle: bottle, url: item.url)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(LibraryCardMetrics.coverAspectRatio, contentMode: .fit)
                .overlay {
                    ArtworkView(url: item.url, name: item.pin.name, style: .cover)
                        .saturation(status == .missing ? 0 : 1)
                        .opacity(status == .missing ? 0.5 : 1)
                }
                .clipped()
                .overlay { hoverControls(status: status) }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.pin.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    LibraryStatusLabel(status: status, text: showsPlayCount ? playCountText(status) : nil)
                    if showsBottle {
                        Text("· \(bottle.settings.name)")
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        LibraryItemMenu(item: item, status: status, actions: actions)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
                }
                .font(.caption)
                .frame(height: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: LibraryCardMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LibraryCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(Color.rum) : AnyShapeStyle(.white.opacity(0.08)),
                              lineWidth: isSelected ? 2.5 : 1)
        }
        .shadow(color: .black.opacity(isHovering ? 0.25 : 0.12), radius: isHovering ? 8 : 3, y: isHovering ? 4 : 1)
        .scaleEffect(isHovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: LibraryCardMetrics.cornerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        // Clicking only selects; games start from the Play buttons, extra instances from the menu.
        .onTapGesture(perform: onSelect)
        .contextMenu {
            LibraryItemMenu(item: item, status: status, actions: actions)
        }
        .help(item.url.path(percentEncoded: false))
        .task(id: item.url) {
            await item.bottle.adoptProductName(for: item.url)
        }
    }

    /// Runs in the past month, or all-time runs when there were none. Nil while starting, running
    /// or missing, which matter more.
    private func playCountText(_ status: LibraryItemStatus) -> String? {
        guard case .played = status,
              let entry = bottle.settings.runHistory.first(where: { $0.url == item.url }) else { return nil }
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let recent = entry.runCount(since: monthAgo)
        if recent > 0 {
            return recent == 1 ? "Played once last month" : "Played \(recent) times last month"
        }
        return entry.runCount == 1 ? "Played once" : "Played \(entry.runCount) times"
    }

    @ViewBuilder
    private func hoverControls(status: LibraryItemStatus) -> some View {
        if status != .missing {
            HStack(spacing: 12) {
                if status.isRunning {
                    Button { actions.stop(item) } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(LibraryOverlayButtonStyle(role: .stop))
                    .help("Stop")
                }
                Button { actions.run(item) } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(LibraryOverlayButtonStyle())
                .help(status.isRunning ? "Run another instance" : "Play")
            }
            .opacity(isHovering ? 1 : 0)
        }
    }
}

/// The last card in the grid: add a game or app from anywhere on the Mac.
struct LibraryAddCard: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Color.clear
                    .aspectRatio(LibraryCardMetrics.coverAspectRatio, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.medium))
                                .frame(width: 44, height: 44)
                                .background(.quaternary, in: Circle())
                            Text("Add Game or App")
                                .font(.headline)
                            Text("Pick a Windows program on your Mac to keep it here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(16)
                    }
                // Same footer height as a program card, so the rows line up.
                VStack(spacing: 3) {
                    Text(" ").font(.headline)
                    Text(" ").font(.caption).frame(height: 16)
                }
                .hidden()
                .padding(.vertical, 8)
            }
            .background {
                RoundedRectangle(cornerRadius: LibraryCardMetrics.cornerRadius, style: .continuous)
                    .fill(.quaternary.opacity(isHovering ? 0.5 : 0.2))
            }
            .overlay {
                RoundedRectangle(cornerRadius: LibraryCardMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: LibraryCardMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

/// Status dot and text, e.g. "● Running".
struct LibraryStatusLabel: View {
    let status: LibraryItemStatus
    /// Replaces the status's own wording.
    var text: String?

    var body: some View {
        // Refreshes running times; other states don't change on their own.
        TimelineView(.periodic(from: .now, by: status.isRunning ? 30 : 3600)) { context in
            HStack(spacing: 4) {
                if status == .starting {
                    ProgressView()
                        .controlSize(.mini)
                } else if let color = status.dotColor {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(text ?? status.text(at: context.date))
                    .foregroundStyle(status.dotColor ?? .secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Menu items for a Library program (the card's ⋯ button and right-click menu).
struct LibraryItemMenu: View {
    let item: LibraryPinItem
    let status: LibraryItemStatus
    let actions: LibraryItemActions

    var body: some View {
        if status == .missing {
            Button("Locate…", systemImage: "magnifyingglass") { locate() }
            // The file is gone: take it off every list in one go.
            Button("Remove", systemImage: "trash", role: .destructive) {
                item.bottle.settings.pins.removeAll { $0.url == item.url }
                item.bottle.settings.runHistory.removeAll { $0.url == item.url }
            }
        } else {
            Button(status.isRunning ? "Run Another Instance" : "Play", systemImage: "play") { actions.run(item) }
            if status.isRunning {
                Button("Stop", systemImage: "stop") { actions.stop(item) }
            }
            Divider()
            if !isPinned {
                Button("Add to Library", systemImage: "plus.square.on.square") {
                    item.bottle.settings.pins.append(PinnedProgram(name: item.pin.name, url: item.url))
                }
            }
            Button("Settings…", systemImage: "gearshape") { actions.showSettings(item) }
            Button("button.showInFinder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        Divider()
        Button("Find Artwork…", systemImage: "photo") { actions.findArtwork(item) }
        if isPinned {
            Button("button.rename", systemImage: "pencil") { actions.rename(item) }
        }
        if status != .missing {
            if isPinned {
                Button("Remove from Library", systemImage: "minus.circle") {
                    item.bottle.settings.pins.removeAll { $0.url == item.url }
                }
            }
            if isInHistory {
                Button("Remove from History", systemImage: "clock.badge.xmark") {
                    item.bottle.settings.runHistory.removeAll { $0.url == item.url }
                }
            }
        }
    }

    /// Run before: it shows in Home and Recently Played.
    private var isInHistory: Bool {
        item.bottle.settings.runHistory.contains { $0.url == item.url }
    }

    /// Home also shows programs that were run but never added to the Library.
    private var isPinned: Bool {
        item.bottle.settings.pins.contains { $0.url == item.url }
    }

    /// Point a pin whose file moved (or whose drive isn't mounted) at its new location.
    private func locate() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(format: "Locate “%@”", item.url.lastPathComponent)
        let bottle = item.bottle
        let oldURL = item.url
        panel.begin { result in
            guard result == .OK, let newURL = panel.urls.first else { return }
            Task { @MainActor in
                guard let index = bottle.settings.pins.firstIndex(where: { $0.url == oldURL }) else { return }
                let name = bottle.settings.pins[index].name
                bottle.settings.pins[index] = PinnedProgram(name: name, url: newURL)
            }
        }
    }
}
