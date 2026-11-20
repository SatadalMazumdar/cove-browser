#!/bin/zsh
# Captures the raw README screenshots from the sample window, never from your own session.
# Usage: scripts/screenshots.sh <output folder>
# Needs Screen Recording permission for the terminal. Each scene is staged by `Clove --demo <scene>`.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:?usage: screenshots.sh <output folder>}"
mkdir -p "$OUT"
swift build -c release >/dev/null
BIN="$(swift build -c release --show-bin-path)"
# A scratch history file keeps your own history out of the command bar.
export CLOVE_HISTORY_FILE="$OUT/history.sqlite" DYLD_FRAMEWORK_PATH="$BIN"

for scene in main command work split settings editor peek zoom; do
    "$BIN/Clove" --demo "$scene" > "$OUT/window.txt" 2>/dev/null &
    sleep 10
    screencapture -x -o -l "$(awk '/^window/ {print $2}' "$OUT/window.txt")" "$OUT/$scene.png"
    pkill -f "Clove --demo" || true
    sleep 1
done
rm -f "$OUT/window.txt" "$OUT"/history.sqlite*
echo "Wrote the screenshots to $OUT"
