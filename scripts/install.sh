#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Applications/ClipOCR.app"

if [[ -e "$DEST" ]]; then
    ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$ID" != "io.otron.clipocr" ]]; then
        printf 'Refusing to replace an unrelated app at %s\n' "$DEST" >&2
        exit 1
    fi
    if /usr/bin/pgrep -f "^$DEST/Contents/MacOS/ClipOCR$" >/dev/null; then
        printf 'Quit ClipOCR from its menu before reinstalling.\n' >&2
        exit 1
    fi
fi
bash "$ROOT/scripts/build.sh"
mkdir -p "$HOME/Applications"
# Copy in place: keep the install location and bundle identity stable for macOS permissions.
/usr/bin/ditto "$ROOT/dist/ClipOCR.app" "$DEST"
/usr/bin/codesign --verify --strict "$DEST"
printf 'Installed %s\nOpen it, then press Command–Shift–6.\n' "$DEST"
