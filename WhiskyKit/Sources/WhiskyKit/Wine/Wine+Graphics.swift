//
//  Wine+Graphics.swift
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
    public static func enableDXVK(bottle: Bottle) throws {
        try RendererStateStore.applyDXVK(bottle: bottle, sourceRoot: Wine.dxvkFolder)
    }

    static func prepareGraphicsBackend(_ backend: GraphicsBackend, for bottle: Bottle) throws {
        let engine = try WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID)
        try prepareGraphicsBackend(backend, for: bottle, engine: engine)
    }

    static func prepareGraphicsBackend(
        _ backend: GraphicsBackend,
        for bottle: Bottle,
        engine: WineEngine
    ) throws {
        switch backend {
        case .wineD3D:
            try RendererStateStore.restoreRenderer(bottle: bottle, sourceRoot: Wine.dxvkFolder)
        case .dxvk:
            try enableDXVK(bottle: bottle)
        case .dxmt:
            let capabilities = WhiskyWineInstaller.graphicsCapabilities(for: engine)
            guard let root = capabilities.dxmtRootURL else {
                throw GraphicsBackendError.unavailable(
                    backend,
                    "Wine engine \(engine.displayName) has no compatible DXMT payload."
                )
            }
            try RendererStateStore.applyDXMT(bottle: bottle, sourceRoot: root)
        case .d3dmetal:
            let capabilities = WhiskyWineInstaller.graphicsCapabilities(for: engine)
            guard let root = capabilities.d3dmetalRootURL else {
                throw GraphicsBackendError.unavailable(
                    backend,
                    "Wine engine \(engine.displayName) has no compatible D3DMetal payload."
                )
            }
            try RendererStateStore.applyD3DMetal(bottle: bottle, sourceRoot: root)
        }
    }

    /// Restore the renderer files previously managed by Rum. A file is never removed when it no
    /// longer matches the installed artifact, which protects a user replacement from being
    /// silently discarded.
    public static func disableDXVK(bottle: Bottle) throws {
        try RendererStateStore.restoreRenderer(bottle: bottle, sourceRoot: Wine.dxvkFolder)
    }

    static func validateGraphicsBackend(_ backend: GraphicsBackend, for bottle: Bottle) throws {
        let engine = try WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID)
        try validateGraphicsBackend(backend, for: bottle, engine: engine)
    }

    static func validateGraphicsBackend(
        _ backend: GraphicsBackend,
        for bottle: Bottle,
        engine: WineEngine
    ) throws {
        if backend.requiresWin64 && bottle.settings.architecture != .win64 {
            throw GraphicsBackendError.unsupportedArchitecture(backend, bottle.settings.architecture)
        }

        if backend == .wineD3D {
            return
        }

        if backend == .dxvk {
            guard WhiskyWineInstaller.isDXVKInstalled(for: bottle.settings.architecture) else {
                throw GraphicsBackendError.unavailable(backend, "DXVK is not installed.")
            }
            return
        }

        let availability = WhiskyWineInstaller.graphicsCapabilities(for: engine).availability(
            for: backend,
            architecture: bottle.settings.architecture,
            dxvkInstalled: false
        )
        guard availability.isAvailable else {
            let reason = availability.reason ?? "No compatible runtime was found."
            throw GraphicsBackendError.unavailable(
                backend,
                "Wine engine \(engine.displayName): \(reason)"
            )
        }
    }
}
