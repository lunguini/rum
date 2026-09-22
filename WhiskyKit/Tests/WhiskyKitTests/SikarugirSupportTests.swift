//
//  SikarugirSupportTests.swift
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
import XCTest
@testable import WhiskyKit

final class SikarugirSupportTests: XCTestCase {
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

    func testTemplateSupportProvidesRendererAndLibraryRoots() throws {
        let wrapperFolder = temporaryLibrary.appending(path: "Sikarugir/Wrapper")
        let frameworks = wrapperFolder.appending(path: "Template-1.0.5.app/Contents/Frameworks")
        try makeFile(frameworks.appending(path: "libinotify.0.dylib"))
        try makeDXMTPayload(at: frameworks.appending(path: "renderer/dxmt/wine"))

        let discoveredFrameworks = WhiskyWineInstaller.sikarugirTemplateFrameworksURL(
            in: wrapperFolder
        )
        let discoveredDXMT = WhiskyWineInstaller.sikarugirTemplateRendererRoot(
            for: .dxmt,
            in: wrapperFolder
        )

        XCTAssertEqual(discoveredFrameworks?.resolvingSymlinksInPath(), frameworks.resolvingSymlinksInPath())
        XCTAssertEqual(
            discoveredDXMT?.resolvingSymlinksInPath(),
            frameworks.appending(path: "renderer/dxmt").resolvingSymlinksInPath()
        )
    }

    func testTemplateReleaseListPrefersNewestTemplateAsset() throws {
        let releases = [
            GcenxRelease(
                tagName: "v1.0",
                assets: [
                    GcenxAsset(
                        name: "Template-1.0.5.tar.xz",
                        browserDownloadUrl: "https://example.test/template05.tar.xz",
                        size: 5
                    ),
                    GcenxAsset(
                        name: "Template-1.0.11.tar.xz",
                        browserDownloadUrl: "https://example.test/template011.tar.xz",
                        size: 11
                    ),
                    GcenxAsset(
                        name: "creator.tar.xz",
                        browserDownloadUrl: "https://example.test/creator.tar.xz",
                        size: 1
                    )
                ]
            )
        ]

        let available = WhiskyWineInstaller.availableSikarugirTemplateReleases(from: releases)

        XCTAssertEqual(available.map(\.version), ["Template-1.0.11", "Template-1.0.5"])
    }

