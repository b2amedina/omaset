#!/usr/bin/env bash
# Composes preview.png (1600x900): hero.svg text layer + the settings window,
# framed with a border so the window reads against the dark background.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

WINDOW="$ROOT/media/window.png"
BORDER="#e68e0d"
RADIUS=12
X=640
Y=110

read -r W H <<< "$(magick identify -format "%w %h" "$WINDOW")"

rsvg-convert -w 1600 -h 900 "$ROOT/media/src/hero.svg" -o "$TMP/hero.png"

magick "$TMP/hero.png" "$WINDOW" -geometry "+${X}+${Y}" -composite \
  -fill none -stroke "$BORDER" -strokewidth 2 \
  -draw "roundrectangle ${X},${Y} $((X+W)),$((Y+H)) ${RADIUS},${RADIUS}" \
  "$ROOT/preview.png"

echo "wrote $ROOT/preview.png" >&2
