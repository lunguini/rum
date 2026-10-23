//
//  BottleRunningProgramsTests.swift
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

final class BottleRunningProgramsTests: XCTestCase {
    private let programURL = URL(filePath: "/Games/Game/Game.exe")

    private func makeBottle() -> Bottle {
        Bottle(bottleUrl: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    func testProgramStaysRunningUntilEveryInstanceExits() {
        let bottle = makeBottle()

        bottle.programDidStart(programURL)
        bottle.programDidStart(programURL)
        XCTAssertEqual(bottle.runningInstances(of: programURL), 2)

        bottle.programDidExit(programURL)
        XCTAssertEqual(bottle.runningInstances(of: programURL), 1)
        XCTAssertTrue(bottle.runningPrograms.contains(programURL))

        bottle.programDidExit(programURL)
        XCTAssertEqual(bottle.runningInstances(of: programURL), 0)
        XCTAssertFalse(bottle.runningPrograms.contains(programURL))
    }

    func testExtraExitDoesNotGoNegative() {
        let bottle = makeBottle()

        bottle.programDidExit(programURL)
        bottle.programDidStart(programURL)

        XCTAssertEqual(bottle.runningInstances(of: programURL), 1)
        XCTAssertTrue(bottle.runningPrograms.contains(programURL))
    }

    func testLaunchingUntilWineStartsEachInstance() {
        let bottle = makeBottle()

        bottle.programDidStart(programURL)
        bottle.programDidStart(programURL)
        XCTAssertTrue(bottle.isLaunching(programURL))

        bottle.programDidLaunch(programURL)
        XCTAssertTrue(bottle.isLaunching(programURL), "the second instance is still being prepared")

        bottle.programDidLaunch(programURL)
        XCTAssertFalse(bottle.isLaunching(programURL))
        XCTAssertTrue(bottle.runningPrograms.contains(programURL))
    }

    func testExitWhileLaunchingClearsLaunching() {
        let bottle = makeBottle()

        bottle.programDidStart(programURL)
        bottle.programDidExit(programURL)

        XCTAssertFalse(bottle.isLaunching(programURL))
        XCTAssertFalse(bottle.runningPrograms.contains(programURL))
    }

    func testPlayTimeCountsWhileAnyInstanceRuns() {
        let bottle = makeBottle()
        bottle.recordRun(url: programURL, name: "Game")
        let start = Date(timeIntervalSince1970: 1_000)

        bottle.programDidStart(programURL, at: start)
        bottle.programDidStart(programURL, at: start.addingTimeInterval(60))
        XCTAssertEqual(bottle.runningSince(programURL), start)
        bottle.programDidExit(programURL, at: start.addingTimeInterval(120))
        XCTAssertEqual(bottle.settings.runHistory.first?.playTime, 0, "one instance is still running")
        bottle.programDidExit(programURL, at: start.addingTimeInterval(300))

        XCTAssertEqual(bottle.settings.runHistory.first?.playTime, 300)
        XCTAssertNil(bottle.runningSince(programURL))
    }

    func testRecordRunCountsRuns() {
        let bottle = makeBottle()

        bottle.recordRun(url: programURL, name: "Game")
        bottle.recordRun(url: programURL, name: "Game")

        XCTAssertEqual(bottle.settings.runHistory.count, 1)
        XCTAssertEqual(bottle.settings.runHistory.first?.runCount, 2)
    }

    func testOlderHistoryEntriesDecode() throws {
        let entry = ["name": "Game", "url": "file:///Games/Game/Game.exe", "lastRun": 0] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: entry)

        let decoded = try JSONDecoder().decode(RunHistoryEntry.self, from: data)

        XCTAssertEqual(decoded.runCount, 1)
        XCTAssertEqual(decoded.playTime, 0)
        XCTAssertEqual(decoded.runDates, [decoded.lastRun])
    }

    func testRunDatesCountRecentRunsOnly() {
        var entry = RunHistoryEntry(name: "Game", url: programURL)
        let now = Date()
        entry.runDates = [now.addingTimeInterval(-200 * 24 * 60 * 60)]

        entry.recordRun(at: now.addingTimeInterval(-40 * 24 * 60 * 60))
        entry.recordRun(at: now.addingTimeInterval(-10 * 24 * 60 * 60))
        entry.recordRun(at: now)

        XCTAssertEqual(entry.runDates.count, 3, "runs older than 90 days are dropped")
        XCTAssertEqual(entry.runCount(since: now.addingTimeInterval(-30 * 24 * 60 * 60)), 2)
        XCTAssertEqual(entry.runCount, 4)
    }
}
