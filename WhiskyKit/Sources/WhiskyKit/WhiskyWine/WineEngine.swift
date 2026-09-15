//
//  WineEngine.swift
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

/// The source family of a Wine runtime. Managed engines live in Rum's library; external engines
/// refer to an application installed elsewhere on the Mac.
public enum WineEngineKind: String, Codable, CaseIterable, Equatable, Sendable {
    case gcenx
    case sikarugir
    case crossOver
    case gamePortingToolkit
    case custom

    public var displayName: String {
        switch self {
        case .gcenx:
            return "Gcenx"
        case .sikarugir:
            return "Sikarugir"
        case .crossOver:
            return "CrossOver"
        case .gamePortingToolkit:
            return "Game Porting Toolkit"
        case .custom:
            return "Custom Wine"
        }
    }

    public var isManaged: Bool {
        switch self {
        case .gcenx, .sikarugir:
            return true
        case .crossOver, .gamePortingToolkit, .custom:
            return false
        }
    }
}

/// A concrete Wine runtime that can be selected for a bottle.
public struct WineEngine: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let kind: WineEngineKind
    public let wineURL: URL
    public let wineBinaryURL: URL
    public let wineserverBinaryURL: URL

    public var displayName: String {
        version.isEmpty ? name : "\(name) \(version)"
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: wineBinaryURL.path)
            && FileManager.default.fileExists(atPath: wineserverBinaryURL.path)
    }

    public init(
        id: String,
        name: String,
        version: String,
        kind: WineEngineKind,
        wineURL: URL,
        wineBinaryURL: URL,
        wineserverBinaryURL: URL
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.kind = kind
        self.wineURL = wineURL
        self.wineBinaryURL = wineBinaryURL
        self.wineserverBinaryURL = wineserverBinaryURL
    }

    public static func managedID(kind: WineEngineKind, version: String) -> String {
        "\(kind.rawValue):\(version)"
    }
}

/// Metadata stored beside a managed Wine tree. The metadata makes engine identity independent of
/// the directory name and lets new engine families coexist with legacy Gcenx directories.
struct InstalledWineEngineMetadata: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let version: String
    let kind: WineEngineKind
}
