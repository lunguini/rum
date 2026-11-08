//
//  LibraryHome.swift
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

import OSLog
import SwiftUI
import RumKit

/// Home: what's running (or starting), what gets played most, what was played last, and what was
/// just added.
struct LibraryHomePage: View {
    let running: [LibraryPinItem]
    let added: [LibraryPinItem]
    let favourites: [LibraryPinItem]
    let recent: [LibraryPinItem]
    let selection: LibraryPinItem.ID?
    let showsBottleNames: Bool
    let actions: LibraryItemActions
    let onSelect: (LibraryPinItem) -> Void
    let onSeeAllRecent: () -> Void
    let onSeeAllAdded: () -> Void
    /// Set when something is added, to scroll it into view in Recently Added.
    var reveal: LibraryReveal?

    private static var spacing: CGFloat { 16 }
    /// Cards in the rows have a fixed size, so the rows never widen the page.
    private static var cardWidth: CGFloat { 170 }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                runningSection
                if !favourites.isEmpty {
                    shelf("Most Played", items: favourites, showsPlayCount: true)
                }
                if !recent.isEmpty {
                    shelf("Recently Played", items: recent, onSeeAll: onSeeAllRecent)
                }
                if !added.isEmpty {
                    shelf("Recently Added", items: added, reveal: reveal, onSeeAll: onSeeAllAdded)
                        .id(Self.addedShelfID)
                }
            }
            .padding(EdgeInsets(top: 10, leading: LibrarySidebarMetrics.margin,
                                bottom: LibrarySidebarMetrics.margin, trailing: LibrarySidebarMetrics.margin))
        }
        // The page scrolls to the shelf here, and the shelf scrolls to the card in `row`. One
        // proxy can't reliably drive both. A new shelf or card only exists after this update, so
        // wait for it to be laid out first.
        .task(id: reveal) {
            guard reveal != nil else { return }
            try? await Task.sleep(for: .milliseconds(150))
            Logger.wineKit.debug("Reveal: scrolling Home to Recently Added")
            withAnimation { proxy.scrollTo(Self.addedShelfID, anchor: .bottom) }
        }
        }
        // Centred in the whole page, not just below the Running header, at any window size.
        .overlay {
            if running.isEmpty && added.isEmpty && favourites.isEmpty && recent.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("Nothing Played Yet")
                    } icon: {
                        Image("RumLogo") // 96pt, pre-rendered per screen scale
                            .renderingMode(.original)
                    }
                } description: {
                    Text("Games and apps you run show up here.")
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Sections

    /// Collapsed to its header while nothing runs; every running program otherwise.
    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Running")
                    .font(.title3.weight(.semibold))
                Text("\(running.count)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(running.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(running.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.green),
                                in: Capsule())
                if running.isEmpty {
                    Text("Nothing running")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                Spacer()
            }
            if !running.isEmpty {
                row(running)
            }
        }
        .animation(.smooth(duration: 0.25), value: running.map(\.id))
    }

    private static let addedShelfID = "recentlyAddedShelf"

    private func shelf(_ title: LocalizedStringKey, items: [LibraryPinItem], showsPlayCount: Bool = false,
                       reveal: LibraryReveal? = nil, onSeeAll: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                if let onSeeAll {
                    Button("See All", action: onSeeAll)
                        .buttonStyle(.link)
                }
            }
            row(items, showsPlayCount: showsPlayCount, reveal: reveal)
        }
    }

    /// One row of cards that scrolls sideways when it doesn't fit, edge to edge across the page.
    /// Shelves hold at most a dozen cards, so a plain HStack keeps every card around to scroll to.
    private func row(_ items: [LibraryPinItem], showsPlayCount: Bool = false,
                     reveal: LibraryReveal? = nil) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Self.spacing) {
                ForEach(items) { item in
                    LibraryCard(bottle: item.bottle,
                                item: item,
                                isSelected: selection == item.id,
                                showsBottle: showsBottleNames,
                                actions: actions,
                                showsPlayCount: showsPlayCount) {
                        onSelect(item)
                    }
                    .frame(width: Self.cardWidth)
                    .id(item.id)
                }
            }
            // Room for the cards' hover shadow and scale, which the scroll view would clip.
            .padding(.vertical, 8)
        }
        .task(id: reveal) {
            guard let reveal else { return }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(reveal.itemID, anchor: .center) }
        }
        }
        .scrollIndicators(.automatic)
        .contentMargins(.horizontal, LibrarySidebarMetrics.margin, for: .scrollContent)
        .padding(.horizontal, -LibrarySidebarMetrics.margin)
        .padding(.vertical, -8)
    }
}

/// Shown away from Home while something is being started, so a launch never goes unnoticed.
struct LibraryLaunchToast: View {
    let names: [String]

    var body: some View {
        if let first = names.first {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(names.count == 1 ? "Starting \(first)…" : "Starting \(names.count) programs…")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
