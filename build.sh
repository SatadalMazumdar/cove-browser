#!/bin/zsh
# Builds Cove.app from the Swift package. Needs only the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Cove"
APP="build/Cove.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cove"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Clove</string>
    <key>CFBundleDisplayName</key><string>Clove</string>
    <key>CFBundleIdentifier</key><string>dev.prototype.cove</string>
    <key>CFBundleExecutable</key><string>Cove</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
    <key>UTExportedTypeDeclarations</key>
    <array><dict>
        <key>UTTypeIdentifier</key><string>dev.prototype.cove.item</string>
        <key>UTTypeDescription</key><string>Cove sidebar item</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    </dict></array>
    <key>NSCameraUsageDescription</key><string>A website wants to use your camera.</string>
    <key>NSMicrophoneUsageDescription</key><string>A website wants to use your microphone.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"
