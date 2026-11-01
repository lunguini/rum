//
//  PortableExecutable+Magic.swift
//  RumKit
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

extension PEFile {
    public enum Magic: UInt16, Hashable, Equatable, CustomStringConvertible, Sendable {
        case unknown = 0x0
        case pe32 = 0x10b
        case pe32Plus = 0x20b

        // MARK: - CustomStringConvertible

        public var description: String {
            switch self {
            case .unknown:
                return "unknown"
            case .pe32:
                return "PE32"
            case .pe32Plus:
                return "PE32+"
            }
        }
    }
}
