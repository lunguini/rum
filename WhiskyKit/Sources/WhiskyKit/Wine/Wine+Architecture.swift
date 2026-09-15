//
//  Wine+Architecture.swift
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

extension Wine {
    /// Identity of the active Wine engine, used to invalidate the win32-support cache when the
    /// Wine Manager activates a different build. Booting a throwaway prefix to probe support is
    /// expensive (seconds of CPU, spawns a wineserver), so the result is cached keyed by this.
    public struct Win32SupportCacheKey: Equatable, Sendable {
        let binaryPath: String
        let resolvedPath: String
        let modificationDate: Date?
    }

    private struct Win32SupportCacheEntry: Sendable {
        let key: Win32SupportCacheKey
        let value: Bool
    }

    private actor Win32SupportCache {
        static let shared = Win32SupportCache()
        private var entry: Win32SupportCacheEntry?

        func cachedValue(for key: Win32SupportCacheKey) -> Bool? {
            Wine.cachedWin32Support(for: key, cachedKey: entry?.key, cachedValue: entry?.value)
        }

        func store(_ value: Bool, for key: Win32SupportCacheKey) {
            entry = Win32SupportCacheEntry(key: key, value: value)
        }
    }

    /// Pure staleness decision: return the cached value only when it was computed for the same
    /// engine identity. Extracted so it can be unit-tested without booting a Wine prefix.
    static func cachedWin32Support(
        for key: Win32SupportCacheKey,
        cachedKey: Win32SupportCacheKey?,
        cachedValue: Bool?
    ) -> Bool? {
        guard let cachedKey, let cachedValue, cachedKey == key else { return nil }
        return cachedValue
    }

    /// Build the cache key from the currently active Wine binary. Uses the binary path plus its
    /// resolved symlink destination and that file's modification date, so activating a different
    /// engine (which swaps the `Libraries/Wine` symlink) produces a different key.
    static func makeWin32SupportCacheKey() -> Win32SupportCacheKey {
        let binary = wineBinary
        let resolved = binary.resolvingSymlinksInPath()
        let modificationDate = (try? FileManager.default
            .attributesOfItem(atPath: resolved.path(percentEncoded: false)))?[.modificationDate] as? Date
        return Win32SupportCacheKey(
            binaryPath: binary.path(percentEncoded: false),
            resolvedPath: resolved.path(percentEncoded: false),
            modificationDate: modificationDate
        )
    }

    public static func supportsPureWin32Prefixes() async -> Bool {
        let key = makeWin32SupportCacheKey()
        if let cached = await Win32SupportCache.shared.cachedValue(for: key) {
            return cached
        }
        let result = await runWin32PrefixProbe()
        await Win32SupportCache.shared.store(result, for: key)
        return result
    }

    private static func runWin32PrefixProbe() async -> Bool {
        let prefix = FileManager.default.temporaryDirectory
            .appending(path: "RumWin32PrefixProbe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: prefix) }

        var output = ""
        var terminationStatus: Int32 = 0
        let environment = [
            "WINEPREFIX": prefix.path,
            "WINEARCH": "win32",
            "WINEDEBUG": "-all"
        ]

        do {
            for await processOutput in try runWineProcess(
                name: "win32-prefix-probe",
                args: ["wineboot", "-u"],
                environment: environment,
                fileHandle: nil
            ) {
                switch processOutput {
                case .started:
                    break
                case .message(let message), .error(let message):
                    output += message
                case .terminated(let process):
                    terminationStatus = process.terminationStatus
                }
            }
        } catch {
            return false
        }

        let initializedPrefix = FileManager.default.fileExists(atPath: prefix.appending(path: "system.reg").path)
        return pureWin32PrefixProbeResult(
            output: output,
            terminationStatus: terminationStatus,
            initializedPrefix: initializedPrefix
        )
    }

    static func pureWin32PrefixProbeResult(
        output: String,
        terminationStatus: Int32,
        initializedPrefix: Bool
    ) -> Bool {
        if output.contains("WINEARCH is set to 'win32' but this is not supported in wow64 mode") {
            return false
        }
        return terminationStatus == 0 && initializedPrefix
    }
}
