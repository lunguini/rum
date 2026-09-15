//
//  WhiskyWineInstaller+SikarugirSupportInstaller.swift
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

public struct SikarugirTemplateRelease: Identifiable, Equatable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let assetName: String
    public let size: Int

    public var id: String { version }
}

extension WhiskyWineInstaller {
    private static let sikarugirWrapperReleasesURL = "https://api.github.com/repos/Sikarugir-App/Wrapper/releases"

    public static func fetchLatestSikarugirTemplateRelease() async -> SikarugirTemplateRelease? {
        guard let url = URL(string: sikarugirWrapperReleasesURL) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let releases = try JSONDecoder().decode([GcenxRelease].self, from: data)
            return availableSikarugirTemplateReleases(from: releases).first
        } catch {
            print("Failed to fetch Sikarugir template release: \(error)")
        }

        return nil
    }

    public static func availableSikarugirTemplateReleases(
        from releases: [GcenxRelease]
    ) -> [SikarugirTemplateRelease] {
        releases
            .flatMap { release in
                release.assets.compactMap { asset -> SikarugirTemplateRelease? in
                    let name = asset.name
                    guard name.lowercased().hasPrefix("template-"),
                          name.lowercased().hasSuffix(".tar.xz"),
                          let downloadURL = URL(string: asset.browserDownloadUrl) else {
                        return nil
                    }
                    return SikarugirTemplateRelease(
                        version: name.replacingOccurrences(of: ".tar.xz", with: ""),
                        downloadURL: downloadURL,
                        assetName: name,
                        size: asset.size
                    )
                }
            }
            .reduce(into: [SikarugirTemplateRelease]()) { result, release in
                guard !result.contains(where: { $0.version == release.version }) else { return }
                result.append(release)
            }
            .sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }

    /// Install a Sikarugir engine and ensure its template-owned support libraries are available.
    /// Existing external Sikarugir templates are reused; otherwise the latest official template
    /// is downloaded only as a user-requested engine installation dependency.
    public static func installSikarugirEngine(
        from tarball: URL,
        version: String,
        activate: Bool = false,
        in libraryFolder: URL = WhiskyWineInstaller.libraryFolder
    ) async throws {
        if sikarugirTemplateFrameworksURL(for: libraryFolder) == nil {
            guard let templateRelease = await fetchLatestSikarugirTemplateRelease() else {
                throw WineManagerError.sikarugirSupportNotInstalled
            }
            let (templateTarball, _) = try await URLSession.shared.download(
                from: templateRelease.downloadURL
            )
            try await installSikarugirSupport(
                from: templateTarball,
                version: templateRelease.version,
                in: libraryFolder
            )
        }

        try await install(
            from: tarball,
            version: version,
            kind: .sikarugir,
            activate: activate,
            in: libraryFolder
        )
    }

    public static func installSikarugirSupport(
        from tarball: URL,
        version: String,
        in libraryFolder: URL = WhiskyWineInstaller.libraryFolder
    ) async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Rum-Sikarugir-Template-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try Tar.untarXZ(tarBall: tarball, toURL: temporaryDirectory)
        let contents = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw WineManagerError.invalidGraphicsRuntimeArchive("Sikarugir template")
        }
        let frameworks = app.appending(path: "Contents/Frameworks")
        guard FileManager.default.fileExists(atPath: frameworks.appending(path: "libinotify.0.dylib").path) else {
            throw WineManagerError.invalidGraphicsRuntimeArchive("Sikarugir template")
        }

        let supportVersion = sanitizedSupportVersion(version)
        let destination = libraryFolder
            .appending(path: sikarugirSupportFolderName)
            .appending(path: supportVersion)
            .appending(path: "Frameworks")
        let versionDirectory = destination.deletingLastPathComponent()
        let supportFolder = versionDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
        let backup = supportFolder
            .appending(path: ".backup-\(UUID().uuidString)")
        if FileManager.default.fileExists(atPath: versionDirectory.path) {
            try FileManager.default.moveItem(
                at: versionDirectory,
                to: backup
            )
        }

        do {
            try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: frameworks, to: destination)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            try? FileManager.default.removeItem(at: versionDirectory)
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.moveItem(
                    at: backup,
                    to: versionDirectory
                )
            }
            throw error
        }

        try? FileManager.default.removeItem(at: tarball)
    }

    private static func sanitizedSupportVersion(_ version: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let result = version.unicodeScalars.reduce(into: "") { result, scalar in
            result.append(allowed.contains(scalar) ? Character(String(scalar)) : "-")
        }
        return result.isEmpty || result == "." || result == ".." ? UUID().uuidString : result
    }
}
