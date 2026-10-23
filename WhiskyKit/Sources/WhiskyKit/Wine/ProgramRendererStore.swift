//
//  ProgramRendererStore.swift
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

/// Renderer DLLs Rum put next to a program, recorded in that folder so they can be swapped or
/// taken away later without losing anything that was there before.
struct ProgramFolderRendererState: Codable, Equatable {
    struct File: Codable, Equatable {
        let name: String
        let installedSHA256: String
        /// The folder's own copy, moved aside to `<name>.rum-orig` while Rum's is in place.
        let hadOriginal: Bool
    }

    let backend: GraphicsBackend
    let files: [File]
}

enum ProgramRendererError: LocalizedError {
    case unexpectedFile(String)
    case folderInUse(String, GraphicsBackend?)

    var errorDescription: String? {
        switch self {
        case .unexpectedFile(let path):
            return "Rum didn't expect \(path) and won't overwrite it. Move it away and try again."
        case .folderInUse(let folder, let backend):
            let renderer = backend.map { "with \($0.displayName)" } ?? "with the bottle's renderer"
            return "Another program in “\(folder)” is running \(renderer). "
                + "Programs sharing a folder share its renderer files; quit it first."
        }
    }
}

enum ProgramRendererStore {
    static let stateFileName = ".rum-renderer.plist"
    static let originalExtension = "rum-orig"

    /// Puts `backend`'s DLLs from `source` in `folder`, replacing another renderer put there before.
    static func install(_ backend: GraphicsBackend, from source: URL, in folder: URL) throws {
        let sources = try dlls(in: source)
        guard !sources.isEmpty else {
            throw GraphicsBackendError.unavailable(backend, "No renderer files in \(source.path).")
        }
        if let state = try load(in: folder) {
            if state.backend == backend, isIntact(state, in: folder, sources: sources) { return }
            try remove(state, in: folder)
        }

        var installed: [ProgramFolderRendererState.File] = []
        do {
            for sourceURL in sources {
                let destination = folder.appending(path: sourceURL.lastPathComponent)
                guard let hash = RendererStateStore.sha256(of: sourceURL) else {
                    throw RendererStateError.invalidManifest(sourceURL.path)
                }
                let hadOriginal = FileManager.default.fileExists(atPath: destination.path(percentEncoded: false))
                if hadOriginal {
                    let backup = destination.appendingPathExtension(originalExtension)
                    guard !FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) else {
                        throw ProgramRendererError.unexpectedFile(backup.path(percentEncoded: false))
                    }
                    try FileManager.default.moveItem(at: destination, to: backup)
                }
                // Recorded before copying, so a failure below still puts the original back.
                installed.append(.init(name: sourceURL.lastPathComponent, installedSHA256: hash,
                                       hadOriginal: hadOriginal))
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            }
            try save(ProgramFolderRendererState(backend: backend, files: installed), in: folder)
        } catch {
            try? remove(ProgramFolderRendererState(backend: backend, files: installed), in: folder)
            throw error
        }
    }

    /// Takes away the renderer Rum put in `folder`, if any, and puts the folder's own files back.
    static func uninstall(in folder: URL) throws {
        guard let state = try load(in: folder) else { return }
        try remove(state, in: folder)
    }

    static func load(in folder: URL) throws -> ProgramFolderRendererState? {
        let url = folder.appending(path: stateFileName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try PropertyListDecoder().decode(ProgramFolderRendererState.self, from: Data(contentsOf: url))
    }

    /// A file that changed since Rum put it there (a game update, a mod) is left alone, and so is
    /// the original it replaced.
    private static func remove(_ state: ProgramFolderRendererState, in folder: URL) throws {
        for file in state.files {
            let destination = folder.appending(path: file.name)
            let path = destination.path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: path) {
                guard RendererStateStore.sha256(of: destination) == file.installedSHA256 else { continue }
                try FileManager.default.removeItem(at: destination)
            }
            let backup = destination.appendingPathExtension(originalExtension)
            if file.hadOriginal, FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) {
                try FileManager.default.moveItem(at: backup, to: destination)
            }
        }
        let stateURL = folder.appending(path: stateFileName)
        if FileManager.default.fileExists(atPath: stateURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: stateURL)
        }
    }

    /// Whether the folder still holds exactly this renderer's current files.
    private static func isIntact(_ state: ProgramFolderRendererState, in folder: URL, sources: [URL]) -> Bool {
        guard state.files.map(\.name) == sources.map(\.lastPathComponent) else { return false }
        return zip(state.files, sources).allSatisfy { file, source in
            RendererStateStore.sha256(of: source) == file.installedSHA256
                && RendererStateStore.sha256(of: folder.appending(path: file.name)) == file.installedSHA256
        }
    }

    private static func dlls(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "dll" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func save(_ state: ProgramFolderRendererState, in folder: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(state).write(to: folder.appending(path: stateFileName))
    }
}

/// Keeps a program folder's renderer files steady while anything launched from it runs.
actor ProgramRendererCoordinator {
    static let shared = ProgramRendererCoordinator()

    private struct FolderState {
        /// The renderer Rum put in the folder, or nil when the folder has none of Rum's files.
        let backend: GraphicsBackend?
        var users = 1
    }
    private var folders: [String: FolderState] = [:]

    /// Readies `folder` for a launch: `backend`'s files when the program needs them next to it,
    /// none otherwise.
    func acquire(folder: URL, placement: ProgramRendererPlacement, backend: GraphicsBackend) throws {
        let key = folder.standardizedFileURL.path(percentEncoded: false)
        let local: GraphicsBackend? = if case .programFolder = placement { backend } else { nil }
        if let active = folders[key] {
            guard active.backend == local else {
                throw ProgramRendererError.folderInUse(folder.lastPathComponent, active.backend)
            }
            folders[key]?.users += 1
            return
        }
        if case .programFolder(let source) = placement {
            try ProgramRendererStore.install(backend, from: source, in: folder)
        } else {
            try ProgramRendererStore.uninstall(in: folder)
        }
        folders[key] = FolderState(backend: local)
    }

    func release(folder: URL) {
        let key = folder.standardizedFileURL.path(percentEncoded: false)
        guard let active = folders[key] else { return }
        if active.users > 1 {
            folders[key]?.users -= 1
        } else {
            folders[key] = nil
        }
    }
}
