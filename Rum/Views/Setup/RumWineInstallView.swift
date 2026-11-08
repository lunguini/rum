//
//  RumWineInstallView.swift
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

import SwiftUI
import RumKit

struct RumWineInstallView: View {
    @State var installing: Bool = true
    @State private var installFailed: Bool = false
    @Binding var tarLocation: URL
    @Binding var wineVersion: String
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack {
            VStack {
                Text("setup.rumwine.install")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.rumwine.install.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if installFailed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Failed to install Wine.")
                            .font(.subheadline)
                    }
                } else if installing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 80)
                } else {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            let tarball = tarLocation
            let version = wineVersion
            Task {
                do {
                    try await RumWineInstaller.install(from: tarball, version: version, activate: true)
                    installing = false
                    try? await Task.sleep(for: .seconds(2))
                    proceed()
                } catch {
                    installing = false
                    installFailed = true
                }
            }
        }
    }

    /// Back to the overview, which re-checks everything and offers the optional runtimes.
    func proceed() {
        path.removeAll()
    }
}
