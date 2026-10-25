//
//  LibraryStyle.swift
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

// MARK: - Colours

extension Color {
    /// Rum's amber, used for the Library's primary actions and selection. The app-wide accent is
    /// near-black to match the icon, which disappears on dark backgrounds.
    static let rum = Color(red: 0.96, green: 0.56, blue: 0.13)
}

extension ShapeStyle where Self == LinearGradient {
    static var rumGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 1.0, green: 0.68, blue: 0.24), Color(red: 0.90, green: 0.40, blue: 0.08)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var stopGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 1.0, green: 0.38, blue: 0.34), Color(red: 0.84, green: 0.16, blue: 0.16)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Buttons

/// The Library's main call to action (Play, Run Windows App…): amber, or red to stop.
struct RumProminentButtonStyle: ButtonStyle {
    enum Role {
        case play, stop
    }

    var role: Role = .play
    var fullWidth = false

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 32)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(role == .play ? AnyShapeStyle(.rumGradient) : AnyShapeStyle(.stopGradient))
                    .brightness(configuration.isPressed ? -0.08 : (isHovering ? 0.05 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: (role == .play ? Color.rum : .red).opacity(isEnabled ? 0.35 : 0), radius: 6, y: 2)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Round Play / Stop button shown over a card's artwork.
struct LibraryOverlayButtonStyle: ButtonStyle {
    var role: RumProminentButtonStyle.Role = .play

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(Circle().fill(role == .play ? AnyShapeStyle(.rumGradient) : AnyShapeStyle(.stopGradient)))
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .contentShape(Circle())
    }
}

// MARK: - Backgrounds

/// Behind-window translucency (the desktop shows through, blurred), like Finder and Music.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Grouped container matching System Settings' inset groups.
private struct LibraryGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
    }
}

extension View {
    func libraryGroup() -> some View {
        modifier(LibraryGroupModifier())
    }
}

// MARK: - Icons

/// Icons read from executables, shared by every view that shows them.
@MainActor
enum ExeIconCache {
    private static var icons: [URL: NSImage] = [:]
    private static var missing: Set<URL> = []

    static func cached(_ url: URL) -> NSImage? {
        icons[url]
    }

    /// Whether the executable is known to have no icon (or couldn't be read).
    static func isMissing(_ url: URL) -> Bool {
        missing.contains(url)
    }

    static func load(_ url: URL) async -> NSImage? {
        if let icon = icons[url] { return icon }
        if missing.contains(url) { return nil }
        // NSImage isn't Sendable; carry the pixels across instead.
        let data = await Task.detached(priority: .utility) {
            (try? PEFile(url: url))?.bestIcon()?.tiffRepresentation
        }.value
        guard let data, let icon = NSImage(data: data) else {
            missing.insert(url)
            return nil
        }
        icons[url] = icon
        return icon
    }
}

/// The icon embedded in a Windows executable. Executables without an icon get a tile with the
/// first letter of `fallbackName`.
struct ExeIconView: View {
    let url: URL
    let size: CGFloat
    var fallbackName: String?

    @State private var icon: NSImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let icon = icon ?? ExeIconCache.cached(url) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.3), radius: size > 40 ? 6 : 0, y: size > 40 ? 3 : 0)
            } else if didLoad || ExeIconCache.isMissing(url) {
                fallback
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            icon = await ExeIconCache.load(url)
            didLoad = true
        }
    }

    private var fallback: some View {
        let name = fallbackName ?? url.deletingPathExtension().lastPathComponent
        let letter = name.first.map { String($0).uppercased() } ?? "?"
        return RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color.gray.gradient)
            .overlay {
                Text(letter)
                    .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.15), radius: size > 40 ? 2 : 0, y: 1)
    }
}

/// The executable's icon blown up and blurred: a colourful backdrop for programs without artwork.
struct ExeIconBackdrop: View {
    let url: URL

    @State private var icon: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let icon = icon ?? ExeIconCache.cached(url) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.8)
                    .blur(radius: 30)
                    .saturation(1.5)
                    .opacity(0.85)
                    .transition(.opacity)
            }
            LinearGradient(colors: [.white.opacity(0.08), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .task(id: url) {
            icon = await ExeIconCache.load(url)
        }
    }
}

// MARK: - Search

/// The Library's search field, inline with the page controls so it never lands over the details
/// panel. ⌘F focuses it, Escape clears it.
struct LibrarySearchField: View {
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand {
                    text = ""
                    isFocused = false
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 26)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .overlay {
            Capsule().strokeBorder(isFocused ? Color.rum.opacity(0.8) : .white.opacity(0.08), lineWidth: 1)
        }
        .background {
            Button("Search") { isFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
