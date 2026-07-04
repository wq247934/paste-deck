#!/bin/bash
# Build DMG for PasteDeck
# This script builds a signed DMG installer for the PasteDeck macOS clipboard manager.

set -e

APP_NAME="PasteDeck"
APP_VERSION="1.1.9"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
EXECUTABLE="${BUILD_DIR}/${APP_NAME}"
ENTITLEMENTS="PasteDeck/PasteDeck/PasteDeck.entitlements"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-PasteDeck Local Code Signing}"

if [ "${PASTEDECK_ALLOW_DMG_BUILD:-}" != "1" ]; then
    echo "⏭️  Skipping DMG build. Set PASTEDECK_ALLOW_DMG_BUILD=1 to create a release installer."
    exit 0
fi

echo "🔎 Checking code signing identity..."
if ! security find-identity -v -p codesigning | grep -F "\"${CODE_SIGN_IDENTITY}\"" >/dev/null; then
    echo "❌ Code signing identity not found: ${CODE_SIGN_IDENTITY}"
    echo ""
    echo "Create the local signing certificate once, then rerun this script:"
    echo "  bash scripts/create-local-codesign-cert.sh"
    echo ""
    echo "Or override the identity:"
    echo "  CODE_SIGN_IDENTITY=\"Your Identity\" bash scripts/build-dmg.sh"
    exit 1
fi

echo "✅ Using code signing identity: ${CODE_SIGN_IDENTITY}"

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
    <string>1.1.9</string>
    <key>CFBundleVersion</key>
    <string>119</string>
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

echo "✍️ Applying stable local code signature..."
if [ ! -f "$ENTITLEMENTS" ]; then
    echo "❌ Entitlements file not found at $ENTITLEMENTS"
    exit 1
fi

codesign --force \
    --sign "$CODE_SIGN_IDENTITY" \
    --timestamp=none \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

echo "🔐 Code signature details:"
codesign -dv --verbose=4 "$APP_BUNDLE"
codesign -dr - "$APP_BUNDLE"
VERIFY_OUTPUT=$(codesign --verify --strict --verbose=2 "$APP_BUNDLE" 2>&1) || {
    if echo "$VERIFY_OUTPUT" | grep -F "CSSMERR_TP_NOT_TRUSTED" >/dev/null; then
        echo "$VERIFY_OUTPUT"
        echo "⚠️  Signature structure is present, but the local certificate is not trusted for code signing."
        echo "   Open Keychain Access and set '${CODE_SIGN_IDENTITY}' to Always Trust for Code Signing,"
        echo "   or recreate the certificate with scripts/create-local-codesign-cert.sh after deleting the old one."
    else
        echo "$VERIFY_OUTPUT"
        exit 1
    fi
}

echo "📀 Creating DMG installer..."
echo "   Detaching existing ${APP_NAME} volumes..."
for mounted_volume in /Volumes/${APP_NAME}*; do
    if [ -e "$mounted_volume" ]; then
        hdiutil detach "$mounted_volume" >/dev/null 2>&1 ||
            hdiutil detach "$mounted_volume" -force >/dev/null 2>&1 ||
            true
    fi
done

DMG_TEMP=$(mktemp -d)
DMG_STAGING="$DMG_TEMP/staging"
DMG_MOUNT="$DMG_TEMP/mount"
DMG_RW="${BUILD_DIR}/${APP_NAME}-rw.dmg"
mkdir -p "$DMG_STAGING" "$DMG_MOUNT"

cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
mkdir -p "$DMG_STAGING/.background"

BACKGROUND_PNG="$DMG_STAGING/.background/install-arrow.png"
BACKGROUND_SWIFT="$DMG_TEMP/generate-dmg-background.swift"
cat > "$BACKGROUND_SWIFT" << 'EOF'
import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 600, height: 340)
let image = NSImage(size: size)

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: text).draw(in: NSRect(x: 0, y: y, width: size.width, height: 28), withAttributes: attributes)
}

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

