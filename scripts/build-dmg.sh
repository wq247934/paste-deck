#!/bin/bash
# Build DMG for PasteDeck
# This script builds a signed DMG installer for the PasteDeck macOS clipboard manager.

set -e

APP_NAME="PasteDeck"
APP_VERSION="1.0"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
EXECUTABLE="${BUILD_DIR}/${APP_NAME}"

echo "🔨 Building ${APP_NAME} in release mode..."
# 先clean再build确保最新代码
swift build -c release

# 检查构建是否成功
if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Build failed: executable not found at $EXECUTABLE"
    exit 1
fi

echo "📦 Creating .app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "${EXECUTABLE}" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Generate Info.plist with hardcoded values
# (Source Info.plist uses Xcode build variables that won't resolve with swift build)
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PasteDeck</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.pastedeck.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PasteDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>PasteDeck 需要访问文件以预览和粘贴您复制的代码、文本等文件内容。</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>PasteDeck 需要访问桌面文件以预览和粘贴您复制的文件内容。</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>PasteDeck 需要访问下载文件夹以预览和粘贴您复制的文件内容。</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 PasteDeck. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <!-- Accessibility permission is required for global hotkey monitoring -->
    <key>NSAppleEventsUsageDescription</key>
    <string>PasteDeck 需要监控键盘快捷键（⌘+Shift+V）来快速呼出剪切板历史面板。</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy assets if they exist
ASSETS_DIR="PasteDeck/PasteDeck/Resources/Assets.xcassets"
if [ -d "$ASSETS_DIR" ]; then
    echo "🎨 Compiling asset catalog..."
    xcrun actool --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        "$ASSETS_DIR" 2>/dev/null || true
else
    echo "⚠️  Warning: Assets directory not found at $ASSETS_DIR"
fi

echo "🖼️ Generating app icon..."
ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"
SRC_DIR="PasteDeck/PasteDeck/Resources/Assets.xcassets/AppIcon.appiconset"

if [ -d "$SRC_DIR" ]; then
    # Copy icon files with fallback checks
    ICON_FILES=(
        "icon_16x16.png"
        "icon_16x16@2x.png"
        "icon_32x32.png"
        "icon_32x32@2x.png"
        "icon_128x128.png"
        "icon_128x128@2x.png"
        "icon_256x256.png"
        "icon_256x256@2x.png"
        "icon_512x512.png"
        "icon_512x512@2x.png"
    )

    for icon in "${ICON_FILES[@]}"; do
        if [ -f "$SRC_DIR/$icon" ]; then
            cp "$SRC_DIR/$icon" "$ICONSET_DIR/$icon"
        else
            echo "⚠️  Warning: Icon file $icon not found"
        fi
    done

    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"

    if [ ! -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]; then
        echo "⚠️  Warning: Failed to create AppIcon.icns"
    fi
else
    echo "⚠️  Warning: AppIcon directory not found at $SRC_DIR"
fi

echo "✍️ Applying ad-hoc code signature..."
codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
codesign -v "$APP_BUNDLE"

echo "📀 Creating DMG installer..."
DMG_TEMP=$(mktemp -d)
cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

echo "   Creating disk image..."
rm -f "${BUILD_DIR}/${DMG_NAME}" "./${DMG_NAME}"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${BUILD_DIR}/${DMG_NAME}"

rm -rf "$DMG_TEMP"

cp "${BUILD_DIR}/${DMG_NAME}" "./${DMG_NAME}"

echo ""
echo "✅ DMG created successfully!"
echo "📍 Location: $(pwd)/${DMG_NAME}"
ls -lh "./${DMG_NAME}"

# Optional: show DMG info
echo ""
echo "📊 DMG Info:"
hdiutil imageinfo "./${DMG_NAME}" 2>/dev/null | grep -E "(format:|sectors:|size:|partition-scheme:|class:|writeable:)" || true
