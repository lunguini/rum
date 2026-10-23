//
//  Bottle.swift
//  WhiskyKit
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

import Foundation
import SwiftUI
import os.log

// swiftlint:disable:next todo
// TODO: Should not be unchecked!
public final class Bottle: ObservableObject, Equatable, Hashable, Identifiable, Comparable, @unchecked Sendable {
    public let url: URL
    private let metadataURL: URL
    @Published public var settings: BottleSettings {
        didSet { saveSettings() }
    }
    @Published public var programs: [Program] = []
    /// Programs with at least one running instance. Updated through `programDidStart` and
    /// `programDidExit` so programs launched several times are tracked per instance.
    @Published public private(set) var runningPrograms: Set<URL> = []
    /// Programs started from Rum that Wine hasn't launched yet: the bottle and graphics are being
    /// prepared. See `programDidLaunch`.
    @Published public private(set) var launchingPrograms: Set<URL> = []
    private var runningInstanceCounts: [URL: Int] = [:]
    private var launchingInstanceCounts: [URL: Int] = [:]
    /// When the first of a program's running instances started.
    private var runningSince: [URL: Date] = [:]
    @Published public var inFlight: Bool = false
    public var isAvailable: Bool = false

    /// All pins with their associated programs
    public var pinnedPrograms: [(pin: PinnedProgram, program: Program, // swiftlint:disable:this large_tuple
                                 id: String)] {
        return settings.pins.compactMap { pin in
            let exists = FileManager.default.fileExists(atPath: pin.url?.path(percentEncoded: false) ?? "")
            guard let program = programs.first(where: { $0.url == pin.url && exists }) else { return nil }
            return (pin, program, "\(pin.name)//\(program.url)")
        }
    }

    public init(bottleUrl: URL, inFlight: Bool = false, isAvailable: Bool = false) {
        let metadataURL = bottleUrl.appending(path: "Metadata").appendingPathExtension("plist")
        self.url = bottleUrl
        self.inFlight = inFlight
        self.isAvailable = isAvailable
        self.metadataURL = metadataURL

        do {
            self.settings = try BottleSettings.decode(from: metadataURL)
        } catch {
            Logger.wineKit.error(
              "Failed to load settings for bottle `\(metadataURL.path(percentEncoded: false))`: \(error)"
            )
            self.settings = BottleSettings()
        }

        // Get rid of duplicates. Pins to missing files are kept so the user can locate or unpin
        // them (an unmounted drive or a moved game folder shouldn't silently lose the pin);
        // `pinnedPrograms` still hides them.
        var found: Set<URL> = []
        self.settings.pins = self.settings.pins.filter { pin in
            guard let url = pin.url else { return false }
            guard !found.contains(url) else { return false }
            found.insert(url)
            return true
        }
    }

    /// Encode and save the bottle settings
    private func saveSettings() {
        do {
            try settings.encode(to: self.metadataURL)
        } catch {
            Logger.wineKit.error(
                "Failed to encode settings for bottle `\(self.metadataURL.path(percentEncoded: false))`: \(error)"
            )
        }
    }

    /// Number of running instances of the program at `url` launched from Rum. Main thread only.
    public func runningInstances(of url: URL) -> Int {
        runningInstanceCounts[url] ?? 0
    }

    /// Whether an instance of the program at `url` is still being prepared. Main thread only.
    public func isLaunching(_ url: URL) -> Bool {
        launchingPrograms.contains(url)
    }

    /// When the program at `url` started running, if it is. Main thread only.
    public func runningSince(_ url: URL) -> Date? {
        runningSince[url]
    }

    /// Call on the main thread when an instance of a program starts. It counts as launching until
    /// `programDidLaunch` or `programDidExit`.
    public func programDidStart(_ url: URL, at date: Date = Date()) {
        runningInstanceCounts[url, default: 0] += 1
        launchingInstanceCounts[url, default: 0] += 1
        if runningSince[url] == nil {
            runningSince[url] = date
        }
        runningPrograms.insert(url)
        launchingPrograms.insert(url)
    }

    /// Call on the main thread once Wine has launched an instance of the program.
    public func programDidLaunch(_ url: URL) {
        finishLaunching(url)
    }

    /// Call on the main thread when an instance of a program exits.
    public func programDidExit(_ url: URL, at date: Date = Date()) {
        finishLaunching(url)
        let remaining = max((runningInstanceCounts[url] ?? 0) - 1, 0)
        runningInstanceCounts[url] = remaining == 0 ? nil : remaining
        if remaining == 0 {
            if let start = runningSince.removeValue(forKey: url),
               let index = settings.runHistory.firstIndex(where: { $0.url == url }) {
                settings.runHistory[index].playTime += max(date.timeIntervalSince(start), 0)
            }
            runningPrograms.remove(url)
        } else {
            // Publish so instance counts shown in the UI update.
            objectWillChange.send()
        }
    }

    private func finishLaunching(_ url: URL) {
        guard let count = launchingInstanceCounts[url] else { return }
        if count > 1 {
            launchingInstanceCounts[url] = count - 1
            objectWillChange.send()
        } else {
            launchingInstanceCounts[url] = nil
            launchingPrograms.remove(url)
        }
    }

    public func recordRun(url: URL, name: String) {
        if let index = settings.runHistory.firstIndex(where: { $0.url == url }) {
            settings.runHistory[index].recordRun()
        } else {
            settings.runHistory.append(RunHistoryEntry(name: name, url: url))
        }
    }

    // MARK: - Equatable

    public static func == (lhs: Bottle, rhs: Bottle) -> Bool {
        return lhs.url == rhs.url
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        return hasher.combine(url)
    }

    // MARK: - Identifiable

    public var id: URL {
        self.url
    }

    // MARK: - Comparable

    public static func < (lhs: Bottle, rhs: Bottle) -> Bool {
        lhs.settings.name.lowercased() < rhs.settings.name.lowercased()
    }
}

public extension Sequence where Iterator.Element == Program {
    /// Filter all pinned programs
    var pinned: [Program] {
        return self.filter({ $0.pinned })
    }

    /// Filter all unpinned programs
    var unpinned: [Program] {
        return self.filter({ !$0.pinned })
    }
}
