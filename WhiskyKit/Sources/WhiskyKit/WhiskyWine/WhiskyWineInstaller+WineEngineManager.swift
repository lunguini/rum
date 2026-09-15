//
//  WhiskyWineInstaller+WineEngineManager.swift
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
    static let activeVersionFileName = "active-wine-version.json"
    static let activeEngineFileName = "active-wine-engine.json"
    static let wineBuildsFolderName = "WineBuilds"
    static let engineMetadataFileName = "engine.json"
    static let githubReleasesURL = "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases"
    static let sikarugirReleasesURL = "https://api.github.com/repos/Sikarugir-App/Engines/releases"

    /// The global default engine identifier. A bottle with no pinned engine follows this value.
    /// The old version file remains a fallback for installations created before engine identity
    /// was persisted.
    public static func activeWineEngineID(in libraryFolder: URL = libraryFolder) -> String {
        if let external = activeExternalWineEngine(in: libraryFolder) {
            return external.id
        }

        if let id = storedActiveWineEngineID(in: libraryFolder) {
            return id
        }

        if let version = activeWineVersion(in: libraryFolder) {
            return WineEngine.managedID(kind: .gcenx, version: version)
        }

        return "managed-wine"
    }

    /// The usable global default engine, resolved from the persisted identifier and legacy files.
    public static func activeWineEngine(in libraryFolder: URL = libraryFolder) -> WineEngine? {
        if let external = activeExternalWineEngine(in: libraryFolder) {
            return external.wineEngine
        }

        let id = activeWineEngineID(in: libraryFolder)
        if let managed = installedWineBuilds(in: libraryFolder).first(where: { $0.id == id }) {
            return managed.wineEngine
        }

        // A pre-engine-manager install may have a valid active symlink but no version metadata.
        let root = activeWineURL(in: libraryFolder)
        let wine = root.appending(path: "bin/wine")
        let wine64 = root.appending(path: "bin/wine64")
        let wineserver = root.appending(path: "bin/wineserver")
        guard FileManager.default.fileExists(atPath: wine.path)
                || FileManager.default.fileExists(atPath: wine64.path),
              FileManager.default.fileExists(atPath: wineserver.path) else {
            return nil
        }
        return WineEngine(
            id: id,
            name: WineEngineKind.gcenx.displayName,
            version: activeWineVersion(in: libraryFolder) ?? "",
            kind: .gcenx,
            wineURL: root,
            wineBinaryURL: FileManager.default.fileExists(atPath: wine.path) ? wine : wine64,
            wineserverBinaryURL: wineserver
        )
    }

    /// All installed runtimes, including external engines imported into the manager.
    public static func installedWineEngines(in libraryFolder: URL = libraryFolder) -> [WineEngine] {
        installedWineBuilds(in: libraryFolder).map(\.wineEngine)
            + externalWineEngines(in: libraryFolder).map(\.wineEngine)
    }

    /// Resolve a bottle's optional engine pin. A missing pinned engine is an explicit error so a
    /// user never silently launches a bottle with the wrong runtime after uninstalling its engine.
    public static func wineEngine(
        for engineID: String?,
        in libraryFolder: URL = libraryFolder
    ) throws -> WineEngine {
        if let engineID {
            guard let engine = installedWineEngines(in: libraryFolder).first(where: { $0.id == engineID }),
                  engine.isAvailable else {
                throw WineManagerError.wineEngineNotInstalled(engineID)
            }
            return engine
        }

        guard let engine = activeWineEngine(in: libraryFolder), engine.isAvailable else {
            throw WineManagerError.noWineEngineInstalled
        }
        return engine
    }

    public static func wineEngine(withID id: String, in libraryFolder: URL = libraryFolder) -> WineEngine? {
        installedWineEngines(in: libraryFolder).first { $0.id == id }
    }

    /// Fetch the latest Gcenx release that has a Wine Staging asset.
    /// Falls back to wine-devel if no staging build is available.
    public static func fetchLatestRelease() async -> (version: String, downloadURL: URL)? {
        guard let release = await fetchAvailableWineReleases().first else { return nil }
        return (release.version, release.downloadURL)
    }

    public static func fetchAvailableWineReleases() async -> [WineRelease] {
        guard let url = URL(string: githubReleasesURL) else { return [] }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let releases = try JSONDecoder().decode([GcenxRelease].self, from: data)
            return availableWineReleases(from: releases)
        } catch {
            print("Failed to fetch Gcenx releases: \(error)")
        }

        return []
    }

    public static func availableWineReleases(from releases: [GcenxRelease]) -> [WineRelease] {
        releases.compactMap { release in
            if release.tagName.contains("-rc") { return nil }

            let stagingAsset = release.assets.first {
                $0.name.contains("wine-staging") && $0.name.hasSuffix("-osx64.tar.xz")
            }
            let develAsset = release.assets.first {
                $0.name.contains("wine-devel") && $0.name.hasSuffix("-osx64.tar.xz")
            }

            guard let asset = stagingAsset ?? develAsset,
                  let downloadURL = URL(string: asset.browserDownloadUrl) else {
                return nil
            }

            return WineRelease(
                kind: .gcenx,
                version: release.tagName,
                downloadURL: downloadURL,
                assetName: asset.name,
                size: asset.size
            )
        }
        .sorted { compareWineVersions($0.version, $1.version) == .orderedDescending }
    }

    public static func fetchAvailableSikarugirReleases() async -> [WineRelease] {
        guard let url = URL(string: sikarugirReleasesURL) else { return [] }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let releases = try JSONDecoder().decode([GcenxRelease].self, from: data)
            return availableSikarugirReleases(from: releases)
        } catch {
            print("Failed to fetch Sikarugir releases: \(error)")
        }

        return []
    }

    public static func availableSikarugirReleases(from releases: [GcenxRelease]) -> [WineRelease] {
        var seenAssets = Set<String>()
        return releases.flatMap { release in
            release.assets.compactMap { asset -> WineRelease? in
                let lowercasedName = asset.name.lowercased()
                guard lowercasedName.contains("winesikarugir"),
                      lowercasedName.hasSuffix(".tar.xz"),
                      seenAssets.insert(asset.name).inserted,
                      let downloadURL = URL(string: asset.browserDownloadUrl) else {
                    return nil
                }

                let version = asset.name.replacingOccurrences(of: ".tar.xz", with: "")
                return WineRelease(
                    kind: .sikarugir,
                    version: version,
                    downloadURL: downloadURL,
                    assetName: asset.name,
                    size: asset.size
                )
            }
        }
        .sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }

    static func activeVersionFile(in libraryFolder: URL) -> URL {
        libraryFolder.appending(path: activeVersionFileName)
    }

    static func legacyVersionFile(in libraryFolder: URL) -> URL {
        libraryFolder.appending(path: "wine-version.json")
    }

    static func wineURL(for version: String, in libraryFolder: URL) -> URL {
        wineURL(for: version, kind: .gcenx, in: libraryFolder)
    }

    static func wineURL(for version: String, kind: WineEngineKind, in libraryFolder: URL) -> URL {
        wineBuildsFolder(in: libraryFolder)
            .appending(path: managedWineDirectoryName(for: version, kind: kind))
            .appending(path: "Wine")
    }

    static func managedWineDirectoryName(for version: String, kind: WineEngineKind) -> String {
        let safeVersion = sanitizedPathComponent(version)
        switch kind {
        case .gcenx:
            return safeVersion
        case .sikarugir:
            return "sikarugir-\(safeVersion)"
        case .crossOver, .gamePortingToolkit, .custom:
            return "\(kind.rawValue)-\(safeVersion)"
        }
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let result = value.unicodeScalars.reduce(into: "") { result, scalar in
            result.append(allowed.contains(scalar) ? Character(String(scalar)) : "-")
        }
        return result.isEmpty || result == "." || result == ".." ? UUID().uuidString : result
    }

    private static func storedActiveWineEngineID(in libraryFolder: URL) -> String? {
        guard let data = try? Data(contentsOf: activeEngineFile(in: libraryFolder)) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    static func saveActiveWineEngineID(_ id: String, in libraryFolder: URL) throws {
        if !FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(id)
        try data.write(to: activeEngineFile(in: libraryFolder))
    }

    private static func activeEngineFile(in libraryFolder: URL) -> URL {
        libraryFolder.appending(path: activeEngineFileName)
    }

    static func writeEngineMetadata(_ metadata: InstalledWineEngineMetadata, at directory: URL) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: directory.appending(path: engineMetadataFileName))
    }

    static func readEngineMetadata(at directory: URL) -> InstalledWineEngineMetadata? {
        let file = directory.appending(path: engineMetadataFileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(InstalledWineEngineMetadata.self, from: data)
    }

    static func wineBuildsFolder(in libraryFolder: URL) -> URL {
        libraryFolder.appending(path: wineBuildsFolderName)
    }

    static func compareWineVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue > rightValue { return .orderedDescending }
            if leftValue < rightValue { return .orderedAscending }
        }
        return lhs.compare(rhs)
    }
}
