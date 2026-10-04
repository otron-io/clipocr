#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_ROOT="${CLIPOCR_WORK_DIR:-$ROOT/.build/packaging}"
mkdir -p "$WORK_ROOT"
WORK="$(mktemp -d "$WORK_ROOT/icon.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/ClipOCR.iconset"
mkdir -p "$ICONSET"
swift "$ROOT/scripts/render-icon.swift" "$ROOT/Resources/ClipOCR.png"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/Resources/ClipOCR.png" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$ROOT/Resources/ClipOCR.png" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/ClipOCR.icns"
printf 'Generated Resources/ClipOCR.png and Resources/ClipOCR.icns\n'
