//
//  ProgramRendererTests.swift
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

final class ProgramRendererTests: XCTestCase {
    private var bottleURL: URL!

    override func setUpWithError() throws {
        bottleURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: bottleURL)
    }

    func testProgramUsesBottleRendererByDefault() {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = .dxvk
        let program = Program(url: bottleURL.appending(path: "Game.exe"), bottle: bottle)

        XCTAssertNil(program.settings.graphicsBackend)
        XCTAssertEqual(program.graphicsBackend, .dxvk)
    }

    func testProgramRendererOverridesBottleAndPersists() {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = .wineD3D
        let url = bottleURL.appending(path: "Game.exe")
        Program(url: url, bottle: bottle).settings.graphicsBackend = .d3dmetal

        let reloaded = Program(url: url, bottle: bottle)
        XCTAssertEqual(reloaded.graphicsBackend, .d3dmetal)
        XCTAssertEqual(bottle.settings.graphicsBackend, .wineD3D)
    }

    func testOldProgramSettingsDecodeWithoutRenderer() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>arguments</key><string>-windowed</string>
        <key>environment</key><dict/>
        <key>locale</key><string></string>
        </dict></plist>
        """
        let settings = try PropertyListDecoder().decode(ProgramSettings.self, from: Data(plist.utf8))

        XCTAssertNil(settings.graphicsBackend)
        XCTAssertEqual(settings.arguments, "-windowed")
    }

    func testEnvironmentFollowsRendererOverride() {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = .wineD3D

        let bottleEnvironment = Wine.constructWineEnvironment(for: bottle)
        let overridden = Wine.constructWineEnvironment(for: bottle, graphicsBackend: .dxvk)

        XCTAssertEqual(bottleEnvironment["WINEDLLOVERRIDES"], "dxgi,d3d9,d3d10core,d3d11=b")
        XCTAssertEqual(overridden["WINEDLLOVERRIDES"], "dxgi,d3d9,d3d10core,d3d11=n,b")
        XCTAssertEqual(bottle.settings.graphicsBackend, .wineD3D)
    }
}
