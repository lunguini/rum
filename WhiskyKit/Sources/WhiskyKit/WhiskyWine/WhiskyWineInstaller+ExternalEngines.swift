//
//  WhiskyWineInstaller+ExternalEngines.swift
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

public enum ExternalWineEngineKind: String, Codable, Equatable, Sendable {
    case crossOver
    case gamePortingToolkit
}

public struct ExternalWineEngine: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let kind: ExternalWineEngineKind
    public let appURL: URL
    public let wineURL: URL
    public let wineBinaryURL: URL
    public let wineserverBinaryURL: URL

    public var displayName: String {
        version.isEmpty ? name : "\(name) \(version)"
    }

    /// Whether the engine's Wine and wineserver binaries still exist on disk. Computed live (not persisted) so a
    /// CrossOver.app that was deleted or moved after import is reported as unavailable. Left out of
    /// the Codable representation on purpose, keeping existing on-disk JSON forward/backward compatible.
    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: wineBinaryURL.path)
            && FileManager.default.fileExists(atPath: wineserverBinaryURL.path)
    }

    public var wineEngine: WineEngine {
        WineEngine(
            id: id,
            name: name,
            version: version,
            kind: kind.wineEngineKind,
            wineURL: wineURL,
            wineBinaryURL: wineBinaryURL,
            wineserverBinaryURL: wineserverBinaryURL
        )
    }
}

extension ExternalWineEngineKind {
    var wineEngineKind: WineEngineKind {
        switch self {
        case .crossOver:
            return .crossOver
        case .gamePortingToolkit:
            return .gamePortingToolkit
        }
    }
}

/// Thread-safe cache for the decoded + refreshed external engine list. The expensive part of
/// `externalWineEngines` (JSON decode plus a CrossOver `Info.plist` parse per engine) runs once per
/// on-disk change; `isAvailable` stays live because it is a computed property on the cached struct.
private final class ExternalEngineCache: @unchecked Sendable {
    static let shared = ExternalEngineCache()

    private let lock = NSLock()
    private var entries: [String: (modificationDate: Date, engines: [ExternalWineEngine])] = [:]

    func engines(
        forKey key: String,
        modificationDate: Date?,
        compute: () -> [ExternalWineEngine]
    ) -> [ExternalWineEngine] {
        lock.lock()
        defer { lock.unlock() }

        // Without a modification date the file is absent; computing is cheap, so skip caching entirely.
        guard let modificationDate else {
            entries[key] = nil
            return compute()
        }

        if let cached = entries[key], cached.modificationDate == modificationDate {
            return cached.engines
        }

        let engines = compute()
        entries[key] = (modificationDate, engines)
        return engines
    }

    func invalidate(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = nil
    }
}

extension WhiskyWineInstaller {
    private static var activeExternalEngineFileName: String { "active-external-wine-engine.json" }
    private static var externalEnginesFileName: String { "external-wine-engines.json" }

    public static func externalWineEngines(in libraryFolder: URL = libraryFolder) -> [ExternalWineEngine] {
        let file = externalEnginesFile(in: libraryFolder)
        let modificationDate = fileModificationDate(file)
        return ExternalEngineCache.shared.engines(
            forKey: libraryFolder.standardizedFileURL.path,
            modificationDate: modificationDate
        ) {
            guard let data = try? Data(contentsOf: file),
                  let engines = try? JSONDecoder().decode([ExternalWineEngine].self, from: data) else {
                return []
            }

            return engines.map(refreshedExternalWineEngine)
        }
    }

    @discardableResult
    public static func importCrossOverEngine(
        at appURL: URL = URL(fileURLWithPath: "/Applications/CrossOver.app"),
        in libraryFolder: URL = libraryFolder
    ) throws -> ExternalWineEngine {
        guard let engine = crossOverEngine(at: appURL) else {
            throw WineManagerError.invalidCrossOverApp(appURL)
        }

        var engines = externalWineEngines(in: libraryFolder).filter { $0.id != engine.id }
        engines.append(engine)
        try saveExternalWineEngines(engines, in: libraryFolder)
        return engine
    }

