//
//  LibraryView+Data.swift
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

import Combine
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

// MARK: - Data

extension LibraryView {
    nonisolated static let runnableExtensions: Set<String> = ["exe", "msi", "bat"]

    var availableBottles: [Bottle] {
        bottleVM.availableBottles
    }

    /// Bottle names are only noise when there is a single bottle.
    var showsBottleNames: Bool {
        availableBottles.count > 1
    }

    var defaultBottle: Bottle? {
        bottleVM.defaultBottle(preferredURL: defaultBottleURL)
    }

    var defaultBottleSelection: Binding<URL> {
        Binding(
            get: { defaultBottle?.url ?? URL(filePath: "/") },
            set: { defaultBottleURL = $0 }
        )
    }

    var pinnedItems: [LibraryPinItem] {
        availableBottles.flatMap { bottle in
            bottle.settings.pins.compactMap { pin in
                guard let url = pin.url else { return nil }
                return LibraryPinItem(bottle: bottle, pin: pin, url: url)
            }
        }
    }

    var filteredPinnedItems: [LibraryPinItem] {
        let items = pinnedItems.filter { matchesSearch($0.pin.name) }
        switch sort {
        case .name:
            return items.sorted { $0.pin.name.localizedStandardCompare($1.pin.name) == .orderedAscending }
        case .recent:
            let lastRun = Dictionary(recentEntries.map { ($0.entry.url, $0.entry.lastRun) },
                                     uniquingKeysWith: { first, _ in first })
            return items.sorted { lhs, rhs in
                switch (lastRun[lhs.url], lastRun[rhs.url]) {
                case let (left?, right?): return left > right
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return lhs.pin.name.localizedStandardCompare(rhs.pin.name) == .orderedAscending
                }
            }
        }
    }

    var selectedItem: LibraryPinItem? {
        guard let selection else { return nil }
        if let pinned = pinnedItems.first(where: { $0.id == selection }) {
            return pinned
        }
        // Home also shows programs that aren't in the Library.
        return (runningItems + recentEntries.map { item(for: $0.entry.url, name: $0.entry.name, in: $0.bottle) })
            .first { $0.id == selection }
    }

    /// A Library item for any program: its pin when it has one.
    func item(for url: URL, name: String, in bottle: Bottle) -> LibraryPinItem {
        let pin = bottle.settings.pins.first { $0.url == url } ?? PinnedProgram(name: name, url: url)
        return LibraryPinItem(bottle: bottle, pin: pin, url: url)
    }

    // MARK: Home

    /// Everything starting or running, most recently started first.
    var runningItems: [LibraryPinItem] {
        availableBottles.flatMap { bottle in
            bottle.runningPrograms.map { url in
                let name = bottle.settings.runHistory.first { $0.url == url }?.name
                    ?? url.deletingPathExtension().lastPathComponent
                return item(for: url, name: name, in: bottle)
            }
        }
        .sorted { lhs, rhs in
            (lhs.bottle.runningSince(lhs.url) ?? .distantPast) > (rhs.bottle.runningSince(rhs.url) ?? .distantPast)
        }
        .filter { matchesSearch($0.pin.name) }
    }

    /// Most played first: by time played, then by number of runs. Installers are left out.
    var favouriteItems: [LibraryPinItem] {
        filteredRecentEntries
            .filter { !Self.isInstaller($0.entry.url) }
            .sorted { lhs, rhs in
                if lhs.entry.playTime != rhs.entry.playTime { return lhs.entry.playTime > rhs.entry.playTime }
                if lhs.entry.runCount != rhs.entry.runCount { return lhs.entry.runCount > rhs.entry.runCount }
                return lhs.entry.lastRun > rhs.entry.lastRun
            }
            .prefix(12)
            .map { item(for: $0.entry.url, name: $0.entry.name, in: $0.bottle) }
    }

    var recentItems: [LibraryPinItem] {
        filteredRecentEntries
            .prefix(12)
            .map { item(for: $0.entry.url, name: $0.entry.name, in: $0.bottle) }
    }

    /// Names of programs being started, for the toast shown away from Home.
    var launchingNames: [String] {
        availableBottles.flatMap { bottle in
            bottle.launchingPrograms.map { url in
                bottle.settings.pins.first { $0.url == url }?.name
                    ?? bottle.settings.runHistory.first { $0.url == url }?.name
                    ?? url.deletingPathExtension().lastPathComponent
            }
        }
        .sorted()
    }

    nonisolated static func isInstaller(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let markers = ["setup", "install", "unins", "redist", "dxweb", "dotnet", "vcrun"]
        return url.pathExtension.lowercased() == "msi" || markers.contains { name.contains($0) }
    }

    var recentEntries: [LibraryRecentItem] {
        availableBottles.flatMap { bottle in
            bottle.settings.runHistory.map { LibraryRecentItem(bottle: bottle, entry: $0) }
        }
        .sorted { $0.entry.lastRun > $1.entry.lastRun }
    }

    var filteredRecentEntries: [LibraryRecentItem] {
        recentEntries.filter { matchesSearch($0.entry.name) }
    }

