//
//  DXVKInstallView.swift
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

import SwiftUI
import WhiskyKit

struct DXVKInstallView: View {
    @AppStorage("skipDXVKSetup") private var skipDXVKSetup = false
    @State private var failureMessage: String?
    @State var installing: Bool = true
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack {
            VStack {
                Text("Installing DXVK")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Setting up DirectX translation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let failureMessage {
                    Text("Failed to install DXVK: \(failureMessage)")
                        .foregroundStyle(.red)
                    Button("Back to Setup") {
                        path.removeAll()
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
            let location = tarLocation
            Task {
                do {
                    try await WhiskyWineInstaller.installDXVK(from: location)
                    installing = false
                    skipDXVKSetup = false
                    try? await Task.sleep(for: .seconds(2))
                    proceed()
                } catch {
                    installing = false
                    failureMessage = (error as? String) ?? error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func proceed() {
        showSetup = false
    }
}
