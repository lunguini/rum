//
//  GraphicsDeviceCanaryTests.swift
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

import XCTest
@testable import WhiskyKit

final class GraphicsDeviceCanaryTests: XCTestCase {
    /// Opt in with a Windows probe built from scripts/d3d11-device-canary.go.
    /// Uses Rum's actual launch path, but only a disposable prefix.
    func testHardwareDeviceWithSelectedRenderer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let executable = environment["RUM_D3D11_CANARY_EXE"],
              let engineID = environment["RUM_D3D11_CANARY_ENGINE_ID"] else {
            throw XCTSkip("Set RUM_D3D11_CANARY_EXE and RUM_D3D11_CANARY_ENGINE_ID for a live device check.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "RumDeviceCanary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bottle = Bottle(bottleUrl: root)
        bottle.settings.wineEngineID = engineID
        bottle.settings.graphicsBackend = GraphicsBackend(
            rawValue: environment["RUM_D3D11_CANARY_BACKEND"] ?? "dxmt"
        ) ?? .dxmt
        bottle.settings.architecture = .win64
        let result = root.appending(path: "device-result.txt")
        do {
            try await Wine.runProgram(
                at: URL(fileURLWithPath: executable), args: ["Z:" + result.path], bottle: bottle
            )
            XCTAssertEqual(try String(contentsOf: result, encoding: .utf8), "PASS")
        } catch {
            try? await Wine.killBottleAndWait(bottle: bottle)
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        try await Wine.killBottleAndWait(bottle: bottle)
        try FileManager.default.removeItem(at: root)
    }
}
