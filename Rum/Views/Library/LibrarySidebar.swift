//
//  LibrarySidebar.swift
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

enum LibrarySidebarMetrics {
    static let width: CGFloat = 220
    /// Wide enough for the window's traffic lights, with room to spare.
    static let compactWidth: CGFloat = 96
    /// Space between a column's edges and its content.
    static let margin: CGFloat = 16
    /// Height of the top row: window controls in the sidebar, each page's title bar beside them.
    static let topBarHeight: CGFloat = 44
}

/// The Library's pages, plus Bottles and Settings at the bottom. Collapsed, it keeps just the icons.
struct LibrarySidebar: View {
    @Binding var page: LibraryPage?
    let isCompact: Bool
    let libraryCount: Int
    let recentCount: Int
    let foundCount: Int
    let runningCount: Int
    let window: NSWindow?

    @Environment(\.openURL) private var openURL

    var body: some View {
        List(selection: $page) {
            Section {
                row("Home", icon: "house", count: runningCount)
                    .tag(LibraryPage.home)
                row("Games & Apps", icon: "square.grid.2x2", count: libraryCount)
                    .tag(LibraryPage.library)
                row("Recently Played", icon: "clock", count: recentCount)
                    .tag(LibraryPage.recent)
                if foundCount > 0 {
                    row("Found in Bottles", icon: "sparkle.magnifyingglass", count: foundCount)
                        .tag(LibraryPage.found)
                }
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, 8, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .environment(\.sidebarRowSize, .large)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    WindowControls(window: window)
                    Spacer(minLength: 0)
                }
                .padding(.leading, LibrarySidebarMetrics.margin)
                .frame(height: LibrarySidebarMetrics.topBarHeight)
                .background(WindowDragArea())
                logo
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
    }

    private var logo: some View {
        let size: CGFloat = isCompact ? 44 : 72
        return Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func row(_ title: LocalizedStringKey, icon: String, count: Int) -> some View {
        if isCompact {
            Image(systemName: icon)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 28)
                .help(title)
                .accessibilityLabel(title)
        } else {
            Label(title, systemImage: icon)
                .badge(count)
        }
    }

    private var footer: some View {
        VStack(alignment: isCompact ? .center : .leading, spacing: 4) {
            Button {
                if let url = URL(string: "https://github.com/adrianlungu/rum") {
                    openURL(url)
                }
            } label: {
                footerLabel("GitHub") {
                    // GitHub's mark (Octicons mark-github), sized to match the symbols beside it.
                    Image("GitHubMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: isCompact ? 18 : 15, height: isCompact ? 18 : 15)
                }
            }
            .buttonStyle(LibrarySidebarFooterButtonStyle(isSelected: false))
            .help("Open Rum on GitHub")
            footerButton("Settings", icon: "gearshape", page: .settings)
                .help("Settings, bottles and Wine engines")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }

    private func footerButton(_ title: LocalizedStringKey, icon: String, page target: LibraryPage) -> some View {
        Button {
            page = target
        } label: {
            footerLabel(title, icon: icon)
        }
        .buttonStyle(LibrarySidebarFooterButtonStyle(isSelected: page == target))
    }

    private func footerLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        footerLabel(title) {
            Image(systemName: icon)
                .font(isCompact ? .title3 : .body)
        }
    }

    private func footerLabel<Icon: View>(_ title: LocalizedStringKey, @ViewBuilder icon: () -> Icon) -> some View {
        let icon = icon()
        return Group {
            if isCompact {
                icon
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(title)
            } else {
                Label {
                    Text(title)
                } icon: {
                    icon
                        .frame(width: 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
}

/// Plain sidebar-style button that highlights on hover, and stays highlighted while its page is open.
private struct LibrarySidebarFooterButtonStyle: ButtonStyle {
    let isSelected: Bool

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(isSelected || isHovering ? .primary : .secondary)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(fillOpacity(isPressed: configuration.isPressed)))
            )
            .onHover { isHovering = $0 }
    }

    private func fillOpacity(isPressed: Bool) -> Double {
        if isPressed { return 0.14 }
        if isSelected { return 0.1 }
        return isHovering ? 0.06 : 0
    }
}

/// Lets menu commands and other pages switch the main window's page (Settings, a bottle, …).
@MainActor
final class LibraryNavigator: ObservableObject {
    static let shared = LibraryNavigator()

    struct Request: Equatable {
        let id = UUID()
        let page: LibraryPage
        let bottleURL: URL?
    }

    /// The latest request, until the main window takes it.
    @Published var request: Request?

    func show(_ page: LibraryPage, bottle bottleURL: URL? = nil) {
        request = Request(page: page, bottleURL: bottleURL)
    }
}

/// The bar at the top of each Library page: sidebar toggle and title on the left, search and the
/// details toggle on the right. Part of the page, so it follows both side panels on its own.
struct LibraryTitleBar: View {
    let title: LocalizedStringKey
    @Binding var searchText: String
    let showsSearch: Bool
    let isSidebarCompact: Bool
    let showsDetailsToggle: Bool
    let isDetailsShown: Bool
    let onToggleSidebar: () -> Void
    let onToggleDetails: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleSidebar) {
                Label("Sidebar", systemImage: "sidebar.leading")
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .help(isSidebarCompact ? "Expand Sidebar (⌃⌘S)" : "Collapse Sidebar (⌃⌘S)")
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 12)
            if showsSearch {
                LibrarySearchField(text: $searchText)
            }
            if showsDetailsToggle {
                Button(action: onToggleDetails) {
                    Label("Details", systemImage: "sidebar.trailing")
                }
                .help(isDetailsShown ? "Hide Details" : "Show Details")
            }
        }
        .buttonStyle(LibraryTitleBarButtonStyle())
        .labelStyle(.iconOnly)
        // The buttons' glyphs, not their hover backgrounds, line up with the page margin.
        .padding(.horizontal, LibrarySidebarMetrics.margin - 8)
        .frame(height: LibrarySidebarMetrics.topBarHeight)
        .background(WindowDragArea())
    }
}

/// Toolbar-like icon button for the title bar.
private struct LibraryTitleBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.primary.opacity(configuration.isPressed ? 0.14 : (isHovering ? 0.08 : 0)))
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}
