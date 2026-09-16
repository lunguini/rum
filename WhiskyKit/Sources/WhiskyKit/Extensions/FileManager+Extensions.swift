//
//  FileHandle+Extensions.swift
//  WhiskyKit
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

extension FileManager {
    func replaceDLLs(
        in destinationDirectory: URL, withContentsIn sourceDirectory: URL, makeOriginalCopy: Bool = true
    ) throws {
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey])

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "dll" else { continue }
            let originalURL = destinationDirectory.appending(path: fileURL.lastPathComponent)
            try FileManager.default.replaceFile(at: originalURL, with: fileURL, makeOriginalCopy: makeOriginalCopy)
        }
    }

    /// Restore DLLs previously replaced by `replaceDLLs`. A replacement is only removed when the
    /// destination still matches the replacement byte-for-byte; this prevents a later user change
    /// from being silently destroyed.
    func restoreDLLs(
        in destinationDirectory: URL, from sourceDirectory: URL
    ) throws {
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory, includingPropertiesForKeys: [.isRegularFileKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "dll" else { continue }
            let destinationURL = destinationDirectory.appending(path: fileURL.lastPathComponent)
            let originalURL = destinationURL.appendingPathExtension("orig")
            let replacementMatches = sameContents(at: destinationURL, and: fileURL)

            guard replacementMatches || fileExists(atPath: originalURL.path(percentEncoded: false)) else {
                continue
            }

            if !replacementMatches {
                throw RendererStateError.userModifiedFile(destinationURL.path(percentEncoded: false))
            }

            if fileExists(atPath: originalURL.path(percentEncoded: false)) {
                try? removeItem(at: destinationURL)
                try moveItem(at: originalURL, to: destinationURL)
            } else {
                try? removeItem(at: destinationURL)
            }
        }
    }

    func replaceFile(at originalURL: URL, with replacementURL: URL, makeOriginalCopy: Bool = true) throws {
        guard fileExists(atPath: replacementURL.path(percentEncoded: false)) else {
            throw RendererStateError.missingReplacementFile(replacementURL.path(percentEncoded: false))
        }

        let copyURL = originalURL.appendingPathExtension("orig")
        if sameContents(at: originalURL, and: replacementURL) {
            // Even when the bytes already match, retain the pre-existing file as the original.
            // Without this, restoring the renderer would delete a file we did not create.
            if makeOriginalCopy,
               fileExists(atPath: originalURL.path(percentEncoded: false)),
               !fileExists(atPath: copyURL.path(percentEncoded: false)) {
                try copyItem(at: originalURL, to: copyURL)
            }
            return
        }

        let temporaryURL = originalURL.appendingPathExtension("tmp-\(UUID().uuidString)")
        var movedOriginal = false

        if makeOriginalCopy,
           !fileExists(atPath: originalURL.path(percentEncoded: false)),
           fileExists(atPath: copyURL.path(percentEncoded: false)) {
            throw RendererStateError.userModifiedFile(copyURL.path(percentEncoded: false))
        }

        do {
            try copyItem(at: replacementURL, to: temporaryURL)

            if fileExists(atPath: originalURL.path(percentEncoded: false)) {
                if makeOriginalCopy {
                    if fileExists(atPath: copyURL.path(percentEncoded: false)) {
                        throw RendererStateError.userModifiedFile(originalURL.path(percentEncoded: false))
                    }
                    try moveItem(at: originalURL, to: copyURL)
                    movedOriginal = true
                } else {
                    try removeItem(at: originalURL)
                }
            }

            try moveItem(at: temporaryURL, to: originalURL)
        } catch {
            try? removeItem(at: temporaryURL)
            if movedOriginal, !fileExists(atPath: originalURL.path(percentEncoded: false)) {
                try? moveItem(at: copyURL, to: originalURL)
            }
            throw error
        }
    }

    private func sameContents(at lhs: URL, and rhs: URL) -> Bool {
        guard fileExists(atPath: lhs.path(percentEncoded: false)),
              fileExists(atPath: rhs.path(percentEncoded: false)),
              let lhsData = try? Data(contentsOf: lhs),
              let rhsData = try? Data(contentsOf: rhs) else {
            return false
        }
        return lhsData == rhsData
    }
}
