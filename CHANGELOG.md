# Changelog

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