    func matchesSearch(_ name: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    var dismissedSuggestions: Set<String> {
        Set(dismissedSuggestionsRaw.split(separator: "\n").map(String.init))
    }

    var visibleSuggestions: [LibrarySuggestion] {
        let dismissed = dismissedSuggestions
        return suggestions.filter { suggestion in
            !dismissed.contains(suggestion.url.path(percentEncoded: false))
                && !suggestion.bottle.settings.pins.contains { $0.url == suggestion.url }
        }
    }

    var bottleChanges: AnyPublisher<Void, Never> {
        Publishers.MergeMany(availableBottles.map { $0.objectWillChange.map { _ in () } })
            // objectWillChange fires before the value changes; read it on the next run loop pass.
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    /// Rescan Start Menus when bottles change, a program exits (installers finish), or Rum comes
    /// back to the front.
    var scanKey: LibraryScanKey {
        LibraryScanKey(
            bottles: availableBottles.map(\.url),
            runningCount: availableBottles.reduce(0) { $0 + $1.runningPrograms.count },
            activationCounter: activationCounter
        )
    }

    func scanForSuggestions() {
        var found: [LibrarySuggestion] = []
        for bottle in availableBottles {
            for shortcut in bottle.startMenuShortcuts() where LibrarySuggestion.isRelevant(shortcut.url) {
                found.append(LibrarySuggestion(bottle: bottle, name: shortcut.name, url: shortcut.url))
            }
        }
        suggestions = found
    }
}

// MARK: - Actions

extension LibraryView {
    var itemActions: LibraryItemActions {
        LibraryItemActions(
            run: { run($0.url, in: $0.bottle) },
            stop: { item in Task { await item.bottle.stopProgram(at: item.url) } },
            showSettings: { item in
                selection = item.id
                inspectorTab = .settings
                showsInspector = true
            },
            showAllSettings: { item in
                settingsProgram = Program(url: item.url, bottle: item.bottle)
            },
            findArtwork: { artworkItem = $0 },
            rename: { renameItem = $0 }
        )
    }

    func add(_ suggestion: LibrarySuggestion) {
        pin(suggestion.url, name: suggestion.name, in: suggestion.bottle)
    }

    func dismiss(_ suggestion: LibrarySuggestion) {
        var dismissed = dismissedSuggestions
        dismissed.insert(suggestion.url.path(percentEncoded: false))
        dismissedSuggestionsRaw = dismissed.sorted().joined(separator: "\n")
    }

    func pin(_ url: URL, name: String, in bottle: Bottle) {
        guard !bottle.settings.pins.contains(where: { $0.url == url }) else { return }
        bottle.settings.pins.append(PinnedProgram(name: name, url: url))
        selection = LibraryPinItem.id(bottle: bottle, url: url)
    }

    /// Runs any program, installer or batch file. It shows up in Recently Played.
    func chooseAndRun() {
        guard let bottle = defaultBottle else { return }
        choose(allowing: [UTType.exe,
                          UTType(exportedAs: "com.microsoft.msi-installer"),
                          UTType(exportedAs: "com.microsoft.bat")],
               message: String(format: "Choose a program to run in “%@”", bottle.settings.name)) { url in
            run(url, in: bottle)
        }
    }

    /// Adds a program to the Library without running it.
    func chooseAndAdd() {
        guard let bottle = defaultBottle else { return }
        choose(allowing: [UTType.exe, UTType(exportedAs: "com.microsoft.bat")],
               message: "Choose a game or app to add to your Library") { url in
            pin(url, name: url.deletingPathExtension().lastPathComponent, in: bottle)
        }
    }

    private func choose(allowing types: [UTType], message: String, then action: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = types
        panel.message = message
        panel.begin { result in
            guard result == .OK, let url = panel.urls.first else { return }
            Task { @MainActor in action(url) }
        }
    }

    func run(_ url: URL, in bottle: Bottle) {
        guard url.pathExtension.lowercased() == "bat" else {
            Program(url: url, bottle: bottle).run()
            return
        }
        // `Program.run` goes through `start /unix`, batch files need `cmd`.
        bottle.recordRun(url: url, name: url.lastPathComponent)
        bottle.programDidStart(url)
        // `runBatchFile` doesn't report when cmd starts, so don't show it as starting.
        bottle.programDidLaunch(url)
        Task {
            do {
                _ = try await Wine.runBatchFile(url: url, bottle: bottle)
            } catch {
                launchError = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
            bottle.programDidExit(url)
        }
    }

    func createDefaultBottle() {
        let location = UserDefaults.standard.url(forKey: "defaultBottleLocation") ?? BottleData.defaultBottleDir
        defaultBottleURL = bottleVM.createNewBottle(bottleName: "Default",
                                                    winVersion: .win10,
                                                    architecture: .win64,
                                                    bottleURL: location)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let bottle = defaultBottle else { return false }
        var didAccept = false
        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self),
                  let suggestedName = provider.suggestedName,
                  Self.runnableExtensions.contains((suggestedName as NSString).pathExtension.lowercased()) else {
                continue
            }
            didAccept = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, Self.runnableExtensions.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in
                    pin(url, name: url.deletingPathExtension().lastPathComponent, in: bottle)
                }
            }
        }
        return didAccept
    }
}

// MARK: - Shared pieces

extension LibraryView {
    /// Which bottle Run Windows App… uses. Only shown when there is a choice.
    var bottleMenu: some View {
        Picker("Run in", selection: defaultBottleSelection) {
            ForEach(availableBottles) { bottle in
                Text(bottle.settings.name).tag(bottle.url)
            }
        }
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("The bottle Run Windows App… uses")
    }

    func groupedRows<Item: Identifiable, Row: View>(
        _ items: [Item], @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                row(item)
            }
        }
        .libraryGroup()
    }

    var noMatches: some View {
        ContentUnavailableView.search(text: searchText)
            .padding(.top, 40)
    }
}
