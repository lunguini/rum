//
//  SteamArtwork.swift
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

/// Works out which Steam app an executable belongs to, using only public, keyless sources:
/// `steam_appid.txt`, Steam library manifests, and the Steam store search.
public enum SteamAppLookup {
    /// Folder names that say nothing about the game, skipped when guessing a name from the path.
    static let genericFolderNames: Set<String> = [
        "bin", "bin32", "bin64", "binaries", "win32", "win64", "x86", "x64", "x86_64", "game", "games",
        "retail", "release", "shipping", "launcher", "client", "app", "program", "programs", "common",
        "program files", "program files (x86)", "drive_c", "desktop", "downloads", "documents", "applications"
    ]

    /// An app ID from a `steam_appid.txt` next to the executable or in one of its parent folders.
    public static func appIDFromFile(near executable: URL, levels: Int = 3) -> Int? {
        var folder = executable.deletingLastPathComponent()
        for _ in 0..<levels {
            let file = folder.appending(path: "steam_appid.txt")
            if let text = try? String(contentsOf: file, encoding: .utf8),
               let appID = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), appID > 0 {
                return appID
            }
            let parent = folder.deletingLastPathComponent()
            guard parent != folder else { break }
            folder = parent
        }
        return nil
    }

    /// An app ID from the Steam library the executable is installed in
    /// (`…/steamapps/common/<installdir>/…` with a matching `appmanifest_<id>.acf`).
    public static func appIDFromSteamLibrary(for executable: URL) -> Int? {
        let components = executable.pathComponents
        guard let commonIndex = components.lastIndex(where: { $0.lowercased() == "common" }),
              commonIndex > 0, commonIndex + 1 < components.count,
              components[commonIndex - 1].lowercased() == "steamapps" else { return nil }

        let installDir = components[commonIndex + 1]
        let steamapps = URL(filePath: components[...(commonIndex - 1)].joined(separator: "/")
            .replacingOccurrences(of: "//", with: "/"))
        let manifests = (try? FileManager.default.contentsOfDirectory(at: steamapps,
                                                                       includingPropertiesForKeys: nil)) ?? []
        for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_")
            && manifest.pathExtension == "acf" {
            guard let text = try? String(contentsOf: manifest, encoding: .utf8),
                  let parsed = parseManifest(text),
                  parsed.installDir.caseInsensitiveCompare(installDir) == .orderedSame else { continue }
            return parsed.appID
        }
        return nil
    }

    /// Reads `appid` and `installdir` from a Steam `appmanifest_*.acf` file.
    static func parseManifest(_ text: String) -> (appID: Int, installDir: String)? {
        var appID: Int?
        var installDir: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "appid": appID = appID ?? Int(parts[1])
            case "installdir": installDir = installDir ?? parts[1]
            default: break
            }
        }
        guard let appID, let installDir else { return nil }
        return (appID, installDir)
    }

    /// Lowercased letters and digits only, so "Cyberpunk 2077™" and "Cyberpunk2077" compare equal.
    public static func normalizedName(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
            .map(String.init)
            .joined()
    }

    /// Names worth searching the Steam store for, most specific first: the name the user sees,
    /// then meaningful folder names above the executable, then the executable's own name.
    public static func nameCandidates(for executable: URL, displayName: String) -> [String] {
        var candidates = [displayName]
        var folder = executable.deletingLastPathComponent()
        for _ in 0..<3 {
            let name = folder.lastPathComponent
            if name.isEmpty || name == "/" { break }
            if !genericFolderNames.contains(name.lowercased()) {
                candidates.append(name)
            }
            folder = folder.deletingLastPathComponent()
        }
        candidates.append(executable.deletingPathExtension().lastPathComponent)

        var seen: Set<String> = []
        return candidates.filter { candidate in
            let normalized = normalizedName(candidate)
            guard normalized.count >= 3, !genericFolderNames.contains(candidate.lowercased()) else { return false }
            return seen.insert(normalized).inserted
        }
    }

    /// The store result whose name matches `candidate` exactly once normalised. Loose matches are
    /// ignored on purpose: wrong artwork is worse than none.
    public static func bestMatch(for candidate: String, in results: [SteamStoreItem]) -> SteamStoreItem? {
        let wanted = normalizedName(candidate)
        return results.first { $0.type == "app" && normalizedName($0.name) == wanted }
    }
}

/// One result of the Steam store search.
public struct SteamStoreItem: Decodable, Identifiable, Hashable, Sendable {
    public let type: String
    public let name: String
    public let id: Int
    public let tinyImage: URL?

    enum CodingKeys: String, CodingKey {
        case type, name, id
        case tinyImage = "tiny_image"
    }

    public init(type: String = "app", name: String, id: Int, tinyImage: URL? = nil) {
        self.type = type
        self.name = name
        self.id = id
        self.tinyImage = tinyImage
    }
}

/// Keyless Steam store endpoints used for artwork.
public enum SteamStore {
    private static let assetBase = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps"

    public enum ImageKind: Sendable {
        /// Portrait library capsule (600×900), used on Library cards.
        case cover
        /// Landscape store header (460×215), used in the details panel.
        case header
    }

    /// Searches the store by name.
    public static func search(_ term: String) async throws -> [SteamStoreItem] {
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "l", value: "english"),
            URLQueryItem(name: "cc", value: "US")
        ]
        guard let url = components?.url else { return [] }
        struct Response: Decodable { let items: [SteamStoreItem] }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Response.self, from: data).items
    }

    /// Image URLs to try for `kind`, best first.
    public static func imageURLs(appID: Int, kind: ImageKind) -> [URL] {
        let names = switch kind {
        case .cover: ["library_600x900_2x.jpg", "library_600x900.jpg"]
        case .header: ["header.jpg"]
        }
        return names.compactMap { URL(string: "\(assetBase)/\(appID)/\($0)") }
    }

    /// The first image of `kind` that exists for `appID`. Newer apps sometimes keep their header
    /// under a hashed path, so headers fall back to the URL the store's app details report.
    public static func downloadImage(appID: Int, kind: ImageKind) async -> Data? {
        for url in imageURLs(appID: appID, kind: kind) {
            if let data = await fetchImage(url) { return data }
        }
        guard kind == .header, let url = await headerURLFromAppDetails(appID: appID) else { return nil }
        return await fetchImage(url)
    }

    private static func headerURLFromAppDetails(appID: Int) async -> URL? {
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&filters=basic"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = json[String(appID)] as? [String: Any],
              let details = app["data"] as? [String: Any],
              let header = details["header_image"] as? String else { return nil }
        return URL(string: header)
    }

    private static func fetchImage(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.hasPrefix("image/") == true, !data.isEmpty else { return nil }
        return data
    }
}
