//
//  LibraryView+Drop.swift
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

import OSLog
import SwiftUI
import UniformTypeIdentifiers
import RumKit

/// A short message at the bottom of the window that says what happened to something the user
/// added, so a drop is never silently ignored.
struct LibraryNotice: Equatable {
    let id = UUID()
    let text: String
    let systemImage: String
}

/// Asks Home to scroll a just-added program into view. Each request is new, so adding the same
/// program twice still scrolls.
struct LibraryReveal: Equatable {
    let id = UUID()
    let itemID: LibraryPinItem.ID
}

// MARK: - Adding programs

extension LibraryView {
    /// Adds a program to the Library. If it's already there, shows it instead.
    func pin(_ url: URL, name: String, in bottle: Bottle) {
        let id = LibraryPinItem.id(bottle: bottle, url: url)
        if let existing = bottle.settings.pins.first(where: { $0.url == url }) {
            Logger.wineKit.debug("Pin: already pinned in \(bottle.settings.name, privacy: .public)")
            // Home lists only recent additions, so go to the full Library unless it's already shown.
            if currentPage == .home && recentlyAddedItems.contains(where: { $0.id == id }) {
                reveal = LibraryReveal(itemID: id)
                Logger.wineKit.debug("Reveal: requested for an existing pin")
            } else if currentPage != .library {
                page = .library
            }
            selection = id
            notice = LibraryNotice(text: String(format: "%@ is already in your library", existing.name),
                                   systemImage: "checkmark.circle")
            return
        }
        bottle.settings.pins.append(PinnedProgram(name: name, url: url))
        Logger.wineKit.debug("Pin: added, \(bottle.settings.pins.count) pin(s) now")
        selection = id
        if currentPage == .home {
            reveal = LibraryReveal(itemID: id)
            Logger.wineKit.debug("Reveal: requested for a new pin")
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let log = Logger.wineKit
        log.debug("Drop: \(providers.count) item(s), types \(providers.map(\.registeredTypeIdentifiers))")
        guard let bottle = defaultBottle else {
            log.debug("Drop: rejected, no default bottle")
            notice = LibraryNotice(text: String(localized: "Create a bottle first, then add games and apps to it."),
                                   systemImage: "exclamationmark.triangle")
            return false
        }
        // Finder's providers often have no `suggestedName`, or one without the extension, so
        // the file type can only be checked once the URL is loaded.
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in fileProviders {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                // Finder often sends a file reference URL (file:///.file/id=…), which has no path
                // extension until it's resolved to the file's real path.
                guard let data, let dropped = URL(dataRepresentation: data, relativeTo: nil),
                      let url = (dropped as NSURL).filePathURL else {
                    log.debug("Drop: couldn't load the file URL: \(String(describing: error))")
                    return
                }
                guard Self.runnableExtensions.contains(url.pathExtension.lowercased()) else {
                    log.debug("Drop: rejected \(url.path(percentEncoded: false), privacy: .public)")
                    let message = Self.rejectionMessage(for: url)
                    Task { @MainActor in
                        notice = LibraryNotice(text: message, systemImage: "nosign")
                    }
                    return
                }
                log.debug("Drop: adding \(url.path(percentEncoded: false), privacy: .public)")
                Task { @MainActor in
                    pin(url, name: url.deletingPathExtension().lastPathComponent, in: bottle)
                }
            }
        }
        return !fileProviders.isEmpty
    }

    /// Why a dropped file can't be added, and what to drop instead.
    nonisolated static func rejectionMessage(for url: URL) -> String {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "app" {
            return String(localized: "Mac apps can't be added. Drop the game's Windows .exe instead.")
        }
        if url.hasDirectoryPath {
            return String(localized: "Folders can't be added. Drop the game's .exe from inside it instead.")
        }
        if fileExtension.isEmpty {
            return String(localized: "That file can't be added. Drop a Windows .exe or .bat instead.")
        }
        return String(format: String(localized: "Can't add .%@ files. Drop a Windows .exe or .bat instead."),
                      fileExtension)
    }
}

extension LibraryPinItem {
    /// When this was added to the Library. Pins from before Rum recorded that fall back to when
    /// the program's file appeared on disk, which is when it was installed or downloaded.
    var addedDate: Date {
        if let added = pin.added { return added }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .addedToDirectoryDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
    }
}

// MARK: - Notice

struct LibraryNoticeView: View {
    let notice: LibraryNotice

    var body: some View {
        Label(notice.text, systemImage: notice.systemImage)
            .font(.callout.weight(.medium))
            .lineLimit(2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
