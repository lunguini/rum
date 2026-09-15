//
//  WhiskyApp.swift
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

import SwiftUI
import WhiskyKit

@main
struct WhiskyApp: App {
    @State var showSetup: Bool = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openURL) var openURL

    var body: some Scene {
        WindowGroup {
            ContentView(showSetup: $showSetup)
                .frame(minWidth: ViewWidth.large, minHeight: 316)
                .environmentObject(BottleVM.shared)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false

                    Task.detached {
                        await WhiskyApp.deleteOldLogs()
                    }
                }
        }
        // Don't ask me how this works, it just does
        .handlesExternalEvents(matching: ["{same path of URL?}"])
        .commands {
            CommandGroup(after: .appInfo) {
                UpdateCheckView()
            }
            CommandGroup(before: .systemServices) {
                Divider()
                Button("open.setup") {
                    showSetup = true
                }
                Button("install.cli") {
                    Task {
                        await WhiskyCmd.install()
                    }
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("open.bottle") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.urls.first {
                                BottleVM.shared.bottlesList.paths.append(url)
                                BottleVM.shared.loadBottles()
                            }
                        }
                    }
                }
                .keyboardShortcut("I", modifiers: [.command])
            }
            CommandGroup(after: .importExport) {
                Button("open.logs") {
                    WhiskyApp.openLogsFolder()
                }
                .keyboardShortcut("L", modifiers: [.command])
                Button("kill.bottles") {
                    WhiskyApp.killBottles()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
                Button("wine.clearShaderCaches") {
                    WhiskyApp.killBottles() // Better not make things more complicated for ourselves
                    WhiskyApp.wipeShaderCaches()
                }
            }
            CommandGroup(replacing: .help) {
                Button("help.website") {
                    if let url = URL(string: "https://github.com/adrianlungu/rum") {
                        openURL(url)
                    }
                }
                Button("help.github") {
                    if let url = URL(string: "https://github.com/adrianlungu/rum") {
                        openURL(url)
                    }
                }
                Button("help.discord") {
                    if let url = URL(string: "https://discord.gg/CsqAfs9CnM") {
                        openURL(url)
                    }
                }
            }
        }
        Settings {
            SettingsView()
        }
    }

    static func killBottles() {
        Task {
            await killBottlesAndWait()
        }
    }

    static func killBottlesAndWait() async {
        let bottles = await MainActor.run {
            BottleVM.shared.bottles
        }
        await killBottles(bottles)
    }

    private static func killBottles(_ bottles: [Bottle]) async {
        for bottle in bottles {
            do {
                try await Wine.killBottleAndWait(bottle: bottle)
            } catch {
                print("Failed to kill bottle: \(error)")
            }
        }
    }

    /// Synchronously kill every bottle, bounded by `timeout`.
    ///
    /// Intended for `applicationWillTerminate`, where the process exits the moment the delegate
    /// returns and the run loop will never service a plain `Task`. Must be called on the main
    /// thread: the bottles list is read synchronously here (we are already main-actor isolated) and
    /// the actual `wineserver -k` work runs on a detached task, so blocking the main thread on the
    /// semaphore cannot deadlock against a `MainActor.run` hop.
    @MainActor
    static func killBottlesAndWaitBlocking(timeout: TimeInterval = 5) {
        let bottles = BottleVM.shared.bottles
        guard !bottles.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await killBottles(bottles)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
    }

    static func openLogsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Wine.logsFolder.path)
    }

    static func deleteOldLogs() {
        let pastDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder,
            includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let logs = urls.filter { url in
            url.pathExtension == "log"
        }

        let oldLogs = logs.filter { url in
            do {
                let resourceValues = try url.resourceValues(forKeys: [.creationDateKey])

                return resourceValues.creationDate ?? Date() < pastDate
            } catch {
                return false
            }
        }

        for log in oldLogs {
            do {
                try FileManager.default.removeItem(at: log)
            } catch {
                print("Failed to delete log: \(error)")
            }
        }
    }

    static func wipeShaderCaches() {
        let getconf = Process()
        getconf.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        getconf.arguments = ["DARWIN_USER_CACHE_DIR"]
        let pipe = Pipe()
        getconf.standardOutput = pipe
        do {
            try getconf.run()
        } catch {
            return
        }
        getconf.waitUntilExit()
        let getconfOutput: Data = {
            do {
                return try pipe.fileHandleForReading.readToEnd() ?? Data()
            } catch {
                return Data()
            }
        }()
        guard let getconfOutputString = String(data: getconfOutput, encoding: .utf8) else {return}
        let cacheRoot = URL(fileURLWithPath: getconfOutputString.trimmingCharacters(in: .whitespacesAndNewlines))
        for cacheName in ["d3dm", "dxmt"] {
            try? FileManager.default.removeItem(at: cacheRoot.appending(path: cacheName))
        }
    }
}
