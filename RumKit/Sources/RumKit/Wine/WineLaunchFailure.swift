//
//  WineLaunchFailure.swift
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

public struct WineLaunchFailure: Error, Equatable, LocalizedError {
    static let quickFailureInterval: TimeInterval = 3

    public enum Reason: Equatable, Sendable {
        case virtualMemoryAllocation
        case unsupportedArchitecture
        case wineServerVersionMismatch
        /// macOS privacy protection (Downloads, Desktop, Documents, removable or network
        /// volumes) refused Wine access to the program's folder.
        case folderAccessDenied
        case processExited(Int32)
    }

    public let reason: Reason
    public let message: String
    public let recoveryAdvice: String
    public let logURL: URL?

    public var recoverySuggestion: String? {
        recoveryAdvice
    }

    public var errorDescription: String? {
        if let logURL {
            return "\(message) \(recoveryAdvice) Log: \(logURL.path(percentEncoded: false))"
        }
        return "\(message) \(recoveryAdvice)"
    }

    private static let virtualMemoryRecoveryAdvice =
        "Kill the bottle and try again with WineD3D and enhanced sync disabled. "
        + "If it keeps happening, try another Wine version."

    public static func folderAccessDenied(folder: URL, logURL: URL? = nil) -> WineLaunchFailure {
        WineLaunchFailure(
            reason: .folderAccessDenied,
            message: "macOS blocked Rum from reading “\(folder.lastPathComponent)”.",
            recoveryAdvice: "Allow Rum in System Settings → Privacy & Security → Files & Folders, "
                + "or move the program out of Downloads, Desktop or Documents.",
            logURL: logURL
        )
    }

    public static func detect(in output: String, logURL: URL? = nil) -> WineLaunchFailure? {
        // c0000022 is STATUS_ACCESS_DENIED: the loader couldn't read a DLL next to the program.
        if output.contains("could not open working directory")
            || (output.contains("err:module:import_dll") && output.contains("(error c0000022)")) {
            return WineLaunchFailure(
                reason: .folderAccessDenied,
                message: "macOS blocked Wine from reading the program's folder.",
                recoveryAdvice: "Allow Rum in System Settings → Privacy & Security → Files & Folders, "
                    + "or move the program out of Downloads, Desktop or Documents.",
                logURL: logURL
            )
        }
        if output.contains("WINEARCH is set to 'win32' but this is not supported in wow64 mode") {
            return WineLaunchFailure(
                reason: .unsupportedArchitecture,
                message: "This Wine build does not support pure 32-bit bottles.",
                recoveryAdvice: "Create a 64-bit bottle for this Wine build, "
                    + "or install a Wine engine that supports win32 prefixes.",
                logURL: logURL
            )
        }
        if output.contains("wine client error") && output.contains("version mismatch") {
            return WineLaunchFailure(
                reason: .wineServerVersionMismatch,
                message: "Wine is connected to an incompatible wineserver.",
                recoveryAdvice: "Kill the bottle, then try again. "
                    + "If you just changed Wine engines, quit Rum and reopen it.",
                logURL: logURL
            )
        }
        if output.contains("err:virtual:try_map_free_area mmap() error Cannot allocate memory") {
            return WineLaunchFailure(
                reason: .virtualMemoryAllocation,
                message: "Wine failed to allocate virtual memory.",
                recoveryAdvice: virtualMemoryRecoveryAdvice,
                logURL: logURL
            )
        }
        if output.contains("err:virtual:virtual_setup_exception nested exception on signal stack") {
            return WineLaunchFailure(
                reason: .virtualMemoryAllocation,
                message: "Wine failed while setting up virtual memory.",
                recoveryAdvice: virtualMemoryRecoveryAdvice,
                logURL: logURL
            )
        }
        return nil
    }

    public static func processExited(status: Int32, logURL: URL?) -> WineLaunchFailure {
        WineLaunchFailure(
            reason: .processExited(status),
            message: "Wine exited with status code \(status).",
            recoveryAdvice: "Check the Wine log for the full output.",
            logURL: logURL
        )
    }

    public static func failureToReport(
        detectedFailure: WineLaunchFailure?,
        terminationStatus: Int32,
        runtime: TimeInterval,
        logURL: URL? = nil
    ) -> WineLaunchFailure? {
        if let detectedFailure, terminationStatus != 0 || runtime <= quickFailureInterval {
            return detectedFailure
        }
        // A bare non-zero exit with no detected failure pattern is only worth surfacing if the
        // process died almost immediately. Many Windows apps exit non-zero benignly after running
        // fine for a long time (canceled installers, self-respawning launchers, games returning
        // their own codes), so anything past the quick-failure window is logged and stays quiet.
        if terminationStatus != 0 && runtime <= quickFailureInterval {
            return processExited(status: terminationStatus, logURL: logURL)
        }
        return nil
    }
}
