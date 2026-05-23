<div align="center">
  <h1>📋 PasteDeck</h1>
  
  <p><strong>A modern clipboard manager for macOS</strong></p>
  
  <p>
    <a href="#features">Features</a> •
    <a href="#installation">Installation</a> •
    <a href="#usage">Usage</a> •
    <a href="#requirements">Requirements</a> •
    <a href="#license">License</a>
  </p>
  
  <img src="https://img.shields.io/badge/platform-macOS%2014.0%2B-lightgrey" alt="Platform">
  <img src="https://img.shields.io/badge/language-Swift%205.10-orange" alt="Language">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</div>

---

## Features

### 📋 Comprehensive Clipboard History
- Records everything you copy: **text**, **links**, **images**, **files**, and **colors**
- Automatic deduplication to keep history clean
- Ignore copies from PasteDeck itself to prevent loops

### ⌨ Quick Access
- Press **⌘ + Shift + V** to instantly open the floating panel
- Horizontal scrolling card layout for easy browsing
- Full keyboard navigation support

### 🎨 Beautiful UI
- Modern, clean design inspired by [Paste](https://pasteapp.io)
- Native macOS look with vibrancy effects
- Dark mode support

### 🔍 Search & Filter
- Real-time fuzzy search across all history
- Filter by favorites
- Content type indicators on each card

### ⚡ Keyboard Shortcuts
| Key | Action |
|-----|--------|
| `←` / `→` | Navigate between items |
| `↑` / `↓` | Page up / page down |
| `Enter` | Paste selected item |
| `Space` | Preview selected item |
| `Delete` | Delete selected item |
| `Esc` | Close panel |

### 📌 Organization
- **Pin** important items to keep them at the top
- **Favorite** items for quick access
- Right-click context menu for quick actions

### ⚙️ Customizable Settings
- Launch at login
- Configurable history limits (count & time)
- Cache size management
- App blacklist to ignore specific applications
- Card size preferences

---

## Installation

### From DMG (Recommended)
1. Download the latest `PasteDeck.dmg` from [Releases](https://github.com/wq247934/paste-deck/releases)
2. Open the DMG file
3. Drag PasteDeck to your Applications folder
4. Launch PasteDeck from Applications

### From Source
```bash
# Clone the repository
git clone https://github.com/wq247934/paste-deck.git
cd paste-deck/PasteDeck

# Open in Xcode
open PasteDeck.xcodeproj

# Build and run (⌘ + R)
```

---

## Usage

### First Launch
On first launch, PasteDeck will request **Accessibility permission**. This is required for:
- Global hotkey monitoring (⌘ + Shift + V)
- Clipboard change detection

**To grant permission:**
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the **+** button
3. Add **PasteDeck** from your Applications

### Basic Workflow
1. Copy anything (text, image, file, etc.) - PasteDeck records it automatically
2. Press **⌘ + Shift + V** to open the panel
3. Navigate with arrow keys or click to select
4. Press **Enter** to paste, or **Space** to preview

### Menu Bar
PasteDeck runs in the menu bar with a clipboard icon. Click it to:
- Open the main panel
- Access Settings
- Quit the app

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (prompted on first launch)

---

## Technical Details

### Architecture
- **UI**: SwiftUI with AppKit integration for window management
- **Storage**: SwiftData for persistent history
- **Cache**: Local file cache at `~/Library/Caches/PasteDeck/`

### Supported Content Types
| Type | Detection | Preview |
|------|-----------|---------|
| Text | Plain string | Full text display |
| Link | URL pattern detection | Clickable link |
| Image | TIFF/PNG data | Image preview |
| File | File URL | File icon & metadata |
| Color | NSColor data | Color swatch & hex |

---

## Roadmap

- [ ] Custom hotkey configuration
- [ ] iCloud sync
- [ ] Clipboard sharing across devices
- [ ] More preview types (markdown, code highlighting)
- [ ] Plugin system

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Design inspired by [Paste](https://pasteapp.io)
- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/) and [SwiftData](https://developer.apple.com/documentation/swiftdata)

---

<div align="center">
  <p>Made with ❤️ for macOS</p>
</div>