//
//  GraphicsBackendTests.swift
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

// These tests keep renderer selection, capability detection, and transactional file handling in
// one fixture because those behaviors must remain compatible as a single feature.
// swiftlint:disable:next type_body_length
final class GraphicsBackendTests: XCTestCase {
    func testLegacyDXVKSelectionMapsToGraphicsBackend() {
        var settings = BottleSettings()

        XCTAssertEqual(settings.graphicsBackend, .dxvk)

        settings.dxvk = false
        XCTAssertEqual(settings.graphicsBackend, .wineD3D)

        settings.graphicsBackend = .dxmt
        XCTAssertEqual(settings.graphicsBackend, .dxmt)
        XCTAssertFalse(settings.dxvk)
    }

    func testLegacyMetadataIsMigratedWithoutChangingItsRenderer() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = root.appending(path: "Metadata.plist")
        var legacy = BottleSettings()
        legacy.dxvk = false
        try legacy.encode(to: metadata)
        var legacyPropertyList = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: metadata),
                format: nil
            ) as? [String: Any]
        )
        legacyPropertyList.removeValue(forKey: "selectedGraphicsBackend")
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: legacyPropertyList,
            format: .xml,
            options: 0
        )
        try legacyData.write(to: metadata)

        let decoded = try BottleSettings.decode(from: metadata)

        XCTAssertEqual(decoded.graphicsBackend, .wineD3D)
        let migrated = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: metadata),
                format: nil
            ) as? [String: Any]
        )
        XCTAssertNotNil(migrated["selectedGraphicsBackend"])
    }

    func testGraphicsBackendEnvironmentUsesBackendSpecificOverrides() {
        var settings = BottleSettings()
        var environment: [String: String] = [:]

        settings.graphicsBackend = .dxmt
        settings.environmentVariables(wineEnv: &environment)
        XCTAssertEqual(environment["WINEDLLOVERRIDES"], "dxgi,d3d11,d3d10core=n,b")
        XCTAssertNil(environment["DXVK_ASYNC"])

        environment.removeAll()
        settings.graphicsBackend = .d3dmetal
        settings.environmentVariables(wineEnv: &environment)
        XCTAssertEqual(environment["WINEDLLOVERRIDES"], "dxgi,d3d11,d3d12=n,b")

        environment.removeAll()
        settings.graphicsBackend = .wineD3D
        settings.environmentVariables(wineEnv: &environment)
        XCTAssertEqual(environment["WINEDLLOVERRIDES"], "dxgi,d3d9,d3d10core,d3d11=b")
    }

    func testMetalBackendsRequireWin64() {
        let capabilities = WineGraphicsCapabilities(
            engineID: "test",
            engineName: "Test",
            wineRootURL: URL(fileURLWithPath: "/tmp/wine"),
            macDriverExportsRequiredAPI: true,
            dxmtRootURL: URL(fileURLWithPath: "/tmp/dxmt"),
            d3dmetalRootURL: URL(fileURLWithPath: "/tmp/d3dmetal")
        )

        let dxmt = capabilities.availability(for: .dxmt, architecture: .win32, dxvkInstalled: true)
        let d3dmetal = capabilities.availability(for: .d3dmetal, architecture: .win32, dxvkInstalled: true)

        XCTAssertFalse(dxmt.isAvailable)
        XCTAssertFalse(d3dmetal.isAvailable)
        XCTAssertEqual(dxmt.reason, "Only 64-bit prefixes are supported by this backend.")
        XCTAssertEqual(d3dmetal.reason, "Only 64-bit prefixes are supported by this backend.")
    }

    func testGraphicsBackendErrorIncludesRecoveryAdvice() {
        let error = GraphicsBackendError.unavailable(
            .dxmt,
            "Wine engine Gcenx 11.15 has no compatible DXMT payload."
        )

        XCTAssertTrue(error.localizedDescription.contains("Gcenx 11.15"))
        XCTAssertTrue(error.localizedDescription.contains("Configuration → Runtime"))
        XCTAssertTrue(error.localizedDescription.contains("another renderer"))
    }

    func testDXMTPayloadRequiresComplete64BitLayout() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(WhiskyWineInstaller.hasDXMTPayload(at: root))
        try makeFile(root.appending(path: "x86_64-unix/winemetal.so"))
        try makeFile(root.appending(path: "x86_64-windows/winemetal.dll"))
        try makeFile(root.appending(path: "x86_64-windows/d3d11.dll"))
        XCTAssertFalse(WhiskyWineInstaller.hasDXMTPayload(at: root))
        try makeFile(root.appending(path: "x86_64-windows/dxgi.dll"))
        XCTAssertTrue(WhiskyWineInstaller.hasDXMTPayload(at: root))
    }

    func testD3DMetalPayloadRequiresFrameworkSharedLibraryAndModules() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appending(path: "external/D3DMetal.framework"),
            withIntermediateDirectories: true
        )
        try makeFile(root.appending(path: "external/libd3dshared.dylib"))
        try makeFile(root.appending(path: "wine/x86_64-windows/d3d11.dll"))
        try makeFile(root.appending(path: "wine/x86_64-windows/d3d12.dll"))
        XCTAssertFalse(WhiskyWineInstaller.hasD3DMetalPayload(at: root))

        try makeFile(root.appending(path: "wine/x86_64-windows/dxgi.dll"))
        XCTAssertTrue(WhiskyWineInstaller.hasD3DMetalPayload(at: root))
    }

    func testGraphicsAvailabilityUsesProvidedLibraryFolderForDXVK() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeFile(root.appending(path: "DXVK/x64/d3d10core.dll"))
        try makeFile(root.appending(path: "DXVK/x64/d3d11.dll"))

        XCTAssertTrue(WhiskyWineInstaller.isDXVKInstalled(for: .win64, in: root))
        let availability = WhiskyWineInstaller.graphicsBackendAvailability(
            for: .win64,
            in: root
        )
        XCTAssertTrue(availability.first { $0.backend == .dxvk }?.isAvailable == true)
    }

    func testRendererDLLReplacementIsIdempotentAndRestorable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        let destination = root.appending(path: "destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let sourceDLL = source.appending(path: "d3d11.dll")
        let destinationDLL = destination.appending(path: "d3d11.dll")
        try Data("replacement".utf8).write(to: sourceDLL)
        try Data("original".utf8).write(to: destinationDLL)

        try FileManager.default.replaceDLLs(
            in: destination,
            withContentsIn: source,
            makeOriginalCopy: true
        )
        XCTAssertEqual(try Data(contentsOf: destinationDLL), Data("replacement".utf8))
        XCTAssertEqual(
            try Data(contentsOf: destinationDLL.appendingPathExtension("orig")),
            Data("original".utf8)
        )

        try FileManager.default.replaceDLLs(
            in: destination,
            withContentsIn: source,
            makeOriginalCopy: true
        )
        XCTAssertEqual(
            try Data(contentsOf: destinationDLL.appendingPathExtension("orig")),
            Data("original".utf8)
        )

        try FileManager.default.restoreDLLs(in: destination, from: source)
        XCTAssertEqual(try Data(contentsOf: destinationDLL), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationDLL.appendingPathExtension("orig").path))
    }

    func testRendererRestoreRejectsUserModifiedReplacement() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        let destination = root.appending(path: "destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sourceDLL = source.appending(path: "d3d11.dll")
        let destinationDLL = destination.appending(path: "d3d11.dll")
        try Data("replacement".utf8).write(to: sourceDLL)
        try Data("original".utf8).write(to: destinationDLL)

        try FileManager.default.replaceDLLs(in: destination, withContentsIn: source)
        try Data("user change".utf8).write(to: destinationDLL)

        XCTAssertThrowsError(try FileManager.default.restoreDLLs(in: destination, from: source)) { error in
            XCTAssertEqual(
                error as? RendererStateError,
                .userModifiedFile(destinationDLL.path(percentEncoded: false))
            )
        }
        XCTAssertEqual(try Data(contentsOf: destinationDLL), Data("user change".utf8))
    }

    func testRendererStateManifestRestoresFilesAfterArtifactChanges() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceRoot = root.appending(path: "renderer")
        try makeFileWithData(sourceRoot.appending(path: "x64/d3d11.dll"), data: "new-x64")
        try makeFileWithData(sourceRoot.appending(path: "x32/d3d11.dll"), data: "new-x32")

        let bottleURL = root.appending(path: "bottle")
        let system32 = bottleURL.appending(path: "drive_c/windows/system32")
        let syswow64 = bottleURL.appending(path: "drive_c/windows/syswow64")
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syswow64, withIntermediateDirectories: true)
        try makeFileWithData(system32.appending(path: "d3d11.dll"), data: "old-x64")
        try makeFileWithData(syswow64.appending(path: "d3d11.dll"), data: "old-x32")
        let bottle = Bottle(bottleUrl: bottleURL)

        try RendererStateStore.applyDXVK(bottle: bottle, sourceRoot: sourceRoot)

        let manifest = bottleURL.appending(path: ".rum-renderer-state.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
        XCTAssertEqual(
            try Data(contentsOf: system32.appending(path: "d3d11.dll")),
            Data("new-x64".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: syswow64.appending(path: "d3d11.dll")),
            Data("new-x32".utf8)
        )

        try RendererStateStore.restoreDXVK(bottle: bottle, sourceRoot: sourceRoot)

        XCTAssertEqual(
            try Data(contentsOf: system32.appending(path: "d3d11.dll")),
            Data("old-x64".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: syswow64.appending(path: "d3d11.dll")),
            Data("old-x32".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
    }

    func testRendererStateManifestRejectsPathsOutsideBottle() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottleURL = root.appending(path: "bottle")
        try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: bottleURL)
        let state = BottleRendererState(
            backend: .dxvk,
            files: [
                RendererFileState(
                    relativePath: "../outside.dll",
                    installedSHA256: "not-used",
                    originalSHA256: nil,
                    originalExisted: false
                )
            ]
        )
        let data = try PropertyListEncoder().encode(state)
        try data.write(to: bottleURL.appending(path: ".rum-renderer-state.plist"))

        XCTAssertThrowsError(
            try RendererStateStore.restoreDXVK(
                bottle: bottle,
                sourceRoot: root.appending(path: "renderer")
            )
        ) { error in
            guard let rendererError = error as? RendererStateError else {
                XCTFail("Expected a renderer manifest error, got \(error)")
                return
            }
            if case .invalidManifest = rendererError {
                return
            }
            XCTFail("Expected an invalid renderer manifest error, got \(error)")
        }
    }

    func testInstalledCrossOverGraphicsPayloadIsDetectedWhenPresent() {
        let crossOver = URL(fileURLWithPath: "/Applications/CrossOver.app")
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.adrianlungu.rum/Libraries")
        guard FileManager.default.fileExists(atPath: crossOver.path),
              FileManager.default.fileExists(
                atPath: library.appending(path: "active-external-wine-engine.json").path
              ) else {
            return
        }

        let capabilities = WhiskyWineInstaller.activeWineGraphicsCapabilities(in: library)
        guard capabilities.engineID.hasPrefix("crossover:") else { return }

        XCTAssertTrue(capabilities.macDriverExportsRequiredAPI)
        XCTAssertTrue(capabilities.supportsDXMT)
        XCTAssertTrue(capabilities.supportsD3DMetal)

        let dxmtEnvironment = WhiskyWineInstaller.graphicsEnvironment(for: .dxmt, in: library)
        XCTAssertEqual(dxmtEnvironment["CX_GRAPHICS_BACKEND"], "dxmt")
        XCTAssertTrue(dxmtEnvironment["WINEDLLPATH"]?.contains("/lib/dxmt/x86_64-windows") == true)

        let d3dmetalEnvironment = WhiskyWineInstaller.graphicsEnvironment(for: .d3dmetal, in: library)
        XCTAssertEqual(d3dmetalEnvironment["CX_GRAPHICS_BACKEND"], "d3dmetal")
        XCTAssertEqual(
            d3dmetalEnvironment["CX_APPLEGPTK_LIBD3DSHARED_PATH"],
            capabilities.d3dmetalRootURL?.appending(path: "external/libd3dshared.dylib").path
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeFile(_ url: URL) throws {
        try makeFileWithData(url, data: "")
    }

    private func makeFileWithData(_ url: URL, data: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(data.utf8).write(to: url)
    }
}
