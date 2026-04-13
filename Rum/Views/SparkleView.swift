//
//  SparkleView.swift
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

struct UpdateCheckView: View {
    @State private var isChecking = false

    var body: some View {
        Button("check.updates") {
            isChecking = true
            Task {
                await checkForUpdate()
                isChecking = false
            }
        }
        .disabled(isChecking)
    }

    @MainActor
    private func checkForUpdate() async {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }

        guard let (latestVersion, releaseURL) = await fetchLatestRelease() else {
            showAlert(
                title: String(localized: "update.error.title"),
                message: String(localized: "update.error.message")
            )
            return
        }

        if latestVersion > currentVersion {
            showUpdateAvailable(latestVersion: latestVersion, releaseURL: releaseURL)
        } else {
            showAlert(
                title: String(localized: "update.uptodate.title"),
                message: String(localized: "update.uptodate.message \(currentVersion)")
            )
        }
    }

    private func fetchLatestRelease() async -> (String, URL)? {
        guard let url = URL(
            string: "https://api.github.com/repos/adrianlungu/rum/releases/latest"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURL = json["html_url"] as? String,
              let releaseURL = URL(string: htmlURL) else {
            return nil
        }

        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        return (version, releaseURL)
    }

    @MainActor
    private func showUpdateAvailable(latestVersion: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = String(localized: "update.available.title \(latestVersion)")
        alert.informativeText = String(localized: "update.available.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "update.available.open"))
        alert.addButton(withTitle: String(localized: "button.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
