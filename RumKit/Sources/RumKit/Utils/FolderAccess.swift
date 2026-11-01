//
//  FolderAccess.swift
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

public enum FolderAccess {
    /// System Settings → Privacy & Security → Files & Folders.
    public static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
    )

    /// Whether Rum may read `folder`. Listing it from Rum's own process is what makes macOS
    /// show its "Allow Rum to access…" prompt for protected folders such as Downloads, Desktop
    /// and Documents; Wine reading it later is refused silently instead. Blocks while the prompt
    /// is on screen, so call it off the main thread.
    public static func canRead(_ folder: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            return true
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return false
        } catch {
            // Missing folders and other errors are reported by the launch itself.
            return true
        }
    }
}
