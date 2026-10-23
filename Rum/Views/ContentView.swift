//
//  ContentView.swift
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
import UniformTypeIdentifiers
import WhiskyKit

/// The main window: the Library. Bottles are managed from Settings / the Bottles window.
struct ContentView: View {
    @AppStorage("checkWhiskyWineUpdates") private var checkWhiskyWineUpdates = true
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

            if !WhiskyWineInstaller.isWhiskyWineInstalled() {
                showSetup = true
            }
            if checkWhiskyWineUpdates {
                let updateStatus = await WhiskyWineInstaller.shouldUpdateWhiskyWine()
                guard updateStatus.shouldUpdate else { return }
                let localVersion = WhiskyWineInstaller.installedWineVersion() ?? "unknown"
                let alert = NSAlert()
                alert.messageText = String(localized: "update.whiskywine.title")
                alert.informativeText = String(format: String(localized: "update.whiskywine.description"),
                                               localVersion,
                                               updateStatus.latestVersion)
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "update.whiskywine.update"))
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
