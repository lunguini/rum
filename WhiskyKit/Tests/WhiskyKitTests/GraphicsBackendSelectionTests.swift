//
//  GraphicsBackendSelectionTests.swift
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

final class GraphicsBackendSelectionTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/wine")

    private func capabilities(
        macDriver: Bool = true,
        dxmt: Bool = true,
        d3dmetal: Bool = true
    ) -> WineGraphicsCapabilities {
        WineGraphicsCapabilities(
            engineID: "test",
            engineName: "Test",
            wineRootURL: root,
            macDriverExportsRequiredAPI: macDriver,
            dxmtRootURL: dxmt ? root : nil,
            d3dmetalRootURL: d3dmetal ? root : nil
        )
    }

    func testCompatibleRendererIsUnchanged() {
        let result = GraphicsBackendSelectionResolver.resolve(
            current: .dxmt,
            architecture: .win64,
            capabilities: capabilities(),
            dxvkInstalled: true
        )

        XCTAssertEqual(result.backend, .dxmt)
        XCTAssertFalse(result.didFallback)
    }

    func testUnsupportedRendererFallsBackToWineD3D() {
        let result = GraphicsBackendSelectionResolver.resolve(
            current: .dxmt,
            architecture: .win64,
            capabilities: capabilities(macDriver: false),
            dxvkInstalled: true
        )

        XCTAssertEqual(result.backend, .wineD3D)
        XCTAssertTrue(result.didFallback)
        XCTAssertNotNil(result.reason)
    }

    func testMissingEngineCapabilitiesRetainRenderer() {
        let result = GraphicsBackendSelectionResolver.resolve(
            current: .d3dmetal,
            architecture: .win64,
            capabilities: nil,
            dxvkInstalled: false
        )

        XCTAssertEqual(result.backend, .d3dmetal)
        XCTAssertFalse(result.didFallback)
    }

    func testWin32MetalRendererFallsBack() {
        let result = GraphicsBackendSelectionResolver.resolve(
            current: .d3dmetal,
            architecture: .win32,
            capabilities: capabilities(),
            dxvkInstalled: true
        )

        XCTAssertEqual(result.backend, .wineD3D)
        XCTAssertTrue(result.didFallback)
        XCTAssertEqual(result.reason, "Only 64-bit prefixes are supported by this backend.")
    }
}
