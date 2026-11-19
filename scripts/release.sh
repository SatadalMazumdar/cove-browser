#!/bin/zsh
# Builds a release: a signed app, a signed and notarized DMG, and the Sparkle appcast.
# Output lands in build/release/.
#
# Notarization credentials, first match wins:
#   1. A keychain profile named clove-notary. Create it once with
#        xcrun notarytool store-credentials clove-notary --apple-id <id> --team-id <team> --password <app-specific>
#   2. APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD in the environment, which CI uses.
# With neither, the script stops, unless CLOVE_SKIP_NOTARY=1.
#
# The Sparkle signing key comes from the login keychain, or from SPARKLE_PRIVATE_KEY in CI.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
REPO="SatadalMazumdar/cove-browser"
OUT="build/release"
DMG="$OUT/Clove-$VERSION.dmg"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

CLOVE_RELEASE=1 ./build.sh >/dev/null

STAGED="${TMPDIR:-/tmp}/clove-build/Clove.app"
IDENTITY="$(codesign -dvv "$STAGED" 2>&1 | awk -F= '/^Authority=Developer ID Application/ && !seen++ {print $2}')"
if [[ -z "$IDENTITY" ]]; then
    echo "error: the app is not signed with a Developer ID certificate" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
scripts/make-dmg.sh "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if xcrun notarytool history --keychain-profile clove-notary >/dev/null 2>&1; then
    CREDS=(--keychain-profile clove-notary)
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    CREDS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
elif [[ "${CLOVE_SKIP_NOTARY:-0}" == "1" ]]; then
    CREDS=()
    echo "warning: skipping notarization, Gatekeeper will block this DMG on other Macs"
else
    echo "error: no notarization credentials, see the top of this script" >&2
    exit 1
fi

if (( ${#CREDS} )); then
    xcrun notarytool submit "$DMG" "${CREDS[@]}" --wait | tee "$OUT/notary.log"
    grep -q "status: Accepted" "$OUT/notary.log" || { echo "error: notarization was not accepted" >&2; exit 1; }
    rm "$OUT/notary.log"
    xcrun stapler staple "$DMG"
fi

# The appcast carries the DMG's EdDSA signature, so Sparkle can check the download.
KEY=()
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    KEYFILE="$(mktemp)"
    trap 'rm -f "$KEYFILE"' EXIT
    print -r -- "$SPARKLE_PRIVATE_KEY" > "$KEYFILE"
    KEY=(--ed-key-file "$KEYFILE")
fi
"$SPARKLE_BIN/generate_appcast" "${KEY[@]}" \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --link "https://github.com/$REPO" \
    -o "$OUT/appcast.xml" "$OUT"

echo "Release $VERSION is in $OUT"
ls -lh "$OUT"
