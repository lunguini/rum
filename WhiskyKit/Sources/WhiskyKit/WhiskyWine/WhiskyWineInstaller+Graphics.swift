//
//  WhiskyWineInstaller+Graphics.swift
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

extension WhiskyWineInstaller {
    /// The Wine tree which owns the active loader. Managed builds and imported engines both
    /// resolve through this path, so renderer payloads are never accidentally selected from a
    /// different engine.
    public static func activeWineRootURL(in libraryFolder: URL = libraryFolder) -> URL {
        activeWineEngine(in: libraryFolder)?.wineURL ?? activeWineURL(in: libraryFolder)
    }

    public static func activeWineEngineName(in libraryFolder: URL = libraryFolder) -> String {
        activeWineEngine(in: libraryFolder)?.displayName ?? activeWineEngineID(in: libraryFolder)
    }

    /// Perform a static capability scan. This intentionally does not claim that a payload has
    /// passed a rendering canary; it only verifies the engine ABI and the complete file layout
    /// needed before a canary can be attempted.
    public static func activeWineGraphicsCapabilities(
        in libraryFolder: URL = libraryFolder
    ) -> WineGraphicsCapabilities {
        guard let engine = activeWineEngine(in: libraryFolder) else {
            return unavailableCapabilities(in: libraryFolder)
        }
        return graphicsCapabilities(for: engine, in: libraryFolder)
    }

    /// Scan a particular bottle-selected engine. `nil` follows the global default; a missing
    /// explicit engine returns `nil` so callers can present a useful configuration error.
    public static func wineGraphicsCapabilities(
        for engineID: String?,
        in libraryFolder: URL = libraryFolder
    ) -> WineGraphicsCapabilities? {
        guard let engine = try? wineEngine(for: engineID, in: libraryFolder) else { return nil }
        return graphicsCapabilities(for: engine, in: libraryFolder)
    }

    static func graphicsCapabilities(
        for engine: WineEngine,
        in libraryFolder: URL = WhiskyWineInstaller.libraryFolder
    ) -> WineGraphicsCapabilities {
        let root = engine.wineURL
        let macDriver = root.appending(path: "lib/wine/x86_64-unix/winemac.so")
        let exportsRequiredAPI = hasExportedSymbol("macdrv_functions", in: macDriver)

        let templateDXMTRoot = engine.kind == .sikarugir
            ? sikarugirTemplateRendererRoot(for: .dxmt, libraryFolder: libraryFolder)
                .flatMap(findDXMTRoot(in:))
            : nil
        let templateD3DMetalRoot = engine.kind == .sikarugir
            ? sikarugirTemplateRendererRoot(for: .d3dmetal, libraryFolder: libraryFolder)
                .flatMap(findD3DMetalRoot(in:))
            : nil

        return WineGraphicsCapabilities(
            engineID: engine.id,
            engineName: engine.displayName,
            wineRootURL: root,
            macDriverExportsRequiredAPI: exportsRequiredAPI,
            dxmtRootURL: findDXMTRoot(in: root)
                ?? installedDXMTRoot(in: libraryFolder)
                ?? templateDXMTRoot,
            d3dmetalRootURL: findD3DMetalRoot(in: root)
                ?? templateD3DMetalRoot
        )
    }

    public static func graphicsBackendAvailability(
        for architecture: BottleArchitecture,
        engineID: String? = nil,
        in libraryFolder: URL = libraryFolder
    ) -> [GraphicsBackendAvailability] {
        let capabilities = wineGraphicsCapabilities(for: engineID, in: libraryFolder)
            ?? unavailableCapabilities(in: libraryFolder)
        let dxvkInstalled = isDXVKInstalled(for: architecture, in: libraryFolder)
        return GraphicsBackend.allCases.map {
            capabilities.availability(
                for: $0,
                architecture: architecture,
                dxvkInstalled: dxvkInstalled
            )
        }
    }

