//
//  WhiskyWineInstaller+WineManager.swift
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

public struct InstalledWineBuild: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: WineEngineKind
    public let version: String
    public let wineURL: URL
    public let isActive: Bool

    public var displayName: String {
        version.isEmpty ? name : "\(name) \(version)"
    }

    public var wineEngine: WineEngine {
        WineEngine(
            id: id,
            name: name,
            version: version,
            kind: kind,
            wineURL: wineURL,
            wineBinaryURL: FileManager.default.fileExists(atPath: wineURL.appending(path: "bin/wine").path)
                ? wineURL.appending(path: "bin/wine")
                : wineURL.appending(path: "bin/wine64"),
            wineserverBinaryURL: wineURL.appending(path: "bin/wineserver")
        )
    }

    init(
        id: String,
        name: String,
        kind: WineEngineKind,
        version: String,
        wineURL: URL,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.version = version
        self.wineURL = wineURL
        self.isActive = isActive
    }

    init(version: String, wineURL: URL, isActive: Bool) {
        self.init(
            id: WineEngine.managedID(kind: .gcenx, version: version),
            name: WineEngineKind.gcenx.displayName,
            kind: .gcenx,
            version: version,
            wineURL: wineURL,
            isActive: isActive
        )
    }
}

public struct WineRelease: Identifiable, Equatable, Sendable {
    public var id: String { WineEngine.managedID(kind: kind, version: version) }
    public let kind: WineEngineKind
    public let version: String
    public let downloadURL: URL
    public let assetName: String
    public let size: Int

    public var displayName: String {
        version.isEmpty ? kind.displayName : "\(kind.displayName) \(version)"
    }

    public init(
        kind: WineEngineKind = .gcenx,
        version: String,
        downloadURL: URL,
        assetName: String,
        size: Int
    ) {
        self.kind = kind
        self.version = version
        self.downloadURL = downloadURL
        self.assetName = assetName
        self.size = size
    }
}

public enum WineManagerError: Error, LocalizedError {
    case wineVersionNotInstalled(String)
    case cannotRemoveActiveWineVersion(String)
    case externalWineEngineNotInstalled(String)
    case invalidCrossOverApp(URL)
    case invalidGamePortingToolkitApp(URL)
    case wineEngineNotInstalled(String)
    case noWineEngineInstalled
    case invalidWineArchive
    case invalidGraphicsRuntimeArchive(String)
    case sikarugirSupportNotInstalled

    public var errorDescription: String? {
        switch self {
        case .wineVersionNotInstalled(let version):
            return "Wine \(version) is not installed."
        case .cannotRemoveActiveWineVersion(let version):
            return "Wine \(version) is active and cannot be removed."
        case .externalWineEngineNotInstalled(let id):
            return "External Wine engine \(id) is not installed."
        case .invalidCrossOverApp(let url):
            return "\(url.path) is not a valid CrossOver app."
        case .invalidGamePortingToolkitApp(let url):
            return "\(url.path) is not a valid Game Porting Toolkit app."
        case .wineEngineNotInstalled(let id):
            return "Wine engine \(id) is not installed."
        case .noWineEngineInstalled:
            return "No usable Wine engine is installed. Open Wine Manager to install one."
        case .invalidWineArchive:
            return "The downloaded archive does not contain a usable Wine engine."
        case .invalidGraphicsRuntimeArchive(let name):
            return "The downloaded archive does not contain a usable \(name) runtime."
        case .sikarugirSupportNotInstalled:
            return "Sikarugir support libraries could not be installed. "
                + "Install the Sikarugir template or choose another engine."
        }
    }
}

extension WhiskyWineInstaller {
    /// Save the installed version string to disk
    public static func saveInstalledVersion(_ version: String) {
        do {
            try saveActiveWineVersion(version, in: libraryFolder)
        } catch {
            print("Failed to save active wine version: \(error)")
        }
    }

