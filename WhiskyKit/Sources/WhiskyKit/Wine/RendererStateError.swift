//
//  RendererStateError.swift
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

public enum RendererStateError: Error, LocalizedError, Equatable, Sendable {
    case missingReplacementFile(String)
    case userModifiedFile(String)
    case invalidManifest(String)

    public var errorDescription: String? {
        switch self {
        case .missingReplacementFile(let path):
            return "Renderer file is missing: \(path)"
        case .userModifiedFile(let path):
            return "Renderer file was changed outside Rum and cannot be replaced safely: \(path)"
        case .invalidManifest(let path):
            return "Renderer state is invalid and cannot be used safely: \(path)"
        }
    }
}
