//
//  RendererStateTests+Fixtures.swift
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

struct RendererStateFixture {
    let root: URL
    let dxmtRoot: URL
    let d3dmetalRoot: URL
    let bottleURL: URL
    let system32: URL
    let syswow64: URL
    let bottle: Bottle
}

private struct BottleFixture {
    let bottle: Bottle
    let url: URL
    let system32: URL
    let syswow64: URL
}

extension RendererStateTests {
    func makeFixture() throws -> RendererStateFixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let dxmtRoot = try makeDXMTFixture(at: root)
        let d3dmetalRoot = try makeD3DMetalFixture(at: root)
        let bottle = try makeBottleFixture(at: root)
        return RendererStateFixture(
            root: root,
            dxmtRoot: dxmtRoot,
            d3dmetalRoot: d3dmetalRoot,
            bottleURL: bottle.url,
            system32: bottle.system32,
            syswow64: bottle.syswow64,
            bottle: bottle.bottle
        )
    }

    func assertOriginalFiles(in fixture: RendererStateFixture) throws {
        try assertFile(fixture.system32.appending(path: "d3d11.dll"), equals: "original-d3d11")
        try assertFile(fixture.system32.appending(path: "dxgi.dll"), equals: "original-dxgi")
        try assertFile(
            fixture.system32.appending(path: "nvapi64.dll"),
            equals: "original-nvapi64"
        )
        try assertFile(
            fixture.system32.appending(path: "nvngx.dll"),
            equals: "original-nvngx"
        )
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

    func makeManagedEngine(at root: URL) throws -> WineEngine {
        try makeFileWithData(root.appending(path: "bin/wine"), data: "wine")
        try makeFileWithData(root.appending(path: "bin/wineserver"), data: "wineserver")
        for (architecture, suffix) in [("x86_64-windows", "x64"), ("i386-windows", "x86")] {
            for filename in ["d3d10core.dll", "d3d11.dll", "dxgi.dll", "winemetal.dll"] {
                try makeFileWithData(
                    root.appending(path: "lib/wine/\(architecture)/\(filename)"),
                    data: "engine-\(suffix)-\(filename)"
                )
            }
        }
        return WineEngine(
            id: "sikarugir:test",
            name: "Sikarugir",
            version: "test",
            kind: .sikarugir,
            wineURL: root,
            wineBinaryURL: root.appending(path: "bin/wine"),
            wineserverBinaryURL: root.appending(path: "bin/wineserver")
        )
    }

    func copyEngineBuiltin(
        _ filename: String,
        architecture: String,
        from engineRoot: URL,
        to destinationDirectory: URL
    ) throws {
        let source = engineRoot.appending(path: "lib/wine/\(architecture)/\(filename)")
        let destination = destinationDirectory.appending(path: filename)
        try Data(contentsOf: source).write(to: destination)
    }

    func simulateManagedEngineRefresh(
        in fixture: RendererStateFixture,
        engineRoot: URL
    ) throws {
        for filename in ["d3d10core.dll", "d3d11.dll", "dxgi.dll", "winemetal.dll"] {
            try copyEngineBuiltin(
                filename,
                architecture: "x86_64-windows",
                from: engineRoot,
                to: fixture.system32
            )
            try copyEngineBuiltin(
                filename,
                architecture: "i386-windows",
                from: engineRoot,
                to: fixture.syswow64
            )
        }
        try Data("original-nvapi64".utf8).write(
            to: fixture.system32.appending(path: "nvapi64.dll")
        )
        try Data("original-nvngx".utf8).write(
            to: fixture.system32.appending(path: "nvngx.dll")
        )
    }

    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func assertFile(_ url: URL, equals data: String) throws {
        XCTAssertEqual(try Data(contentsOf: url), Data(data.utf8))
    }

    private func makeDXMTFixture(at root: URL) throws -> URL {
        let renderer = root.appending(path: "dxmt")
        let files = [
            ("x86_64-windows/d3d10core.dll", "dxmt-d3d10core"),
            ("x86_64-windows/d3d11.dll", "dxmt-d3d11"),
            ("x86_64-windows/dxgi.dll", "dxmt-dxgi"),
            ("x86_64-windows/winemetal.dll", "dxmt-winemetal"),
            ("x86_64-windows/nvapi64.dll", "dxmt-nvapi64"),
            ("x86_64-windows/nvngx.dll", "dxmt-nvngx"),
            ("i386-windows/d3d10core.dll", "dxmt-x86-d3d10core"),
            ("i386-windows/d3d11.dll", "dxmt-x86-d3d11"),
            ("i386-windows/dxgi.dll", "dxmt-x86-dxgi"),
            ("i386-windows/winemetal.dll", "dxmt-x86-winemetal")
        ]
        try makeFiles(files, in: renderer)
        return renderer
    }

    private func makeD3DMetalFixture(at root: URL) throws -> URL {
        let renderer = root.appending(path: "d3dmetal")
        let files = [
            ("wine/x86_64-windows/d3d11.dll", "d3dmetal-d3d11"),
            ("wine/x86_64-windows/d3d12.dll", "d3dmetal-d3d12"),
            ("wine/x86_64-windows/dxgi.dll", "d3dmetal-dxgi")
        ]
        try makeFiles(files, in: renderer)
        return renderer
    }

    private func makeBottleFixture(at root: URL) throws -> BottleFixture {
        let url = root.appending(path: "bottle")
        let system32 = url.appending(path: "drive_c/windows/system32")
        let syswow64 = url.appending(path: "drive_c/windows/syswow64")
        try makeFiles([
            ("d3d11.dll", "original-d3d11"),
            ("dxgi.dll", "original-dxgi"),
            ("winemetal.dll", "original-winemetal"),
            ("nvapi64.dll", "original-nvapi64"),
            ("nvngx.dll", "original-nvngx")
        ], in: system32)
        try makeFiles([("d3d11.dll", "original-x86-d3d11")], in: syswow64)
        return BottleFixture(
            bottle: Bottle(bottleUrl: url),
            url: url,
            system32: system32,
            syswow64: syswow64
        )
    }

    private func makeFiles(_ files: [(String, String)], in directory: URL) throws {
        for (relativePath, data) in files {
            try makeFileWithData(directory.appending(path: relativePath), data: data)
        }
    }

    private func makeFileWithData(_ url: URL, data: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(data.utf8).write(to: url)
    }
}
