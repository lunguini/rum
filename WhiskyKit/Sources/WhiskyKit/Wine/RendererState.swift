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
}

struct BottleRendererState: Codable, Equatable, Sendable {
    let backend: GraphicsBackend
    let files: [RendererFileState]
}

enum RendererStateStore {
    private static let stateFileName = ".rum-renderer-state.plist"

    private struct RestoreBackup {
        let destination: URL
        let destinationBackup: URL
        let original: URL
        let originalBackup: URL?
    }

    static func applyDXVK(bottle: Bottle, sourceRoot: URL) throws {
        try apply(
            bottle: bottle,
            backend: .dxvk,
            mappings: sourceMappings(for: bottle, backend: .dxvk, sourceRoot: sourceRoot),
            restoreLegacyDXVKFiles: false
        )
    }

    static func applyDXMT(bottle: Bottle, sourceRoot: URL) throws {
        try apply(
            bottle: bottle,
            backend: .dxmt,
            mappings: sourceMappings(for: bottle, backend: .dxmt, sourceRoot: sourceRoot),
            restoreLegacyDXVKFiles: true
        )
    }

    static func applyD3DMetal(bottle: Bottle, sourceRoot: URL) throws {
        try apply(
            bottle: bottle,
            backend: .d3dmetal,
            mappings: sourceMappings(for: bottle, backend: .d3dmetal, sourceRoot: sourceRoot),
            restoreLegacyDXVKFiles: true
        )
    }

    private static func apply(
        bottle: Bottle,
        backend: GraphicsBackend,
        mappings: [(destination: URL, source: URL)],
        restoreLegacyDXVKFiles: Bool
    ) throws {
        if let state = try load(for: bottle) {
            if state.backend == backend,
               stateMatchesInstalledFiles(state, bottle: bottle, mappings: mappings) {
                return
            }
            try restore(state, for: bottle)
        } else if restoreLegacyDXVKFiles {
            try restoreLegacyDXVK(bottle: bottle, sourceRoot: Wine.dxvkFolder)
        }

        do {
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
            let state = try makeState(for: bottle, backend: backend, mappings: mappings)
            try save(state, for: bottle)
        } catch {
            for mapping in mappings {
                try? FileManager.default.restoreDLLs(
                    in: mapping.destination,
                    from: mapping.source
                )
            }
            throw error
        }
    }

    static func restoreRenderer(bottle: Bottle, sourceRoot: URL) throws {
        if let state = try load(for: bottle) {
            try restore(state, for: bottle)
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
        mappings: [(destination: URL, source: URL)]
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
                files.append(
                    RendererFileState(
                        relativePath: relativePath(of: destinationURL, to: bottle.url),
                        installedSHA256: installedSHA256,
                        originalSHA256: originalSHA256,
                        originalExisted: originalExisted
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

    private static func restore(_ state: BottleRendererState, for bottle: Bottle) throws {
        try validateRestoreState(state, for: bottle)

        let backupDirectory = bottle.url.appending(path: ".rum-renderer-restore-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let backups = try makeRestoreBackups(state, for: bottle, in: backupDirectory)
            do {
                try applyRestore(state, backups: backups)
                try FileManager.default.removeItem(at: stateURL(for: bottle))
            } catch {
                rollbackRestore(backups)
                throw error
            }
            try? FileManager.default.removeItem(at: backupDirectory)
        } catch {
            try? FileManager.default.removeItem(at: backupDirectory)
            throw error
        }
    }

    private static func validateRestoreState(
        _ state: BottleRendererState,
        for bottle: Bottle
    ) throws {
        for file in state.files {
            let destinationURL = try destinationURL(for: file.relativePath, in: bottle)
            guard sha256(of: destinationURL) == file.installedSHA256 else {
                throw RendererStateError.userModifiedFile(destinationURL.path)
            }

            let originalURL = destinationURL.appendingPathExtension("orig")
            if file.originalExisted {
                guard let originalSHA256 = file.originalSHA256,
                      sha256(of: originalURL) == originalSHA256 else {
                    throw RendererStateError.userModifiedFile(originalURL.path)
                }
            } else if FileManager.default.fileExists(atPath: originalURL.path) {
                throw RendererStateError.userModifiedFile(originalURL.path)
            }
        }
    }

    private static func makeRestoreBackups(
        _ state: BottleRendererState,
        for bottle: Bottle,
        in backupDirectory: URL
    ) throws -> [RestoreBackup] {
        var backups: [RestoreBackup] = []
        for (index, file) in state.files.enumerated() {
            let destinationURL = try destinationURL(for: file.relativePath, in: bottle)
            let originalURL = destinationURL.appendingPathExtension("orig")
            let directory = backupDirectory.appending(path: String(index))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destinationBackup = directory.appending(path: "destination")
            try FileManager.default.copyItem(at: destinationURL, to: destinationBackup)
            var originalBackup: URL?
            if file.originalExisted {
                let backup = directory.appending(path: "original")
                try FileManager.default.copyItem(at: originalURL, to: backup)
                originalBackup = backup
            }
            backups.append(
                RestoreBackup(
                    destination: destinationURL,
                    destinationBackup: destinationBackup,
                    original: originalURL,
                    originalBackup: originalBackup
                )
            )
        }
        return backups
    }

    private static func applyRestore(
        _ state: BottleRendererState,
        backups: [RestoreBackup]
    ) throws {
        for (file, backup) in zip(state.files, backups) {
            if file.originalExisted {
                try FileManager.default.removeItem(at: backup.destination)
                try FileManager.default.moveItem(at: backup.original, to: backup.destination)
            } else {
                try FileManager.default.removeItem(at: backup.destination)
            }
        }
    }

    private static func rollbackRestore(_ backups: [RestoreBackup]) {
        for backup in backups.reversed() {
            try? FileManager.default.removeItem(at: backup.destination)
            try? FileManager.default.moveItem(at: backup.destinationBackup, to: backup.destination)
            if let originalBackup = backup.originalBackup {
                try? FileManager.default.removeItem(at: backup.original)
                try? FileManager.default.moveItem(at: originalBackup, to: backup.original)
            }
        }
    }
}

extension RendererStateStore {
    private static func load(for bottle: Bottle) throws -> BottleRendererState? {
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

    private static func stateURL(for bottle: Bottle) -> URL {
        bottle.url.appending(path: stateFileName)
    }

    private static func destinationURL(
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

    private static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
