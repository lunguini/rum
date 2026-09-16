//
//  Wine+EnginePinning.swift
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

extension Wine {
    /// Adopt the engine a launch resolved to as the bottle's pin when it has none. New bottles are
    /// pinned at creation; this gives bottles made before engine identity was persisted the same
    /// explicit runtime, so a later change to the global default does not silently move them to
    /// another engine and charge them a prefix refresh for it.
    @MainActor
    static func pinResolvedEngineIfNeeded(for bottle: Bottle, engine: WineEngine) {
        guard bottle.settings.wineEngineID == nil else { return }
        bottle.settings.wineEngineID = engine.id
    }
}
