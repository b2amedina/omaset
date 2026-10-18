#!/usr/bin/env bash
# Records a short clip of the omaset settings window for the README.
# Takes over the screen for ~15s: it focuses the window, records its region with
# wf-recorder, and drives the keyboard with wtype.
#
#   bash media/src/ui-demo.sh                 # writes media/ui.mp4
#   ffmpeg -y -i media/ui.mp4 -vf "fps=12,scale=720:-1:flags=lanczos,split[a][b];\
#     [a]palettegen[p];[b][p]paletteuse" media/ui.gif
#
# The clip deliberately ends with the window still open (no closing key), so it
# never records the desktop behind it.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OMASET="${OMASET:-$HOME/.local/bin/omaset}"
OUT="${1:-$ROOT/media/ui.mp4}"
LOG="${TMPDIR:-/tmp}/omaset-ui-rec.log"
JOURNAL="${OMASET_JOURNAL:-$HOME/.local/state/omaset/journal.jsonl}"
MARGIN=14

# The window drives the *live* engine, so the key sequence below really changes
# settings. Snapshot the journal and undo exactly what we changed afterwards,
# leaving the system as we found it.
before=$(wc -l <"$JOURNAL" 2>/dev/null || echo 0)

"$OMASET" ui open >/dev/null 2>&1
sleep 1.5

read -r ADDR X Y W H < <(hyprctl clients -j |
  jq -r '.[] | select(.title == "omaset Settings") | "\(.address) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"' |
  head -1)
hyprctl dispatch focuswindow "address:$ADDR" >/dev/null
sleep 0.6

GEO="$((X - MARGIN)),$((Y - MARGIN)) $((W + 2 * MARGIN))x$((H + 2 * MARGIN))"
echo "geometry: $GEO" >&2

wf-recorder -g "$GEO" -f "$OUT" >"$LOG" 2>&1 &
REC=$!
sleep 1.2

key() { wtype -k "$1"; sleep "${2:-0.5}"; }
type_s() { wtype -d 90 "$1"; sleep "${2:-0.5}"; }

# browse a few settings and nudge a control
key j 0.45; key j 0.45; key j 0.45
key l 0.28; key l 0.28; key l 0.28
# search for a setting, jump to it, and toggle it
type_s "/" 0.35
type_s "blur" 0.5
key Return 0.9
key space 1.3
# end on the open window — no closing key
sleep 1.1

kill -INT "$REC"
wait "$REC" 2>/dev/null

# undo the changes the demo just made (most recent journal entries)
after=$(wc -l <"$JOURNAL" 2>/dev/null || echo 0)
for ((i = 0; i < after - before; i++)); do
  "$OMASET" undo >/dev/null 2>&1
done
echo "undid $((after - before)) change(s)" >&2

echo "wrote $OUT" >&2
