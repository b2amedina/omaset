#!/usr/bin/env bash
# Captures the omaset settings window for the plugin marketplace listing.
#
#   bash media/src/preview.sh            # writes preview.png (repo root)
#
# Opens the window, screenshots it with a small margin of desktop around it,
# then closes it. The window sizes to its content, so the shot tracks the
# current UI without any hard-coded geometry.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OMASET="${OMASET:-$HOME/.local/bin/omaset}"
OUT="${1:-$ROOT/preview.png}"
MARGIN=14

"$OMASET" ui open >/dev/null 2>&1
sleep 1.8
hyprctl dispatch "hl.dsp.window.bring_to_top()" >/dev/null 2>&1
sleep 0.4

read -r X Y W H < <(hyprctl clients -j |
  jq -r '.[] | select(.title == "omaset Settings") |
    "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' | head -1)

grim -g "$((X - MARGIN)),$((Y - MARGIN)) $((W + 2 * MARGIN))x$((H + 2 * MARGIN))" "$OUT"

"$OMASET" ui close >/dev/null 2>&1
echo "wrote $OUT" >&2
