#!/bin/zsh
# Builds Clove.app from the Swift package. Needs only the Command Line Tools.
#
# Signing: uses CLOVE_SIGN_IDENTITY if set, else the first Developer ID Application
# certificate in the keychain, else an ad hoc signature. Set CLOVE_SIGN_IDENTITY=- to force ad hoc.
# CLOVE_RELEASE=1 adds a secure timestamp, which notarization needs and which needs the network.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
REPO="thedesignmvp/Clove-Browser"
SPARKLE_KEY="9jiHTiEwpsrcW6vOBFY1CRvlRKXKFcOEduqp2xo0BmY="

swift build -c release
BINDIR="$(swift build -c release --show-bin-path)"
# The bundle is put together and signed outside the project folder. A folder that iCloud or
# another file provider syncs stamps Finder info onto new files, and codesign rejects that.
# build/Clove.app is a copy of the signed result. Packaging reads the staged one.
FINAL="build/Clove.app"
STAGE="${TMPDIR:-/tmp}/clove-build"
APP="$STAGE/Clove.app"
finish() {
    rm -rf "$FINAL"
    mkdir -p build
    ditto "$APP" "$FINAL"
    echo "Built $FINAL $VERSION ($BUILD), $1"
}

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BINDIR/Clove" "$APP/Contents/MacOS/Clove"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# ditto keeps the framework's symlinks, which cp -R can flatten.
ditto "$BINDIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Clove</string>
    <key>CFBundleDisplayName</key><string>Clove</string>
    <key>CFBundleIdentifier</key><string>dev.clove.browser</string>
    <key>CFBundleExecutable</key><string>Clove</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key><string>MIT licensed.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>Web site URL</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
    </dict></array>
    <key>CFBundleDocumentTypes</key>
    <array><dict>
        <key>CFBundleTypeName</key><string>HTML document</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSHandlerRank</key><string>Alternate</string>
        <key>LSItemContentTypes</key><array><string>public.html</string><string>public.xhtml</string></array>
    </dict></array>
    <key>UTExportedTypeDeclarations</key>
    <array><dict>
        <key>UTTypeIdentifier</key><string>dev.clove.browser.item</string>
        <key>UTTypeDescription</key><string>Clove sidebar item</string>
        <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    </dict></array>
    <key>NSCameraUsageDescription</key><string>A website wants to use your camera.</string>
    <key>NSMicrophoneUsageDescription</key><string>A website wants to use your microphone.</string>
    <key>SUFeedURL</key><string>https://github.com/$REPO/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_KEY</string>
</dict>
</plist>
PLIST

# codesign rejects Finder info and resource forks, which copies out of a synced folder can carry.
xattr -cr "$APP"

IDENTITY="${CLOVE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ && !seen++ {print $2}')"
fi
[[ -z "$IDENTITY" ]] && IDENTITY="-"

if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1
    finish "ad hoc signed"
    exit 0
fi

STAMP="--timestamp=none"
[[ "${CLOVE_RELEASE:-0}" == "1" ]] && STAMP="--timestamp"
sign() { codesign --force --options runtime $STAMP --sign "$IDENTITY" "$@"; }

# Inside out: Sparkle's helpers first, then the framework, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Resources/Clove.entitlements "$APP"

codesign --verify --deep --strict "$APP"
finish "signed by $IDENTITY"
