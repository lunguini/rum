//
//  WhiskyWineInstaller.swift
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

public struct GcenxRelease: Codable, Sendable {
    public let tagName: String
    public let assets: [GcenxAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

public struct GcenxAsset: Codable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

public struct InstalledWineVersion: Codable {
    public var version: String
}

public class WhiskyWineInstaller {
    /// The Whisky application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.whiskyBundleIdentifier)

    /// The folder of all the library files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    public static func isWhiskyWineInstalled() -> Bool {
        return installedWineVersion() != nil
    }

    /// Install a Wine build from a downloaded tarball.
    ///
    /// This performs a large, synchronous tar extraction. It is a `nonisolated async`
    /// function, so calling it from a `@MainActor` context suspends and runs the blocking
    /// work on the cooperative thread pool rather than freezing the UI.
    ///
    /// - Parameter kind: The managed engine family represented by the archive.
    /// - Parameter activate: When `true`, the newly installed build becomes the global default.
    ///   Pass `false` to install without switching the active engine; this is what the manager
    ///   uses so installing an engine never changes existing bottles unexpectedly.
    public static func install(
        from tarball: URL,
        version: String,
        kind: WineEngineKind = .gcenx,
        activate: Bool = true,
        in libraryFolder: URL = WhiskyWineInstaller.libraryFolder
    ) async throws {
        guard kind.isManaged else {
            throw WineManagerError.invalidWineArchive
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Extract the tar.xz to a temp directory
        try Tar.untarXZ(tarBall: tarball, toURL: tempDir)

        // Gcenx archives contain a Wine .app, while Sikarugir engine archives contain a
        // `wswine.bundle`. Both are accepted by looking for the root that owns bin/wine and
        // bin/wineserver instead of depending on either wrapper name.
        guard let extractedWine = findWineRoot(in: tempDir) else {
            throw WineManagerError.invalidWineArchive
        }

        // Ensure Libraries folder exists.
        let wineDestination = wineURL(for: version, kind: kind, in: libraryFolder)
        let destinationDirectory = wineDestination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: libraryFolder.path) {
            try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        }
        let buildsDirectory = destinationDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: buildsDirectory, withIntermediateDirectories: true)

        let engineID = WineEngine.managedID(kind: kind, version: version)
        let wasActive = activeWineEngineID(in: libraryFolder) == engineID
        let backupDirectory = buildsDirectory.appending(path: ".backup-\(UUID().uuidString)")
        if FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.moveItem(at: destinationDirectory, to: backupDirectory)
        }

        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            // Move Wine resources -> Libraries/WineBuilds/{engine}/Wine.
            try FileManager.default.moveItem(at: extractedWine, to: wineDestination)
            try writeEngineMetadata(
                InstalledWineEngineMetadata(
                    id: engineID,
                    name: kind.displayName,
                    version: version,
                    kind: kind
                ),
                at: destinationDirectory
            )

