#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ClipOCR.app"
ARCH="${CLIPOCR_ARCH:-universal}"

if [[ -e "$APP" ]]; then
    ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$ID" != "io.otron.clipocr" ]]; then
        printf 'Refusing to replace an unrecognized bundle at %s\n' "$APP" >&2
        exit 1
    fi
fi
if [[ ! -f "$ROOT/Resources/ClipOCR.icns" ]]; then
    printf 'App icon missing; run bash scripts/make-icon.sh first.\n' >&2
    exit 1
fi
case "$ARCH" in
    universal) ARCHITECTURES=(arm64 x86_64) ;;
    arm64|x86_64) ARCHITECTURES=("$ARCH") ;;
    *) printf 'CLIPOCR_ARCH must be universal, arm64, or x86_64.\n' >&2; exit 1 ;;
esac

BINARIES=()
for CPU in "${ARCHITECTURES[@]}"; do
    TRIPLE="$CPU-apple-macosx13.0"
    swift build --package-path "$ROOT" -c release --triple "$TRIPLE"
    BINARIES+=("$(swift build --package-path "$ROOT" -c release --triple "$TRIPLE" --show-bin-path)/ClipOCR")
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "$ARCH" == universal ]]; then
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/ClipOCR"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/ClipOCR"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/ClipOCR.icns" "$APP/Contents/Resources/ClipOCR.icns"
# No Developer ID identity is required. Public releases are NOT notarized.
# Preserve a stable designated requirement across local rebuilds for TCC.
codesign --force --sign - --identifier io.otron.clipocr \
    --requirements '=designated => identifier "io.otron.clipocr"' "$APP"
codesign --verify --strict "$APP"
lipo -info "$APP/Contents/MacOS/ClipOCR"
printf 'Built %s (%s)\n' "$APP" "$ARCH"
