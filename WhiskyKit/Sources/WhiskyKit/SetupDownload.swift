//
//  SetupDownload.swift
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

/// Preserves a URLSession download before its completion handler returns.
public enum SetupDownload {
    public static func preserve(location: URL?, response: URLResponse?, error: Error?) throws -> URL {
        if let error { throw error }
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let location else { throw URLError(.fileDoesNotExist) }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.moveItem(at: location, to: destination)
        return destination
    }
}
