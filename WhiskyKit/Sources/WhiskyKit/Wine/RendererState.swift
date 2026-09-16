//
//  RendererState.swift
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

import CryptoKit
import Foundation

struct RendererFileState: Codable, Equatable, Sendable {
    let relativePath: String
    let installedSHA256: String
    let originalSHA256: String?
    let originalExisted: Bool
    /// Hashes of Wine's builtin copies seen while this renderer was installed.  These are kept
    /// across engine selection changes so a wineboot refresh from the previous engine is still a
    /// known, safe replacement.
    let knownEngineSHA256s: [String]

    private enum CodingKeys: String, CodingKey {
        case relativePath, installedSHA256, originalSHA256, originalExisted, knownEngineSHA256s
    }

    init(
        relativePath: String,
        installedSHA256: String,
        originalSHA256: String?,
        originalExisted: Bool,
        knownEngineSHA256s: [String] = []
    ) {
        self.relativePath = relativePath
        self.installedSHA256 = installedSHA256
        self.originalSHA256 = originalSHA256
        self.originalExisted = originalExisted
        self.knownEngineSHA256s = knownEngineSHA256s
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        installedSHA256 = try container.decode(String.self, forKey: .installedSHA256)
        originalSHA256 = try container.decodeIfPresent(String.self, forKey: .originalSHA256)
        originalExisted = try container.decode(Bool.self, forKey: .originalExisted)
        knownEngineSHA256s = try container.decodeIfPresent([String].self, forKey: .knownEngineSHA256s) ?? []
    }
}

struct BottleRendererState: Codable, Equatable, Sendable {
    let backend: GraphicsBackend
    let files: [RendererFileState]
}

enum RendererStateStore {
    private static let stateFileName = ".rum-renderer-state.plist"

    static func applyDXVK(
        bottle: Bottle,
        sourceRoot: URL,
        engine: WineEngine? = nil
    ) throws {
        try apply(
            bottle: bottle,
            backend: .dxvk,
            mappings: sourceMappings(for: bottle, backend: .dxvk, sourceRoot: sourceRoot),
            restoreLegacyDXVKFiles: false,
            engine: engine
        )
    }

    static func applyDXMT(
        bottle: Bottle,
        sourceRoot: URL,
        engine: WineEngine? = nil
    ) throws {
        try apply(
            bottle: bottle,
            backend: .dxmt,
            mappings: sourceMappings(for: bottle, backend: .dxmt, sourceRoot: sourceRoot),
            restoreLegacyDXVKFiles: true,
            engine: engine
        )
    }

    static func applyD3DMetal(
        bottle: Bottle,
        sourceRoot: URL,
        engine: WineEngine? = nil
    ) throws {
        try apply(
            bottle: bottle,
            backend: .d3dmetal,
            mappings: sourceMappings(for: bottle, backend: .d3dmetal, sourceRoot: sourceRoot),
            restoreLegacyDXVKFiles: true,
            engine: engine
        )
    }

    private static func apply(
        bottle: Bottle,
        backend: GraphicsBackend,
        mappings: [(destination: URL, source: URL)],
        restoreLegacyDXVKFiles: Bool,
        engine: WineEngine?
    ) throws {
        let previousState = try load(for: bottle)
        if let state = previousState {
            try validateCurrentState(state, for: bottle, engine: engine)
            if state.backend == backend,
               stateMatchesInstalledFiles(state, bottle: bottle, mappings: mappings) {
                return
            }
        }
        let transactionDirectory = bottle.url.appending(path: ".rum-renderer-transaction-\(UUID().uuidString)")
        var transactionBackup: RendererTransactionBackup?
        do {
            let snapshotMappings = mappings + (restoreLegacyDXVKFiles
                ? sourceMappings(for: bottle, backend: .dxvk, sourceRoot: Wine.dxvkFolder) : [])
            let snapshotPaths = try transactionPaths(previousState, bottle: bottle, mappings: snapshotMappings)
            try FileManager.default.createDirectory(
                at: transactionDirectory,
                withIntermediateDirectories: true
            )
            transactionBackup = try makeTransactionBackup(
                for: bottle,
                paths: snapshotPaths,
                in: transactionDirectory
            )
            if let previousState {
                try restore(previousState, for: bottle, engine: engine)
            } else if restoreLegacyDXVKFiles {
                try restoreLegacyDXVK(bottle: bottle, sourceRoot: Wine.dxvkFolder)
            }
            for mapping in mappings {
                try FileManager.default.createDirectory(
                    at: mapping.destination,
                    withIntermediateDirectories: true
                )
                try FileManager.default.replaceDLLs(
                    in: mapping.destination,
                    withContentsIn: mapping.source,
                    makeOriginalCopy: true
                )
            }
            let state = try makeState(for: bottle, backend: backend, mappings: mappings, engine: engine)
            try save(state, for: bottle)
            try? FileManager.default.removeItem(at: transactionDirectory)
        } catch {
            if let transactionBackup {
                rollbackTransaction(transactionBackup, for: bottle, mappings: mappings)
            }
            try? FileManager.default.removeItem(at: transactionDirectory)
            throw error
        }
    }

