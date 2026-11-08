// swift-tools-version: 5.9
//
//  PortableExecutable.swift
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

import PackageDescription

let package = Package(
    name: "RumKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RumKit",
            targets: ["RumKit"]
        )
    ],
    dependencies: [
      .package(url: "https://github.com/SwiftPackageIndex/SemanticVersion.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "RumKit",
            dependencies: ["SemanticVersion"]
        ),
        .testTarget(
            name: "RumKitTests",
            dependencies: ["RumKit"]
        )
    ],
    swiftLanguageVersions: [.version("6")]
)