    public static func saveActiveWineVersion(_ version: String, in libraryFolder: URL = libraryFolder) throws {
        let info = InstalledWineVersion(version: version)
        let data = try JSONEncoder().encode(info)
        if !FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }
        try data.write(to: activeVersionFile(in: libraryFolder))
        try data.write(to: legacyVersionFile(in: libraryFolder))
    }

    /// Read the locally installed version string.
    public static func installedWineVersion() -> String? {
        installedWineVersion(in: libraryFolder)
    }

    public static func installedWineVersion(in libraryFolder: URL) -> String? {
        if let engine = activeExternalWineEngine(in: libraryFolder) {
            return engine.displayName
        }

        if let version = activeWineVersion(in: libraryFolder) {
            return version
        }

        if let data = try? Data(contentsOf: legacyVersionFile(in: libraryFolder)),
           let info = try? JSONDecoder().decode(InstalledWineVersion.self, from: data) {
            return info.version
        }

        let wineUnified = activeWineURL(in: libraryFolder).appending(path: "bin/wine")
        let wineLegacy = activeWineURL(in: libraryFolder).appending(path: "bin/wine64")
        if FileManager.default.fileExists(atPath: wineUnified.path)
            || FileManager.default.fileExists(atPath: wineLegacy.path) {
            return "unknown"
        }

        return nil
    }

    public static func activeWineVersion(in libraryFolder: URL = libraryFolder) -> String? {
        guard let data = try? Data(contentsOf: activeVersionFile(in: libraryFolder)),
              let info = try? JSONDecoder().decode(InstalledWineVersion.self, from: data) else {
            return nil
        }
        return info.version
    }

    public static func installedWineBuilds(in libraryFolder: URL = libraryFolder) -> [InstalledWineBuild] {
        try? migrateLegacyWineIfNeeded(in: libraryFolder)
        let buildsFolder = wineBuildsFolder(in: libraryFolder)
        let activeID = activeWineEngineID(in: libraryFolder)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: buildsFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { versionURL in
            let wineURL = versionURL.appending(path: "Wine")
            let wine = wineURL.appending(path: "bin/wine")
            let wine64 = wineURL.appending(path: "bin/wine64")
            guard FileManager.default.fileExists(atPath: wine.path)
                    || FileManager.default.fileExists(atPath: wine64.path) else {
                return nil
            }
            let version = versionURL.lastPathComponent
            let metadata = readEngineMetadata(at: versionURL)
            let kind = metadata?.kind ?? .gcenx
            let metadataVersion = metadata?.version ?? version
            let id = metadata?.id ?? WineEngine.managedID(kind: kind, version: metadataVersion)
            let name = metadata?.name ?? kind.displayName
            return InstalledWineBuild(
                id: id,
                name: name,
                kind: kind,
                version: metadataVersion,
                wineURL: wineURL,
                isActive: id == activeID
            )
        }
        .sorted {
            compareWineVersions($0.version, $1.version) == .orderedDescending
                || ($0.version == $1.version && $0.id < $1.id)
        }
    }

    public static func activateWineVersion(_ version: String, in libraryFolder: URL = libraryFolder) throws {
        guard let build = installedWineBuilds(in: libraryFolder)
            .first(where: { $0.version == version && $0.kind == .gcenx })
                ?? installedWineBuilds(in: libraryFolder).first(where: { $0.version == version }) else {
            throw WineManagerError.wineVersionNotInstalled(version)
        }

        try activateWineEngine(build.id, in: libraryFolder)
    }

    public static func activateWineEngine(_ id: String, in libraryFolder: URL = libraryFolder) throws {
        guard let build = installedWineBuilds(in: libraryFolder).first(where: { $0.id == id }) else {
            throw WineManagerError.wineEngineNotInstalled(id)
        }

        try activateWineURL(build.wineURL, in: libraryFolder)
        try clearActiveExternalWineEngine(in: libraryFolder)
        try saveActiveWineEngineID(build.id, in: libraryFolder)
        try saveActiveWineVersion(build.version, in: libraryFolder)
    }

    public static func migrateLegacyWineIfNeeded(in libraryFolder: URL = libraryFolder) throws {
        let activeWine = activeWineURL(in: libraryFolder)
        let isSymlink = (try? activeWine.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        guard !isSymlink else { return }

        let wine = activeWine.appending(path: "bin/wine")
        let wine64 = activeWine.appending(path: "bin/wine64")
        guard FileManager.default.fileExists(atPath: wine.path)
                || FileManager.default.fileExists(atPath: wine64.path) else {
            return
        }

        let version = installedWineVersion(in: libraryFolder) ?? "unknown"
        let versionedWine = wineURL(for: version, in: libraryFolder)
        if FileManager.default.fileExists(atPath: versionedWine.path) {
            try FileManager.default.removeItem(at: activeWine)
            try activateWineVersion(version, in: libraryFolder)
            return
        }

        try FileManager.default.createDirectory(
            at: versionedWine.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: activeWine, to: versionedWine)
        try writeEngineMetadata(
            InstalledWineEngineMetadata(
                id: WineEngine.managedID(kind: .gcenx, version: version),
                name: WineEngineKind.gcenx.displayName,
                version: version,
                kind: .gcenx
            ),
            at: versionedWine.deletingLastPathComponent()
        )
        do {
            try activateWineVersion(version, in: libraryFolder)
        } catch {
            // Roll the move back so a failed activation doesn't strand ~1 GB of Wine under
            // WineBuilds/ with no usable active symlink (the app would then report Wine as
            // uninstalled). If activation got as far as swapping in the new symlink, drop it first
            // so the legacy directory can move back into its original place.
            if (try? activeWine.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try? FileManager.default.removeItem(at: activeWine)
            }
            try? FileManager.default.moveItem(at: versionedWine, to: activeWine)
            throw error
        }
    }

    public static func removeWineVersion(_ version: String, in libraryFolder: URL = libraryFolder) throws {
        guard let build = installedWineBuilds(in: libraryFolder).first(where: { $0.version == version }) else {
            throw WineManagerError.wineVersionNotInstalled(version)
        }
        try removeWineEngine(build.id, in: libraryFolder)
    }

    public static func removeWineEngine(_ id: String, in libraryFolder: URL = libraryFolder) throws {
        guard let build = installedWineBuilds(in: libraryFolder).first(where: { $0.id == id }) else {
            throw WineManagerError.wineEngineNotInstalled(id)
        }

        if activeWineEngineID(in: libraryFolder) == id {
            throw WineManagerError.cannotRemoveActiveWineVersion(build.displayName)
        }

        let selectedWineURL = build.wineURL
        let versionDir = selectedWineURL.deletingLastPathComponent()

        // `activeWineVersion` is nil for legacy installs, so also resolve the Libraries/Wine symlink
        // and refuse when it points inside the directory being removed — otherwise we'd leave the
        // active symlink dangling.
        if symlinkResolves(activeWineURL(in: libraryFolder), inside: versionDir) {
            throw WineManagerError.cannotRemoveActiveWineVersion(build.displayName)
        }

        if FileManager.default.fileExists(atPath: selectedWineURL.path) {
            try FileManager.default.removeItem(at: versionDir)
        }
    }

    private static func symlinkResolves(_ symlink: URL, inside directory: URL) -> Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: symlink.path) else {
            return false
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: symlink.deletingLastPathComponent())
            .standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return resolved == directoryPath || resolved.hasPrefix(directoryPath + "/")
    }

    static func activeWineURL(in libraryFolder: URL) -> URL {
        libraryFolder.appending(path: "Wine")
    }
}
