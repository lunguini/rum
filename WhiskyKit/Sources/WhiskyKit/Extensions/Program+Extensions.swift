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
import UserNotifications
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
        let programName = self.url.lastPathComponent
        let notificationID = "launch-\(UUID().uuidString)"

        Self.postLaunchNotification(programName: programName, identifier: notificationID)
        let dockBounce = NSApp.requestUserAttention(.informationalRequest)

        Task.detached(priority: .userInitiated) {
            do {
                try await Wine.runProgram(
                    at: self.url, args: arguments, bottle: self.bottle, environment: environment,
                    onStarted: {
                        Self.removeLaunchNotification(identifier: notificationID)
                        NSApp.cancelUserAttentionRequest(dockBounce)
                        onStarted?()
                    }
                )
            } catch {
                Self.removeLaunchNotification(identifier: notificationID)
                NSApp.cancelUserAttentionRequest(dockBounce)
                await MainActor.run {
                    self.showRunError(message: error.localizedDescription)
                }
            }
            onFinished?()
        }
    }

    private static func postLaunchNotification(programName: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.launching.title")
        content.body = String(localized: "notification.launching.body \(programName)")

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func removeLaunchNotification(identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
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
        alert.runModal()
    }
}