    private static func transactionPaths(
        _ previousState: BottleRendererState?,
        bottle: Bottle,
        mappings: [(destination: URL, source: URL)]
    ) throws -> Set<URL> {
        var paths = Set<URL>()
        for file in previousState?.files ?? [] {
            let destination = try destinationURL(for: file.relativePath, in: bottle)
            paths.formUnion([destination, destination.appendingPathExtension("orig")])
        }
        for mapping in mappings {
            let enumerator = FileManager.default.enumerator(at: mapping.source, includingPropertiesForKeys: nil)
            while let source = enumerator?.nextObject() as? URL {
                guard source.pathExtension == "dll" else { continue }
                let destination = mapping.destination.appending(path: source.lastPathComponent)
                paths.formUnion([destination, destination.appendingPathExtension("orig")])
            }
        }
        return paths
    }

    static func restoreRenderer(
        bottle: Bottle,
        sourceRoot: URL,
        engine: WineEngine? = nil
    ) throws {
        if let state = try load(for: bottle) {
            try restore(state, for: bottle, engine: engine)
            return
        }

        try restoreLegacyDXVK(bottle: bottle, sourceRoot: sourceRoot)
    }

    /// Compatibility entry point for callers that only know about the legacy DXVK toggle.
    static func restoreDXVK(bottle: Bottle, sourceRoot: URL) throws {
        try restoreRenderer(bottle: bottle, sourceRoot: sourceRoot)
    }

    private static func restoreLegacyDXVK(bottle: Bottle, sourceRoot: URL) throws {
        let mappings = sourceMappings(for: bottle, backend: .dxvk, sourceRoot: sourceRoot)
        for mapping in mappings {
            try FileManager.default.restoreDLLs(
                in: mapping.destination,
                from: mapping.source
            )
        }
    }
}

extension RendererStateStore {
    private static func sourceMappings(
        for bottle: Bottle,
        backend: GraphicsBackend,
        sourceRoot: URL
    ) -> [(destination: URL, source: URL)] {
        let system32 = bottle.url.appending(path: "drive_c/windows/system32")
        let syswow64 = bottle.url.appending(path: "drive_c/windows/syswow64")

        switch backend {
        case .dxvk:
            if bottle.settings.architecture == .win32 {
                return [(system32, sourceRoot.appending(path: "x32"))]
            }
            return [
                (system32, sourceRoot.appending(path: "x64")),
                (syswow64, sourceRoot.appending(path: "x32"))
            ]
        case .dxmt:
            var mappings = [
                (system32, sourceRoot.appending(path: "x86_64-windows"))
            ]
            let x86 = sourceRoot.appending(path: "i386-windows")
            if FileManager.default.fileExists(atPath: x86.path) {
                mappings.append((syswow64, x86))
            }
            return mappings
        case .d3dmetal:
            return [
                (system32, sourceRoot.appending(path: "wine/x86_64-windows"))
            ]
        case .wineD3D:
            return []
        }
    }