    /// Environment additions required to run the active Wine engine and its selected renderer.
    /// User/program-provided values are merged later by `Wine.constructWineEnvironment`, so these
    /// values establish safe defaults without taking away an explicit override.
    public static func graphicsEnvironment(
        for backend: GraphicsBackend,
        engineID: String? = nil,
        in libraryFolder: URL = libraryFolder
    ) -> [String: String] {
        let engine = try? wineEngine(for: engineID, in: libraryFolder)
        let root = engine?.wineURL ?? activeWineRootURL(in: libraryFolder)
        let wineBinary = engine?.wineBinaryURL ?? activeWineExecutable(in: libraryFolder)
        let wineserver = engine?.wineserverBinaryURL ?? activeWineserverExecutable(in: libraryFolder)
        let capabilities: WineGraphicsCapabilities? = {
            switch backend {
            case .dxmt, .d3dmetal:
                return engine.map { graphicsCapabilities(for: $0, in: libraryFolder) }
            case .wineD3D, .dxvk:
                return nil
            }
        }()

        var result = baseEngineEnvironment(
            root: root,
            wineBinary: wineBinary,
            wineserver: wineserver,
            rendererPaths: rendererDLLPaths(for: backend, capabilities: capabilities)
        )

        if engine?.kind == .sikarugir,
           let frameworks = sikarugirTemplateFrameworksURL(for: libraryFolder) {
            result["DYLD_FALLBACK_LIBRARY_PATH"] = prepend(
                [frameworks.path],
                to: result["DYLD_FALLBACK_LIBRARY_PATH"]
            )
        }

        if engine?.kind == .crossOver {
            if let engine {
                result["CX_ROOT"] = engine.wineURL.path
                result["CX_GRAPHICS_BACKEND"] = backend.crossOverValue
            }
        }

        if backend == .d3dmetal {
            result.merge(
                d3dmetalEnvironment(root: capabilities?.d3dmetalRootURL),
                uniquingKeysWith: { _, newValue in newValue }
            )
        }

        return result
    }

    private static func unavailableCapabilities(in libraryFolder: URL) -> WineGraphicsCapabilities {
        WineGraphicsCapabilities(
            engineID: activeWineEngineID(in: libraryFolder),
            engineName: activeWineEngineName(in: libraryFolder),
            wineRootURL: activeWineURL(in: libraryFolder),
            macDriverExportsRequiredAPI: false,
            dxmtRootURL: nil,
            d3dmetalRootURL: nil
        )
    }

    private static func rendererDLLPaths(
        for backend: GraphicsBackend,
        capabilities: WineGraphicsCapabilities?
    ) -> [URL] {
        switch backend {
        case .dxmt:
            guard let root = capabilities?.dxmtRootURL else { return [] }
            return [root.appending(path: "x86_64-windows"), root.appending(path: "x86_64-unix")]
        case .d3dmetal:
            guard let root = capabilities?.d3dmetalRootURL else { return [] }
            return [root.appending(path: "wine/x86_64-windows"), root.appending(path: "wine/x86_64-unix")]
        case .wineD3D, .dxvk:
            return []
        }
    }

    private static func baseEngineEnvironment(
        root: URL,
        wineBinary: URL,
        wineserver: URL,
        rendererPaths: [URL]
    ) -> [String: String] {
        var pathDirectories = [wineBinary.deletingLastPathComponent()]
        if wineserver.deletingLastPathComponent() != wineBinary.deletingLastPathComponent() {
            pathDirectories.append(wineserver.deletingLastPathComponent())
        }
        let bin = root.appending(path: "bin")
        if FileManager.default.fileExists(atPath: bin.path) {
            pathDirectories.append(bin)
        }

        let baseDLLPaths = [
            root.appending(path: "lib/wine/x86_64-windows"),
            root.appending(path: "lib/wine/x86_64-unix"),
            root.appending(path: "lib/wine/i386-windows"),
            root.appending(path: "lib/wine/i386-unix"),
            root.appending(path: "lib/wine")
        ]
        let dllPaths = (rendererPaths + baseDLLPaths)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)

