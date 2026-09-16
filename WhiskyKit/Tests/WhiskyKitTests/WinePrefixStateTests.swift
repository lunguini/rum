//
//  WinePrefixStateTests.swift
//  Whisky
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

final class WinePrefixStateTests: XCTestCase {
    private var bottleURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        bottleURL = FileManager.default.temporaryDirectory
            .appending(path: "rum-prefix-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bottleURL)
        try super.tearDownWithError()
    }

    private func makeEngine(id: String = "gcenx:11.15", version: String = "11.15") -> WineEngine {
        WineEngine(
            id: id,
            name: "Test",
            version: version,
            kind: .gcenx,
            wineURL: bottleURL,
            wineBinaryURL: bottleURL.appending(path: "bin/wine"),
            wineserverBinaryURL: bottleURL.appending(path: "bin/wineserver")
        )
    }

    func testFreshBottleNeedsInitialization() {
        let bottle = Bottle(bottleUrl: bottleURL)
        XCTAssertTrue(WinePrefixStateStore.needsInitialization(for: bottle, engine: makeEngine()))
    }

    func testRecordedEngineSkipsSubsequentInitialization() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let engine = makeEngine()

        try WinePrefixStateStore.recordInitialization(for: bottle, engine: engine)

        XCTAssertFalse(WinePrefixStateStore.needsInitialization(for: bottle, engine: engine))
    }

    func testChangedEngineIDNeedsInitialization() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        try WinePrefixStateStore.recordInitialization(for: bottle, engine: makeEngine())

        let other = makeEngine(id: "sikarugir:10.0", version: "10.0")
        XCTAssertTrue(WinePrefixStateStore.needsInitialization(for: bottle, engine: other))
    }

    func testUpgradedEngineVersionNeedsInitialization() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        try WinePrefixStateStore.recordInitialization(for: bottle, engine: makeEngine(version: "11.15"))

        let upgraded = makeEngine(version: "11.16")
        XCTAssertTrue(WinePrefixStateStore.needsInitialization(for: bottle, engine: upgraded))
    }

    func testCorruptMarkerNeedsInitialization() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let engine = makeEngine()
        try WinePrefixStateStore.recordInitialization(for: bottle, engine: engine)

        try Data("not a plist".utf8).write(to: WinePrefixStateStore.stateURL(for: bottle))

        XCTAssertTrue(WinePrefixStateStore.needsInitialization(for: bottle, engine: engine))
    }

    func testClearForcesReinitialization() throws {
        let bottle = Bottle(bottleUrl: bottleURL)
        let engine = makeEngine()
        try WinePrefixStateStore.recordInitialization(for: bottle, engine: engine)

        WinePrefixStateStore.clear(for: bottle)

        XCTAssertTrue(WinePrefixStateStore.needsInitialization(for: bottle, engine: engine))
    }
}

@MainActor
final class WineEnginePinningTests: XCTestCase {
    private var bottleURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        bottleURL = FileManager.default.temporaryDirectory
            .appending(path: "rum-engine-pin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bottleURL)
        try super.tearDownWithError()
    }

    private func makeEngine(id: String) -> WineEngine {
        WineEngine(
            id: id,
            name: "Test",
            version: "11.15",
            kind: .gcenx,
            wineURL: bottleURL,
            wineBinaryURL: bottleURL.appending(path: "bin/wine"),
            wineserverBinaryURL: bottleURL.appending(path: "bin/wineserver")
        )
    }

    func testUnpinnedBottleAdoptsResolvedEngine() {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.wineEngineID = nil

        Wine.pinResolvedEngineIfNeeded(for: bottle, engine: makeEngine(id: "gcenx:11.15"))

        XCTAssertEqual(bottle.settings.wineEngineID, "gcenx:11.15")
    }

    func testExistingPinIsNotOverwritten() {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.wineEngineID = "sikarugir:10.0"

        Wine.pinResolvedEngineIfNeeded(for: bottle, engine: makeEngine(id: "gcenx:11.15"))

        XCTAssertEqual(bottle.settings.wineEngineID, "sikarugir:10.0")
    }

    func testAdoptedPinPersistsToDisk() {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.wineEngineID = nil

        Wine.pinResolvedEngineIfNeeded(for: bottle, engine: makeEngine(id: "gcenx:11.15"))

        let reloaded = Bottle(bottleUrl: bottleURL)
        XCTAssertEqual(reloaded.settings.wineEngineID, "gcenx:11.15")
    }
}
