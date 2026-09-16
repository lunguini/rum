//
//  WhiskyWineInstaller+RendererLoader.swift
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

extension WhiskyWineInstaller {
    /// Patched macOS Wine loaders search this overlay before their own builtin DLL tree.
    /// WINEDLLPATH alone is searched after that tree and cannot replace WineD3D builtins.
    static func rendererLoaderEnvironment(
        for backend: GraphicsBackend,
        capabilities: WineGraphicsCapabilities?
    ) -> [String: String] {
        let root: URL?
        let modules: String
        switch backend {
        case .dxmt:
            root = capabilities?.dxmtRootURL
            modules = "dxgi,d3d11,d3d10core"
        case .d3dmetal:
            root = capabilities?.d3dmetalRootURL?.appending(path: "wine")
            modules = "dxgi,d3d11,d3d12"
        case .wineD3D, .dxvk:
            return [:]
        }
        guard let root else { return [:] }
        var result = ["WINEDLLPATH_PREPEND": root.path]
        // The Wine builtin marker follows the 64-byte DOS header.
        // Native DXMT builds retain their native-first override from BottleSettings.
        if isWineBuiltinDLL(root.appending(path: "x86_64-windows/d3d11.dll")) {
            result["WINEDLLOVERRIDES"] = "\(modules)=b"
        }
        return result
    }

    static func isWineBuiltinDLL(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 81), header.count >= 81,
              header.prefix(2) == Data([0x4d, 0x5a]) else { return false }
        return header[64..<81] == Data("Wine builtin DLL\0".utf8)
    }
}
