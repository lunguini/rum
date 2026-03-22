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

    private static let versionFile = libraryFolder.appending(path: "wine-version.json")

    private static let githubReleasesURL =
        "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases"

    public static func isWhiskyWineInstalled() -> Bool {
        return installedWineVersion() != nil
    }

    public static func install(from tarball: URL) {
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)

            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Extract the tar.xz to a temp directory
            try Tar.untarXZ(tarBall: tarball, toURL: tempDir)

            // Gcenx archives extract to "Wine Staging.app/Contents/Resources/wine/"
            // or "Wine Devel.app/Contents/Resources/wine/" — find the .app dynamically
            let contents = try FileManager.default.contentsOfDirectory(
                at: tempDir, includingPropertiesForKeys: nil
            )
            guard let appBundle = contents.first(where: { $0.lastPathComponent.hasSuffix(".app") }) else {
                throw "No .app bundle found in extracted archive"
            }
            let extractedWine = appBundle
                .appending(path: "Contents")
                .appending(path: "Resources")
                .appending(path: "wine")

            // Ensure application folder exists
            if !FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)
            }

            // Ensure Libraries folder exists (clean)
            let wineDestination = libraryFolder.appending(path: "Wine")
            if FileManager.default.fileExists(atPath: wineDestination.path) {
                try FileManager.default.removeItem(at: wineDestination)
            }
            if !FileManager.default.fileExists(atPath: libraryFolder.path) {
                try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
            }

            // Move wine resources -> Libraries/Wine
            try FileManager.default.moveItem(at: extractedWine, to: wineDestination)

            // Clean up
            try FileManager.default.removeItem(at: tempDir)
            try FileManager.default.removeItem(at: tarball)
        } catch {
            print("Failed to install Wine: \(error)")
        }
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall Wine: \(error)")
        }
    }

    /// Save the installed version string to disk
    public static func saveInstalledVersion(_ version: String) {
        do {
            let info = InstalledWineVersion(version: version)
            let data = try JSONEncoder().encode(info)
            try data.write(to: versionFile)
        } catch {
            print("Failed to save wine version: \(error)")
        }
    }

    /// Read the locally installed version string
    public static func installedWineVersion() -> String? {
        // Check for version file
        if let data = try? Data(contentsOf: versionFile),
           let info = try? JSONDecoder().decode(InstalledWineVersion.self, from: data) {
            return info.version
        }

        // Fallback: check if a wine binary exists
        let wineUnified = binFolder.appending(path: "wine")
        let wineLegacy = binFolder.appending(path: "wine64")
        if FileManager.default.fileExists(atPath: wineUnified.path)
            || FileManager.default.fileExists(atPath: wineLegacy.path) {
            return "unknown"
        }

        return nil
    }

    /// Fetch the latest Gcenx release that has a Wine Staging asset.
    /// Falls back to wine-devel if no staging build is available.
    public static func fetchLatestRelease() async -> (version: String, downloadURL: URL)? {
        guard let url = URL(string: githubReleasesURL) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, _) = try await URLSession.shared.data(for: request)
            let releases = try JSONDecoder().decode([GcenxRelease].self, from: data)

            for release in releases {
                // Skip pre-release candidates
                if release.tagName.contains("-rc") { continue }

                // Prefer staging, fall back to devel
                let stagingAsset = release.assets.first {
                    $0.name.contains("wine-staging") && $0.name.hasSuffix("-osx64.tar.xz")
                }
                let develAsset = release.assets.first {
                    $0.name.contains("wine-devel") && $0.name.hasSuffix("-osx64.tar.xz")
                }

                if let asset = stagingAsset ?? develAsset,
                   let downloadURL = URL(string: asset.browserDownloadUrl) {
                    return (release.tagName, downloadURL)
                }
            }
        } catch {
            print("Failed to fetch Gcenx releases: \(error)")
        }

        return nil
    }

    // MARK: - DXVK

    private static let dxvkReleasesURL =
        "https://api.github.com/repos/Gcenx/DXVK-macOS/releases/latest"

    public static let dxvkFolder: URL = libraryFolder.appending(path: "DXVK")

    public static func isDXVKInstalled() -> Bool {
        let x64 = dxvkFolder.appending(path: "x64")
        return FileManager.default.fileExists(atPath: x64.path)
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
        guard let release = await fetchLatestRelease() else {
            return WineUpdateStatus(shouldUpdate: false, latestVersion: "")
        }

        guard let localVersion = installedWineVersion() else {
            return WineUpdateStatus(shouldUpdate: false, latestVersion: "")
        }

        if localVersion == "unknown" || localVersion != release.version {
            return WineUpdateStatus(shouldUpdate: true, latestVersion: release.version)
        }

        return WineUpdateStatus(shouldUpdate: false, latestVersion: release.version)
    }
}

public struct WineUpdateStatus {
    public let shouldUpdate: Bool
    public let latestVersion: String
}
