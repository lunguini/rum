//
//  Program+Extensions.swift
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
import os.log

extension Program {
    public func run(onStarted: (@Sendable () -> Void)? = nil, onFinished: (@Sendable () -> Void)? = nil) {
        if NSEvent.modifierFlags.contains(.shift) {
            self.runInTerminal()
        } else {
            self.runInWine(onStarted: onStarted, onFinished: onFinished)
        }
    }

    func runInWine(onStarted: (@Sendable () -> Void)? = nil, onFinished: (@Sendable () -> Void)? = nil) {
        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()
        let programURL = self.url
        let programName = self.name

        self.bottle.recordRun(url: programURL, name: programName)
        DispatchQueue.main.async { self.bottle.runningPrograms.insert(programURL) }

        Task.detached(priority: .userInitiated) {
            do {
                try await Wine.runProgram(
                    at: self.url, args: arguments, bottle: self.bottle, environment: environment,
                    onStarted: onStarted
                )
            } catch {
                let errorMessage = error.localizedDescription
                DispatchQueue.main.async {
                    self.showRunError(message: errorMessage)
                }
            }
            DispatchQueue.main.async { self.bottle.runningPrograms.remove(programURL) }
            onFinished?()
        }
    }

    public func generateTerminalCommand() -> String {
        return Wine.generateRunCommand(
            at: self.url, bottle: bottle, args: settings.arguments, environment: generateEnvironment()
        )
    }

    public func runInTerminal() {
        let wineCmd = generateTerminalCommand().replacingOccurrences(of: "\\", with: "\\\\")

        let script = """
        tell application "Terminal"
            activate
            do script "\(wineCmd)"
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

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
