//
//  RendererLoaderTests.swift
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

final class RendererLoaderTests: XCTestCase {
    func testBuiltinOverlayHasPriorityAndUsesBuiltinOverride() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let windows = root.appending(path: "x86_64-windows")
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        var header = Data(repeating: 0, count: 96)
        header.replaceSubrange(0..<2, with: [0x4d, 0x5a])
        header.replaceSubrange(64..<81, with: Data("Wine builtin DLL\0".utf8))
        let dll = windows.appending(path: "d3d11.dll")
        try header.write(to: dll)
        let capabilities = WineGraphicsCapabilities(
            engineID: "test", engineName: "Test", wineRootURL: root,
            macDriverExportsRequiredAPI: true, dxmtRootURL: root, d3dmetalRootURL: nil
        )
        let environment = WhiskyWineInstaller.rendererLoaderEnvironment(for: .dxmt, capabilities: capabilities)
        XCTAssertEqual(environment["WINEDLLPATH_PREPEND"], root.path)
        XCTAssertEqual(environment["WINEDLLOVERRIDES"], "dxgi,d3d11,d3d10core=b")

        header.replaceSubrange(64..<81, with: Data(repeating: 0, count: 17))
        try header.write(to: dll)
        XCTAssertNil(WhiskyWineInstaller.rendererLoaderEnvironment(
            for: .dxmt, capabilities: capabilities
        )["WINEDLLOVERRIDES"])
        XCTAssertTrue(WhiskyWineInstaller.rendererLoaderEnvironment(
            for: .wineD3D, capabilities: capabilities
        ).isEmpty)
    }

    func testTruncatedOrUnrelatedFileIsNotBuiltin() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("Wine builtin DLL\0".utf8).write(to: file)
        XCTAssertFalse(WhiskyWineInstaller.isWineBuiltinDLL(file))
    }
}
