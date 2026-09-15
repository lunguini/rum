//
//  BottleArchitectureTests.swift
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

final class BottleArchitectureTests: XCTestCase {
    func testBottleArchitectureDefaultsToWin64() {
        let settings = BottleSettings()
        var environment: [String: String] = [:]

        settings.environmentVariables(wineEnv: &environment)

        XCTAssertEqual(settings.architecture, .win64)
        XCTAssertNil(environment["WINEARCH"])
    }

    func testWin32BottleArchitectureSetsWineArchEnvironment() {
        var settings = BottleSettings()
        settings.architecture = .win32
        var environment: [String: String] = [:]

        settings.environmentVariables(wineEnv: &environment)

        XCTAssertEqual(environment["WINEARCH"], "win32")
    }

    func testDisabledDXVKDoesNotSetDXVKAsyncEnvironment() {
        var settings = BottleSettings()
        settings.dxvk = false
        settings.dxvkAsync = true
        var environment: [String: String] = [:]

        settings.environmentVariables(wineEnv: &environment)

        XCTAssertNil(environment["DXVK_ASYNC"])
    }

    func testExplicitEnvironmentCanOverrideBottleArchitecture() throws {
        let bottleURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bottleURL) }

        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.architecture = .win32

        let environment = Wine.constructWineEnvironment(
            for: bottle,
            environment: ["WINEARCH": "win64"]
        )

        XCTAssertEqual(environment["WINEARCH"], "win64")
    }

    func testWin32PrefixProbeRejectsWow64OnlyWine() {
        let output = "wine: WINEARCH is set to 'win32' but this is not supported in wow64 mode."

        let supported = Wine.pureWin32PrefixProbeResult(
            output: output,
            terminationStatus: 1,
            initializedPrefix: false
        )

        XCTAssertFalse(supported)
    }

    func testWin32PrefixProbeRequiresSuccessfulPrefixInitialization() {
        XCTAssertTrue(
            Wine.pureWin32PrefixProbeResult(output: "", terminationStatus: 0, initializedPrefix: true)
        )
        XCTAssertFalse(
            Wine.pureWin32PrefixProbeResult(output: "", terminationStatus: 0, initializedPrefix: false)
        )
    }

    private func makeKey(
        binary: String = "/Libraries/Wine/bin/wine",
        resolved: String = "/WineBuilds/1.0/bin/wine",
        date: Date? = Date(timeIntervalSince1970: 1000)
    ) -> Wine.Win32SupportCacheKey {
        Wine.Win32SupportCacheKey(binaryPath: binary, resolvedPath: resolved, modificationDate: date)
    }

    func testWin32SupportCacheReturnsNilWhenEmpty() {
        XCTAssertNil(
            Wine.cachedWin32Support(for: makeKey(), cachedKey: nil, cachedValue: nil)
        )
    }

    func testWin32SupportCacheReturnsValueForMatchingKey() {
        let key = makeKey()
        XCTAssertEqual(
            Wine.cachedWin32Support(for: key, cachedKey: key, cachedValue: true),
            true
        )
        XCTAssertEqual(
            Wine.cachedWin32Support(for: key, cachedKey: key, cachedValue: false),
            false
        )
    }

    func testWin32SupportCacheInvalidatesWhenResolvedEngineChanges() {
        // Activating a different engine swaps the symlink target, so the resolved path differs.
        let cached = makeKey(resolved: "/WineBuilds/1.0/bin/wine")
        let current = makeKey(resolved: "/WineBuilds/2.0/bin/wine")
        XCTAssertNil(
            Wine.cachedWin32Support(for: current, cachedKey: cached, cachedValue: true)
        )
    }

    func testWin32SupportCacheInvalidatesWhenModificationDateChanges() {
        let cached = makeKey(date: Date(timeIntervalSince1970: 1000))
        let current = makeKey(date: Date(timeIntervalSince1970: 2000))
        XCTAssertNil(
            Wine.cachedWin32Support(for: current, cachedKey: cached, cachedValue: true)
        )
    }
}
