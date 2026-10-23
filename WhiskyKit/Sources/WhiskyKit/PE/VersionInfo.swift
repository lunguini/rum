//
//  VersionInfo.swift
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

/// Reads the `StringFileInfo` strings (ProductName, FileDescription, …) of a `VS_VERSIONINFO`
/// resource.
///
/// https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo
public enum VersionInfo {
    /// Names engines and installers put in their version info instead of the product's name.
    static let placeholderNames: Set<String> = [
        "bootstrappackagedgame", "unity", "unityplayer", "ue4game", "ue5game", "game", "launcher",
        "application", "app", "setup", "installer", "nwjs", "electron", "node.js", "chromium"
    ]

    /// All version strings, keyed by name (e.g. `ProductName`). The first string table wins.
    public static func strings(from data: Data) -> [String: String] {
        var result: [String: String] = [:]
        let bytes = [UInt8](data)
        parseBlock(bytes, at: 0, end: bytes.count, depth: 0, into: &result)
        return result
    }

    /// The best human-readable name in `strings`, or nil when they only hold placeholders.
    /// `FileDescription` names the program itself ("Steam Win32 MiniDump Helper"), `ProductName`
    /// often the suite it ships with ("Steam"), so the description wins unless it's just the
    /// file name.
    public static func displayName(from strings: [String: String], executableName: String? = nil) -> String? {
        let fileName = executableName.map { ($0 as NSString).deletingPathExtension.lowercased() }
        for key in ["FileDescription", "ProductName"] {
            guard let raw = strings[key] else { continue }
            let value = withoutTrailingVersion(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            let lowered = value.lowercased()
            guard value.count >= 2, value.count <= 60,
                  !placeholderNames.contains(lowered),
                  !lowered.hasSuffix(".exe"),
                  lowered != fileName else { continue }
            return value
        }
        return nil
    }

    /// "Cheat Engine 7.5" → "Cheat Engine", "Foo v1.2.3" → "Foo".
    static func withoutTrailingVersion(_ name: String) -> String {
        let pattern = #"\s+v?\d+(\.\d+)+[a-z]?$"#
        guard let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
              range.lowerBound != name.startIndex else { return name }
        return String(name[..<range.lowerBound])
    }

    /// Each block: wLength, wValueLength, wType, a NUL-terminated UTF-16 key, padding to 32 bits,
    /// the value, padding, then child blocks. Strings live at depth 3:
    /// VS_VERSIONINFO → StringFileInfo → StringTable → String.
    private static func parseBlock(_ bytes: [UInt8], at start: Int, end: Int, depth: Int,
                                   into result: inout [String: String]) {
        guard depth <= 3, start + 6 <= end else { return }
        let length = Int(uint16(bytes, start))
        let valueLength = Int(uint16(bytes, start + 2))
        guard length >= 6, start + length <= end else { return }
        let blockEnd = start + length

        var position = start + 6
        let key = utf16String(bytes, from: &position, limit: blockEnd)
        position = align4(position)

        // String values are measured in UTF-16 characters, everything else in bytes.
        let valueBytes = depth == 3 ? valueLength * 2 : valueLength
        if depth == 3 {
            var valuePosition = position
            let value = utf16String(bytes, from: &valuePosition, limit: min(position + valueBytes, blockEnd))
            if result[key] == nil, !value.isEmpty {
                result[key] = value
            }
            return
        }
        if depth == 1 && key != "StringFileInfo" { return }

        position = align4(position + valueBytes)
        while position + 6 <= blockEnd {
            let childLength = Int(uint16(bytes, position))
            guard childLength > 0 else { break }
            parseBlock(bytes, at: position, end: blockEnd, depth: depth + 1, into: &result)
            position = align4(position + childLength)
        }
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    /// Reads UTF-16LE up to a NUL or `limit`, leaving `position` after the NUL.
    private static func utf16String(_ bytes: [UInt8], from position: inout Int, limit: Int) -> String {
        var units: [UInt16] = []
        while position + 1 < limit {
            let unit = uint16(bytes, position)
            position += 2
            if unit == 0 { break }
            units.append(unit)
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func align4(_ value: Int) -> Int {
        (value + 3) & ~3
    }
}

extension PEFile {
    /// Version strings such as `ProductName` and `FileDescription`, empty when there are none.
    public func versionStrings() -> [String: String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }
        guard let table = rsrc(handle: handle, types: [.version]),
              let entry = table.allEntries.first,
              let offset = entry.resolveRVA(sections: sections) else { return [:] }
        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: Int(min(entry.size, 64 * 1024))) else { return [:] }
            return VersionInfo.strings(from: data)
        } catch {
            return [:]
        }
    }

    /// The product name from the version info, if it has a meaningful one.
    public var productDisplayName: String? {
        VersionInfo.displayName(from: versionStrings(), executableName: url.lastPathComponent)
    }
}
