//
//  SetupDownloadTests.swift
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

import XCTest
@testable import WhiskyKit

final class SetupDownloadTests: XCTestCase {
    func testDownloadSurvivesSessionTemporaryFileCleanup() throws {
        let original = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let content = Data("archive contents".utf8)
        try content.write(to: original)
        defer { try? FileManager.default.removeItem(at: original) }
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(fileURLWithPath: "/wine.tar.xz"),
            statusCode: 200, httpVersion: nil, headerFields: nil
        ))
        let saved = try SetupDownload.preserve(location: original, response: response, error: nil)
        defer { try? FileManager.default.removeItem(at: saved) }
        // Simulate URLSession discarding the original after its completion handler returns.
        try? FileManager.default.removeItem(at: original)
        XCTAssertEqual(try Data(contentsOf: saved), content)
    }

    func testHTTPErrorIsNotPreservedAsAnArchive() throws {
        let response = HTTPURLResponse(
            url: URL(fileURLWithPath: "/wine.tar.xz"),
            statusCode: 404, httpVersion: nil, headerFields: nil
        )
        XCTAssertThrowsError(try SetupDownload.preserve(location: nil, response: response, error: nil)) {
            XCTAssertEqual(($0 as? URLError)?.code, .badServerResponse)
        }
    }

    func testTransportErrorIsReported() {
        XCTAssertThrowsError(try SetupDownload.preserve(
            location: nil, response: nil, error: URLError(.timedOut)
        )) {
            XCTAssertEqual(($0 as? URLError)?.code, .timedOut)
        }
    }
}
