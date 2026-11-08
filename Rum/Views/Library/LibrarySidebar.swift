//
//  LibrarySidebar.swift
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

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            // Room for the system's traffic lights, which stay where macOS puts them.
            WindowDragArea()
                .frame(height: LibrarySidebarMetrics.topBarHeight)
            logo
            ScrollView {
                VStack(alignment: isCompact ? .center : .leading, spacing: 2) {
                    pageButton("Home", icon: "house", page: .home, count: runningCount)
                    pageButton("Games & Apps", icon: "square.grid.2x2", page: .library, count: libraryCount)
                    pageButton("Recently Played", icon: "clock", page: .recent, count: recentCount)
                    if foundCount > 0 {
                        pageButton("Found in Bottles", icon: "sparkle.magnifyingglass", page: .found,
                                   count: foundCount)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)
            footer
        }
        .background(LibrarySidebarTint().ignoresSafeArea())
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
    }

    /// The logo with the name beside it, like a native app's sidebar header. Collapsed, the
    /// sidebar is too narrow for the name, so it shows the logo alone.
    private var logo: some View {
        HStack(spacing: 8) {
            // Pre-rendered at exactly these sizes for each screen scale, so it is never resampled.
            Image(isCompact ? "RumLogoCompact" : "RumLogoSidebar")
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            if !isCompact {
                Text(verbatim: "Rum")
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, isCompact ? 0 : LibrarySidebarMetrics.margin)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rum")
    }

    private func pageButton(_ title: LocalizedStringKey, icon: String, page target: LibraryPage,
                            count: Int) -> some View {
        Button {
            page = target
        } label: {
            HStack(spacing: 0) {
                footerLabel(title, icon: icon)
                if !isCompact && count > 0 {
                    Text("\(count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(LibrarySidebarFooterButtonStyle(isSelected: page == target))
        .help(isCompact ? Text(title) : Text(verbatim: ""))
    }

    private var footer: some View {
        VStack(alignment: isCompact ? .center : .leading, spacing: 4) {
            Button {
                if let url = URL(string: "https://github.com/lunguini/rum") {
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

/// The logo's colours washed over the sidebar's vibrant material: amber at the top, through pink,
/// to violet at the bottom. Kept faint so text and the system material still read as native.
private struct LibrarySidebarTint: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 1.0 : 0.6
        LinearGradient(
            stops: [
                .init(color: Color(red: 1.0, green: 0.66, blue: 0.16).opacity(0.22 * strength), location: 0),
                .init(color: Color(red: 0.98, green: 0.30, blue: 0.45).opacity(0.12 * strength), location: 0.5),
                .init(color: Color(red: 0.45, green: 0.20, blue: 1.0).opacity(0.20 * strength), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
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
                    .fill(isSelected
                          ? AnyShapeStyle(Color.rum.opacity(configuration.isPressed ? 0.34 : 0.24))
                          : AnyShapeStyle(.primary.opacity(fillOpacity(isPressed: configuration.isPressed))))
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
struct LibraryTitleBar<Accessory: View>: View {
    let title: LocalizedStringKey
    @Binding var searchText: String
    let showsSearch: Bool
    let isSidebarCompact: Bool
    let showsDetailsToggle: Bool
    let isDetailsShown: Bool
    let onToggleSidebar: () -> Void
    let onToggleDetails: () -> Void
    /// Page actions such as Run Windows App…, just before the search field.
    @ViewBuilder let accessory: () -> Accessory

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
            accessory()
                .buttonStyle(.automatic)
                .labelStyle(.titleAndIcon)
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
