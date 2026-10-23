//
//  ProgramRendererStoreTests.swift
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

final class ProgramRendererStoreTests: XCTestCase {
    private var root: URL!
    private var game: URL!
    private var dxvk: URL!
    private var dxmt: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        game = root.appending(path: "Game")
        dxvk = root.appending(path: "dxvk")
        dxmt = root.appending(path: "dxmt")
        for folder: URL in [game, dxvk, dxmt] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try write("dxvk-dxgi", to: dxvk.appending(path: "dxgi.dll"))
        try write("dxvk-d3d11", to: dxvk.appending(path: "d3d11.dll"))
        try write("dxmt-d3d11", to: dxmt.appending(path: "d3d11.dll"))
        try write("game", to: game.appending(path: "Game.exe"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testInstallCopiesRendererAndUninstallLeavesFolderAsItWas() throws {
        try ProgramRendererStore.install(.dxvk, from: dxvk, in: game)

        XCTAssertEqual(try read(game.appending(path: "d3d11.dll")), "dxvk-d3d11")
        XCTAssertEqual(try ProgramRendererStore.load(in: game)?.backend, .dxvk)

        try ProgramRendererStore.uninstall(in: game)

        let left = try FileManager.default.contentsOfDirectory(atPath: game.path(percentEncoded: false))
        XCTAssertEqual(left, ["Game.exe"])
    }

    func testProgramsOwnDLLIsPutBackAfterwards() throws {
        try write("reshade", to: game.appending(path: "dxgi.dll"))

        try ProgramRendererStore.install(.dxvk, from: dxvk, in: game)
        XCTAssertEqual(try read(game.appending(path: "dxgi.dll")), "dxvk-dxgi")

        try ProgramRendererStore.uninstall(in: game)
        XCTAssertEqual(try read(game.appending(path: "dxgi.dll")), "reshade")
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.appending(path: "dxgi.dll.rum-orig").path))
    }

    func testSwitchingRendererReplacesThePreviousOne() throws {
        try ProgramRendererStore.install(.dxvk, from: dxvk, in: game)
        try ProgramRendererStore.install(.dxmt, from: dxmt, in: game)

        XCTAssertEqual(try read(game.appending(path: "d3d11.dll")), "dxmt-d3d11")
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.appending(path: "dxgi.dll").path))
        XCTAssertEqual(try ProgramRendererStore.load(in: game)?.backend, .dxmt)
    }

    func testFileChangedSinceInstallIsLeftAlone() throws {
        try ProgramRendererStore.install(.dxvk, from: dxvk, in: game)
        try write("patched-by-game-update", to: game.appending(path: "d3d11.dll"))

        try ProgramRendererStore.uninstall(in: game)

        XCTAssertEqual(try read(game.appending(path: "d3d11.dll")), "patched-by-game-update")
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.appending(path: "dxgi.dll").path))
    }

    func testFolderRunningOneRendererRefusesAnother() async throws {
        let coordinator = ProgramRendererCoordinator()
        try await coordinator.acquire(folder: game, placement: .programFolder(source: dxvk), backend: .dxvk)
        try await coordinator.acquire(folder: game, placement: .programFolder(source: dxvk), backend: .dxvk)

        do {
            try await coordinator.acquire(folder: game, placement: .bottle, backend: .wineD3D)
            XCTFail("A folder in use with DXVK must not lose its files")
        } catch ProgramRendererError.folderInUse {}

        await coordinator.release(folder: game)
        await coordinator.release(folder: game)
        try await coordinator.acquire(folder: game, placement: .bottle, backend: .wineD3D)
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.appending(path: "dxgi.dll").path))
    }

    func testOverridesPinEveryDirect3DModule() {
        XCTAssertNil(ProgramRenderer.dllOverrides(for: .dxvk, placement: .bottle))
        XCTAssertEqual(ProgramRenderer.dllOverrides(for: .wineD3D, placement: .environment),
                       "dxgi,d3d9,d3d10core,d3d11,d3d12=b")
        XCTAssertEqual(ProgramRenderer.dllOverrides(for: .dxvk, placement: .programFolder(source: dxvk)),
                       "dxgi,d3d9,d3d10core,d3d11=n,b;d3d12=b")
        XCTAssertEqual(ProgramRenderer.dllOverrides(for: .d3dmetal, placement: .programFolder(source: dxmt)),
                       "dxgi,d3d11,d3d12=n,b;d3d9,d3d10core=b")
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        String(bytes: try Data(contentsOf: url), encoding: .utf8) ?? ""
    }
}