    func testInstallingTemplateSupportStoresFrameworksInLibrary() async throws {
        let sourceContainer = temporaryLibrary.appending(path: "template-archive-source")
        let frameworks = sourceContainer.appending(path: "Template-1.0.11.app/Contents/Frameworks")
        try makeFile(frameworks.appending(path: "libinotify.0.dylib"))

        let archive = temporaryLibrary.deletingLastPathComponent().appending(path: "template.tar.xz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-cJf", archive.path,
            "-C", sourceContainer.path,
            "Template-1.0.11.app"
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        try await WhiskyWineInstaller.installSikarugirSupport(
            from: archive,
            version: "Template-1.0.11",
            in: temporaryLibrary
        )

        let installedFrameworks = WhiskyWineInstaller.sikarugirTemplateFrameworksURL(
            for: temporaryLibrary
        )
        XCTAssertEqual(
            installedFrameworks?.resolvingSymlinksInPath(),
            temporaryLibrary
                .appending(path: "SikarugirSupport/Template-1.0.11/Frameworks")
                .resolvingSymlinksInPath()
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testInstalledSikarugirTemplateIsDetectedWhenPresent() throws {
        let libraryFolder = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.adrianlungu.rum/Libraries")
        guard let engine = WhiskyWineInstaller.activeWineEngine(in: libraryFolder),
              engine.kind == .sikarugir,
              WhiskyWineInstaller.sikarugirTemplateFrameworksURL(for: libraryFolder) != nil else {
            return
        }

        let capabilities = WhiskyWineInstaller.activeWineGraphicsCapabilities(in: libraryFolder)
        let environment = WhiskyWineInstaller.graphicsEnvironment(for: .dxmt, in: libraryFolder)

        XCTAssertTrue(capabilities.macDriverExportsRequiredAPI)
        XCTAssertNotNil(capabilities.dxmtRootURL)
        XCTAssertTrue(environment["WINEDLLPATH"]?.contains("renderer/dxmt/wine/x86_64-unix") == true)
        XCTAssertTrue(environment["DYLD_FALLBACK_LIBRARY_PATH"]?.contains("Frameworks") == true)
    }

    func testSupportLibrariesAreLinkedIntoEngineLibFolder() throws {
        let frameworks = temporaryLibrary.appending(path: "SikarugirSupport/Template-1.0.5/Frameworks")
        try makeFile(frameworks.appending(path: "libinotify.0.dylib"))
        try makeFile(frameworks.appending(path: "libintl.8.dylib"))
        // GStreamer keeps its libraries in a versioned framework rather than at the top level.
        let gstreamerLib = frameworks.appending(path: "GStreamer.framework/Versions/1.0/lib")
        try makeFile(gstreamerLib.appending(path: "libgstreamer-1.0.0.dylib"))

        let engineRoot = temporaryLibrary.appending(path: "WineBuilds/sikarugir/Wine")
        try makeFile(engineRoot.appending(path: "bin/wine"))

        let linked = WhiskyWineInstaller.linkSikarugirSupportLibraries(
            forEngineRoot: engineRoot,
            frameworks: frameworks
        )

        XCTAssertTrue(linked.contains("libinotify.0.dylib"))
        XCTAssertTrue(linked.contains("libintl.8.dylib"))
        XCTAssertTrue(linked.contains("libgstreamer-1.0.0.dylib"))

        // @rpath on the Sikarugir binaries is @loader_path/../lib, so the links must land here.
        let libFolder = engineRoot.appending(path: "lib")
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: libFolder.appending(path: "libinotify.0.dylib").path
            ),
            frameworks.appending(path: "libinotify.0.dylib").path
        )
        // Directory enumeration resolves /var to /private/var, so compare resolved paths.
        XCTAssertEqual(
            URL(filePath: try FileManager.default.destinationOfSymbolicLink(
                atPath: libFolder.appending(path: "libgstreamer-1.0.0.dylib").path
            )).resolvingSymlinksInPath(),
            gstreamerLib.appending(path: "libgstreamer-1.0.0.dylib").resolvingSymlinksInPath()
        )

        // Libraries the template does not ship are simply skipped.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: libFolder.appending(path: "libavcodec.61.dylib").path)
        )
    }

    func testLinkingIsIdempotentAndRepointsStaleLinks() throws {
        let engineRoot = temporaryLibrary.appending(path: "WineBuilds/sikarugir/Wine")
        let oldFrameworks = temporaryLibrary.appending(path: "SikarugirSupport/Template-1.0.5/Frameworks")
        try makeFile(oldFrameworks.appending(path: "libinotify.0.dylib"))

        WhiskyWineInstaller.linkSikarugirSupportLibraries(
            forEngineRoot: engineRoot,
            frameworks: oldFrameworks
        )
        // Repeating the call must not fail on the existing link.
        WhiskyWineInstaller.linkSikarugirSupportLibraries(
            forEngineRoot: engineRoot,
            frameworks: oldFrameworks
        )

        let destination = engineRoot.appending(path: "lib/libinotify.0.dylib")
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: destination.path),
            oldFrameworks.appending(path: "libinotify.0.dylib").path
        )

        // Installing a newer template must repoint the link instead of leaving it dangling.
        let newFrameworks = temporaryLibrary.appending(path: "SikarugirSupport/Template-1.0.11/Frameworks")
        try makeFile(newFrameworks.appending(path: "libinotify.0.dylib"))
        try FileManager.default.removeItem(at: oldFrameworks.deletingLastPathComponent())

        WhiskyWineInstaller.linkSikarugirSupportLibraries(
            forEngineRoot: engineRoot,
            frameworks: newFrameworks
        )

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: destination.path),
            newFrameworks.appending(path: "libinotify.0.dylib").path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testEngineOwnedLibraryIsNotReplacedByLink() throws {
        let frameworks = temporaryLibrary.appending(path: "SikarugirSupport/Template-1.0.5/Frameworks")
        try makeFile(frameworks.appending(path: "libinotify.0.dylib"))

        let engineRoot = temporaryLibrary.appending(path: "WineBuilds/sikarugir/Wine")
        let shipped = engineRoot.appending(path: "lib/libinotify.0.dylib")
        try makeFile(shipped)

        WhiskyWineInstaller.linkSikarugirSupportLibraries(
            forEngineRoot: engineRoot,
            frameworks: frameworks
        )

        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: shipped.path))
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
