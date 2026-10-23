//
//  VersionInfoTests.swift
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

final class VersionInfoTests: XCTestCase {
    /// Builds one version-info block: header, key, padding, value, padding, children.
    private func block(_ key: String, value: Data = Data(), valueLength: Int? = nil, type: UInt16 = 1,
                       children: [Data] = []) -> Data {
        var body = Data()
        body.append(utf16(key))
        pad(&body, offset: 6)
        body.append(value)
        if !children.isEmpty { pad(&body, offset: 6) }
        for child in children {
            body.append(child)
            pad(&body, offset: 6)
        }
        var data = Data()
        append(&data, UInt16(6 + body.count))
        append(&data, UInt16(valueLength ?? value.count))
        append(&data, type)
        data.append(body)
        return data
    }

    private func string(_ key: String, _ value: String) -> Data {
        let encoded = utf16(value)
        return block(key, value: encoded, valueLength: encoded.count / 2)
    }

    private func utf16(_ text: String) -> Data {
        var data = Data()
        for unit in text.utf16 { append(&data, unit) }
        append(&data, UInt16(0))
        return data
    }

    private func append(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    /// Pads so that `offset + data.count` is a multiple of 4.
    private func pad(_ data: inout Data, offset: Int) {
        while (offset + data.count) % 4 != 0 { data.append(0) }
    }

    private func versionInfo(_ strings: [(String, String)]) -> Data {
        let table = block("040904b0", children: strings.map { string($0.0, $0.1) })
        let stringFileInfo = block("StringFileInfo", children: [table])
        let varFileInfo = block("VarFileInfo", children: [block("Translation", value: Data([9, 4, 0xB0, 4]), type: 0)])
        let fixedInfo = Data(repeating: 0, count: 52)
        return block("VS_VERSION_INFO", value: fixedInfo, type: 0, children: [stringFileInfo, varFileInfo])
    }

    func testReadsStrings() {
        let data = versionInfo([("FileDescription", "Cheat Engine 7.5"), ("ProductName", "Cheat Engine")])
        let strings = VersionInfo.strings(from: data)
        XCTAssertEqual(strings["ProductName"], "Cheat Engine")
        XCTAssertEqual(strings["FileDescription"], "Cheat Engine 7.5")
        XCTAssertEqual(VersionInfo.displayName(from: strings), "Cheat Engine")
    }

    func testPrefersDescriptionUnlessItIsTheFileName() {
        let helper = ["FileDescription": "Steam Win32 MiniDump Helper", "ProductName": "Steam"]
        XCTAssertEqual(VersionInfo.displayName(from: helper), "Steam Win32 MiniDump Helper")
        let overlay = ["FileDescription": "gameoverlayui.exe", "ProductName": "Steam"]
        XCTAssertEqual(VersionInfo.displayName(from: overlay, executableName: "gameoverlayui64.exe"), "Steam")
        let bare = ["FileDescription": "HeroesOldenEra", "ProductName": "Heroes of Might and Magic: Olden Era"]
        XCTAssertEqual(VersionInfo.displayName(from: bare, executableName: "HeroesOldenEra.exe"),
                       "Heroes of Might and Magic: Olden Era")
    }

    func testSkipsEnginePlaceholders() {
        let strings = ["ProductName": "BootstrapPackagedGame", "FileDescription": "Olden Era"]
        XCTAssertEqual(VersionInfo.displayName(from: strings), "Olden Era")
        XCTAssertNil(VersionInfo.displayName(from: ["ProductName": "Unity"]))
    }

    func testTruncatedDataDoesNotCrash() {
        let data = versionInfo([("ProductName", "Steam")])
        for length in stride(from: 0, to: data.count, by: 7) {
            _ = VersionInfo.strings(from: data.prefix(length))
        }
    }
}