NSGradient(
    starting: NSColor(calibratedRed: 0.97, green: 0.98, blue: 0.99, alpha: 1),
    ending: NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.93, alpha: 1)
)?.draw(in: NSRect(origin: .zero, size: size), angle: -90)

let guideColor = NSColor(calibratedRed: 0.00, green: 0.48, blue: 1.00, alpha: 1)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
shadow.shadowBlurRadius = 8
shadow.shadowOffset = NSSize(width: 0, height: -2)
NSGraphicsContext.saveGraphicsState()
shadow.set()

let shaft = NSBezierPath(roundedRect: NSRect(x: 242, y: 158, width: 118, height: 26), xRadius: 13, yRadius: 13)
guideColor.setFill()
shaft.fill()

let head = NSBezierPath()
head.move(to: NSPoint(x: 352, y: 139))
head.line(to: NSPoint(x: 410, y: 171))
head.line(to: NSPoint(x: 352, y: 203))
head.close()
guideColor.setFill()
head.fill()

NSGraphicsContext.restoreGraphicsState()

drawCentered(
    "拖到 Applications 安装",
    y: 260,
    font: .systemFont(ofSize: 21, weight: .semibold),
    color: NSColor(calibratedWhite: 0.18, alpha: 1)
)
drawCentered(
    "Drag PasteDeck to Applications",
    y: 233,
    font: .systemFont(ofSize: 13, weight: .regular),
    color: NSColor(calibratedWhite: 0.42, alpha: 1)
)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render DMG background")
}

try pngData.write(to: outputURL)
EOF

if swift "$BACKGROUND_SWIFT" "$BACKGROUND_PNG" >/dev/null 2>&1; then
    rm -f "$BACKGROUND_SWIFT"
else
    echo "❌ Could not generate DMG arrow background."
    rm -f "$BACKGROUND_SWIFT" "$BACKGROUND_PNG"
    exit 1
fi

echo "   Creating disk image..."
rm -f "${BUILD_DIR}/${DMG_NAME}" "$DMG_RW" "./${DMG_NAME}"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDRW \
    -fs HFS+ \
    "$DMG_RW"

echo "   Applying Finder install layout..."
hdiutil attach "$DMG_RW" -mountpoint "$DMG_MOUNT" -nobrowse -quiet

LAYOUT_STATUS=0
if osascript << EOF
tell application "Finder"
    set dmgFolder to POSIX file "$DMG_MOUNT" as alias
    set backgroundImage to POSIX file "$DMG_MOUNT/.background/install-arrow.png" as alias
    open dmgFolder
    delay 1
    set current view of container window of dmgFolder to icon view
    set the bounds of container window of dmgFolder to {100, 100, 700, 440}
    set viewOptions to the icon view options of container window of dmgFolder
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to backgroundImage
    set position of item "$APP_NAME.app" of dmgFolder to {145, 155}
    set position of item "Applications" of dmgFolder to {505, 155}
    update dmgFolder without registering applications
    delay 1
end tell
EOF
then
    echo "   Finder layout applied."
else
    echo "❌ Could not apply Finder layout."
    LAYOUT_STATUS=1
fi

sync
hdiutil detach "$DMG_MOUNT" -quiet

if [ "$LAYOUT_STATUS" -ne 0 ]; then
    rm -rf "$DMG_TEMP"
    rm -f "$DMG_RW"
    exit 1
fi

hdiutil convert "$DMG_RW" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${BUILD_DIR}/${DMG_NAME}"

rm -rf "$DMG_TEMP"
rm -f "$DMG_RW"

cp "${BUILD_DIR}/${DMG_NAME}" "./${DMG_NAME}"

echo ""
echo "✅ DMG created successfully!"
echo "📍 Location: $(pwd)/${DMG_NAME}"
ls -lh "./${DMG_NAME}"

# Optional: show DMG info
echo ""
echo "📊 DMG Info:"
hdiutil imageinfo "./${DMG_NAME}" 2>/dev/null | grep -E "(format:|sectors:|size:|partition-scheme:|class:|writeable:)" || true
