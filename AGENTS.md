# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

PasteDeck is a native macOS clipboard manager that records clipboard history and provides quick access via a global keyboard shortcut (⌘+Shift+V). Built with SwiftUI and SwiftData for macOS 14.0+.

## Build & Run

```bash
# Build from terminal when a narrow validation is enough
swift build
```

This repository is Swift Package Manager based; there is no checked-in `.xcodeproj`. Open `Package.swift` in Xcode only when an interactive app run is explicitly needed, then run with ⌘+R and the local Mac run destination.

## DMG Packaging

- Do not run `scripts/build-dmg.sh`, `hdiutil attach`, or `open *.dmg` during routine investigation, validation, or bugfix work.
- The DMG build script uses Finder/AppleScript to apply installer window layout, so it intentionally opens the mounted DMG folder and can leave temporary disk images mounted if interrupted.
- Only run DMG packaging when the user explicitly asks for a release installer, and verify afterward that no PasteDeck DMG images remain mounted.

## Development Principles

- Bug fixes must be normal, maintainable fixes: identify the root cause, keep responsibilities separated, and avoid workaround-style code that piles timers, duplicated state changes, or unrelated logic into existing paths.
- Prefer small semantic helpers over scattered inline patches when a fix touches repeated behavior, especially for SwiftUI/AppKit focus, selection, paste, and lifecycle interactions.
- Performance is the default priority for all development bugfixes. Avoid unnecessary recomputation, repeated disk I/O, repeated image decoding, broad SwiftData fetches, excessive view invalidation, and avoid animation or async work that can make keyboard navigation, panel opening, search, or paste feel sluggish.
- Validate fixes with the narrowest useful build or test command, and call out any remaining manual QA needed for macOS UI behavior.

## Versioning

- Every feature or bugfix change must bump the app version in the same change set.
- Follow SemVer: bugfixes bump patch, new backward-compatible features bump minor, and breaking changes bump major.
- Keep the app metadata in sync with the release version, including `CFBundleShortVersionString` and `CFBundleVersion` in `PasteDeck/PasteDeck/Info.plist`.
- Increment `CFBundleVersion` monotonically for every version bump, even when only `CFBundleShortVersionString` changes.
- Do not create a Git tag or GitHub release unless the user explicitly asks for a release.

## Architecture

### Entry Point
- `PasteDeck/PasteDeck/App/PasteDeckApp.swift` - SwiftUI App entry with `@main` attribute
- `AppDelegate` - Handles lifecycle, status bar, clipboard monitoring, and hotkey registration
- `AppModelContainer` - Singleton SwiftData ModelContainer for `ClipboardItem`, `AppSettings`, and `FavoriteCollection`

### Data Layer (SwiftData)
- `Models/ClipboardItem.swift` - `@Model` class for clipboard history entries
- `Models/ClipboardContentType.swift` - Enum: text, link, markdown, json, image, file, color
- `Models/AppSettings.swift` - User preferences storage
- `Models/FavoriteCollection.swift` - Favorite collection storage and default favorite grouping

### Services
- `Services/ClipboardMonitor.swift` - Polls NSPasteboard (0.5s interval), detects content type, saves to SwiftData, handles deduplication, and schedules OCR for images
- `Services/ClipboardHistoryStore.swift` - Main-panel data loading, filtering, selection mutations, and batch paste orchestration
- `Services/HotKeyManager.swift` - Global hotkey via Carbon `RegisterEventHotKey` (requires Accessibility permission)
- `Services/CacheManager.swift` - Manages image cache at `~/Library/Caches/PasteDeck/`
- `Services/PasteService.swift` - Writes selected content to NSPasteboard and simulates paste with CGEvent
- `Services/ImageOCRService.swift` - Runs Vision OCR for copied images and persists searchable text
- `Services/TranslateService.swift` - Baidu Translate integration used by the preview window
- `Services/PreviewConfig.swift` - Preview sizing and mode preferences

### UI Layer
- `Views/MainWindow/MainPanelController.swift` - NSPanel controller for floating window (centered, popUpMenu level, vibrancy effect)
- `Views/MainWindow/MainPanelView.swift` - Main SwiftUI view with search, favorite filters, virtualized horizontal cards, and keyboard handling
- `Views/MainWindow/SearchBarView.swift` - Search field component
- `Views/MainWindow/ClipCardView.swift` - Individual clipboard item card
- `Views/Preview/PreviewWindow.swift` - Large preview window (triggered by Space key)
- `Views/Preview/CodeHighlightView.swift` - Editable code preview and syntax highlighting
- `Views/Preview/MarkdownRenderedText.swift` - Markdown rendering support
- `Views/Settings/SettingsWindow.swift` - Settings tabs (General, Hotkey, History, Filter, Favorites, Appearance, Advanced)

### Key Data Flow
1. User copies content -> `ClipboardMonitor` detects change via `changeCount`
2. Content parsed based on NSPasteboard types (fileURL -> file, tiff/png -> image, string -> link/json/markdown/text, color -> color)
3. Images saved to cache directory, other content stored directly in SwiftData
4. Image items are sent to `ImageOCRService` so OCR text can participate in search
5. User presses the configured hotkey -> `HotKeyManager` triggers -> `MainPanelController.togglePanel()`
6. User selects item -> `PasteService` writes to pasteboard and simulates ⌘+V

## Permissions

The app requires **Accessibility permission** for:
- Global hotkey registration and handling via Carbon
- Simulated paste events via CGEvent

Clipboard polling uses NSPasteboard. `HotKeyManager` prompts for Accessibility permission with `AXIsProcessTrustedWithOptions`, and `SettingsWindow` displays current permission status with a shortcut to System Settings.

## Content Type Detection

`ClipboardMonitor.parsePasteboard()` checks types in priority order:
1. `.fileURL` -> file reference (checked before images because Finder copies can include icon image data)
2. `.tiff` or `.png` -> image (saved to cache)
3. `.string` -> link, json, markdown, or text; RTF data is preserved for rich text paste when present
4. `.color` -> NSColor converted to hex

## Cache Location

Images are cached at: `~/Library/Caches/PasteDeck/images/`

Cache size limit is configurable in settings (default 500MB, options: 100MB/500MB/1GB/unlimited).
