//
//  SetupPlan.swift
//  Rum
//
//  This file is part of Rum.
//
//  Rum is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Rum is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Rum.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import RumKit

enum ExternalEngineKind: Hashable { case crossOver, gamePortingToolkit }

/// What the setup assistant installs. Basic is `SetupPlan.basic`; Advanced lets the user
/// change the engine and drop either graphics runtime (WineD3D ships with every engine).
struct SetupPlan: Hashable {
    enum Engine: Hashable {
        case sikarugir
        case gcenx
        /// An engine the user already has installed, such as CrossOver or Game Porting Toolkit.
        case external(ExternalEngineChoice)

        var title: String {
            switch self {
            case .sikarugir: "Sikarugir (recommended)"
            case .gcenx: "Gcenx Wine"
            case .external(let choice): choice.name
            }
        }
    }

    struct ExternalEngineChoice: Hashable {
        let kind: ExternalEngineKind
        let name: String
        let appURL: URL
    }

    var engine: Engine = .sikarugir
    var installDXVK = true
    var installDXMT = true
    var createDefaultBottle = true

    static let basic = SetupPlan()

    /// External engines found in /Applications, offered in Advanced.
    static func detectedExternalEngines() -> [ExternalEngineChoice] {
        var choices: [ExternalEngineChoice] = []
        if let crossOver = RumWineInstaller.defaultCrossOverEngine() {
            choices.append(.init(kind: .crossOver, name: crossOver.displayName, appURL: crossOver.appURL))
        }
        if let gptk = RumWineInstaller.defaultGamePortingToolkitEngine() {
            choices.append(.init(kind: .gamePortingToolkit, name: gptk.displayName, appURL: gptk.appURL))
        }
        return choices
    }
}
