//
//  WineLaunchFailureTests.swift
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

final class WineLaunchFailureTests: XCTestCase {
    func testRunProgramArgumentsWaitForStartedProgram() {
        let url = URL(fileURLWithPath: "/Games/Heroes/h3hota HD.exe")

        let arguments = Wine.runProgramArguments(for: url, args: ["-windowed"])

        XCTAssertEqual(arguments, ["start", "/wait", "/unix", "/Games/Heroes/h3hota HD.exe", "-windowed"])
    }

    func testRunProgramDirectoryUsesExecutableParent() {
        let url = URL(fileURLWithPath: "/Games/Heroes/HD_Launcher.exe")

        XCTAssertEqual(Wine.runProgramDirectory(for: url).path, "/Games/Heroes")
    }

    func testDetectsWineVirtualMemoryMappingFailure() {
        let output = """
        002c:err:virtual:try_map_free_area mmap() error Cannot allocate memory
        """

        let failure = WineLaunchFailure.detect(in: output)

        XCTAssertEqual(failure?.reason, .virtualMemoryAllocation)
        XCTAssertEqual(failure?.message, "Wine failed to allocate virtual memory.")
        XCTAssertEqual(
            failure?.recoverySuggestion,
            "Kill the bottle and try again with WineD3D and enhanced sync disabled. "
                + "If it keeps happening, try another Wine version."
        )
    }

    func testDetectsWineNestedSignalStackException() {
        let output = """
        00dc:err:virtual:virtual_setup_exception nested exception on signal stack addr 0x7ff806e9d254
        """

        let failure = WineLaunchFailure.detect(in: output)

        XCTAssertEqual(failure?.reason, .virtualMemoryAllocation)
        XCTAssertEqual(failure?.message, "Wine failed while setting up virtual memory.")
    }

    func testDetectsUnsupportedWin32PrefixInWow64Wine() {
        let output = """
        wine: WINEARCH is set to 'win32' but this is not supported in wow64 mode.
        """

        let failure = WineLaunchFailure.detect(in: output)

        XCTAssertEqual(failure?.reason, .unsupportedArchitecture)
        XCTAssertEqual(failure?.message, "This Wine build does not support pure 32-bit bottles.")
        XCTAssertEqual(
            failure?.recoverySuggestion,
            "Create a 64-bit bottle for this Wine build, or install a Wine engine that supports win32 prefixes."
        )
    }

    func testDetectsWineServerVersionMismatch() {
        let output = """
        wine client error:0: version mismatch 932/1809.
        Your wineserver binary was not upgraded correctly,
        or you have an older one somewhere in your PATH.
        Or maybe the wrong wineserver is still running?
        """

        let failure = WineLaunchFailure.detect(in: output)

        XCTAssertEqual(failure?.reason, .wineServerVersionMismatch)
        XCTAssertEqual(failure?.message, "Wine is connected to an incompatible wineserver.")
        XCTAssertEqual(
            failure?.recoverySuggestion,
            "Kill the bottle, then try again. If you just changed Wine engines, quit Rum and reopen it."
        )
    }

    func testDefersDetectedFailureForLongRunningSuccessfulProcess() {
        let failure = WineLaunchFailure(
            reason: .virtualMemoryAllocation,
            message: "Wine failed to allocate virtual memory.",
            recoveryAdvice: "Try another Wine version.",
            logURL: nil
        )

        let result = WineLaunchFailure.failureToReport(
            detectedFailure: failure,
            terminationStatus: 0,
            runtime: 10
        )

        XCTAssertNil(result)
    }

    func testReportsDetectedFailureForQuickSuccessfulExit() {
        let failure = WineLaunchFailure(
            reason: .virtualMemoryAllocation,
            message: "Wine failed to allocate virtual memory.",
            recoveryAdvice: "Try another Wine version.",
            logURL: nil
        )

        let result = WineLaunchFailure.failureToReport(
            detectedFailure: failure,
            terminationStatus: 0,
            runtime: 1
        )

        XCTAssertEqual(result, failure)
    }

    func testDetectedFailureTakesPrecedenceOverProcessExitStatus() {
        let failure = WineLaunchFailure(
            reason: .unsupportedArchitecture,
            message: "This Wine build does not support pure 32-bit bottles.",
            recoveryAdvice: "Create a 64-bit bottle.",
            logURL: nil
        )

        let result = WineLaunchFailure.failureToReport(
            detectedFailure: failure,
            terminationStatus: 1,
            runtime: 1
        )

        XCTAssertEqual(result, failure)
    }

    func testReportsBareNonZeroExitForQuickFailure() {
        let result = WineLaunchFailure.failureToReport(
            detectedFailure: nil,
            terminationStatus: 1,
            runtime: 1
        )

        XCTAssertEqual(result?.reason, .processExited(1))
    }

    func testDoesNotReportBareNonZeroExitForLongRunningProcess() {
        let result = WineLaunchFailure.failureToReport(
            detectedFailure: nil,
            terminationStatus: 1,
            runtime: 3600
        )

        XCTAssertNil(result)
    }

    func testDoesNotReportZeroExitForQuickProcess() {
        let result = WineLaunchFailure.failureToReport(
            detectedFailure: nil,
            terminationStatus: 0,
            runtime: 1
        )

        XCTAssertNil(result)
    }

    func testReportsDetectedFailureForLongRunningNonZeroExit() {
        let failure = WineLaunchFailure(
            reason: .wineServerVersionMismatch,
            message: "Wine is connected to an incompatible wineserver.",
            recoveryAdvice: "Kill the bottle, then try again.",
            logURL: nil
        )

        let result = WineLaunchFailure.failureToReport(
            detectedFailure: failure,
            terminationStatus: 1,
            runtime: 3600
        )

        XCTAssertEqual(result, failure)
    }
}
