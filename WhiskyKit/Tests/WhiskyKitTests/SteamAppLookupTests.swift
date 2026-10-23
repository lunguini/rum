//
//  SteamAppLookupTests.swift
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

import XCTest
@testable import WhiskyKit

final class SteamAppLookupTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAppIDFileInParentFolder() throws {
        let gameFolder = root.appending(path: "Hades")
        let binFolder = gameFolder.appending(path: "x64")
        try FileManager.default.createDirectory(at: binFolder, withIntermediateDirectories: true)
        try " 1145360\n".write(to: gameFolder.appending(path: "steam_appid.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(SteamAppLookup.appIDFromFile(near: binFolder.appending(path: "Hades.exe")), 1145360)
    }

    func testAppIDFromSteamLibraryManifest() throws {
        let steamapps = root.appending(path: "Steam/steamapps")
        let gameFolder = steamapps.appending(path: "common/Baldurs Gate 3/bin")
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        let manifest = """
        "AppState"
        {
        \t"appid"\t\t"1086940"
        \t"name"\t\t"Baldur's Gate 3"
        \t"installdir"\t\t"Baldurs Gate 3"
        }
        """
        try manifest.write(to: steamapps.appending(path: "appmanifest_1086940.acf"), atomically: true, encoding: .utf8)

        let exe = gameFolder.appending(path: "bg3.exe")
        XCTAssertEqual(SteamAppLookup.appIDFromSteamLibrary(for: exe), 1086940)
    }

    func testNotInSteamLibrary() {
        XCTAssertNil(SteamAppLookup.appIDFromSteamLibrary(for: URL(filePath: "/Games/Foo/Foo.exe")))
    }

    func testNormalizedName() {
        XCTAssertEqual(SteamAppLookup.normalizedName("Cyberpunk 2077™"), "cyberpunk2077")
        XCTAssertEqual(SteamAppLookup.normalizedName("Pokémon-Like: Café"), "pokemonlikecafe")
    }

    func testNameCandidatesSkipGenericFolders() {
        let exe = URL(filePath: "/Users/me/Games/Elden Ring/Game/start_protected_game.exe")
        let candidates = SteamAppLookup.nameCandidates(for: exe, displayName: "start_protected_game")
        // "Games" and "Game" say nothing; the exe name is a duplicate of the display name.
        XCTAssertEqual(candidates, ["start_protected_game", "Elden Ring"])
    }

    func testBestMatchRequiresExactName() {
        let results = [
            SteamStoreItem(name: "Cyberpunk 2077: Phantom Liberty", id: 2),
            SteamStoreItem(name: "Cyberpunk 2077", id: 1)
        ]
        XCTAssertEqual(SteamAppLookup.bestMatch(for: "Cyberpunk2077", in: results)?.id, 1)
        XCTAssertNil(SteamAppLookup.bestMatch(for: "Cyberpunk", in: results))
    }
}
