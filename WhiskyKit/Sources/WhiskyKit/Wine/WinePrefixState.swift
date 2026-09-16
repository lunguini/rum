//
//  WinePrefixState.swift
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

/// Records which engine last refreshed a prefix so `wineboot -u` is only paid when the engine
/// actually changes, rather than on every cold launch of the bottle.
struct WinePrefixState: Codable, Equatable, Sendable {
    let engineID: String
    let engineVersion: String
}

enum WinePrefixStateStore {
    private static let stateFileName = ".rum-prefix-state.plist"

    static func stateURL(for bottle: Bottle) -> URL {
        bottle.url.appending(path: stateFileName)
    }

    static func load(for bottle: Bottle) -> WinePrefixState? {
        let url = stateURL(for: bottle)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(WinePrefixState.self, from: data)
    }

    /// A missing or unreadable marker is treated as "needs initialization", so a corrupt file
    /// costs one extra `wineboot` rather than leaving the prefix stale.
    static func needsInitialization(for bottle: Bottle, engine: WineEngine) -> Bool {
        guard let state = load(for: bottle) else { return true }
        return state.engineID != engine.id || state.engineVersion != engine.version
    }

    static func recordInitialization(for bottle: Bottle, engine: WineEngine) throws {
        let state = WinePrefixState(engineID: engine.id, engineVersion: engine.version)
        let data = try PropertyListEncoder().encode(state)
        try data.write(to: stateURL(for: bottle), options: .atomic)
    }

    static func clear(for bottle: Bottle) {
        try? FileManager.default.removeItem(at: stateURL(for: bottle))
    }
}
