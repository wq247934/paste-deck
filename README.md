<div align="center">
  <h1>📋 PasteDeck</h1>
  
  <p><strong>A modern clipboard manager for macOS</strong></p>
  
  <p>
    <a href="#features">English</a> •
    <a href="#功能特性">中文</a>
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

---

# 功能特性

### 📋 全面的剪切板历史
- 记录你复制的所有内容：**文本**、**链接**、**图片**、**文件** 和 **颜色**
- 自动去重，保持历史记录整洁
- 忽略来自 PasteDeck 自身的复制，避免循环记录

### ⌨ 快速访问
- 按 **⌘ + Shift + V** 即可打开浮动面板
- 水平滚动的卡片布局，方便浏览
- 完整的键盘导航支持

### 🎨 精美界面
- 现代简洁的设计，灵感来自 [Paste](https://pasteapp.io)
- 原生 macOS 风格，带有毛玻璃效果
- 支持深色模式

### 🔍 搜索与筛选
- 实时模糊搜索所有历史记录
- 按收藏筛选
- 每张卡片显示内容类型标识

### ⚡ 键盘快捷键
| 按键 | 操作 |
|-----|------|
| `←` / `→` | 在项目间导航 |
| `↑` / `↓` | 向上/向下翻页 |
| `Enter` | 粘贴选中项 |
| `Space` | 预览选中项 |
| `Delete` | 删除选中项 |
| `Esc` | 关闭面板 |

### 📌 整理管理
- **置顶** 重要项目，保持在顶部
- **收藏** 项目以便快速访问
- 右键菜单快速操作

### ⚙️ 可自定义设置
- 开机启动
- 可配置的历史记录限制（数量和时间）
- 缓存空间管理
- 应用黑名单，忽略指定应用
- 卡片大小偏好

---

## 安装

### 从 DMG 安装（推荐）
1. 从 [Releases](https://github.com/wq247934/paste-deck/releases) 下载最新的 `PasteDeck.dmg`
2. 打开 DMG 文件
3. 将 PasteDeck 拖到应用程序文件夹
4. 从应用程序启动 PasteDeck

### 从源码构建
```bash
# 克隆仓库
git clone https://github.com/wq247934/paste-deck.git
cd paste-deck/PasteDeck

# 用 Xcode 打开
open PasteDeck.xcodeproj

# 构建并运行（⌘ + R）
```

---

## 使用方法

### 首次启动
首次启动时，PasteDeck 会请求**辅助功能权限**。这是以下功能所需的：
- 全局快捷键监听（⌘ + Shift + V）
- 剪切板变化检测

**授予权限：**
1. 打开 **系统设置** → **隐私与安全性** → **辅助功能**
2. 点击 **+** 按钮
3. 从应用程序中添加 **PasteDeck**

### 基本工作流程
1. 复制任何内容（文本、图片、文件等）- PasteDeck 会自动记录
2. 按 **⌘ + Shift + V** 打开面板
3. 使用方向键导航或点击选择
4. 按 **Enter** 粘贴，或按 **Space** 预览

### 菜单栏
PasteDeck 会在菜单栏显示一个剪切板图标。点击可以：
- 打开主面板
- 访问设置
- 退出应用

---

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- 辅助功能权限（首次启动时会提示）

---

## 技术细节

### 架构
- **界面**：SwiftUI 与 AppKit 集成用于窗口管理
- **存储**：SwiftData 用于持久化历史记录
- **缓存**：本地文件缓存位于 `~/Library/Caches/PasteDeck/`

### 支持的内容类型
| 类型 | 检测方式 | 预览 |
|------|---------|------|
| 文本 | 普通字符串 | 完整文本显示 |
| 链接 | URL 模式检测 | 可点击链接 |
| 图片 | TIFF/PNG 数据 | 图片预览 |
| 文件 | 文件 URL | 文件图标和元数据 |
| 颜色 | NSColor 数据 | 色块和十六进制值 |

---

## 开发计划

- [ ] 自定义快捷键配置
- [ ] iCloud 同步
- [ ] 跨设备剪切板共享
- [ ] 更多预览类型（Markdown、代码高亮）
- [ ] 插件系统

---

## 许可证

本项目采用 MIT 许可证 - 详情见 [LICENSE](LICENSE) 文件。

---

## 致谢

- 设计灵感来自 [Paste](https://pasteapp.io)
- 使用 [SwiftUI](https://developer.apple.com/xcode/swiftui/) 和 [SwiftData](https://developer.apple.com/documentation/swiftdata) 构建

---

<div align="center">
  <p>用 ❤️ 为 macOS 打造</p>
</div>
