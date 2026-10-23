//
//  ArtworkStore.swift
//  Rum
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

import AppKit
import CryptoKit
import WhiskyKit

/// Cover and header images for a Library program.
struct ProgramArtwork {
    var cover: NSImage?
    var header: NSImage?

    var isEmpty: Bool { cover == nil && header == nil }
}

private enum ArtworkSource: String, Codable {
    /// Downloaded from Steam.
    case steam
    /// An image the user picked.
    case custom
    /// Nothing found. Looked up again after `ArtworkStore.retryInterval`.
    case notFound
    /// The user removed the artwork; never looked up automatically again.
    case removed
}

/// Finds, downloads and caches Library artwork, keyed by executable path. Steam artwork is looked
/// up once per program; programs Steam doesn't know keep their icon.
@MainActor
final class ArtworkStore: ObservableObject {
    static let shared = ArtworkStore()

    private struct Record: Codable {
        var source: ArtworkSource
        var steamAppID: Int?
        var updated: Date
        /// Which version of the lookup produced this; older "not found" results are retried.
        var lookupVersion: Int?
    }

    /// Bump when the lookup gets smarter, so programs it missed are tried again.
    private static let lookupVersion = 2

    private static let retryInterval: TimeInterval = 7 * 24 * 60 * 60

    @Published private(set) var artwork: [URL: ProgramArtwork] = [:]
    @Published private(set) var lookingUp: Set<URL> = []
    private var records: [String: Record] = [:]
    private let folder = BottleData.containerDir.appending(path: "Artwork")
    private var indexURL: URL { folder.appending(path: "index.json") }

    private init() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        }
    }

    func steamAppID(for url: URL) -> Int? {
        records[key(for: url)]?.steamAppID
    }

    /// Loads cached artwork for `url`, looking it up on Steam the first time.
    func load(for url: URL, name: String) async {
        guard artwork[url] == nil, !lookingUp.contains(url) else { return }
        let record = records[key(for: url)]
        if let record {
            artwork[url] = await readFromDisk(url)
            let shouldRetry = record.source == .notFound
                && (record.updated.addingTimeInterval(Self.retryInterval) < Date()
                    || (record.lookupVersion ?? 1) < Self.lookupVersion)
            guard shouldRetry else { return }
        }
        await lookUp(url, name: name)
    }

    /// Forgets what was found for `url` and searches Steam again.
    func searchAgain(for url: URL, name: String) async {
        records[key(for: url)] = nil
        artwork[url] = nil
        await lookUp(url, name: name)
    }

    /// Uses the artwork of Steam app `appID`. Returns false when Steam has no images for it.
    @discardableResult
    func useSteamApp(_ appID: Int, for url: URL) async -> Bool {
        lookingUp.insert(url)
        defer { lookingUp.remove(url) }
        async let cover = SteamStore.downloadImage(appID: appID, kind: .cover)
        async let header = SteamStore.downloadImage(appID: appID, kind: .header)
        let (coverData, headerData) = await (cover, header)
        guard coverData != nil || headerData != nil else { return false }

        removeFiles(for: url)
        write(coverData, to: fileURL(for: url, kind: .cover))
        write(headerData, to: fileURL(for: url, kind: .header))
        setRecord(Record(source: .steam, steamAppID: appID, updated: Date()), for: url)
        artwork[url] = ProgramArtwork(cover: coverData.flatMap(NSImage.init(data:)),
                                      header: headerData.flatMap(NSImage.init(data:)))
        return true
    }

    /// Uses an image file from the Mac for both the card and the details panel.
    @discardableResult
    func useImage(at imageURL: URL, for url: URL) -> Bool {
        guard let data = try? Data(contentsOf: imageURL), let image = NSImage(data: data) else { return false }
        removeFiles(for: url)
        write(data, to: fileURL(for: url, kind: .cover))
        setRecord(Record(source: .custom, updated: Date()), for: url)
        artwork[url] = ProgramArtwork(cover: image, header: nil)
        return true
    }

    /// Goes back to the program's icon and stops looking for artwork.
    func removeArtwork(for url: URL) {
        removeFiles(for: url)
        setRecord(Record(source: .removed, updated: Date()), for: url)
        artwork[url] = ProgramArtwork()
    }

    // MARK: - Lookup

    private func lookUp(_ url: URL, name: String) async {
        lookingUp.insert(url)
        defer { lookingUp.remove(url) }

        let result = await Task.detached(priority: .utility) {
            await Self.findSteamAppID(for: url, name: name)
        }.value

        switch result {
        case .found(let appID):
            if await useSteamApp(appID, for: url) { return }
            fallthrough
        case .notFound:
            setRecord(Record(source: .notFound, updated: Date(), lookupVersion: Self.lookupVersion), for: url)
            artwork[url] = ProgramArtwork()
        case .offline:
            // Try again next time the card appears.
            artwork[url] = ProgramArtwork()
        }
    }

    private enum LookupResult: Sendable {
        case found(Int)
        case notFound
        case offline
    }

    nonisolated private static func findSteamAppID(for url: URL, name: String) async -> LookupResult {
        if let appID = SteamAppLookup.appIDFromFile(near: url) ?? SteamAppLookup.appIDFromSteamLibrary(for: url) {
            return .found(appID)
        }
        // The name in the executable's version info is often the store name ("HeroesOldenEra.exe"
        // → "Heroes of Might and Magic: Olden Era").
        let productName = (try? PEFile(url: url))?.productDisplayName
        var candidates = SteamAppLookup.nameCandidates(for: url, displayName: name)
        if let productName {
            let normalized = SteamAppLookup.normalizedName(productName)
            if !candidates.contains(where: { SteamAppLookup.normalizedName($0) == normalized }) {
                candidates.insert(productName, at: 0)
            }
        }
        for candidate in candidates.prefix(4) {
            guard let results = try? await SteamStore.search(candidate) else { return .offline }
            if let match = SteamAppLookup.bestMatch(for: candidate, in: results) {
                return .found(match.id)
            }
        }
        return .notFound
    }

    // MARK: - Storage

    private func key(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.path(percentEncoded: false).utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(for url: URL, kind: SteamStore.ImageKind) -> URL {
        let suffix = kind == .cover ? "cover" : "header"
        return folder.appending(path: "\(key(for: url))-\(suffix)")
    }

    private func readFromDisk(_ url: URL) async -> ProgramArtwork {
        let coverURL = fileURL(for: url, kind: .cover)
        let headerURL = fileURL(for: url, kind: .header)
        let (coverData, headerData) = await Task.detached(priority: .utility) {
            (try? Data(contentsOf: coverURL), try? Data(contentsOf: headerURL))
        }.value
        return ProgramArtwork(cover: coverData.flatMap(NSImage.init(data:)),
                              header: headerData.flatMap(NSImage.init(data:)))
    }

    private func write(_ data: Data?, to fileURL: URL) {
        guard let data else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func removeFiles(for url: URL) {
        try? FileManager.default.removeItem(at: fileURL(for: url, kind: .cover))
        try? FileManager.default.removeItem(at: fileURL(for: url, kind: .header))
    }

    private func setRecord(_ record: Record, for url: URL) {
        records[key(for: url)] = record
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
