//
//  WineEngineTests.swift
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

import Foundation
import SemanticVersion
import XCTest
@testable import WhiskyKit

// These tests cover the shared engine catalog, archive installation, and runtime resolution as one
// behavior because the three pieces must stay compatible.
// swiftlint:disable:next type_body_length
final class WineEngineTests: XCTestCase {
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

    func testSikarugirReleaseListUsesAssetIdentityAndSkipsOtherEngines() throws {
        let releases = [
            GcenxRelease(
                tagName: "v1.0",
                assets: [
                    GcenxAsset(
                        name: "WS12WineSikarugir10.0_6.tar.xz",
                        browserDownloadUrl: "https://example.test/sikarugir.tar.xz",
                        size: 10
                    ),
                    GcenxAsset(
                        name: "WS12WineCX24.0.7_7.tar.xz",
                        browserDownloadUrl: "https://example.test/crossover.tar.xz",
                        size: 11
                    ),
                    GcenxAsset(
                        name: "WS12WineSikarugir10.0_6.tar.xz",
                        browserDownloadUrl: "https://example.test/duplicate.tar.xz",
                        size: 12
                    )
                ]
            )
        ]

        let available = WhiskyWineInstaller.availableSikarugirReleases(from: releases)

        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available.first?.kind, .sikarugir)
        XCTAssertEqual(available.first?.version, "WS12WineSikarugir10.0_6")
        XCTAssertEqual(available.first?.id, "sikarugir:WS12WineSikarugir10.0_6")
    }

    func testDXMTReleasePrefersTheBuiltinAsset() throws {
        let release = GcenxRelease(
            tagName: "v0.80",
            assets: [
                GcenxAsset(
                    name: "dxmt-v0.80-source.tar.gz",
                    browserDownloadUrl: "https://example.test/source.tar.gz",
                    size: 1
                ),
                GcenxAsset(
                    name: "dxmt-v0.80-builtin.tar.gz",
                    browserDownloadUrl: "https://example.test/builtin.tar.gz",
                    size: 2
                )
            ]
        )

        let available = try XCTUnwrap(WhiskyWineInstaller.availableDXMTRelease(from: release))

        XCTAssertEqual(available.version, "v0.80")
        XCTAssertEqual(available.assetName, "dxmt-v0.80-builtin.tar.gz")
    }

    func testStandaloneDXMTRootIsDiscoveredInRumLibrary() throws {
        let runtimeRoot = temporaryLibrary.appending(path: "DXMT/dxmt-v0.80-builtin")
        try makeDXMTPayload(at: runtimeRoot)

        XCTAssertTrue(WhiskyWineInstaller.isDXMTInstalled(in: temporaryLibrary))
        XCTAssertEqual(
            WhiskyWineInstaller.installedDXMTRoot(in: temporaryLibrary)?.resolvingSymlinksInPath(),
            runtimeRoot.resolvingSymlinksInPath()
        )
    }

    func testStandaloneDXMTPayloadIsUsedAsSharedFallbackForAnEngine() throws {
        let engineRoot = temporaryLibrary.appending(path: "engine/Wine")
        let sharedRoot = temporaryLibrary.appending(path: "DXMT/dxmt-v0.80-builtin")
        try makeWineExecutables(at: engineRoot)
        try makeDXMTPayload(at: sharedRoot)

        let engine = WineEngine(
            id: "sikarugir:test",
            name: "Sikarugir",
            version: "test",
            kind: .sikarugir,
            wineURL: engineRoot,
            wineBinaryURL: engineRoot.appending(path: "bin/wine"),
            wineserverBinaryURL: engineRoot.appending(path: "bin/wineserver")
        )
        let capabilities = WhiskyWineInstaller.graphicsCapabilities(
            for: engine,
            in: temporaryLibrary
        )

        XCTAssertEqual(
            capabilities.dxmtRootURL?.resolvingSymlinksInPath(),
            sharedRoot.resolvingSymlinksInPath()
        )
    }

    func testInstallingStandaloneDXMTPayloadWritesVersionMetadata() async throws {
        let sourceContainer = temporaryLibrary.appending(path: "dxmt-archive-source")
        let sourceRoot = sourceContainer.appending(path: "dxmt-v0.80-builtin")
        try makeDXMTPayload(at: sourceRoot)

        let archive = temporaryLibrary.deletingLastPathComponent().appending(path: "dxmt.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-czf", archive.path,
            "-C", sourceContainer.path,
            "dxmt-v0.80-builtin"
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        try await WhiskyWineInstaller.installDXMT(
            from: archive,
            version: "v0.80",
            in: temporaryLibrary
        )

        XCTAssertEqual(WhiskyWineInstaller.installedDXMTVersion(in: temporaryLibrary), "v0.80")
        XCTAssertTrue(WhiskyWineInstaller.isDXMTInstalled(in: temporaryLibrary))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testManagedBuildMetadataKeepsSikarugirSeparateFromLegacyGcenx() throws {
        try makeManagedBuild(version: "11.15", kind: .gcenx)
        try makeManagedBuild(version: "WS12WineSikarugir10.0_6", kind: .sikarugir)

        let builds = WhiskyWineInstaller.installedWineBuilds(in: temporaryLibrary)

        XCTAssertEqual(builds.count, 2)
        XCTAssertTrue(builds.contains { $0.id == "gcenx:11.15" && $0.kind == .gcenx })
        XCTAssertTrue(
            builds.contains {
                $0.id == "sikarugir:WS12WineSikarugir10.0_6" && $0.kind == .sikarugir
            }
        )
    }

    func testGlobalActivationPersistsEngineIDWithoutChangingTheOtherBuild() throws {
        try makeManagedBuild(version: "11.15", kind: .gcenx)
        try makeManagedBuild(version: "WS12WineSikarugir10.0_6", kind: .sikarugir)

        try WhiskyWineInstaller.activateWineEngine(
            "sikarugir:WS12WineSikarugir10.0_6",
            in: temporaryLibrary
        )

        XCTAssertEqual(
            WhiskyWineInstaller.activeWineEngineID(in: temporaryLibrary),
            "sikarugir:WS12WineSikarugir10.0_6"
        )
        XCTAssertEqual(
            WhiskyWineInstaller.activeWineEngine(in: temporaryLibrary)?.kind,
            .sikarugir
        )
        XCTAssertTrue(
            WhiskyWineInstaller.installedWineBuilds(in: temporaryLibrary)
                .first { $0.id == "gcenx:11.15" }?.isActive == false
        )
    }

    func testPinnedEngineResolutionUsesSelectedBuildAndRejectsMissingBuild() throws {
        try makeManagedBuild(version: "11.15", kind: .gcenx)
        try makeManagedBuild(version: "WS12WineSikarugir10.0_6", kind: .sikarugir)
        try WhiskyWineInstaller.activateWineEngine("gcenx:11.15", in: temporaryLibrary)

        let selected = try WhiskyWineInstaller.wineEngine(
            for: "sikarugir:WS12WineSikarugir10.0_6",
            in: temporaryLibrary
        )
        let global = try WhiskyWineInstaller.wineEngine(for: nil, in: temporaryLibrary)

        XCTAssertEqual(selected.kind, .sikarugir)
        XCTAssertEqual(global.kind, .gcenx)
        XCTAssertThrowsError(
            try WhiskyWineInstaller.wineEngine(for: "sikarugir:removed", in: temporaryLibrary)
        )
    }

    func testSelectedEngineIsUsedToConstructWineEnvironment() throws {
        try makeManagedBuild(version: "11.15", kind: .gcenx)
        try makeManagedBuild(version: "WS12WineSikarugir10.0_6", kind: .sikarugir)
        try WhiskyWineInstaller.activateWineEngine("gcenx:11.15", in: temporaryLibrary)

        let bottleURL = temporaryLibrary.deletingLastPathComponent().appending(path: "Bottle")
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.wineEngineID = "sikarugir:WS12WineSikarugir10.0_6"

        let environment = WhiskyWineInstaller.graphicsEnvironment(
            for: .wineD3D,
            engineID: bottle.settings.wineEngineID,
            in: temporaryLibrary
        )
        let selected = try XCTUnwrap(
            WhiskyWineInstaller.wineEngine(
                withID: "sikarugir:WS12WineSikarugir10.0_6",
                in: temporaryLibrary
            )
        )

        XCTAssertEqual(environment["WINELOADER"], selected.wineBinaryURL.path)
        XCTAssertEqual(environment["WINESERVER"], selected.wineserverBinaryURL.path)
    }

    func testBottleMetadataPreservesWineVersionAndEnginePin() throws {
        let metadata = temporaryLibrary.deletingLastPathComponent().appending(path: "Metadata.plist")
        var settings = BottleSettings()
        settings.wineVersion = SemanticVersion(10, 0, 0)
        settings.wineEngineID = "sikarugir:WS12WineSikarugir10.0_6"
        try settings.encode(to: metadata)

        let decoded = try BottleSettings.decode(from: metadata)

        XCTAssertEqual(decoded.wineVersion, SemanticVersion(10, 0, 0))
        XCTAssertEqual(decoded.wineEngineID, settings.wineEngineID)
    }

    func testWineRootDiscoveryAcceptsAppAndWineskinBundleLayouts() throws {
        let appContainer = temporaryLibrary.appending(path: "app-archive")
        let bundleContainer = temporaryLibrary.appending(path: "bundle-archive")
        let appWine = appContainer
            .deletingLastPathComponent()
            .appending(path: "app-archive/Wine Staging.app/Contents/Resources/wine")
        let bundleWine = bundleContainer
            .deletingLastPathComponent()
            .appending(path: "bundle-archive/wswine.bundle/Contents/Resources/wine")
        try makeWineExecutables(at: appWine)
        try makeWineExecutables(at: bundleWine)

        let appDiscovered = WhiskyWineInstaller.findWineRoot(in: appContainer)
        let bundleDiscovered = WhiskyWineInstaller.findWineRoot(in: bundleContainer)

        XCTAssertEqual(appDiscovered?.resolvingSymlinksInPath(), appWine.resolvingSymlinksInPath())
        XCTAssertEqual(bundleDiscovered?.resolvingSymlinksInPath(), bundleWine.resolvingSymlinksInPath())
    }

    func testInstallingSikarugirArchiveWritesManagedMetadataWithoutActivating() async throws {
        let sourceContainer = temporaryLibrary.appending(path: "archive-source")
        let sourceRoot = sourceContainer.appending(path: "wswine.bundle/Contents/Resources/wine")
        try makeWineExecutables(at: sourceRoot)

        let archive = temporaryLibrary.deletingLastPathComponent().appending(path: "sikarugir.tar.xz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-cJf", archive.path,
            "-C", sourceContainer.path,
            "wswine.bundle"
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        try await WhiskyWineInstaller.install(
            from: archive,
            version: "WS12WineSikarugir10.0_6",
            kind: .sikarugir,
            activate: false,
            in: temporaryLibrary
        )

        let installed = try XCTUnwrap(
            WhiskyWineInstaller.wineEngine(
                withID: "sikarugir:WS12WineSikarugir10.0_6",
                in: temporaryLibrary
            )
        )
        XCTAssertEqual(installed.kind, .sikarugir)
        XCTAssertEqual(
            WhiskyWineInstaller.activeWineEngineID(in: temporaryLibrary),
            "managed-wine"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    private func makeManagedBuild(version: String, kind: WineEngineKind) throws {
        let directoryName = WhiskyWineInstaller.managedWineDirectoryName(for: version, kind: kind)
        let root = temporaryLibrary
            .appending(path: "WineBuilds")
            .appending(path: directoryName)
            .appending(path: "Wine")
        try makeWineExecutables(at: root)
        let metadata = InstalledWineEngineMetadata(
            id: WineEngine.managedID(kind: kind, version: version),
            name: kind.displayName,
            version: version,
            kind: kind
        )
        try WhiskyWineInstaller.writeEngineMetadata(
            metadata,
            at: root.deletingLastPathComponent()
        )
    }

    private func makeWineExecutables(at root: URL) throws {
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appending(path: "wine").path, contents: Data())
        FileManager.default.createFile(atPath: bin.appending(path: "wineserver").path, contents: Data())
    }

    private func makeDXMTPayload(at root: URL) throws {
        try makeFile(root.appending(path: "x86_64-unix/winemetal.so"))
        try makeFile(root.appending(path: "x86_64-windows/winemetal.dll"))
        try makeFile(root.appending(path: "x86_64-windows/d3d11.dll"))
        try makeFile(root.appending(path: "x86_64-windows/dxgi.dll"))
    }

    private func makeFile(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }
}
