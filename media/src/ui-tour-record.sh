#!/usr/bin/env bash
# Records the raw keyboard interaction for the README's annotated feature tour.
# Post-processing (media/src/ui-tour-build.py) adds the camera moves and callouts.
#
#   bash media/src/ui-tour-record.sh          # writes media/ui.mp4 + a beats file
#
# The window drives the *live* engine, so the key sequence really changes
# settings; the journal is snapshotted and undone afterwards. It is opened on a
# deliberately empty workspace so the desktop behind it is just wallpaper, and
# filmed with a generous margin of that desktop around it -- the window has to
# float in context, or you cannot see its border and corners change.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OMASET="${OMASET:-$HOME/.local/bin/omaset}"
OUT="${1:-$ROOT/media/ui.mp4}"
TOUR_WS="${TOUR_WS:-5}"          # an empty workspace to record on
MARGIN="${MARGIN:-64}"           # logical px of desktop kept around the window
LOG="${TMPDIR:-/tmp}/omaset-ui-tour-rec.log"
BEATS="${TMPDIR:-/tmp}/omaset-ui-tour-beats.txt"
GEOM="${TMPDIR:-/tmp}/omaset-ui-tour-geometry.txt"
JOURNAL="${OMASET_JOURNAL:-$HOME/.local/state/omaset/journal.jsonl}"

focus_ws() { hyprctl dispatch "hl.dsp.focus({ workspace = \"$1\" })" >/dev/null 2>&1; }

# Hyprland here is configured in Lua, so dispatchers are called as hl.dsp.*
# expressions; a bare `hyprctl dispatch focuswindow ...` is a no-op.
ORIG_WS="$(hyprctl activeworkspace -j | jq -r '.id')"
focus_ws "$TOUR_WS"
sleep 0.6

# Omarchy tags every window with a default opacity (0.985/0.96), so wallpaper
# bleeds through the settings window on film. omaset writes a "-default-opacity"
# rule for its own window when launch_floating is on (lib/omaset/backends/
# hypr_window.lua), so the window stays opaque even though every setting change
# reloads the Hyprland config.
before=$(wc -l <"$JOURNAL" 2>/dev/null || echo 0)

"$OMASET" ui open >/dev/null 2>&1
sleep 1.8
hyprctl dispatch "hl.dsp.window.bring_to_top()" >/dev/null 2>&1
sleep 0.4

read -r ADDR X Y W H < <(hyprctl clients -j |
  jq -r '.[] | select(.title == "omaset Settings") |
    "\(.address) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' | head -1)

GEO="$((X - MARGIN)),$((Y - MARGIN)) $((W + 2 * MARGIN))x$((H + 2 * MARGIN))"
# The build runs on a machine whose monitor scale (and thus every pixel) may
# differ from this one, so record the margin and scale it should undo.
SCALE="$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .scale')"
printf '%s %s\n' "$MARGIN" "$SCALE" >"$GEOM"
echo "geometry: $GEO  margin=$MARGIN scale=$SCALE (workspace $TOUR_WS)" >&2
echo "beats -> $BEATS" >&2

wf-recorder -g "$GEO" -f "$OUT" >"$LOG" 2>&1 &
REC=$!
sleep 2.5   # pre-roll: idle, full window in view

: >"$BEATS"
t0=$(date +%s.%N)
beat() { printf '%.2f %s\n' "$(echo "$(date +%s.%N) - $t0" | bc)" "$1" >>"$BEATS"; }
key() { wtype -k "$1"; }
type_s() { wtype -d 120 "$1"; }

# slow, deliberate pacing so every beat is easy to read on a loop
beat idle                          # full window, untouched
sleep 2.4
key slash; sleep 0.6; beat search  # / opens search
type_s "rounding"; sleep 1.3; beat typed
key Return; sleep 1.9; beat row    # jump to the matching setting
for _ in $(seq 1 10); do key l; sleep 0.26; done   # watch the corners round off
sleep 1.0; beat adjusted
sleep 0.9
key c; sleep 2.3; beat changed     # c = what differs from stock
key j; sleep 1.0; beat selected
key Return; sleep 2.1; beat jumped # jump straight to that setting
sleep 1.3; beat end

kill -INT "$REC" 2>/dev/null
wait "$REC" 2>/dev/null

after=$(wc -l <"$JOURNAL" 2>/dev/null || echo 0)
for ((i = 0; i < after - before; i++)); do "$OMASET" undo >/dev/null 2>&1; done
echo "undid $((after - before)) change(s)" >&2

"$OMASET" ui close >/dev/null 2>&1
focus_ws "$ORIG_WS"
echo "wrote $OUT" >&2