        return [
            "PATH": prepend(pathDirectories.map(\.path), to: ProcessInfo.processInfo.environment["PATH"]),
            "WINELOADER": wineBinary.path,
            "WINESERVER": wineserver.path,
            "WINEDLLPATH": prepend(dllPaths, to: ProcessInfo.processInfo.environment["WINEDLLPATH"])
        ]
    }

    private static func d3dmetalEnvironment(root: URL?) -> [String: String] {
        guard let root else { return [:] }
        let external = root.appending(path: "external")
        guard FileManager.default.fileExists(atPath: external.path) else { return [:] }

        var result: [String: String] = [:]
        let libraryPath = external.appending(path: "libd3dshared.dylib")
        if FileManager.default.fileExists(atPath: libraryPath.path) {
            result["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = libraryPath.path
            result["GPTK_METAL_LIB_PATH"] = libraryPath.path
        }
        result["DYLD_FALLBACK_LIBRARY_PATH"] = prepend(
            [external.path],
            to: ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"]
        )
        result["DYLD_FALLBACK_FRAMEWORK_PATH"] = prepend(
            [external.path],
            to: ProcessInfo.processInfo.environment["DYLD_FALLBACK_FRAMEWORK_PATH"]
        )
        return result
    }

    /// The renderer directories used by DXMT's builtin/native payloads. Kept internal so the
    /// layout can be unit-tested without requiring an installed renderer.
    static func findDXMTRoot(in wineRoot: URL) -> URL? {
        let candidates = [
            wineRoot,
            wineRoot.appending(path: "wine"),
            wineRoot.appending(path: "lib/dxmt"),
            wineRoot.appending(path: "lib/wine")
        ]
        return candidates.first(where: hasDXMTPayload)
    }

    static func findD3DMetalRoot(in wineRoot: URL) -> URL? {
        let candidates = [
            wineRoot.appending(path: "lib64/apple_gptk"),
            wineRoot.appending(path: "lib/apple_gptk"),
            wineRoot.appending(path: "lib/gptk"),
            wineRoot.appending(path: "lib")
        ]
        return candidates.first(where: hasD3DMetalPayload)
    }

    static func hasDXMTPayload(at root: URL) -> Bool {
        let requiredFiles = [
            "x86_64-unix/winemetal.so",
            "x86_64-windows/winemetal.dll",
            "x86_64-windows/d3d11.dll",
            "x86_64-windows/dxgi.dll"
        ]
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: root.appending(path: $0).path)
        }
    }

    static func hasD3DMetalPayload(at root: URL) -> Bool {
        let commonFiles = [
            "external/D3DMetal.framework",
            "external/libd3dshared.dylib"
        ]
        guard commonFiles.allSatisfy({
            FileManager.default.fileExists(atPath: root.appending(path: $0).path)
        }) else {
            return false
        }

        let windowsFiles = [
            "wine/x86_64-windows/d3d11.dll",
            "wine/x86_64-windows/d3d12.dll",
            "wine/x86_64-windows/dxgi.dll"
        ]
        let unixFiles = [
            "wine/x86_64-unix/d3d11.so",
            "wine/x86_64-unix/d3d12.so",
            "wine/x86_64-unix/dxgi.so"
        ]
        return windowsFiles.allSatisfy { FileManager.default.fileExists(atPath: root.appending(path: $0).path) }
            || unixFiles.allSatisfy { FileManager.default.fileExists(atPath: root.appending(path: $0).path) }
    }

    static func hasExportedSymbol(_ symbol: String, in binary: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: binary.path) else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = ["-gU", binary.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard process.terminationStatus == 0,
              let data = try? output.fileHandleForReading.readToEnd(),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }

        return text.split(whereSeparator: \.isNewline).contains { line in
            let name = line.split(whereSeparator: \.isWhitespace).last.map(String.init)
            return name == symbol || name == "_\(symbol)"
        }
    }

    private static func prepend(_ values: [String], to existing: String?) -> String {
        var result: [String] = []
        for value in values + (existing?.split(separator: ":").map(String.init) ?? []) where !value.isEmpty {
            if !result.contains(value) {
                result.append(value)
            }
        }
        return result.joined(separator: ":")
    }
}
