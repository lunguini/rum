//
//  LibraryArtwork.swift
//  Rum
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

/// A program's artwork filling its frame, or its icon on a neutral backdrop when there is none.
struct ArtworkView: View {
    enum Style {
        /// Portrait cover for Library cards.
        case cover
        /// Wide banner for the details panel.
        case banner
    }

    let url: URL
    let name: String
    let style: Style

    @ObservedObject private var store = ArtworkStore.shared

    var body: some View {
        let artwork = store.artwork[url]
        let image = style == .cover
            ? artwork?.cover ?? artwork?.header
            : artwork?.header ?? artwork?.cover
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                fallback
            }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: url) {
            await store.load(for: url, name: name)
        }
    }

    private var fallback: some View {
        ZStack {
            ExeIconBackdrop(url: url)
            ExeIconView(url: url, size: style == .cover ? 72 : 64, fallbackName: name)
        }
    }
}

/// Pick the right Steam game, or any image, for a program whose artwork is missing or wrong.
struct ArtworkPickerSheet: View {
    let item: LibraryPinItem

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ArtworkStore.shared
    @State private var term = ""
    @State private var results: [SteamStoreItem] = []
    @State private var isSearching = false
    @State private var searchFailed = false
    @State private var applyingID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artwork for “\(item.pin.name)”")
                .font(.headline)
            HStack {
                TextField("Search Steam", text: $term)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                Button("Search") { Task { await search() } }
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            resultsList
                .frame(height: 260)
            HStack {
                Button("Choose Image…", action: chooseImage)
                Button("Use Icon") {
                    store.removeArtwork(for: item.url)
                    dismiss()
                }
                Spacer()
                Button("button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task {
            term = item.pin.name
            await search()
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            Text(searchFailed ? "Couldn’t reach Steam." : "No Steam games found.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(results) { result in
                Button {
                    Task { await apply(result) }
                } label: {
                    HStack(spacing: 10) {
                        AsyncImage(url: result.tinyImage) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                        .frame(width: 92, height: 35)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text(result.name)
                            .lineLimit(1)
                        Spacer()
                        if applyingID == result.id {
                            ProgressView().controlSize(.small)
                        } else if store.steamAppID(for: item.url) == result.id {
                            Image(systemName: "checkmark").foregroundStyle(Color.rum)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(applyingID != nil)
            }
            .listStyle(.bordered)
        }
    }

    private func search() async {
        let query = term.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await SteamStore.search(query).filter { $0.type == "app" }
            searchFailed = false
        } catch {
            results = []
            searchFailed = true
        }
    }

    private func apply(_ result: SteamStoreItem) async {
        applyingID = result.id
        let didApply = await store.useSteamApp(result.id, for: item.url)
        applyingID = nil
        if didApply { dismiss() }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a cover image. Portrait images (2:3) look best."
        panel.begin { response in
            guard response == .OK, let imageURL = panel.url else { return }
            Task { @MainActor in
                if store.useImage(at: imageURL, for: item.url) { dismiss() }
            }
        }
    }
}
