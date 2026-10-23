//
//  ProgramRenderer.swift
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
import os

/// How a program's own renderer is put in place when it differs from its bottle's. The bottle's
/// renderer stays installed in the bottle and the program's is layered on top, so programs on
/// different renderers can share a bottle and run at the same time.
enum ProgramRendererPlacement: Equatable, Sendable {
    /// The program uses the bottle's renderer.
    case bottle
    /// Wine loads the renderer from where it already is; only the launch environment changes.
    case environment
    /// The renderer's DLLs are copied next to the program, which Wine searches before the bottle.
    case programFolder(source: URL)
}

public enum ProgramRenderer {
    /// Whether `backend` can be a program's own renderer under the given engine. False only for
    /// Wine-builtin renderer builds on engines that can't load them from their own folder.
    public static func supportsProgramOverride(_ backend: GraphicsBackend, engineID: String?) -> Bool {
        switch backend {
        case .wineD3D, .dxvk:
            return true
        case .dxmt, .d3dmetal:
            guard let engine = try? WhiskyWineInstaller.wineEngine(for: engineID) else { return false }
            guard let folder = rendererFolder(for: backend, engine: engine, is64Bit: true) else { return false }
            return !WhiskyWineInstaller.isWineBuiltinDLL(folder.appending(path: "d3d11.dll"))
                || supportsLoaderOverlay(engine)
        }
    }

    static func placement(
        for backend: GraphicsBackend,
        bottleBackend: GraphicsBackend,
        programURL: URL,
        engine: WineEngine
    ) throws -> ProgramRendererPlacement {
        guard backend != bottleBackend else { return .bottle }
        let is64Bit = (try? PEFile(url: programURL))?.architecture != .x32
        switch backend {
        case .wineD3D:
            return .environment
        case .dxvk:
            return .programFolder(source: Wine.dxvkFolder.appending(path: is64Bit ? "x64" : "x32"))
        case .dxmt, .d3dmetal:
            guard let folder = rendererFolder(for: backend, engine: engine, is64Bit: is64Bit) else {
                throw GraphicsBackendError.unavailable(
                    backend, "\(engine.displayName) has no \(backend.displayName) for this program."
                )
            }
            guard WhiskyWineInstaller.isWineBuiltinDLL(folder.appending(path: "d3d11.dll")) else {
                return .programFolder(source: folder)
            }
            // A Wine-builtin build can't be loaded from the program's folder: Wine would pick its
            // own copy of the DLL instead. Engines with the loader overlay load it in place.
            guard supportsLoaderOverlay(engine) else {
                throw GraphicsBackendError.unavailable(
                    backend, "\(engine.displayName) can only use it as the bottle's renderer."
                )
            }
            return .environment
        }
    }

    /// The DLL load order for a program whose renderer differs from its bottle's. Every Direct3D
    /// module is pinned, so whatever renderer the bottle has installed can't leak in.
    static func dllOverrides(for backend: GraphicsBackend, placement: ProgramRendererPlacement) -> String? {
        let modules = ["dxgi", "d3d9", "d3d10core", "d3d11", "d3d12"]
        switch placement {
        case .bottle:
            return nil
        case .environment:
            return modules.joined(separator: ",") + "=b"
        case .programFolder:
            let native: Set<String> = switch backend {
            case .dxvk: ["dxgi", "d3d9", "d3d10core", "d3d11"]
            case .dxmt: ["dxgi", "d3d10core", "d3d11"]
            case .d3dmetal: ["dxgi", "d3d11", "d3d12"]
            case .wineD3D: []
            }
            let builtin = modules.filter { !native.contains($0) }
            let nativeList = modules.filter(native.contains).joined(separator: ",")
            return builtin.isEmpty
                ? "\(nativeList)=n,b"
                : "\(nativeList)=n,b;\(builtin.joined(separator: ","))=b"
        }
    }

