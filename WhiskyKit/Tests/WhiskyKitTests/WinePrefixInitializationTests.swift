//
//  WinePrefixInitializationTests.swift
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

final class WinePrefixInitializationTests: XCTestCase {
    func testPrefixInitializationCompletesBeforeRendererPreparation() async throws {
        var events: [String] = []
        let bottlePath = "/tmp/rum-prefix-order-(UUID().uuidString)"

        try await Wine.prepareLaunchResources(
            bottlePath: bottlePath,
            backend: .dxvk,
            initialize: {
                events.append("wineboot-start")
                events.append("wineboot-finished")
            },
            prepare: {
                events.append("renderer-prepared")
            }
        )

        XCTAssertEqual(events, ["wineboot-start", "wineboot-finished", "renderer-prepared"])
    }

    func testPrefixInitializationFailurePreventsRendererPreparationAndReleasesLock() async throws {
        enum TestError: Error { case winebootFailed }
        var prepareCount = 0
        let bottlePath = "/tmp/rum-prefix-failure-(UUID().uuidString)"

        do {
            try await Wine.prepareLaunchResources(
                bottlePath: bottlePath,
                backend: .dxvk,
                initialize: { throw TestError.winebootFailed },
                prepare: { prepareCount += 1 }
            )
            XCTFail("Expected wineboot failure")
        } catch TestError.winebootFailed {
            // Expected.
        }
        XCTAssertEqual(prepareCount, 0)

        // A released lock allows a later launch attempt to proceed.
        try await Wine.prepareLaunchResources(
            bottlePath: bottlePath,
            backend: .dxvk,
            initialize: {},
            prepare: { prepareCount += 1 }
        )
        XCTAssertEqual(prepareCount, 1)
    }
}
