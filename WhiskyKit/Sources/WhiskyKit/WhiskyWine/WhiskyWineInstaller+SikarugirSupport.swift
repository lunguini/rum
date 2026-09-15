//
//  WhiskyWineInstaller+SikarugirSupport.swift
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
    static let sikarugirSupportFolderName = "SikarugirSupport"
    private static let defaultSikarugirWrapperFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Sikarugir/Wrapper")

    /// Find the framework directory from an installed Sikarugir template. The engine archive is
    /// intentionally separate from the template, which owns libinotify and renderer payloads.
    static func sikarugirTemplateFrameworksURL() -> URL? {
        sikarugirTemplateFrameworksURL(in: defaultSikarugirWrapperFolder)
    }

    static func sikarugirTemplateFrameworksURL(for libraryFolder: URL) -> URL? {
        if let managed = managedSikarugirTemplateFrameworksURL(in: libraryFolder) {
            return managed
        }
        return sikarugirTemplateFrameworksURL()
    }

    static func sikarugirTemplateFrameworksURL(in wrapperFolder: URL) -> URL? {
        guard let templates = try? FileManager.default.contentsOfDirectory(
            at: wrapperFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return templates
            .filter { $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix("Template-") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appending(path: "Contents/Frameworks") }
            .first {
                FileManager.default.fileExists(atPath: $0.appending(path: "libinotify.0.dylib").path)
            }
    }

    private static func managedSikarugirTemplateFrameworksURL(in libraryFolder: URL) -> URL? {
        let supportFolder = libraryFolder.appending(path: sikarugirSupportFolderName)
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: supportFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return versions
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appending(path: "Frameworks") }
            .first {
                FileManager.default.fileExists(atPath: $0.appending(path: "libinotify.0.dylib").path)
            }
    }

    static func sikarugirTemplateRendererRoot(
        for backend: GraphicsBackend,
        in wrapperFolder: URL? = nil,
        libraryFolder: URL = WhiskyWineInstaller.libraryFolder
    ) -> URL? {
        let frameworks: URL?
        if let wrapperFolder {
            frameworks = sikarugirTemplateFrameworksURL(in: wrapperFolder)
        } else {
            frameworks = sikarugirTemplateFrameworksURL(for: libraryFolder)
        }
        guard let frameworks else { return nil }

        let rendererName: String
        switch backend {
        case .dxmt:
            rendererName = "dxmt"
        case .d3dmetal:
            rendererName = "d3dmetal"
        case .wineD3D, .dxvk:
            return nil
        }
        return frameworks.appending(path: "renderer/\(rendererName)")
    }
}
