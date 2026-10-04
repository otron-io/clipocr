#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
if [[ $# -gt 0 && "${1#v}" != "$VERSION" ]]; then
    printf 'Tag version does not match Info.plist (%s). Update app metadata first.\n' "$VERSION" >&2
    exit 1
fi
APP="$ROOT/dist/ClipOCR.app"
DMG="$ROOT/dist/ClipOCR-$VERSION-universal.dmg"
ZIP="$ROOT/dist/ClipOCR-$VERSION-universal.zip"
CHECKSUMS="$ROOT/dist/SHA256SUMS.txt"
for OUTPUT in "$DMG" "$ZIP" "$CHECKSUMS"; do
    if [[ -e "$OUTPUT" ]]; then
        printf 'Refusing to overwrite existing release file: %s\n' "$OUTPUT" >&2
        exit 1
    fi
done
CLIPOCR_ARCH=universal bash "$ROOT/scripts/build.sh"
lipo "$APP/Contents/MacOS/ClipOCR" -verify_arch arm64 x86_64

WORK_ROOT="${CLIPOCR_WORK_DIR:-$ROOT/.build/packaging}"
mkdir -p "$WORK_ROOT"
WORK="$(mktemp -d "$WORK_ROOT/dmg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STAGING="$WORK/ClipOCR"
mkdir -p "$STAGING"
ditto --noqtn --noextattr --norsrc "$APP" "$STAGING/ClipOCR.app"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/Resources/Install.txt" "$STAGING/READ ME FIRST.txt"
cp "$ROOT/LICENSE" "$STAGING/LICENSE.txt"

hdiutil create -volname "ClipOCR $VERSION" -srcfolder "$STAGING" \
    -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify "$DMG"
ditto -c -k --keepParent --noqtn --noextattr --norsrc "$APP" "$ZIP"
python3 - "$DMG" "$ZIP" "$CHECKSUMS" <<'PY'
import hashlib
import pathlib
import sys

assets = [pathlib.Path(p) for p in sys.argv[1:3]]
lines = [f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in assets]
pathlib.Path(sys.argv[3]).write_text("".join(lines))
PY
printf '\nRelease assets:\n%s\n%s\n%s\n' "$DMG" "$ZIP" "$CHECKSUMS"