            if activate || wasActive {
                try activateWineEngine(engineID, in: libraryFolder)
            }
            try? FileManager.default.removeItem(at: backupDirectory)
        } catch {
            try? FileManager.default.removeItem(at: destinationDirectory)
            if FileManager.default.fileExists(atPath: backupDirectory.path) {
                try? FileManager.default.moveItem(at: backupDirectory, to: destinationDirectory)
            }
            throw error
        }

        // Clean up
        try? FileManager.default.removeItem(at: tarball)
    }
    /// Locate a Wine root in either a Gcenx application archive or a Wineskin-compatible engine
    /// bundle. Kept separate from extraction so archive layout regressions are unit-testable.
    static func findWineRoot(in extractedDirectory: URL) -> URL? {
        let fileManager = FileManager.default
        let candidates = [extractedDirectory] + (fileManager
            .enumerator(at: extractedDirectory, includingPropertiesForKeys: [.isDirectoryKey])?
            .compactMap { $0 as? URL } ?? [])

        return candidates.first { candidate in
            let wine = candidate.appending(path: "bin/wine")
            let wine64 = candidate.appending(path: "bin/wine64")
            let wineserver = candidate.appending(path: "bin/wineserver")
            return (fileManager.fileExists(atPath: wine.path)
                    || fileManager.fileExists(atPath: wine64.path))
                && fileManager.fileExists(atPath: wineserver.path)
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall Wine: \(error)")
        }
    }

    // MARK: - DXVK

    private static let dxvkReleasesURL =
        "https://api.github.com/repos/Gcenx/DXVK-macOS/releases/latest"

    public static let dxvkFolder: URL = libraryFolder.appending(path: "DXVK")

    public static func isDXVKInstalled() -> Bool {
        isDXVKInstalled(for: .win64, in: libraryFolder)
    }

    public static func isDXVKInstalled(for architecture: BottleArchitecture) -> Bool {
        isDXVKInstalled(for: architecture, in: libraryFolder)
    }

    public static func isDXVKInstalled(
        for architecture: BottleArchitecture,
        in libraryFolder: URL
    ) -> Bool {
        let directory = libraryFolder
            .appending(path: "DXVK")
            .appending(path: architecture == .win64 ? "x64" : "x32")
        let requiredFiles = ["d3d10core.dll", "d3d11.dll"]
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appending(path: $0).path)
        }
    }

    /// Fetch the latest DXVK-macOS release download URL (async variant, non-builtin).
    public static func fetchLatestDXVKRelease() async -> URL? {
        guard let url = URL(string: dxvkReleasesURL) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GcenxRelease.self, from: data)

            // Prefer the non-builtin async variant
            let asset = release.assets.first {
                $0.name.hasSuffix(".tar.gz") && !$0.name.contains("builtin")
            } ?? release.assets.first {
                $0.name.hasSuffix(".tar.gz")
            }

            if let asset = asset, let downloadURL = URL(string: asset.browserDownloadUrl) {
                return downloadURL
            }
        } catch {
            print("Failed to fetch DXVK releases: \(error)")
        }

        return nil
    }

    /// Install DXVK from a downloaded tar.gz
    public static func installDXVK(from tarball: URL) {
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            try Tar.untar(tarBall: tarball, toURL: tempDir)

            // Find the extracted directory (e.g. dxvk-macOS-async-v1.10.3-...)
            let contents = try FileManager.default.contentsOfDirectory(
                at: tempDir, includingPropertiesForKeys: nil
            )
            guard let extractedDir = contents.first(where: {
                $0.hasDirectoryPath
            }) else {
                throw "No directory found in extracted DXVK archive"
            }

            // Clean existing DXVK
            if FileManager.default.fileExists(atPath: dxvkFolder.path) {
                try FileManager.default.removeItem(at: dxvkFolder)
            }
            if !FileManager.default.fileExists(atPath: libraryFolder.path) {
                try FileManager.default.createDirectory(
                    at: libraryFolder, withIntermediateDirectories: true
                )
            }

            // Move extracted -> Libraries/DXVK
            try FileManager.default.moveItem(at: extractedDir, to: dxvkFolder)

            // Clean up
            try FileManager.default.removeItem(at: tempDir)
            try FileManager.default.removeItem(at: tarball)
        } catch {
            print("Failed to install DXVK: \(error)")
        }
    }

    /// Check if a Wine update is available.
    public static func shouldUpdateWhiskyWine() async -> WineUpdateStatus {
        // External engines and Sikarugir are deliberate runtime choices; never nag about
        // replacing them with a Gcenx build from the legacy setup flow.
        if let activeEngine = activeWineEngine(), activeEngine.kind != .gcenx {
            return WineUpdateStatus(shouldUpdate: false, latestVersion: "")
        }

        guard let release = await fetchLatestRelease() else {
            return WineUpdateStatus(shouldUpdate: false, latestVersion: "")
        }

        guard installedWineVersion() != nil else {
            return WineUpdateStatus(shouldUpdate: false, latestVersion: "")
        }

        // Consider the latest release "already installed" if it's among the downloaded
        // builds — the user may have pinned an older build as active on purpose.
        let alreadyInstalled = installedWineBuilds().contains {
            $0.kind == .gcenx && $0.version == release.version
        }
        if alreadyInstalled {
            return WineUpdateStatus(shouldUpdate: false, latestVersion: release.version)
        }

        return WineUpdateStatus(shouldUpdate: true, latestVersion: release.version)
    }

}

public struct WineUpdateStatus {
    public let shouldUpdate: Bool
    public let latestVersion: String
}
