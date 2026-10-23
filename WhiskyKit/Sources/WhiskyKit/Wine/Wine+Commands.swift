//
//  Wine+Commands.swift
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

/// Shell commands that run Wine the way Rum would, for Terminal and app shortcuts.
extension Wine {
    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String],
        graphicsBackend: GraphicsBackend? = nil
    ) -> String {
        var wineCmd = "\(wineBinary(for: bottle).esc) start /wait /unix \(url.esc) \(args)"
        let env = constructWineEnvironment(for: bottle, environment: environment, graphicsBackend: graphicsBackend)
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }

        return wineCmd
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        let env = constructWineEnvironment(for: bottle)
        var cmd = "export WINE=\"\(wineBinary(for: bottle).path)\""
        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            cmd += "\nexport \(key)=\"\(value)\""
        }

        return cmd
    }
}
