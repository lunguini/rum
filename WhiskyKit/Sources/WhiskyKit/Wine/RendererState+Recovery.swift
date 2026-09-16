//
//  RendererState+Recovery.swift
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

struct RendererRestoreBackup {
    let destination: URL
    let destinationBackup: URL
    let original: URL
    let originalBackup: URL?
}

struct RendererTransactionBackup {
    let directory: URL
    let paths: [RendererPathBackup]
    let stateExisted: Bool
    let stateBackup: URL?
}

struct RendererPathBackup {
    let path: URL
    let backup: URL?
}

extension RendererStateStore {
    static func validateCurrentState(for bottle: Bottle, engine: WineEngine?) throws {
        guard let state = try load(for: bottle) else { return }
        try validateCurrentState(state, for: bottle, engine: engine)
    }

    static func makeTransactionBackup(
        _ state: BottleRendererState,
        for bottle: Bottle,
        in directory: URL
    ) throws -> RendererTransactionBackup {
        let paths = Set(state.files.flatMap { file -> [URL] in
            guard let destination = try? destinationURL(for: file.relativePath, in: bottle) else { return [] }
            return [destination, destination.appendingPathExtension("orig")]
        })
        return try makeTransactionBackup(for: bottle, paths: paths, in: directory)
    }

    static func makeTransactionBackup(
        for bottle: Bottle,
        paths: Set<URL>,
        in directory: URL
    ) throws -> RendererTransactionBackup {
        var backups: [RendererPathBackup] = []
        for (index, path) in paths.enumerated() {
            guard FileManager.default.fileExists(atPath: path.path) else {
                backups.append(RendererPathBackup(path: path, backup: nil))
                continue
            }
            let backup = directory.appending(path: "path-\(index)")
            try FileManager.default.copyItem(at: path, to: backup)
            backups.append(RendererPathBackup(path: path, backup: backup))
        }
        let state = stateURL(for: bottle)
        let stateBackup: URL?
        if FileManager.default.fileExists(atPath: state.path) {
            let backup = directory.appending(path: "state")
            try FileManager.default.copyItem(at: state, to: backup)
            stateBackup = backup
        } else { stateBackup = nil }
        return RendererTransactionBackup(directory: directory, paths: backups,
                                         stateExisted: stateBackup != nil, stateBackup: stateBackup)
    }

    static func rollbackTransaction(
        _ backup: RendererTransactionBackup,
        for bottle: Bottle,
        mappings: [(destination: URL, source: URL)]
    ) {
        for item in backup.paths { try? FileManager.default.removeItem(at: item.path) }
        for item in backup.paths {
            if let source = item.backup { try? FileManager.default.copyItem(at: source, to: item.path) }
        }
        let state = stateURL(for: bottle)
        try? FileManager.default.removeItem(at: state)
        if let source = backup.stateBackup { try? FileManager.default.copyItem(at: source, to: state) }
    }

    static func validateCurrentState(_ state: BottleRendererState, for bottle: Bottle, engine: WineEngine?) throws {
        try validateRestoreState(state, for: bottle, engine: engine)
    }

    static func restore(
        _ state: BottleRendererState,
        for bottle: Bottle,
        engine: WineEngine?
    ) throws {
        try validateRestoreState(state, for: bottle, engine: engine)

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
        for bottle: Bottle,
        engine: WineEngine?
    ) throws {
        for file in state.files {
            let destinationURL = try destinationURL(for: file.relativePath, in: bottle)
            guard fileMatchesInstalledRenderer(
                file,
                at: destinationURL,
                engine: engine,
                bottleArchitecture: bottle.settings.architecture
            ) else {
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

    /// Wine engines can repopulate a prefix's system32 directories during `wineboot`. Treating
    /// those known engine copies as arbitrary user edits leaves a renderer manifest permanently
    /// stuck and prevents switching backends. They are safe to reconcile because the bytes are
    /// read directly from the selected engine; unknown replacements remain protected.
    private static func fileMatchesInstalledRenderer(
        _ file: RendererFileState,
        at destinationURL: URL,
        engine: WineEngine?,
        bottleArchitecture: BottleArchitecture
    ) -> Bool {
        guard let destinationSHA256 = sha256(of: destinationURL) else { return false }
        if destinationSHA256 == file.installedSHA256 {
            return true
        }
        if file.originalExisted,
           destinationSHA256 == file.originalSHA256 {
            return true
        }

        if file.knownEngineSHA256s.contains(destinationSHA256) {
            return true
        }

        guard let engine else {
            return false
        }

        // Older manifests did not record engine provenance. Accept only exact copies from
        // installed engines when migrating them, including the engine just switched away from.
        let candidates = file.knownEngineSHA256s.isEmpty
            ? [engine] + WhiskyWineInstaller.installedWineEngines() : [engine]
        return candidates.contains { candidate in
            engineBuiltinURLs(for: file.relativePath, engine: candidate,
                              bottleArchitecture: bottleArchitecture).contains {
                sha256(of: $0) == destinationSHA256
            }
        }
    }

    static func engineBuiltinURLs(
        for relativePath: String,
        engine: WineEngine,
        bottleArchitecture: BottleArchitecture
    ) -> [URL] {
        let components = relativePath.split(separator: "/")
        guard components.count == 4,
              components[0] == "drive_c",
              components[1] == "windows" else {
            return []
        }

        let architecture: String
        switch components[2] {
        case "system32":
            architecture = bottleArchitecture == .win32 ? "i386-windows" : "x86_64-windows"
        case "syswow64":
            architecture = "i386-windows"
        default:
            return []
        }

        let filename = String(components[3])
        let wineRoots = [
            engine.wineURL.appending(path: "lib/wine"),
            engine.wineURL.appending(path: "lib64/wine"),
            engine.wineURL.appending(path: "lib32/wine")
        ]
        return wineRoots.map {
            $0.appending(path: architecture).appending(path: filename)
        }
    }

    private static func makeRestoreBackups(
        _ state: BottleRendererState,
        for bottle: Bottle,
        in backupDirectory: URL
    ) throws -> [RendererRestoreBackup] {
        var backups: [RendererRestoreBackup] = []
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
                RendererRestoreBackup(
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
        backups: [RendererRestoreBackup]
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

    private static func rollbackRestore(_ backups: [RendererRestoreBackup]) {
        for backup in backups.reversed() {
            try? FileManager.default.removeItem(at: backup.destination)
            try? FileManager.default.moveItem(at: backup.destinationBackup, to: backup.destination)
            if let originalBackup = backup.originalBackup {
                try? FileManager.default.removeItem(at: backup.original)
                try? FileManager.default.moveItem(at: originalBackup, to: backup.original)
            } else {
                try? FileManager.default.removeItem(at: backup.original)
            }
        }
    }
}
