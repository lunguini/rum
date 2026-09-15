//
//  RendererStateTests.swift
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

final class RendererStateTests: XCTestCase {
    func testEngineRendererPayloadsAreTransactional() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try RendererStateStore.applyDXMT(bottle: fixture.bottle, sourceRoot: fixture.dxmtRoot)
        try assertFile(fixture.system32.appending(path: "d3d11.dll"), equals: "dxmt-d3d11")
        try assertFile(fixture.syswow64.appending(path: "d3d11.dll"), equals: "dxmt-x86-d3d11")

        try RendererStateStore.applyD3DMetal(
            bottle: fixture.bottle,
            sourceRoot: fixture.d3dmetalRoot
        )
        try assertFile(fixture.system32.appending(path: "d3d11.dll"), equals: "d3dmetal-d3d11")
        try assertFile(fixture.syswow64.appending(path: "d3d11.dll"), equals: "original-x86-d3d11")

        try RendererStateStore.restoreRenderer(
            bottle: fixture.bottle,
            sourceRoot: fixture.root.appending(path: "unused-dxvk")
        )
        try assertOriginalFiles(in: fixture)
    }

    func testInstalledCrossOverPayloadsCanBeStagedAndRestored() throws {
        let crossOverLibrary = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.adrianlungu.rum/Libraries")
        let crossOver = URL(fileURLWithPath: "/Applications/CrossOver.app")
        guard FileManager.default.fileExists(atPath: crossOver.path),
              FileManager.default.fileExists(
                atPath: crossOverLibrary.appending(path: "active-external-wine-engine.json").path
              ) else {
            return
        }

        let capabilities = WhiskyWineInstaller.activeWineGraphicsCapabilities(in: crossOverLibrary)
        guard let dxmtRoot = capabilities.dxmtRootURL,
              let d3dmetalRoot = capabilities.d3dmetalRootURL else {
            return
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottleURL = root.appending(path: "bottle")
        let system32 = bottleURL.appending(path: "drive_c/windows/system32")
        let syswow64 = bottleURL.appending(path: "drive_c/windows/syswow64")
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syswow64, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleURL)

        try RendererStateStore.applyDXMT(bottle: bottle, sourceRoot: dxmtRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: system32.appending(path: "d3d11.dll").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: system32.appending(path: "winemetal.dll").path))

        try RendererStateStore.applyD3DMetal(bottle: bottle, sourceRoot: d3dmetalRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: system32.appending(path: "d3d12.dll").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: system32.appending(path: "d3d11.dll").path))

        try RendererStateStore.restoreRenderer(
            bottle: bottle,
            sourceRoot: root.appending(path: "unused-dxvk")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: system32.appending(path: "d3d11.dll").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: system32.appending(path: "d3d12.dll").path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: bottleURL.appending(path: ".rum-renderer-state.plist").path
            )
        )
    }

    func testManagedEngineRefreshDoesNotBlockRendererSwitch() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let engineRoot = fixture.root.appending(path: "engine")
        let engine = try makeEngine(at: engineRoot)

        try RendererStateStore.applyDXMT(
            bottle: fixture.bottle,
            sourceRoot: fixture.dxmtRoot,
            engine: engine
        )

        try simulateManagedEngineRefresh(in: fixture, engineRoot: engineRoot)

        try RendererStateStore.applyD3DMetal(
            bottle: fixture.bottle,
            sourceRoot: fixture.d3dmetalRoot,
            engine: engine
        )

        try assertFile(fixture.system32.appending(path: "d3d11.dll"), equals: "d3dmetal-d3d11")
        try assertFile(fixture.system32.appending(path: "dxgi.dll"), equals: "d3dmetal-dxgi")
        try assertFile(fixture.system32.appending(path: "d3d12.dll"), equals: "d3dmetal-d3d12")
        try assertFile(
            fixture.system32.appending(path: "winemetal.dll"),
            equals: "original-winemetal"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.system32.appending(path: "d3d10core.dll").path
            )
        )
        try assertFile(
            fixture.system32.appending(path: "nvapi64.dll"),
            equals: "original-nvapi64"
        )
        try assertFile(fixture.system32.appending(path: "nvngx.dll"), equals: "original-nvngx")
        try assertFile(fixture.syswow64.appending(path: "d3d11.dll"), equals: "original-x86-d3d11")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.syswow64.appending(path: "d3d10core.dll").path
            )
        )
    }

    func testExternalEngineRefreshDoesNotBlockRendererSwitch() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let engineRoot = fixture.root.appending(path: "engine")
        let engine = try makeEngine(at: engineRoot, kind: .crossOver)

        try RendererStateStore.applyDXMT(
            bottle: fixture.bottle,
            sourceRoot: fixture.dxmtRoot,
            engine: engine
        )
        try simulateManagedEngineRefresh(in: fixture, engineRoot: engineRoot)
        try RendererStateStore.applyD3DMetal(
            bottle: fixture.bottle,
            sourceRoot: fixture.d3dmetalRoot,
            engine: engine
        )

        try assertFile(fixture.system32.appending(path: "d3d11.dll"), equals: "d3dmetal-d3d11")
        try assertFile(fixture.system32.appending(path: "dxgi.dll"), equals: "d3dmetal-dxgi")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.system32.appending(path: "d3d10core.dll").path
            )
        )
    }

    func testManagedEngineRecoveryStillRejectsUnknownReplacement() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let engineRoot = fixture.root.appending(path: "engine")
        let engine = try makeEngine(at: engineRoot)

        try RendererStateStore.applyDXMT(
            bottle: fixture.bottle,
            sourceRoot: fixture.dxmtRoot,
            engine: engine
        )
        try Data("user-change".utf8).write(
            to: fixture.system32.appending(path: "d3d10core.dll")
        )

        XCTAssertThrowsError(
            try RendererStateStore.applyD3DMetal(
                bottle: fixture.bottle,
                sourceRoot: fixture.d3dmetalRoot,
                engine: engine
            )
        ) { error in
            XCTAssertEqual(
                error as? RendererStateError,
                .userModifiedFile(fixture.system32.appending(path: "d3d10core.dll").path)
            )
        }
    }

}
