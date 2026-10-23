//
//  LibraryHome.swift
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
import WhiskyKit

/// Home: what's running (or starting), what gets played most, and what was played last.
struct LibraryHomePage<RunControls: View>: View {
    let running: [LibraryPinItem]
    let favourites: [LibraryPinItem]
    let recent: [LibraryPinItem]
    let selection: LibraryPinItem.ID?
    let showsBottleNames: Bool
    let actions: LibraryItemActions
    let onSelect: (LibraryPinItem) -> Void
    let onSeeAllRecent: () -> Void
    /// Run Windows App… and friends, at the end of the Running header like on the other pages.
    @ViewBuilder let runControls: () -> RunControls

    private static var spacing: CGFloat { 16 }
    /// Cards in the rows have a fixed size, so the rows never widen the page.
    private static var cardWidth: CGFloat { 170 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                runningSection
                if !favourites.isEmpty {
                    shelf("Most Played", items: favourites, showsPlayCount: true)
                }
                if !recent.isEmpty {
                    shelf("Recently Played", items: recent, onSeeAll: onSeeAllRecent)
                }
                if running.isEmpty && favourites.isEmpty && recent.isEmpty {
                    ContentUnavailableView("Nothing Played Yet", systemImage: "gamecontroller",
                                           description: Text("Games and apps you run show up here."))
                        .padding(.top, 40)
                }
            }
            .padding(EdgeInsets(top: 10, leading: LibrarySidebarMetrics.margin,
                                bottom: LibrarySidebarMetrics.margin, trailing: LibrarySidebarMetrics.margin))
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
                runControls()
            }
            if !running.isEmpty {
                row(running)
            }
        }
        .animation(.smooth(duration: 0.25), value: running.map(\.id))
    }

    private func shelf(_ title: LocalizedStringKey, items: [LibraryPinItem], showsPlayCount: Bool = false,
                       onSeeAll: (() -> Void)? = nil) -> some View {
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
            row(items, showsPlayCount: showsPlayCount)
        }
    }

    /// One row of cards that scrolls sideways when it doesn't fit, edge to edge across the page.
    private func row(_ items: [LibraryPinItem], showsPlayCount: Bool = false) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Self.spacing) {
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
                }
            }
            // Room for the cards' hover shadow and scale, which the scroll view would clip.
            .padding(.vertical, 8)
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
