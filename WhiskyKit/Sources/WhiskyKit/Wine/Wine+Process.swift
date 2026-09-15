//
//  Wine+Process.swift
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

struct ProgramOutputContext {
    let url: URL
    let args: [String]
    let bottle: Bottle
    let environment: [String: String]
    let engine: WineEngine
    let logFile: (url: URL, fileHandle: FileHandle)
    let onStarted: (@Sendable () -> Void)?
}

struct ProgramOutputResult {
    let terminationStatus: Int32
    let failure: WineLaunchFailure?
    let runtime: TimeInterval
}

extension Wine {
    static func collectProgramOutput(context: ProgramOutputContext) async throws -> ProgramOutputResult {
        var terminationStatus: Int32 = 0
        var detectedFailure: WineLaunchFailure?
        // Failure markers can be split across two pipe reads, so run detection against an
        // accumulated tail of the combined output rather than each chunk in isolation.
        var tailBuffer = ""
        let startTime = Date()

        for await output in try Self.runWineProcess(
            name: context.url.lastPathComponent,
            args: runProgramArguments(for: context.url, args: context.args),
            environment: constructWineEnvironment(
                for: context.bottle,
                environment: context.environment,
                engine: context.engine
            ),
            directory: runProgramDirectory(for: context.url),
            fileHandle: context.logFile.fileHandle,
            engine: context.engine
        ) {
            switch output {
            case .started:
                context.onStarted?()
            case .message(let message), .error(let message):
                if detectedFailure == nil {
                    tailBuffer += message
                    if tailBuffer.utf8.count > Self.failureDetectionTailByteLimit {
                        tailBuffer = String(tailBuffer.suffix(Self.failureDetectionTailByteLimit))
                    }
                    detectedFailure = WineLaunchFailure.detect(in: tailBuffer, logURL: context.logFile.url)
                }
            case .terminated(let process):
                terminationStatus = process.terminationStatus
            }
        }

        return ProgramOutputResult(
            terminationStatus: terminationStatus,
            failure: detectedFailure,
            runtime: Date().timeIntervalSince(startTime)
        )
    }
}