    private static func makeState(
        for bottle: Bottle,
        backend: GraphicsBackend,
        mappings: [(destination: URL, source: URL)],
        engine: WineEngine?
    ) throws -> BottleRendererState {
        var files: [RendererFileState] = []
        for mapping in mappings {
            let enumerator = FileManager.default.enumerator(
                at: mapping.source,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            while let sourceURL = enumerator?.nextObject() as? URL {
                guard sourceURL.pathExtension == "dll" else { continue }
                let destinationURL = mapping.destination.appending(path: sourceURL.lastPathComponent)
                guard let installedSHA256 = sha256(of: sourceURL),
                      FileManager.default.fileExists(atPath: destinationURL.path) else {
                    throw RendererStateError.invalidManifest(destinationURL.path)
                }
                let originalURL = destinationURL.appendingPathExtension("orig")
                let originalExisted = FileManager.default.fileExists(atPath: originalURL.path)
                let originalSHA256 = originalExisted ? sha256(of: originalURL) : nil
                if originalExisted && originalSHA256 == nil {
                    throw RendererStateError.invalidManifest(originalURL.path)
                }
                var knownEngineSHA256s: [String] = []
                if let engine {
                    for engineURL in engineBuiltinURLs(
                        for: relativePath(of: destinationURL, to: bottle.url),
                        engine: engine,
                        bottleArchitecture: bottle.settings.architecture
                    ) {
                        if let hash = sha256(of: engineURL) { knownEngineSHA256s.append(hash) }
                    }
                }
                files.append(
                    RendererFileState(
                        relativePath: relativePath(of: destinationURL, to: bottle.url),
                        installedSHA256: installedSHA256,
                        originalSHA256: originalSHA256,
                        originalExisted: originalExisted,
                        knownEngineSHA256s: knownEngineSHA256s
                    )
                )
            }
        }
        guard !files.isEmpty else {
            throw RendererStateError.invalidManifest("No \(backend.displayName) renderer DLLs were installed.")
        }
        return BottleRendererState(backend: backend, files: files)
    }

    private static func stateMatchesInstalledFiles(
        _ state: BottleRendererState,
        bottle: Bottle,
        mappings: [(destination: URL, source: URL)]
    ) -> Bool {
        let installed = state.files.reduce(into: [String: String]()) { result, file in
            result[file.relativePath] = file.installedSHA256
        }
        var current: [String: String] = [:]
        for mapping in mappings {
            let enumerator = FileManager.default.enumerator(
                at: mapping.source,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            while let sourceURL = enumerator?.nextObject() as? URL {
                guard sourceURL.pathExtension == "dll" else { continue }
                let destinationURL = mapping.destination.appending(path: sourceURL.lastPathComponent)
                guard let sourceHash = sha256(of: sourceURL),
                      let destinationHash = sha256(of: destinationURL) else {
                    return false
                }
                let path = relativePath(of: destinationURL, to: bottle.url)
                guard sourceHash == installed[path], destinationHash == installed[path] else {
                    return false
                }
                current[path] = destinationHash
            }
        }
        return current == installed
    }

}

extension RendererStateStore {
    static func load(for bottle: Bottle) throws -> BottleRendererState? {
        let url = stateURL(for: bottle)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try PropertyListDecoder().decode(
                BottleRendererState.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw RendererStateError.invalidManifest(url.path)
        }
    }

    private static func save(_ state: BottleRendererState, for bottle: Bottle) throws {
        let data = try PropertyListEncoder().encode(state)
        try data.write(to: stateURL(for: bottle), options: .atomic)
    }

    static func stateURL(for bottle: Bottle) -> URL {
        bottle.url.appending(path: stateFileName)
    }

    static func destinationURL(
        for relativePath: String,
        in bottle: Bottle
    ) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains(where: { $0 == "." || $0 == ".." }) else {
            throw RendererStateError.invalidManifest(relativePath)
        }

        let root = bottle.url.standardizedFileURL
        let destination = root.appending(path: relativePath).standardizedFileURL
        let rootPath = root.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard destination.path(percentEncoded: false).hasPrefix(prefix) else {
            throw RendererStateError.invalidManifest(relativePath)
        }
        return destination
    }

    private static func relativePath(of url: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let urlPath = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return urlPath.hasPrefix(prefix) ? String(urlPath.dropFirst(prefix.count)) : urlPath
    }

    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
