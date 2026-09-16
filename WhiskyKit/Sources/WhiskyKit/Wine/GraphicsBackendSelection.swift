//
//  GraphicsBackendSelection.swift
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

import Foundation

/// The result of checking a bottle's renderer against the Wine engine it will use.
public struct GraphicsBackendSelectionResolution: Equatable, Sendable {
    public let backend: GraphicsBackend
    public let didFallback: Bool
    public let reason: String?

    public init(backend: GraphicsBackend, didFallback: Bool, reason: String? = nil) {
        self.backend = backend
        self.didFallback = didFallback
        self.reason = reason
    }
}

/// Resolves renderer selections without silently changing settings when engine capability data
/// is unavailable (for example, while a pinned engine is missing or has been uninstalled).
public enum GraphicsBackendSelectionResolver {
    public static func resolve(
        current backend: GraphicsBackend,
        architecture: BottleArchitecture,
        capabilities: WineGraphicsCapabilities?,
        dxvkInstalled: Bool
    ) -> GraphicsBackendSelectionResolution {
        guard let capabilities else {
            return GraphicsBackendSelectionResolution(backend: backend, didFallback: false)
        }

        let availability = capabilities.availability(
            for: backend,
            architecture: architecture,
            dxvkInstalled: dxvkInstalled
        )
        guard !availability.isAvailable else {
            return GraphicsBackendSelectionResolution(backend: backend, didFallback: false)
        }

        return GraphicsBackendSelectionResolution(
            backend: .wineD3D,
            didFallback: true,
            reason: availability.reason
                ?? "The selected Wine engine does not support \(backend.displayName)."
        )
    }
}
