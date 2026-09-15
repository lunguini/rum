//
//  WineManagerTests.swift
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

final class WineManagerTests: XCTestCase {
    private var temporaryLibrary: URL!

    override func setUpWithError() throws {
        temporaryLibrary = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "Libraries")
        try FileManager.default.createDirectory(at: temporaryLibrary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryLibrary {
            try? FileManager.default.removeItem(at: temporaryLibrary.deletingLastPathComponent())
        }
    }

    func testInstalledWineBuildsAreReadFromVersionedStore() throws {
        try makeWineBuild(version: "11.6.0")
        try makeWineBuild(version: "11.10")

        let builds = WhiskyWineInstaller.installedWineBuilds(in: temporaryLibrary)

        XCTAssertEqual(builds.map(\.version), ["11.10", "11.6.0"])
        XCTAssertEqual(
            builds.first?.wineURL.standardizedFileURL,
            temporaryLibrary.appending(path: "WineBuilds/11.10/Wine").standardizedFileURL
        )
    }

    func testActiveWineVersionIsPersistedSeparatelyFromLegacyVersionFile() throws {
        try WhiskyWineInstaller.saveActiveWineVersion("11.6.0", in: temporaryLibrary)

        XCTAssertEqual(WhiskyWineInstaller.activeWineVersion(in: temporaryLibrary), "11.6.0")
        XCTAssertEqual(WhiskyWineInstaller.installedWineVersion(in: temporaryLibrary), "11.6.0")
    }

