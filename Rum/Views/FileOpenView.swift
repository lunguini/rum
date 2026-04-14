//
//  FileOpenView.swift
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

struct FileOpenView: View {
    var fileURL: URL
    var currentBottle: URL?
    var bottles: [Bottle]

    @State private var selection: URL = URL(filePath: "")
    @State private var isLaunching = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLaunching {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("program.launching \(fileURL.lastPathComponent)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
                Form {
                    Picker("run.bottle", selection: $selection) {
                        ForEach(bottles, id: \.self) {
                            Text($0.settings.name)
                                .tag($0.url)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .formStyle(.grouped)
            }
            .navigationTitle(String(format: String(localized: "run.title"), fileURL.lastPathComponent))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isLaunching)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("button.run") {
                        run()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLaunching)
                }
            }
        }
        .animation(.whiskyDefault, value: isLaunching)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
        .onAppear {
            if bottles.count <= 0 {
                dismiss()
                return
            }

            selection = bottles.first(where: { $0.url == currentBottle })?.url ?? bottles[0].url

            if bottles.count == 1 {
                run()
            }
        }
    }

    func run() {
        if let bottle = bottles.first(where: { $0.url == selection }) {
            isLaunching = true
            Task.detached(priority: .userInitiated) {
                do {
                    if fileURL.pathExtension == "bat" {
                        try await Wine.runBatchFile(url: fileURL, bottle: bottle)
                    } else {
                        try await Wine.runProgram(at: fileURL, bottle: bottle,
                                                  onStarted: {
                            Task { @MainActor in dismiss() }
                        })
                    }
                } catch {
                    print(error)
                }
                Task { @MainActor in
                    isLaunching = false
                    dismiss()
                }
            }
        }
    }
}
