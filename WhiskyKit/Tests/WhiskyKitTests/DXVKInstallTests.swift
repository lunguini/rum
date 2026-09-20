//
//  DXVKInstallTests.swift
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

final class DXVKInstallTests: XCTestCase {
    func testValidArchiveInstallsDetectableRuntime() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source/dxvk/x64")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for name in ["d3d10core.dll", "d3d11.dll"] {
            try Data("runtime".utf8).write(to: source.appending(path: name))
        }
        let archive = root.appending(path: "dxvk.tar.gz")
        try makeArchive(from: root.appending(path: "source"), to: archive)
        let library = root.appending(path: "Libraries")
        try await WhiskyWineInstaller.installDXVK(from: archive, in: library)
        XCTAssertTrue(WhiskyWineInstaller.isDXVKInstalled(for: .win64, in: library))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testInvalidArchiveReportsFailureAndPreservesExistingRuntime() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        let library = root.appending(path: "Libraries")
        let existing = library.appending(path: "DXVK/x64")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        for name in ["d3d10core.dll", "d3d11.dll"] {
            try Data("existing".utf8).write(to: existing.appending(path: name))
        }
        let archive = root.appending(path: "invalid.tar.gz")
        try makeArchive(from: source, to: archive)
        do {
            try await WhiskyWineInstaller.installDXVK(from: archive, in: library)
            XCTFail("Invalid archive must not report success")
        } catch WineManagerError.invalidGraphicsRuntimeArchive(let name) {
            XCTAssertEqual(name, "DXVK")
        }
        XCTAssertEqual(try Data(contentsOf: existing.appending(path: "d3d11.dll")), Data("existing".utf8))
    }

    private func makeArchive(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", destination.path, "-C", source.path, "."]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
