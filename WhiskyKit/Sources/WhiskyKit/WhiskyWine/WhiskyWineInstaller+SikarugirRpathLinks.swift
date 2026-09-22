//
//  WhiskyWineInstaller+SikarugirRpathLinks.swift
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

extension WhiskyWineInstaller {
    /// Libraries the Sikarugir Wine binaries reference through `@rpath`. Their only `LC_RPATH` is
    /// `@loader_path/../lib`, so the loader looks for them in `<engine root>/lib` and nowhere else.
    ///
    /// Rum normally satisfies them by exporting `DYLD_FALLBACK_LIBRARY_PATH` to the Sikarugir
    /// template's `Frameworks` folder, which works when Rum spawns Wine itself. It cannot work when
    /// Wine is reached through a system shell: macOS SIP strips every `DYLD_*` variable from the
    /// environment of protected binaries such as `/bin/sh` and `/bin/zsh`, and the stripped
    /// environment is what those shells pass on to their children. Winetricks is a `#!/bin/sh`
    /// script launched from Terminal's shell, so `wineserver` there failed with
    /// `Library not loaded: @rpath/libinotify.0.dylib`.
    ///
    /// Symlinking the libraries into `<engine root>/lib` makes the engine self-sufficient, so it no
    /// longer depends on `DYLD_*` surviving into the process.
    static let sikarugirRpathLibraries = [
        "libinotify.0.dylib",
        "libintl.8.dylib",
        "libavcodec.61.dylib",
        "libavformat.61.dylib",
        "libavutil.59.dylib",
        "libglib-2.0.0.dylib",
        "libgobject-2.0.0.dylib",
        "libgstaudio-1.0.0.dylib",
        "libgstbase-1.0.0.dylib",
        "libgstreamer-1.0.0.dylib",
        "libgsttag-1.0.0.dylib",
        "libgstvideo-1.0.0.dylib"
    ]

    /// Directories inside a Sikarugir template's `Frameworks` folder that hold the `@rpath`
    /// libraries. GStreamer keeps its payload in a versioned framework, so every installed version
    /// is searched rather than assuming `1.0`.
    static func sikarugirLibrarySearchPaths(inFrameworks frameworks: URL) -> [URL] {
        var paths = [frameworks]
        let gstreamerVersions = frameworks.appending(path: "GStreamer.framework/Versions")
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: gstreamerVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        paths.append(contentsOf: versions.map { $0.appending(path: "lib") })
        return paths
    }

    /// Link the template-owned support libraries into a Sikarugir engine's `lib` folder.
    /// Idempotent, and never replaces a real file the engine shipped itself.
    /// - Returns: the library names that are present in `lib` once the call completes.
    @discardableResult
    static func linkSikarugirSupportLibraries(
        forEngineRoot root: URL,
        frameworks: URL
    ) -> [String] {
        let fileManager = FileManager.default
        let libFolder = root.appending(path: "lib")
        guard (try? fileManager.createDirectory(at: libFolder, withIntermediateDirectories: true)) != nil else {
            return []
        }

        let searchPaths = sikarugirLibrarySearchPaths(inFrameworks: frameworks)
        var linked: [String] = []

        for name in sikarugirRpathLibraries {
            let destination = libFolder.appending(path: name)

            // A regular file here is the engine's own copy and always wins.
            let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
            if let type = attributes?[.type] as? FileAttributeType, type != .typeSymbolicLink {
                linked.append(name)
                continue
            }

            guard let source = searchPaths
                .map({ $0.appending(path: name) })
                .first(where: { fileManager.fileExists(atPath: $0.path) }) else {
                continue
            }

            // Replace a stale symlink, e.g. one pointing at a template version that was removed.
            if let existing = try? fileManager.destinationOfSymbolicLink(atPath: destination.path) {
                guard existing != source.path else {
                    linked.append(name)
                    continue
                }
                try? fileManager.removeItem(at: destination)
            }

            do {
                try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
                linked.append(name)
            } catch {
                print("Failed to link Sikarugir support library \(name): \(error)")
            }
        }

        return linked
    }

    /// Refresh the support links for every installed Sikarugir engine. Safe to call repeatedly;
    /// it is invoked after installing an engine or a template, and before launching winetricks.
    public static func linkSikarugirSupportLibraries(in libraryFolder: URL = libraryFolder) {
        guard let frameworks = sikarugirTemplateFrameworksURL(for: libraryFolder) else { return }

        for engine in installedWineEngines(in: libraryFolder) where engine.kind == .sikarugir {
            linkSikarugirSupportLibraries(forEngineRoot: engine.wineURL, frameworks: frameworks)
        }
    }
}
