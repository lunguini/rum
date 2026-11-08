//
//  ContentView.swift
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
import UniformTypeIdentifiers
import RumKit

/// The main window: the Library. Bottles are managed from Settings / the Bottles window.
struct ContentView: View {
    @AppStorage("checkRumWineUpdates") private var checkRumWineUpdates = true
    @AppStorage(BottleVM.defaultBottleKey) private var defaultBottleURL: URL?
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool

    @State private var bottlesLoaded: Bool = false
    @State private var openedFileURL: URL?

    var body: some View {
        Group {
            if bottlesLoaded {
                LibraryView()
            }
        }
        .sheet(isPresented: $showSetup) {
            SetupView(showSetup: $showSetup, firstTime: false)
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: bottleVM.defaultBottle(preferredURL: defaultBottleURL)?.url,
                         bottles: bottleVM.bottles)
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            bottleVM.loadBottles()
            bottlesLoaded = true

            if !RumWineInstaller.isRumWineInstalled() {
                showSetup = true
            }
            if checkRumWineUpdates {
                let updateStatus = await RumWineInstaller.shouldUpdateRumWine()
                guard updateStatus.shouldUpdate else { return }
                let localVersion = RumWineInstaller.installedWineVersion() ?? "unknown"
                let alert = NSAlert()
                alert.messageText = String(localized: "update.rumwine.title")
                alert.informativeText = String(format: String(localized: "update.rumwine.description"),
                                               localVersion,
                                               updateStatus.latestVersion)
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "update.rumwine.update"))
                alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    showSetup = true
                }
            }
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}
