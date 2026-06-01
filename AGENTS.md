# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

PasteDeck is a native macOS clipboard manager that records clipboard history and provides quick access via a global keyboard shortcut (⌘+Shift+V). Built with SwiftUI and SwiftData for macOS 14.0+.

## Build & Run

```bash
# Open in Xcode
open Package.swift

# Or open the Xcode project directly
open PasteDeck/PasteDeck.xcodeproj
```

Build and run with ⌘+R in Xcode. Select "Mac (My Mac)" as the run target.

## Architecture

### Entry Point
- `PasteDeck/PasteDeck/App/PasteDeckApp.swift` - SwiftUI App entry with `@main` attribute
- `AppDelegate` - Handles lifecycle, status bar, clipboard monitoring, and hotkey registration
- `AppModelContainer` - Singleton SwiftData ModelContainer for `ClipboardItem` and `AppSettings`

### Data Layer (SwiftData)
- `Models/ClipboardItem.swift` - `@Model` class for clipboard history entries
- `Models/ClipboardContentType.swift` - Enum: text, link, image, file, color
- `Models/AppSettings.swift` - User preferences storage

### Services
- `Services/ClipboardMonitor.swift` - Polls NSPasteboard (0.5s interval), detects content type, saves to SwiftData, handles deduplication
- `Services/HotKeyManager.swift` - Global hotkey via NSEvent.addGlobalMonitorForEvents (requires Accessibility permission)
- `Services/CacheManager.swift` - Manages image cache at `~/Library/Caches/PasteDeck/`
- `Services/PasteService.swift` - Handles pasting content to active application

### UI Layer
- `Views/MainWindow/MainPanelController.swift` - NSPanel controller for floating window (centered, popUpMenu level, vibrancy effect)
- `Views/MainWindow/MainPanelView.swift` - Main SwiftUI view with search bar and card list
- `Views/MainWindow/CardListView.swift` - Horizontal scrolling card list
- `Views/MainWindow/ClipCardView.swift` - Individual clipboard item card
- `Views/Preview/PreviewWindow.swift` - Large preview window (triggered by Space key)
- `Views/Settings/SettingsWindow.swift` - Settings tabs (General, Hotkey, History, Filter, Appearance, Advanced)

### Key Data Flow
1. User copies content → `ClipboardMonitor` detects change via `changeCount`
2. Content parsed based on NSPasteboard types (tiff/png → image, fileURL → file, string → text/link)
3. Images saved to cache directory, other content stored directly in SwiftData
4. User presses ⌘+Shift+V → `HotKeyManager` triggers → `MainPanelController.showPanel()`
5. User selects item → `PasteService` writes to pasteboard and simulates ⌘+V

## Permissions

The app requires **Accessibility permission** for:
- Global hotkey monitoring via NSEvent
- Clipboard change detection

On first launch, `checkAndRequestAccessibilityPermission()` prompts the user to enable this in System Settings → Privacy & Security → Accessibility.

## Content Type Detection

`ClipboardMonitor.parsePasteboard()` checks types in priority order:
1. `.tiff` or `.png` → image (saved to cache)
2. `.fileURL` → file reference
3. `.string` → text or link (URL detected via NSDataDetector)
4. `.color` → NSColor converted to hex

## Cache Location

Images are cached at: `~/Library/Caches/PasteDeck/images/`

Cache size limit is configurable in settings (default 500MB, options: 100MB/500MB/1GB/unlimited).