    func testActivatingWineVersionRefreshesCompatibilityWineFolder() throws {
        try makeWineBuild(version: "11.6.0")
        try makeWineBuild(version: "11.10")
        let legacyWine = temporaryLibrary.appending(path: "Wine")
        try FileManager.default.createDirectory(at: legacyWine, withIntermediateDirectories: true)
        try "old".write(to: legacyWine.appending(path: "marker"), atomically: true, encoding: .utf8)

        try WhiskyWineInstaller.activateWineVersion("11.6.0", in: temporaryLibrary)

        XCTAssertEqual(WhiskyWineInstaller.activeWineVersion(in: temporaryLibrary), "11.6.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyWine.appending(path: "bin/wine").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyWine.appending(path: "marker").path))
    }

    func testRemovingActiveWineVersionFails() throws {
        try makeWineBuild(version: "11.6.0")
        try WhiskyWineInstaller.saveActiveWineVersion("11.6.0", in: temporaryLibrary)

        XCTAssertThrowsError(try WhiskyWineInstaller.removeWineVersion("11.6.0", in: temporaryLibrary))
    }

    func testMigratingLegacyWineFolderPreservesCurrentInstallAsVersionedBuild() throws {
        let legacyWineBin = temporaryLibrary.appending(path: "Wine/bin")
        try FileManager.default.createDirectory(at: legacyWineBin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: legacyWineBin.appending(path: "wine").path, contents: Data())
        try WhiskyWineInstaller.saveActiveWineVersion("11.10", in: temporaryLibrary)

        try WhiskyWineInstaller.migrateLegacyWineIfNeeded(in: temporaryLibrary)

        let migratedWine = temporaryLibrary.appending(path: "WineBuilds/11.10/Wine/bin/wine")
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedWine.path))
        XCTAssertEqual(WhiskyWineInstaller.activeWineVersion(in: temporaryLibrary), "11.10")
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryLibrary.appending(path: "Wine/bin/wine").path))
    }

    func testStableReleaseListPrefersStagingAssetAndSkipsReleaseCandidates() throws {
        let releases = [
            GcenxRelease(
                tagName: "11.11-rc1",
                assets: [
                    GcenxAsset(
                        name: "wine-staging-11.11-rc1-osx64.tar.xz",
                        browserDownloadUrl: "https://example.test/rc.tar.xz",
                        size: 1
                    )
                ]
            ),
            GcenxRelease(
                tagName: "11.10",
                assets: [
                    GcenxAsset(
                        name: "wine-devel-11.10-osx64.tar.xz",
                        browserDownloadUrl: "https://example.test/devel.tar.xz",
                        size: 2
                    ),
                    GcenxAsset(
                        name: "wine-staging-11.10-osx64.tar.xz",
                        browserDownloadUrl: "https://example.test/staging.tar.xz",
                        size: 3
                    )
                ]
            )
        ]

        let available = WhiskyWineInstaller.availableWineReleases(from: releases)

        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available.first?.version, "11.10")
        XCTAssertEqual(available.first?.downloadURL.absoluteString, "https://example.test/staging.tar.xz")
        XCTAssertEqual(available.first?.assetName, "wine-staging-11.10-osx64.tar.xz")
        XCTAssertEqual(available.first?.size, 3)
    }

    func testCrossOverEngineIsDetectedFromAppBundle() throws {
        let appURL = try makeCrossOverApp(version: "26.0")

        let engine = try XCTUnwrap(WhiskyWineInstaller.crossOverEngine(at: appURL))

        XCTAssertEqual(engine.name, "CrossOver")
        XCTAssertEqual(engine.version, "26.0")
        XCTAssertEqual(engine.kind, .crossOver)
        XCTAssertEqual(
            engine.wineBinaryURL.standardizedFileURL,
            appURL.appending(path: "Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine")
                .standardizedFileURL
        )
        XCTAssertEqual(
            engine.wineserverBinaryURL.standardizedFileURL,
            appURL.appending(path: "Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineserver")
                .standardizedFileURL
        )
    }

    func testGamePortingToolkitEngineIsDetectedFromAppBundle() throws {
        let appURL = try makeGamePortingToolkitApp(version: "3.0")

        let engine = try XCTUnwrap(WhiskyWineInstaller.gamePortingToolkitEngine(at: appURL))

        XCTAssertEqual(engine.name, "Game Porting Toolkit")
        XCTAssertEqual(engine.version, "3.0")
        XCTAssertEqual(engine.kind, .gamePortingToolkit)
        XCTAssertEqual(
            engine.wineBinaryURL.standardizedFileURL,
            appURL.appending(path: "Contents/Resources/wine/bin/wine64").standardizedFileURL
        )
        XCTAssertEqual(
            engine.wineserverBinaryURL.standardizedFileURL,
            appURL.appending(path: "Contents/Resources/wine/bin/wineserver").standardizedFileURL
        )
    }

    func testImportingCrossOverPersistsExternalEngine() throws {
        let appURL = try makeCrossOverApp(version: "26.0")

        let imported = try WhiskyWineInstaller.importCrossOverEngine(at: appURL, in: temporaryLibrary)
        let engines = WhiskyWineInstaller.externalWineEngines(in: temporaryLibrary)

        XCTAssertEqual(engines, [imported])
        XCTAssertEqual(imported.displayName, "CrossOver 26.0")
    }

    func testActivatingExternalCrossOverEngineUsesItsExecutables() throws {
        let appURL = try makeCrossOverApp(version: "26.0")
        let imported = try WhiskyWineInstaller.importCrossOverEngine(at: appURL, in: temporaryLibrary)

        try WhiskyWineInstaller.activateExternalWineEngine(imported.id, in: temporaryLibrary)

        XCTAssertEqual(WhiskyWineInstaller.installedWineVersion(in: temporaryLibrary), "CrossOver 26.0")
        XCTAssertEqual(WhiskyWineInstaller.activeExternalWineEngine(in: temporaryLibrary), imported)
        XCTAssertEqual(
            WhiskyWineInstaller.activeWineExecutable(in: temporaryLibrary).standardizedFileURL,
            imported.wineBinaryURL.standardizedFileURL
        )
        XCTAssertEqual(
            WhiskyWineInstaller.activeWineserverExecutable(in: temporaryLibrary).standardizedFileURL,
            imported.wineserverBinaryURL.standardizedFileURL
        )
    }

    func testActiveCrossOverEngineRefreshesStaleExecutableMetadata() throws {
        let appURL = try makeCrossOverApp(version: "26.0")
        let oldWine = appURL.appending(path: "Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wine")
        let newWine = appURL.appending(path: "Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix/wine")
        let engine = ExternalWineEngine(
            id: "crossover:\(appURL.standardizedFileURL.path)",
            name: "CrossOver",
            version: "26.0",
            kind: .crossOver,
            appURL: appURL,
            wineURL: appURL.appending(path: "Contents/SharedSupport/CrossOver"),
            wineBinaryURL: oldWine,
            wineserverBinaryURL: appURL.appending(
                path: "Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wineserver"
            )
        )
        let enginesData = try JSONEncoder().encode([engine])
        try enginesData.write(to: temporaryLibrary.appending(path: "external-wine-engines.json"))
        let activeData = try JSONEncoder().encode(engine.id)
        try activeData.write(to: temporaryLibrary.appending(path: "active-external-wine-engine.json"))

        let active = try XCTUnwrap(WhiskyWineInstaller.activeExternalWineEngine(in: temporaryLibrary))

        XCTAssertEqual(active.wineBinaryURL.standardizedFileURL, newWine.standardizedFileURL)
        XCTAssertEqual(
            WhiskyWineInstaller.activeWineExecutable(in: temporaryLibrary).standardizedFileURL,
            newWine.standardizedFileURL
        )
    }

    private func makeWineBuild(version: String) throws {
        let bin = temporaryLibrary
            .appending(path: "WineBuilds")
            .appending(path: version)
            .appending(path: "Wine")
            .appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appending(path: "wine").path, contents: Data())
    }

    private func makeCrossOverApp(version: String) throws -> URL {
        let appURL = temporaryLibrary
            .deletingLastPathComponent()
            .appending(path: "CrossOver.app")
        let hostedApplication = appURL
            .appending(path: "Contents/SharedSupport/CrossOver/CrossOver-Hosted Application")
        let unixWine = appURL
            .appending(path: "Contents/SharedSupport/CrossOver/lib/wine/x86_64-unix")
        try FileManager.default.createDirectory(at: hostedApplication, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unixWine, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: hostedApplication.appending(path: "wine").path, contents: Data())
        FileManager.default.createFile(atPath: hostedApplication.appending(path: "wineserver").path, contents: Data())
        FileManager.default.createFile(atPath: unixWine.appending(path: "wine").path, contents: Data())

        let info: [String: Any] = [
            "CFBundleName": "CrossOver",
            "CFBundleShortVersionString": version
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: appURL.appending(path: "Contents/Info.plist"))
        return appURL
    }

    private func makeGamePortingToolkitApp(version: String) throws -> URL {
        let appURL = temporaryLibrary
            .deletingLastPathComponent()
            .appending(path: "Game Porting Toolkit.app")
        let binURL = appURL.appending(path: "Contents/Resources/wine/bin")
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: binURL.appending(path: "wine64").path, contents: Data())
        FileManager.default.createFile(atPath: binURL.appending(path: "wineserver").path, contents: Data())

        let info: [String: Any] = [
            "CFBundleName": "Game Porting Toolkit",
            "CFBundleShortVersionString": version
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: appURL.appending(path: "Contents/Info.plist"))
        return appURL
    }
}
