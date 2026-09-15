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

    private struct Fixture {
        let root: URL
        let dxmtRoot: URL
        let d3dmetalRoot: URL
        let bottleURL: URL
        let system32: URL
        let syswow64: URL
        let bottle: Bottle
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let dxmtRoot = root.appending(path: "dxmt")
        try makeFileWithData(dxmtRoot.appending(path: "x86_64-windows/d3d11.dll"), data: "dxmt-d3d11")
        try makeFileWithData(dxmtRoot.appending(path: "x86_64-windows/dxgi.dll"), data: "dxmt-dxgi")
        try makeFileWithData(
            dxmtRoot.appending(path: "x86_64-windows/winemetal.dll"),
            data: "dxmt-winemetal"
        )
        try makeFileWithData(
            dxmtRoot.appending(path: "i386-windows/d3d11.dll"),
            data: "dxmt-x86-d3d11"
        )

        let d3dmetalRoot = root.appending(path: "d3dmetal")
        try makeFileWithData(
            d3dmetalRoot.appending(path: "wine/x86_64-windows/d3d11.dll"),
            data: "d3dmetal-d3d11"
        )
        try makeFileWithData(
            d3dmetalRoot.appending(path: "wine/x86_64-windows/d3d12.dll"),
            data: "d3dmetal-d3d12"
        )
        try makeFileWithData(
            d3dmetalRoot.appending(path: "wine/x86_64-windows/dxgi.dll"),
            data: "d3dmetal-dxgi"
        )

        let bottleURL = root.appending(path: "bottle")
        let system32 = bottleURL.appending(path: "drive_c/windows/system32")
        let syswow64 = bottleURL.appending(path: "drive_c/windows/syswow64")
        try makeFileWithData(system32.appending(path: "d3d11.dll"), data: "original-d3d11")
        try makeFileWithData(system32.appending(path: "dxgi.dll"), data: "original-dxgi")
        try makeFileWithData(
            system32.appending(path: "winemetal.dll"),
            data: "original-winemetal"
        )
        try makeFileWithData(
            syswow64.appending(path: "d3d11.dll"),
            data: "original-x86-d3d11"
        )

        return Fixture(
            root: root,
            dxmtRoot: dxmtRoot,
            d3dmetalRoot: d3dmetalRoot,
            bottleURL: bottleURL,
            system32: system32,
            syswow64: syswow64,
            bottle: Bottle(bottleUrl: bottleURL)
        )
    }

    private func assertOriginalFiles(in fixture: Fixture) throws {
        try assertFile(fixture.system32.appending(path: "d3d11.dll"), equals: "original-d3d11")
        try assertFile(fixture.system32.appending(path: "dxgi.dll"), equals: "original-dxgi")
        try assertFile(
            fixture.system32.appending(path: "winemetal.dll"),
            equals: "original-winemetal"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.bottleURL.appending(path: ".rum-renderer-state.plist").path
            )
        )
    }

    private func makeFileWithData(_ url: URL, data: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(data.utf8).write(to: url)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func assertFile(_ url: URL, equals data: String) throws {
        XCTAssertEqual(try Data(contentsOf: url), Data(data.utf8))
    }
}
