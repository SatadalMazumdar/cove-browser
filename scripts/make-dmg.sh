#!/bin/zsh
# Packs build/Clove.app into a DMG with a drag-to-Applications layout.
# Usage: scripts/make-dmg.sh <output.dmg>
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: make-dmg.sh <output.dmg>}"
# The staged, signed bundle from build.sh, kept outside any synced folder.
APP="${TMPDIR:-/tmp}/clove-build/Clove.app"
VOL="Clove"
WORK="$(mktemp -d)"
RW="$WORK/rw.dmg"
trap 'rm -rf "$WORK"' EXIT

mkdir "$WORK/root"
ditto "$APP" "$WORK/root/Clove.app"
ln -s /Applications "$WORK/root/Applications"

hdiutil create -quiet -volname "$VOL" -srcfolder "$WORK/root" -fs HFS+ -format UDRW -ov "$RW"
MOUNT="$(hdiutil attach -nobrowse -noautoopen -readwrite "$RW" | awk -F'\t' '/\/Volumes\// && !seen++ {print $NF}')"

# Lays the window out: the app on the left, Applications on the right. Finder scripting can be
# refused or slow on a fresh machine, so a failure here leaves a plain but working DMG.
layout() {
    osascript <<APPLESCRIPT
with timeout of 30 seconds
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 160, 760, 520}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set position of item "Clove.app" of container window to {150, 170}
        set position of item "Applications" of container window to {410, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
end timeout
APPLESCRIPT
}
layout >/dev/null 2>&1 || echo "warning: could not set the DMG window layout, continuing without it"

sync
hdiutil detach -quiet "$MOUNT" || hdiutil detach -quiet -force "$MOUNT"
rm -f "$OUT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Packed $OUT"
