//
//  Bottle+Extensions.swift
//  Rum
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
import AppKit
import RumKit
import os.log

extension Bottle {
    func openCDrive() {
        NSWorkspace.shared.open(url.appending(path: "drive_c"))
    }

    func openTerminal() {
        let rumCmdURL = Bundle.main.url(forResource: "RumCmd", withExtension: nil)
        if let rumCmdURL = rumCmdURL {
            let rumCmd = rumCmdURL.path(percentEncoded: false)
            let cmd = "eval \\\"$(\\\"\(rumCmd)\\\" shellenv \\\"\(settings.name)\\\")\\\""

            let script = """
            tell application "Terminal"
            activate
            do script "\(cmd)"
            end tell
            """

            Task.detached(priority: .userInitiated) {
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else { return }
                appleScript.executeAndReturnError(&error)

                if let error = error {
                    Logger.wineKit.error("Failed to run terminal script \(error)")
                    guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                    await self.showRunError(message: String(describing: description))
                }
            }
        }
    }

    /// Stop every instance of the program at `url` in this bottle. Asks it to close first (like
    /// clicking the window's close button), then force-quits whatever is still running.
    /// Processes are matched by executable name, so another program in this bottle with the same
    /// file name is stopped too.
    func stopProgram(at url: URL) async {
        let imageName = url.lastPathComponent
        _ = try? await Wine.runWine(["taskkill.exe", "/IM", imageName], bottle: self)

        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(300))
            let isRunning = await MainActor.run { runningPrograms.contains(url) }
            guard isRunning else { return }
        }

        _ = try? await Wine.runWine(["taskkill.exe", "/IM", imageName, "/F"], bottle: self)
    }

    /// Kill every instance of the program at `url` right away, for when it hangs. Skips the polite
    /// close request. If Wine itself is stuck and `taskkill` can't get through, the program's
    /// macOS processes are sent SIGKILL instead.
    func forceStopProgram(at url: URL) async {
        let imageName = url.lastPathComponent
        let taskkill = Task.detached { [self] in
            _ = try? await Wine.runWine(["taskkill.exe", "/IM", imageName, "/F"], bottle: self)
        }

        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(300))
            let isRunning = await MainActor.run { runningPrograms.contains(url) }
            guard isRunning else { return }
        }

        taskkill.cancel()
        Self.killUnixProcesses(runningImage: imageName)
    }

    /// SIGKILLs processes whose command line runs a Windows executable named `imageName`.
    private static func killUnixProcesses(runningImage imageName: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", "pid=,command="]
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(bytes: data, encoding: .utf8) else { return }

        let needle = imageName.lowercased()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[..<space]), pid != ownPID else { continue }
            // Match the executable as a path component: `…\game.exe` or `…/game.exe`.
            let command = trimmed[space...].lowercased()
            let matches = command.contains("\\" + needle) || command.contains("/" + needle)
                || command.trimmingCharacters(in: .whitespaces).hasPrefix(needle)
            if matches {
                kill(pid, SIGKILL)
            }
        }
    }

    /// Replaces a pin's default name (its file name) with the program's own name from its version
    /// info, e.g. `cheatengine-x86_64` → "Cheat Engine". Names the user picked are left alone.
    @MainActor
    func adoptProductName(for url: URL) async {
        let fileName = url.deletingPathExtension().lastPathComponent
        func hasDefaultName() -> Bool {
            settings.pins.contains { $0.url == url && $0.name.caseInsensitiveCompare(fileName) == .orderedSame }
        }
        guard hasDefaultName() else { return }
        let name = await Task.detached(priority: .utility) {
            (try? PEFile(url: url))?.productDisplayName
        }.value
        guard let name, hasDefaultName(),
              let index = settings.pins.firstIndex(where: { $0.url == url }) else { return }
        settings.pins[index].name = name
    }

    /// All `.lnk` files in the bottle's global and per-user Start Menus, sorted by name.
    private func startMenuLinkURLs() -> [URL] {
        let driveC = url.appending(path: "drive_c")
        let startMenuPath = "Microsoft/Windows/Start Menu"

        var startMenus = [driveC.appending(path: "ProgramData").appending(path: startMenuPath)]
        // Engines name the Windows user differently (CrossOver uses `crossover`, others the Mac
        // username), so look in every user's profile.
        let usersFolder = driveC.appending(path: "users")
        let users = (try? FileManager.default.contentsOfDirectory(at: usersFolder,
                                                                  includingPropertiesForKeys: nil)) ?? []
        for user in users {
            startMenus.append(user.appending(path: "AppData/Roaming").appending(path: startMenuPath))
        }

        var linkURLs: [URL] = []
        for startMenu in startMenus {
            let enumerator = FileManager.default.enumerator(at: startMenu,
                                                            includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles])
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "lnk" {
                    linkURLs.append(url)
                }
            }
        }

        return linkURLs.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
    }

    /// Start Menu shortcuts resolved to their target executables. Unlike `getStartMenuPrograms`
    /// this is read-only: the `.lnk` files are left in place.
    func startMenuShortcuts() -> [(name: String, url: URL)] {
        var shortcuts: [(name: String, url: URL)] = []
        for link in startMenuLinkURLs() {
            guard let handle = try? FileHandle(forReadingFrom: link) else { continue }
            defer { try? handle.close() }
            guard let program = ShellLinkHeader.getProgram(url: link, handle: handle, bottle: self),
                  !shortcuts.contains(where: { $0.url == program.url }) else { continue }
            shortcuts.append((link.deletingPathExtension().lastPathComponent, program.url))
        }
        return shortcuts
    }

    @discardableResult
    func getStartMenuPrograms() -> [Program] {
        var startMenuPrograms: [Program] = []
        let linkURLs = startMenuLinkURLs()

        for link in linkURLs {
            do {
                if let program = ShellLinkHeader.getProgram(url: link,
                                                            handle: try FileHandle(forReadingFrom: link),
                                                            bottle: self) {
                    if !startMenuPrograms.contains(where: { $0.url == program.url }) {
                        startMenuPrograms.append(program)
                        try FileManager.default.removeItem(at: link)
                    }
                }
            } catch {
                print(error)
            }
        }

        return startMenuPrograms
    }

    func updateInstalledPrograms() {
        let driveC = url.appending(path: "drive_c")
        var programs: [Program] = []
        var foundURLS: Set<URL> = []

        for folderName in ["Program Files", "Program Files (x86)"] {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath && url.pathExtension == "exe" else { continue }
                guard !settings.blocklist.contains(url) else { continue }
                foundURLS.insert(url)
                programs.append(Program(url: url, bottle: self))
            }
        }

        // Add missing programs from pins
        for pin in settings.pins {
            guard let url = pin.url else { continue }
            guard !foundURLS.contains(url) else { continue }
            programs.append(Program(url: url, bottle: self))
        }

        self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    @MainActor
    func move(destination: URL) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
                for index in 0..<bottle.settings.pins.count {
                    let pin = bottle.settings.pins[index]
                    if let url = pin.url {
                        bottle.settings.pins[index].url = url.updateParentBottle(old: url,
                                                                                 new: destination)
                    }
                }

                for index in 0..<bottle.settings.blocklist.count {
                    let blockedUrl = bottle.settings.blocklist[index]
                    bottle.settings.blocklist[index] = blockedUrl.updateParentBottle(old: url,
                                                                                     new: destination)
                }
            }
            try FileManager.default.moveItem(at: url, to: destination)
            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths[path] = destination
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to move bottle")
        }
    }

    func exportAsArchive(destination: URL) {
        do {
            try Tar.tar(folder: url, toURL: destination)
        } catch {
            print("Failed to export bottle")
        }
    }

    @MainActor
    func remove(delete: Bool) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
            }

            if delete {
                try FileManager.default.removeItem(at: url)
            }

            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths.remove(at: path)
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to remove bottle")
        }
    }

    @MainActor
    func rename(newName: String) {
        settings.name = newName
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
