//
//  WhiskyWineInstaller+DXMT.swift
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

public struct DXMTRelease: Identifiable, Equatable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let assetName: String
    public let size: Int

    public var id: String { version }

    public init(version: String, downloadURL: URL, assetName: String, size: Int) {
        self.version = version
        self.downloadURL = downloadURL
        self.assetName = assetName
        self.size = size
    }
}

struct InstalledDXMTRuntimeMetadata: Codable, Equatable, Sendable {
    let version: String
}

extension WhiskyWineInstaller {
    private static let dxmtReleasesURL = "https://api.github.com/repos/3Shain/dxmt/releases/latest"
    private static let dxmtFolderName = "DXMT"
    private static let dxmtMetadataFileName = "version.json"

    public static func fetchLatestDXMTRelease() async -> DXMTRelease? {
        guard let url = URL(string: dxmtReleasesURL) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GcenxRelease.self, from: data)
            return availableDXMTRelease(from: release)
        } catch {
            print("Failed to fetch DXMT release: \(error)")
        }

        return nil
    }

    public static func availableDXMTRelease(from release: GcenxRelease) -> DXMTRelease? {
        let asset = release.assets.first {
            let name = $0.name.lowercased()
            return name.contains("builtin") && name.hasSuffix(".tar.gz")
        } ?? release.assets.first {
            $0.name.lowercased().hasSuffix(".tar.gz")
        }

        guard let asset, let downloadURL = URL(string: asset.browserDownloadUrl) else { return nil }
        return DXMTRelease(
            version: release.tagName,
            downloadURL: downloadURL,
            assetName: asset.name,
            size: asset.size
        )
    }

    public static func isDXMTInstalled(in libraryFolder: URL = libraryFolder) -> Bool {
        installedDXMTRoot(in: libraryFolder) != nil
    }

    public static func installedDXMTVersion(in libraryFolder: URL = libraryFolder) -> String? {
        let metadataURL = dxmtFolder(in: libraryFolder).appending(path: dxmtMetadataFileName)
        if let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(InstalledDXMTRuntimeMetadata.self, from: data) {
            return metadata.version
        }
        return installedDXMTRoot(in: libraryFolder) == nil ? nil : "Installed"
    }

    public static func installDXMT(
        from tarball: URL,
        version: String,
        in libraryFolder: URL = WhiskyWineInstaller.libraryFolder
    ) async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Rum-DXMT-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try Tar.untar(tarBall: tarball, toURL: temporaryDirectory)
        guard let extractedRoot = findDXMTPayloadRoot(in: temporaryDirectory) else {
            throw WineManagerError.invalidGraphicsRuntimeArchive("DXMT")
        }

        let destination = dxmtFolder(in: libraryFolder)
        try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        let backup = libraryFolder.appending(path: ".DXMT-backup-\(UUID().uuidString)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: destination, to: backup)
        }

        do {
            try FileManager.default.moveItem(at: extractedRoot, to: destination)
            let metadata = try JSONEncoder().encode(InstalledDXMTRuntimeMetadata(version: version))
            try metadata.write(to: destination.appending(path: dxmtMetadataFileName), options: .atomic)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            throw error
        }

        try? FileManager.default.removeItem(at: tarball)
    }

    static func dxmtFolder(in libraryFolder: URL) -> URL {
        libraryFolder.appending(path: dxmtFolderName)
    }

    static func installedDXMTRoot(in libraryFolder: URL) -> URL? {
        let folder = dxmtFolder(in: libraryFolder)
        return findDXMTPayloadRoot(in: folder)
    }

    static func findDXMTPayloadRoot(in directory: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let candidates = [directory] + (FileManager.default
            .enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])?
            .compactMap { $0 as? URL } ?? [])
        return candidates.first(where: hasDXMTPayload)
    }
}
