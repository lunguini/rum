//
//  Wine.swift
//  Whisky
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
import os.log

private actor RendererExecutionCoordinator {
    static let shared = RendererExecutionCoordinator()

    private var activeBackends: [String: GraphicsBackend] = [:]

    func acquire(bottlePath: String, backend: GraphicsBackend) throws {
        if let active = activeBackends[bottlePath] {
            throw GraphicsBackendError.conflictingBackend(bottlePath, active, backend)
        }
        activeBackends[bottlePath] = backend
    }

    func release(bottlePath: String, backend: GraphicsBackend) {
        guard activeBackends[bottlePath] == backend else { return }
        activeBackends[bottlePath] = nil
    }
}

// swiftlint:disable:next type_body_length
public class Wine {
    /// URL to the installed `DXVK` folder
    static let dxvkFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
    /// Upper bound on the retained tail of program output used for launch-failure detection.
    static let failureDetectionTailByteLimit = 16 * 1024
    /// Path to the `wine` binary (Wine 11+ uses a unified binary; fall back to wine64 for older builds)
    public static var wineBinary: URL {
        WhiskyWineInstaller.activeWineExecutable()
    }

    /// The executable selected by a bottle, falling back to the global default for command
    /// previews that cannot surface a throwing resolution error.
    public static func wineBinary(for bottle: Bottle) -> URL {
        (try? WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID))?.wineBinaryURL ?? wineBinary
    }
    /// Parth to the `wineserver` binary
    private static var wineserverBinary: URL {
        WhiskyWineInstaller.activeWineserverExecutable()
    }

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        directory: URL? = nil, fileHandle: FileHandle?, engine: WineEngine? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: engine?.wineBinaryURL ?? wineBinary,
            directory: directory, fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        fileHandle: FileHandle?, engine: WineEngine? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment,
            executableURL: engine?.wineserverBinaryURL ?? wineserverBinary,
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let engine = try WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID)
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineProcess(
            name: name, args: args,
            environment: constructWineEnvironment(for: bottle, environment: environment, engine: engine),
            fileHandle: fileHandle,
            engine: engine
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let engine = try WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID)
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        fileHandle.writeInfo(for: bottle)

        return try runWineserverProcess(
            name: name, args: args,
            environment: constructWineServerEnvironment(for: bottle, environment: environment, engine: engine),
            fileHandle: fileHandle,
            engine: engine
        )
    }

    /// Execute a `wine start /unix {url}` command returning the output result
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:],
        onStarted: (@Sendable () -> Void)? = nil
    ) async throws {
        let engine = try WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID)
        let backend = bottle.settings.graphicsBackend
        try validateGraphicsBackend(backend, for: bottle, engine: engine)
        try await RendererExecutionCoordinator.shared.acquire(
            bottlePath: bottle.url.path(percentEncoded: false),
            backend: backend
        )
        do {
            try prepareGraphicsBackend(backend, for: bottle, engine: engine)

            let logFile = try makeLogFile()
            logFile.fileHandle.writeApplicaitonInfo()
            logFile.fileHandle.writeInfo(for: bottle)
            let result = try await collectProgramOutput(context: ProgramOutputContext(
                url: url,
                args: args,
                bottle: bottle,
                environment: environment,
                engine: engine,
                logFile: logFile,
                onStarted: onStarted
            ))

            if let failure = WineLaunchFailure.failureToReport(
                detectedFailure: result.failure,
                terminationStatus: result.terminationStatus,
                runtime: result.runtime,
                logURL: logFile.url
            ) {
                throw failure
            }
        } catch {
            await RendererExecutionCoordinator.shared.release(
                bottlePath: bottle.url.path(percentEncoded: false),
                backend: backend
            )
            throw error
        }

        await RendererExecutionCoordinator.shared.release(
            bottlePath: bottle.url.path(percentEncoded: false),
            backend: backend
        )
    }

    static func runProgramArguments(for url: URL, args: [String]) -> [String] {
        ["start", "/wait", "/unix", url.path(percentEncoded: false)] + args
    }

    static func runProgramDirectory(for url: URL) -> URL {
        url.deletingLastPathComponent()
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        var wineCmd = "\(wineBinary(for: bottle).esc) start /wait /unix \(url.esc) \(args)"
        let env = constructWineEnvironment(for: bottle, environment: environment)
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }

        return wineCmd
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        let env = constructWineEnvironment(for: bottle)
        var cmd = "export WINE=\"\(wineBinary(for: bottle).path)\""
        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            cmd += "\nexport \(key)=\"\(value)\""
        }

        return cmd
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        let engine = try WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID)
        var result: [ProcessOutput] = []

        for await output in try runWineserverProcess(
            name: nil,
            args: args,
            environment: constructWineServerEnvironment(for: bottle, engine: engine),
            fileHandle: nil,
            engine: engine
        ) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                return message
            }
        }.joined()
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:]
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = try makeFileHandle()
        fileHandle.writeApplicaitonInfo()
        var environment = environment
        var engine: WineEngine?

        if let bottle = bottle {
            engine = try WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID)
            fileHandle.writeInfo(for: bottle)
            environment = constructWineEnvironment(for: bottle, environment: environment, engine: engine)
        }

        for await output in try runWineProcess(
            args: args,
            environment: environment,
            fileHandle: fileHandle,
            engine: engine
        ) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }

        return result.joined()
    }

    public static func wineVersion() async throws -> String {
        let output = try await runWine(["--version"], bottle: nil)
        return parseWineVersion(from: output)
    }

    public static func wineVersion(bottle: Bottle) async throws -> String {
        let output = try await runWine(["--version"], bottle: bottle)
        return parseWineVersion(from: output)
    }

    /// Extract a dotted numeric version from `wine --version` output.
    ///
    /// Gcenx builds print `wine-X.Y`, but CrossOver and staging builds print other
    /// prefixes/suffixes (e.g. `wine-9.0 (Staging)`, `CrossOver-wine-...`), so we pull out the
    /// first dotted numeric run instead of stripping a fixed `wine-` prefix. If nothing matches we
    /// return the trimmed raw output, letting downstream version parsing fail the same way it does
    /// today rather than silently mis-parsing.
    static func parseWineVersion(from rawOutput: String) -> String {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "[0-9]+(\\.[0-9]+)+", options: .regularExpression) {
            return String(trimmed[range])
        }
        return trimmed
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) throws {
        Task.detached(priority: .userInitiated) {
            try await killBottleAndWait(bottle: bottle)
        }
    }

    public static func killBottleAndWait(bottle: Bottle) async throws {
        _ = try await runWineserver(["-k"], bottle: bottle)
        _ = try await runWineserver(["-w"], bottle: bottle)
    }

    /// Construct an environment merging the bottle values with the given values
    static func constructWineEnvironment(
        for bottle: Bottle,
        environment: [String: String] = [:],
        engine: WineEngine? = nil
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        bottle.settings.environmentVariables(wineEnv: &result)
        let resolvedEngine = engine ?? (try? WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID))
        result.merge(
            WhiskyWineInstaller.graphicsEnvironment(
                for: bottle.settings.graphicsBackend,
                engineID: resolvedEngine?.id
            ),
            uniquingKeysWith: { _, newValue in newValue }
        )
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineServerEnvironment(
        for bottle: Bottle,
        environment: [String: String] = [:],
        engine: WineEngine? = nil
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        let resolvedEngine = engine ?? (try? WhiskyWineInstaller.wineEngine(for: bottle.settings.wineEngineID))
        result.merge(
            WhiskyWineInstaller.graphicsEnvironment(
                for: .wineD3D,
                engineID: resolvedEngine?.id
            ),
            uniquingKeysWith: { _, newValue in newValue }
        )
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}

enum WineInterfaceError: Error {
    case invalidResponce
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

extension Wine {
    public static let logsFolder = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    )[0].appending(path: "Logs").appending(path: Bundle.whiskyBundleIdentifier)

    public static func makeFileHandle() throws -> FileHandle {
        return try makeLogFile().fileHandle
    }

    static func makeLogFile() throws -> (url: URL, fileHandle: FileHandle) {
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }

        let dateString = Date.now.ISO8601Format()
        let fileURL = Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try (fileURL, FileHandle(forWritingTo: fileURL))
    }
}
