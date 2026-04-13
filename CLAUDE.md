# Rum

Wine wrapper for running Windows apps on macOS, built with SwiftUI. Forked from Whisky.

## Build & Lint

```bash
# Lint (must pass before tagging a release)
swiftlint --strict

# Build (requires Xcode, macOS only)
xcodebuild archive -scheme Whisky -configuration Release
```

**Important:** SwiftLint must be installed for the Xcode build to succeed — the Rum target has a SwiftLint build phase (`Script-6E50D98129CD0EAF008C39F6`) that runs during every build. Do not remove `brew install swiftlint` from the Release workflow.

## Release Checklist

1. Run `swiftlint --strict` locally and fix any issues
2. Verify the project builds in Xcode
3. Update version numbers as needed
4. Commit, tag with `vX.Y.Z`, and push — the Release workflow handles the rest:
   - Builds and archives the app
   - Creates the GitHub release with auto-generated notes
   - Updates the Homebrew cask in `lunguini/homebrew-tap`

## Project Structure

- **Rum/** — Main SwiftUI app (scheme: `Whisky`)
- **WhiskyKit/** — Swift package with Wine/bottle management logic
- **RumCmd/** — CLI tool
- **RumThumbnail/** — QuickLook thumbnail extension for .exe files