    @discardableResult
    public static func importGamePortingToolkitEngine(
        at appURL: URL,
        in libraryFolder: URL = libraryFolder
    ) throws -> ExternalWineEngine {
        guard let engine = gamePortingToolkitEngine(at: appURL) else {
            throw WineManagerError.invalidGamePortingToolkitApp(appURL)
        }

        var engines = externalWineEngines(in: libraryFolder).filter { $0.id != engine.id }
        engines.append(engine)
        try saveExternalWineEngines(engines, in: libraryFolder)
        return engine
    }

    public static func defaultCrossOverEngine() -> ExternalWineEngine? {
        crossOverEngine(at: URL(fileURLWithPath: "/Applications/CrossOver.app"))
    }

    public static func defaultGamePortingToolkitEngine() -> ExternalWineEngine? {
        gamePortingToolkitEngine(at: URL(fileURLWithPath: "/Applications/Game Porting Toolkit.app"))
    }

    public static func crossOverEngine(at appURL: URL) -> ExternalWineEngine? {
        let wineURL = appURL.appending(path: "Contents/SharedSupport/CrossOver")
        let hostedApplication = wineURL.appending(path: "CrossOver-Hosted Application")
        let wineBinary = wineURL.appending(path: "lib/wine/x86_64-unix/wine")
        let wineserverBinary = hostedApplication.appending(path: "wineserver")
        guard FileManager.default.fileExists(atPath: wineBinary.path),
              FileManager.default.fileExists(atPath: wineserverBinary.path) else {
            return nil
        }

        let infoURL = appURL.appending(path: "Contents/Info.plist")
        let infoData = try? Data(contentsOf: infoURL)
        let info = infoData.flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        let version = info?["CFBundleShortVersionString"] as? String ?? ""

        return ExternalWineEngine(
            id: "crossover:\(appURL.standardizedFileURL.path)",
            name: "CrossOver",
            version: version,
            kind: .crossOver,
            appURL: appURL,
            wineURL: wineURL,
            wineBinaryURL: wineBinary,
            wineserverBinaryURL: wineserverBinary
        )
    }

    public static func gamePortingToolkitEngine(at appURL: URL) -> ExternalWineEngine? {
        let wineURL = appURL.appending(path: "Contents/Resources/wine")
        let binURL = wineURL.appending(path: "bin")
        let wineCandidates = [binURL.appending(path: "wine"), binURL.appending(path: "wine64")]
        guard let wineBinary = wineCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            return nil
        }
        let wineserverBinary = binURL.appending(path: "wineserver")
        guard FileManager.default.fileExists(atPath: wineserverBinary.path) else {
            return nil
        }

        let infoURL = appURL.appending(path: "Contents/Info.plist")
        let infoData = try? Data(contentsOf: infoURL)
        let info = infoData.flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        let version = info?["CFBundleShortVersionString"] as? String ?? ""

