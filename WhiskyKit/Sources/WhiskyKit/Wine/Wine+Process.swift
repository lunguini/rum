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
    /// Initialize/refresh a bottle with the selected engine before installing renderer files.
    /// This deliberately uses WineD3D overrides so prefix maintenance never depends on the
    /// renderer currently selected by the bottle. `wineboot -u` is awaited to completion; unlike
    /// `wineserver -w`, it is bounded by the lifecycle of the command and does not stop users'
    /// existing processes.
    static func initializePrefix(for bottle: Bottle, engine: WineEngine) async throws {
        let logFile = try makeLogFile()
        logFile.fileHandle.writeApplicaitonInfo()
        logFile.fileHandle.writeInfo(for: bottle)

        defer { try? logFile.fileHandle.close() }
        let process = Process()
        process.executableURL = engine.wineBinaryURL
        process.arguments = ["wineboot", "-u"]
        process.environment = prefixInitializationEnvironment(for: bottle, engine: engine)
        // Wine services inherit stdout/stderr. A pipe's EOF can therefore arrive long after
        // wineboot exits. Log directly to disk and await only the command's termination.
        process.standardOutput = logFile.fileHandle
        process.standardError = logFile.fileHandle
        logFile.fileHandle.writeInfo(for: process)
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        let reader = try FileHandle(forReadingFrom: logFile.url)
        defer { try? reader.close() }
        let size = try reader.seekToEnd()
        let tailLimit = UInt64(failureDetectionTailByteLimit)
        try reader.seek(toOffset: size > failureDetectionTailByteLimit ? size - tailLimit : 0)
        let tail = try reader.read(upToCount: failureDetectionTailByteLimit) ?? Data()
        let output = String(bytes: tail, encoding: .utf8) ?? ""
        if let failure = WineLaunchFailure.detect(in: output, logURL: logFile.url) {
            throw failure
        }
        guard status == 0 else {
            throw WineLaunchFailure.processExited(status: status, logURL: logFile.url)
        }
    }

    /// Construct a launch environment that keeps the selected engine but forces Wine's builtin
    /// D3D implementation while the prefix is being maintained.
    static func prefixInitializationEnvironment(
        for bottle: Bottle,
        engine: WineEngine
    ) -> [String: String] {
        var settings = bottle.settings
        settings.graphicsBackend = .wineD3D
        var environment = ["WINEPREFIX": bottle.url.path, "WINEDEBUG": "fixme-all", "GST_DEBUG": "1"]
        settings.environmentVariables(wineEnv: &environment)
        environment.merge(WhiskyWineInstaller.graphicsEnvironment(
            for: .wineD3D,
            engineID: engine.id
        ), uniquingKeysWith: { _, newValue in newValue })
        return environment
    }

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
            environment: context.environment,
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
