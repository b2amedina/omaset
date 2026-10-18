#!/usr/bin/env bash
# Captures the omaset settings window in two themes and composites a labelled
# strip for the README. Briefly switches the live theme, then restores it.
#
#   bash media/src/themes.sh            # writes media/themes.png
#
# `omarchy theme set` runs a fan-out of retint hooks, including
# `omarchy-restart-opencode` (killall -SIGUSR2 opencode) and
# `omarchy-restart-terminal` (SIGUSR to kitty/ghostty). Running this from inside
# opencode would kill the session, so those two hooks are shimmed to no-ops for
# the duration. Everything else (palette, background, shell applyTheme) runs.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OMASET="${OMASET:-$HOME/.local/bin/omaset}"
OUT="${1:-$ROOT/media/themes.png}"
ORIG="$(cat "$HOME/.local/state/omarchy/current/theme.name")"
MARGIN=14
WORK="${THEMES_WORK:-$(mktemp -d)}"
mkdir -p "$WORK"
KEEP="${KEEP:-0}"

SHIM="$WORK/hookshim"
mkdir -p "$SHIM"
printf '#!/bin/sh\nexit 0\n' >"$SHIM/omarchy-restart-opencode"
printf '#!/bin/sh\nexit 0\n' >"$SHIM/omarchy-restart-terminal"
chmod +x "$SHIM"/omarchy-restart-*
export PATH="$SHIM:$PATH"

trap 'omarchy theme set "$ORIG" >/dev/null 2>&1; [[ $KEEP == 1 ]] || rm -rf "$WORK"' EXIT

capture() {
  local theme="$1" out="$2"
  omarchy theme set "$theme" >/dev/null 2>&1
  sleep 3
  "$OMASET" ui open >/dev/null 2>&1
  sleep 1.8
  read -r X Y W H < <(hyprctl clients -j |
    jq -r '.[] | select(.title == "omaset Settings") |
      "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' | head -1)
  grim -g "$((X - MARGIN)),$((Y - MARGIN)) $((W + 2 * MARGIN))x$((H + 2 * MARGIN))" "$out"
  "$OMASET" ui close >/dev/null 2>&1
  sleep 0.9
}

panel() {  # <shot> <label> <accent> <out>
  magick "$1" -background '#181414' -gravity south -splice 0x58 \
    -fill "$3" -font 'JetBrainsMono-NF-Bold' -pointsize 28 \
    -annotate +0+14 "$2" "$4"
}

capture tokyo-night "$WORK/tokyo.png"
capture osaka-jade  "$WORK/osaka.png"

panel "$WORK/tokyo.png" "Tokyo Night" "#7aa2f7" "$WORK/tokyo-panel.png"
panel "$WORK/osaka.png" "Osaka Jade"  "#509475" "$WORK/osaka-panel.png"

montage "$WORK/tokyo-panel.png" "$WORK/osaka-panel.png" \
  -tile 2x1 -geometry +40+0 -background '#181414' "$WORK/strip.png"
magick "$WORK/strip.png" -bordercolor '#181414' -border 40 "$OUT"

echo "wrote $OUT" >&2
