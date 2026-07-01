//
//  Winetricks.swift
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
import AppKit
import WhiskyKit

enum WinetricksCategories: String {
    case apps
    case benchmarks
    case dlls
    case fonts
    case games
    case settings
}

struct WinetricksVerb: Identifiable {
    var id = UUID()

    var name: String
    var description: String
}

struct WinetricksCategory {
    var category: WinetricksCategories
    var verbs: [WinetricksVerb]
}

class Winetricks {
    static let winetricksURL: URL = WhiskyWineInstaller.libraryFolder
        .appending(path: "winetricks")
    static let verbsURL: URL = WhiskyWineInstaller.libraryFolder
        .appending(path: "verbs.txt")

    /// Official self-contained winetricks script.
    private static let winetricksDownloadURL = URL(
        string: "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks"
    )

    /// Ensures the `winetricks` script and its `verbs.txt` verb list exist in the library folder,
    /// downloading/generating them on first use. Rum's installer does not bundle these, so the
    /// Winetricks UI would otherwise open with an empty list. Returns `true` when the verb list
    /// is available to parse.
    @discardableResult
    static func ensureInstalled() async -> Bool {
        let fileManager = FileManager.default
        let libraryFolder = WhiskyWineInstaller.libraryFolder

        if !fileManager.fileExists(atPath: winetricksURL.path(percentEncoded: false)) {
            guard let winetricksDownloadURL else { return false }
            do {
                if !fileManager.fileExists(atPath: libraryFolder.path(percentEncoded: false)) {
                    try fileManager.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
                }
                let (data, _) = try await URLSession.shared.data(from: winetricksDownloadURL)
                try data.write(to: winetricksURL)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: winetricksURL.path(percentEncoded: false)
                )
            } catch {
                print("Failed to download winetricks: \(error)")
                return false
            }
        }

        if !fileManager.fileExists(atPath: verbsURL.path(percentEncoded: false)) {
            await generateVerbs()
        }

        return fileManager.fileExists(atPath: verbsURL.path(percentEncoded: false))
    }

    /// Runs `winetricks list-all` headlessly and captures its output into `verbs.txt`. The
    /// output is already grouped as `===== category =====` blocks, which `parseVerbs` expects.
    private static func generateVerbs() async {
        guard let resourcesURL = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent() else { return }
        let binPath = WhiskyWineInstaller.binFolder.path
        let resPath = resourcesURL.path(percentEncoded: false)
        let wineName = Wine.wineBinary.lastPathComponent
        let tricks = winetricksURL.path(percentEncoded: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            #"PATH="\#(binPath):\#(resPath):$PATH" WINE=\#(wineName) "\#(tricks)" list-all"#
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try data.write(to: verbsURL)
        } catch {
            print("Failed to generate winetricks verbs: \(error)")
        }
    }

    static func runCommand(command: String, bottle: Bottle) async {
        guard let resourcesURL = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent() else { return }
        let wineName = Wine.wineBinary.lastPathComponent
        let binPath = WhiskyWineInstaller.binFolder.path
        let resPath = resourcesURL.path(percentEncoded: false)
        let prefix = bottle.url.path
        let tricks = winetricksURL.path(percentEncoded: false)
        let winetricksCmd = #"PATH=\"\#(binPath):\#(resPath):$PATH\""#
            + #" WINE=\#(wineName) WINEPREFIX=\"\#(prefix)\""#
            + #" \"\#(tricks)\" \#(command)"#

        let script = """
        tell application "Terminal"
            activate
            do script "\(winetricksCmd)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                print(error)
                if let description = error["NSAppleScriptErrorMessage"] as? String {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "alert.message")
                        alert.informativeText = String(localized: "alert.info")
                            + " \(command): "
                            + description
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: String(localized: "button.ok"))
                        alert.runModal()
                    }
                }
            }
        }
    }

    static func parseVerbs() async -> [WinetricksCategory] {
        // Make sure the winetricks script and verb list are present before reading them.
        guard await ensureInstalled() else { return [] }

        // Grab the verbs file
        let verbs: String = (try? String(contentsOf: verbsURL, encoding: .utf8)) ?? String()

        // Read the file line by line
        let lines = verbs.components(separatedBy: "\n")
        var categories: [WinetricksCategory] = []
        var currentCategory: WinetricksCategory?

        for line in lines {
            // Categories are label as "===== <name> ====="
            if line.starts(with: "=====") {
                // If we have a current category, add it to the list
                if let currentCategory = currentCategory {
                    categories.append(currentCategory)
                }

                // Create a new category
                // Capitalize the first letter of the category name
                let categoryName = line.replacingOccurrences(of: "=====", with: "").trimmingCharacters(in: .whitespaces)
                if let cateogry = WinetricksCategories(rawValue: categoryName) {
                    currentCategory = WinetricksCategory(category: cateogry,
                                                         verbs: [])
                } else {
                    currentCategory = nil
                }
            } else {
                guard currentCategory != nil else {
                    continue
                }

                // If we have a current category, add the verb to it
                // Verbs eg. "3m_library               3M Cloud Library (3M Company, 2015) [downloadable]"
                let verbName = line.components(separatedBy: " ")[0]
                let verbDescription = line.replacingOccurrences(of: "\(verbName) ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentCategory?.verbs.append(WinetricksVerb(name: verbName, description: verbDescription))
            }
        }

        // Add the last category
        if let currentCategory = currentCategory {
            categories.append(currentCategory)
        }

        return categories
    }
}
