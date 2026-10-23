//
//  LibraryWindowChrome.swift
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

/// Hides the window's title bar, traffic lights included. Even when hidden by the window style it
/// keeps the clicks in its strip, so the Library couldn't put controls at the top of the window.
/// `WindowControls` stands in for the traffic lights.
struct HiddenSystemTitleBar: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let found = view?.window else { return }
            Self.hideTitleBar(of: found)
            window = found
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            Self.hideTitleBar(of: window)
        }
    }

    @MainActor
    private static func hideTitleBar(of window: NSWindow) {
        // The traffic lights' superview is the title bar, and its superview the container that
        // takes the clicks.
        window.standardWindowButton(.closeButton)?.superview?.superview?.isHidden = true
    }
}

/// Close, minimise and full-screen buttons, drawn like the system's traffic lights.
struct WindowControls: View {
    let window: NSWindow?

    @Environment(\.controlActiveState) private var activeState
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            control(Color(red: 1.0, green: 0.37, blue: 0.34), symbol: "xmark", help: "Close") {
                window?.performClose(nil)
            }
            control(Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus", help: "Minimize") {
                window?.miniaturize(nil)
            }
            control(Color(red: 0.16, green: 0.78, blue: 0.25),
                    symbol: "arrow.up.left.and.arrow.down.right", help: "Enter Full Screen") {
                window?.toggleFullScreen(nil)
            }
        }
        .onHover { isHovering = $0 }
    }

    private func control(_ color: Color, symbol: String, help: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(activeState == .inactive && !isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(color))
                .overlay {
                    Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
                }
                .overlay {
                    if isHovering {
                        Image(systemName: symbol)
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Empty space that drags the window, now that it has no title bar to drag by. A SwiftUI gesture,
/// so controls drawn on top still get their clicks.
struct WindowDragArea: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        } else {
            Color.clear
        }
    }
}