        return ExternalWineEngine(
            id: "gptk:\(appURL.standardizedFileURL.path)",
            name: "Game Porting Toolkit",
            version: version,
            kind: .gamePortingToolkit,
            appURL: appURL,
            wineURL: wineURL,
            wineBinaryURL: wineBinary,
            wineserverBinaryURL: wineserverBinary
        )
    }

    /// The external engine the user selected as active, whether or not its binary still exists.
    /// The UI uses this (plus `ExternalWineEngine.isAvailable`) to show a broken/missing engine;
    /// engine *resolution* should use `activeExternalWineEngine`, which drops a broken engine so
    /// launches fall back to the managed-build symlink instead of a dead path.
    public static func selectedExternalWineEngine(in libraryFolder: URL = libraryFolder) -> ExternalWineEngine? {
        guard let data = try? Data(contentsOf: activeExternalEngineFile(in: libraryFolder)),
              let id = try? JSONDecoder().decode(String.self, from: data) else {
            return nil
        }

        return externalWineEngines(in: libraryFolder).first { $0.id == id }
    }

    public static func activeExternalWineEngine(in libraryFolder: URL = libraryFolder) -> ExternalWineEngine? {
        guard let engine = selectedExternalWineEngine(in: libraryFolder), engine.isAvailable else {
            return nil
        }

        return engine
    }

    public static func activateExternalWineEngine(_ id: String, in libraryFolder: URL = libraryFolder) throws {
        guard let engine = externalWineEngines(in: libraryFolder).first(where: { $0.id == id }) else {
            throw WineManagerError.externalWineEngineNotInstalled(id)
        }

        try activateWineURL(engine.wineURL, in: libraryFolder)
        try saveActiveExternalWineEngineID(id, in: libraryFolder)
        try saveActiveWineEngineID(id, in: libraryFolder)
        try saveActiveWineVersion(engine.displayName, in: libraryFolder)
    }

    public static func activeWineExecutable(in libraryFolder: URL = libraryFolder) -> URL {
        if let engine = activeExternalWineEngine(in: libraryFolder) {
            return engine.wineBinaryURL
        }

        let binFolder = activeWineBinFolder(in: libraryFolder)
        let unified = binFolder.appending(path: "wine")
        if FileManager.default.fileExists(atPath: unified.path) {
            return unified
        }
        return binFolder.appending(path: "wine64")
    }

    public static func activeWineserverExecutable(in libraryFolder: URL = libraryFolder) -> URL {
        if let engine = activeExternalWineEngine(in: libraryFolder) {
            return engine.wineserverBinaryURL
        }

        return activeWineBinFolder(in: libraryFolder).appending(path: "wineserver")
    }

    public static func activeWineBinFolder(in libraryFolder: URL = libraryFolder) -> URL {
        activeWineURL(in: libraryFolder).appending(path: "bin")
    }

    static func activateWineURL(_ selectedWineURL: URL, in libraryFolder: URL) throws {
        if !FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }

        let activeWine = activeWineURL(in: libraryFolder)

        // Build the new symlink at a sibling temp path, then atomically swap it into place with
        // rename(2). A crash or error can only leave the old symlink or the fully-formed new one —
        // never a window with no active Wine at all.
        let stagingLink = libraryFolder.appending(path: ".Wine.\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: stagingLink, withDestinationURL: selectedWineURL)

        do {
            // rename(2) atomically replaces an existing symlink, but fails with ENOTEMPTY if the
            // destination is a real (legacy) directory, so clear that specific case first.
            let isSymlink = (try? activeWine.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
            if !isSymlink && FileManager.default.fileExists(atPath: activeWine.path) {
                try FileManager.default.removeItem(at: activeWine)
            }

            if rename(stagingLink.path, activeWine.path) != 0 {
                let code = errno
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(code),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: stagingLink)
            throw error
        }
    }

    static func clearActiveExternalWineEngine(in libraryFolder: URL) throws {
        let file = activeExternalEngineFile(in: libraryFolder)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private static func externalEnginesFile(in libraryFolder: URL) -> URL {
        libraryFolder.appending(path: externalEnginesFileName)
    }

    private static func activeExternalEngineFile(in libraryFolder: URL) -> URL {
        libraryFolder.appending(path: activeExternalEngineFileName)
    }

    private static func saveExternalWineEngines(_ engines: [ExternalWineEngine], in libraryFolder: URL) throws {
        if !FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(engines)
        try data.write(to: externalEnginesFile(in: libraryFolder))
        ExternalEngineCache.shared.invalidate(forKey: libraryFolder.standardizedFileURL.path)
    }

    private static func fileModificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private static func saveActiveExternalWineEngineID(_ id: String, in libraryFolder: URL) throws {
        if !FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(id)
        try data.write(to: activeExternalEngineFile(in: libraryFolder))
    }

    private static func refreshedExternalWineEngine(_ engine: ExternalWineEngine) -> ExternalWineEngine {
        switch engine.kind {
        case .crossOver:
            return crossOverEngine(at: engine.appURL) ?? engine
        case .gamePortingToolkit:
            return gamePortingToolkitEngine(at: engine.appURL) ?? engine
        }
    }
}
