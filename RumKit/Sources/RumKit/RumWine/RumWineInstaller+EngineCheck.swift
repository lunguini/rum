//
//  RumWineInstaller+EngineCheck.swift
//  RumKit
//
//  This file is part of Rum.
//
//  Rum is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Rum is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Rum.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

extension RumWineInstaller {
    /// Whether a Wine prefix was actually initialised. A prefix where `wineboot` failed still has
    /// registry stubs and an empty `drive_c/windows`, so look for a core system DLL instead.
    public static func isPrefixInitialized(_ prefix: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: prefix.appending(path: "drive_c/windows/system32/kernel32.dll").path(percentEncoded: false)
        )
    }

    /// Check that an engine can start Windows programs on this Mac by initialising a throwaway
    /// prefix with it. Some engine builds install cleanly but die on start (for example when they
    /// need newer support libraries), which otherwise only shows up as every bottle failing.
    public static func engineStarts(
        _ engineID: String?,
        in libraryFolder: URL = libraryFolder,
        timeout: Duration = .seconds(240)
    ) async -> Bool {
        guard let engine = try? wineEngine(for: engineID, in: libraryFolder) else { return false }

        let prefix = FileManager.default.temporaryDirectory
            .appending(path: "Rum-EngineCheck-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: prefix) }

        var environment = ProcessInfo.processInfo.environment
        environment.merge(graphicsEnvironment(for: .wineD3D, engineID: engine.id, in: libraryFolder)) { $1 }
        environment["WINEPREFIX"] = prefix.path(percentEncoded: false)
        environment["WINEDEBUG"] = "-all"
        // Skip the Mono and Gecko installers; they aren't needed to tell whether Wine starts.
        environment["WINEDLLOVERRIDES"] = "mscoree,mshtml="

        let wineboot = Process()
        wineboot.executableURL = engine.wineBinaryURL
        wineboot.arguments = ["wineboot", "-u"]
        wineboot.environment = environment
        wineboot.standardOutput = FileHandle.nullDevice
        wineboot.standardError = FileHandle.nullDevice

        let finished = await withCheckedContinuation { continuation in
            let resumer = ResumeOnce(continuation)
            wineboot.terminationHandler = { _ in resumer.resume(true) }
            do {
                try wineboot.run()
            } catch {
                resumer.resume(false)
                return
            }
            Task {
                try? await Task.sleep(for: timeout)
                if wineboot.isRunning { wineboot.terminate() }
                resumer.resume(false)
            }
        }

        // Stop the wineserver the check started, so it doesn't linger or hold the prefix open.
        let wineserver = Process()
        wineserver.executableURL = engine.wineserverBinaryURL
        wineserver.arguments = ["-k"]
        wineserver.environment = environment
        wineserver.standardOutput = FileHandle.nullDevice
        wineserver.standardError = FileHandle.nullDevice
        try? wineserver.run()
        wineserver.waitUntilExit()

        return finished && isPrefixInitialized(prefix)
    }
}

/// Resumes a continuation exactly once, whichever of the exit handler or the timeout fires first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