    /// Where the engine keeps `backend`'s Windows DLLs for a program of the given bitness.
    private static func rendererFolder(for backend: GraphicsBackend, engine: WineEngine, is64Bit: Bool) -> URL? {
        let capabilities = WhiskyWineInstaller.graphicsCapabilities(for: engine)
        let folder: URL?
        switch backend {
        case .dxmt:
            folder = capabilities.dxmtRootURL?.appending(path: is64Bit ? "x86_64-windows" : "i386-windows")
        case .d3dmetal:
            // D3DMetal only ships 64-bit modules.
            folder = capabilities.d3dmetalRootURL?.appending(path: "wine/x86_64-windows")
        case .wineD3D, .dxvk:
            folder = nil
        }
        guard let folder, FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
            return nil
        }
        return folder
    }

    private static let overlaySupport = OSAllocatedUnfairLock<[String: Bool]>(initialState: [:])

    /// Whether the engine's loader honours `WINEDLLPATH_PREPEND`, so renderer builds can be loaded
    /// from their own folder ahead of Wine's. Patched macOS builds mention it in ntdll.
    static func supportsLoaderOverlay(_ engine: WineEngine) -> Bool {
        if let known = overlaySupport.withLock({ $0[engine.id] }) { return known }
        let ntdll = engine.wineURL.appending(path: "lib/wine/x86_64-unix/ntdll.so")
        let supported = (try? Data(contentsOf: ntdll, options: .mappedIfSafe))?
            .range(of: Data("WINEDLLPATH_PREPEND".utf8)) != nil
        overlaySupport.withLock { $0[engine.id] = supported }
        return supported
    }
}

extension Wine {
    static func programRendererPlacement(
        for backend: GraphicsBackend,
        bottle: Bottle,
        programURL: URL,
        engine: WineEngine
    ) throws -> ProgramRendererPlacement {
        let bottleBackend = bottle.settings.graphicsBackend
        guard backend != bottleBackend else { return .bottle }
        // The Windows folder holds the bottle's own renderer files; programs there share them.
        let windowsFolder = bottle.url.appending(path: "drive_c/windows")
            .standardizedFileURL.path(percentEncoded: false)
        if programURL.standardizedFileURL.path(percentEncoded: false).hasPrefix(windowsFolder + "/") {
            throw GraphicsBackendError.unavailable(
                backend, "Programs in the Windows folder can only use the bottle's renderer."
            )
        }
        return try ProgramRenderer.placement(
            for: backend, bottleBackend: bottleBackend, programURL: programURL, engine: engine
        )
    }

    /// The launch environment, with the DLL load order a program's own renderer needs.
    static func programLaunchEnvironment(
        for bottle: Bottle,
        engine: WineEngine,
        backend: GraphicsBackend,
        placement: ProgramRendererPlacement,
        environment: [String: String]
    ) -> [String: String] {
        var result = constructWineEnvironment(for: bottle, engine: engine, graphicsBackend: backend)
        if let overrides = ProgramRenderer.dllOverrides(for: backend, placement: placement) {
            result["WINEDLLOVERRIDES"] = overrides
        }
        // The program's own variables still win, as for any launch.
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    /// Readies the program's folder once the bottle's renderer lock is held; gives the lock back
    /// when that fails.
    static func acquireProgramFolder(
        _ folder: URL,
        placement: ProgramRendererPlacement,
        backend: GraphicsBackend,
        bottle: Bottle,
        bottleBackend: GraphicsBackend
    ) async throws {
        do {
            try await ProgramRendererCoordinator.shared.acquire(folder: folder, placement: placement, backend: backend)
        } catch {
            await RendererExecutionCoordinator.shared.release(bottlePath: bottle.url.path, backend: bottleBackend)
            throw error
        }
    }

    static func releaseLaunch(folder: URL, bottle: Bottle, backend: GraphicsBackend) async {
        await ProgramRendererCoordinator.shared.release(folder: folder)
        await RendererExecutionCoordinator.shared.release(bottlePath: bottle.url.path, backend: backend)
    }
}
