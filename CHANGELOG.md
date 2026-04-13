# Changelog

## 1.0.3

### Fixes

- Fixed `.exe` files not appearing in Finder's "Open With" menu — added UTImportedTypeDeclarations for `com.microsoft.windows-executable`
- Fixed SwiftLint violations in Process+Extensions.swift
- Fixed SwiftLint config not excluding `WhiskyKit/.build/` dependency checkouts
- Updated default Wine version for new bottles to 11.6.0
- Removed standalone SwiftLint workflow — already runs as an Xcode build phase
- Restored SwiftLint install in release workflow (required by Xcode build phase)
- Fixed app version not matching git tag — release workflow now injects version from tag
- Added `contents: write` permission to release workflow for GitHub release creation

## 1.0.2

### Fixes

- Fixed high CPU usage (99% single core) after launching a Wine application via the Run button
- Fixed ad-hoc code signing in release workflow so macOS doesn't treat exported app as damaged
- Automated Homebrew cask updates in the release workflow — tap moved to `lunguini/tap`

## 1.0.1

### Fixes

- Fixed Sparkle update checker compatibility with Swift 6 concurrency
- Fixed `@Sendable` closure warning on program launch callback
- Fixed Sparkle dependency pinned to unstable branch — now uses stable 2.x releases
- Fixed SemanticVersion dependency using SSH URL that fails in CI — switched to HTTPS
- Fixed missing local package references for WhiskyKit in Xcode project
- Renamed product names to Rum/RumCmd/RumThumbnail so the built app is `Rum.app`
- Updated CLI install path to `/usr/local/bin/rum`
- Updated bundled CLI resource reference from `WhiskyCmd` to `RumCmd`

## 1.0.0

First release of Rum, forked from [Whisky](https://github.com/Whisky-App/Whisky) v2.3.5.

### Wine Engine

- Replaced CrossOver 22.1.1 / Game Porting Toolkit (GPTK) Wine build with [Gcenx's Wine Staging](https://github.com/Gcenx/macOS_Wine_builds) 11.x
- Wine is now downloaded directly from Gcenx's GitHub releases, preferring Wine Staging with fallback to Wine Devel
- Supports Wine 11+ unified `wine` binary (no longer requires separate `wine64`)
- Version checking uses GitHub API instead of the old plist-based system

### DXVK

- Added automatic [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) download and installation during setup
- DXVK is now enabled by default on new bottles for DirectX 9/10/11 compatibility
- Setup flow checks for DXVK alongside Rosetta and Wine, with dedicated download and install steps

### Run Button

- The Run button now allows launching multiple programs concurrently
- Button shows a loading spinner only while a program is starting, not for its entire runtime
- Once a program has started, the Run button becomes available again immediately

### Rebranding

- Renamed from Whisky to Rum across all user-facing strings, menus, and localized text (30+ languages)
- Updated bundle identifier to `com.adrianlungu.rum`
- Updated all GitHub and website URLs to point to `github.com/adrianlungu/rum`

### macOS Tahoe Compatibility

- Fixed deprecated `.foregroundColor()` calls → `.foregroundStyle()`
- Fixed deprecated `withAnimation(_:body:completion:)` closure pattern
- Fixed `@State` used with class type → `@ObservedObject` with `ObservableObject` conformance
- Removed dead `#available(macOS 10.15)` check (minimum target is macOS 14)
- Fixed `@Published` properties being modified from background threads in bottle creation

### Target

- macOS Tahoe (26.0) or later
- Apple Silicon (M-series) only
