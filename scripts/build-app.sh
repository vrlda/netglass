#!/bin/bash
# Builds a launchable Netglass.app bundle from the SwiftPM release build.
# Usage: ./scripts/build-app.sh [--open]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION=release
BUNDLE_DIR="$ROOT/build/Netglass.app"
CONTENTS="$BUNDLE_DIR/Contents"
VERSION="1.2.1"

echo "==> Building (swift build -c $CONFIGURATION)"
swift build --package-path "$ROOT" -c "$CONFIGURATION"

BINARY="$ROOT/.build/arm64-apple-macosx/$CONFIGURATION/NetglassMac"

echo "==> Assembling $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/Netglass"
chmod +x "$CONTENTS/MacOS/Netglass"

# app icon (generated once into build/AppIcon.icns; regenerate with make-icon)
if [[ -f "$ROOT/build/AppIcon.icns" ]]; then
    cp "$ROOT/build/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
            <string>Netglass</string>
    <key>CFBundleDisplayName</key>
            <string>Netglass</string>
    <key>CFBundleIdentifier</key>
            <string>com.netglass.app</string>
    <key>CFBundleExecutable</key>
            <string>Netglass</string>
    <key>CFBundlePackageType</key>
            <string>APPL</string>
    <key>CFBundleShortVersionString</key>
            <string>$VERSION</string>
    <key>CFBundleVersion</key>
            <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
            <string>15.0</string>
    <key>LSUIElement</key>
            <false/>
    <key>CFBundleIconFile</key>
            <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
            <true/>
    <key>NSHumanReadableCopyright</key>
            <string>MIT License</string>
</dict>
</plist>
PLIST

echo "==> Done: $BUNDLE_DIR"

if [[ "${1:-}" == "--open" ]]; then
    echo "==> Launching"
    open "$BUNDLE_DIR"
fi
