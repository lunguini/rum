//
//  Wine+ExecutionCoordinator.swift
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

actor RendererExecutionCoordinator {
    static let shared = RendererExecutionCoordinator()

    private struct LaunchState {
        let backend: GraphicsBackend
        let engineID: String
        var preparing = true
        var users = 1
    }
    private var activeBackends: [String: LaunchState] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// Returns true only for the first launch, which must initialize and prepare the prefix.
    func acquire(bottlePath: String, backend: GraphicsBackend, engineID: String = "") async throws -> Bool {
        while let active = activeBackends[bottlePath] {
            guard active.backend == backend else {
                throw GraphicsBackendError.conflictingBackend(bottlePath, active.backend, backend)
            }
            guard active.engineID == engineID else {
                throw GraphicsBackendError.unavailable(backend, "This bottle is still using another Wine engine.")
            }
            if active.preparing {
                await withCheckedContinuation { waiters[bottlePath, default: []].append($0) }
                try Task.checkCancellation()
                continue
            }
            activeBackends[bottlePath]?.users += 1
            return false
        }
        activeBackends[bottlePath] = LaunchState(backend: backend, engineID: engineID)
        return true
    }

    func prepared(bottlePath: String) {
        activeBackends[bottlePath]?.preparing = false
        resumeWaiters(bottlePath)
    }

    func release(bottlePath: String, backend: GraphicsBackend) {
        guard let active = activeBackends[bottlePath], active.backend == backend else { return }
        if active.users > 1 {
            activeBackends[bottlePath]?.users -= 1
            return
        }
        activeBackends[bottlePath] = nil
        resumeWaiters(bottlePath)
    }

    private func resumeWaiters(_ bottlePath: String) {
        let pending = waiters.removeValue(forKey: bottlePath) ?? []
        for waiter in pending { waiter.resume() }
    }
}
