//
//  SparkleView.swift
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

import SwiftUI
import SemanticVersion

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

        // Compared as versions, so 2.0.10 is newer than 2.0.9 and 2.0.0 newer than 2.0.0-beta.3.
        let isNewer = if let latest = SemanticVersion(latestVersion), let current = SemanticVersion(currentVersion) {
            latest > current
        } else {
            latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending
        }
        if isNewer {
            showUpdateAvailable(latestVersion: latestVersion, releaseURL: releaseURL)
        } else {
            showAlert(
                title: String(localized: "update.uptodate.title"),
                message: String(localized: "update.uptodate.message \(currentVersion)")
            )
        }
    }

    /// The newest release on this app's own major line (v1 never offers v2, and the other way
    /// round). Betas are offered only to people already running a pre-release.
    private func fetchLatestRelease() async -> (String, URL)? {
        guard let url = URL(
            string: "https://api.github.com/repos/lunguini/rum/releases?per_page=50"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let currentMajor = current.split(separator: ".").first.map(String.init)
        let includePrereleases = current.contains("-")

        for release in releases {
            guard let tagName = release["tag_name"] as? String,
                  let htmlURL = release["html_url"] as? String,
                  let releaseURL = URL(string: htmlURL),
                  release["draft"] as? Bool != true else { continue }
            if release["prerelease"] as? Bool == true && !includePrereleases { continue }
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            guard version.split(separator: ".").first.map(String.init) == currentMajor else { continue }
            // GitHub lists releases newest first.
            return (version, releaseURL)
        }
        return nil
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
