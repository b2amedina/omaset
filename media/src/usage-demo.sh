#!/usr/bin/env bash
# Prints `omaset --help` for the README's static usage screenshot.
#
#   asciinema rec --headless --window-size 84x34 -c "bash media/src/usage-demo.sh" /tmp/usage.cast
#   ~/.cargo/bin/agg --cols 84 --rows 34 --font-size 20 --font-family "JetBrainsMono Nerd Font" \
#     --theme "1a1b26,a9b1d6,13141c,f7768e,9ece6a,e0af68,7aa2f7,ad8ee6,449dab,a9b1d6,414868,ff7a93,b9f27c,ff9e64,7da6ff,bb9af7,0db9d7,c0caf5" \
#     /tmp/usage.cast /tmp/usage.gif
#   ffmpeg -y -sseof -0.1 -i /tmp/usage.gif -frames:v 1 media/usage.png   # (or extract the last frame)
#
# Runs against stubbed `omarchy`/`hyprctl` and a scratch HOME.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/tests/fixtures/omarchy"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
cat >"$WORK/bin/omarchy" <<'STUB'
#!/bin/sh
case "$*" in
  *--status*) echo '{"enabled": false}' ;;
  *enabled*) exit 1 ;;
  *) exit 0 ;;
esac
STUB
cat >"$WORK/bin/hyprctl" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$WORK/bin/omarchy" "$WORK/bin/hyprctl"

export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
export PATH="$WORK/bin:$PATH"

export OMARCHY_PATH="$FIXTURES"
export OMASET_HYPR_DIR="$WORK/hypr"
export OMASET_SHELL_CONFIG="$WORK/shell.json"
export OMASET_HYPRSUNSET_CONFIG="$WORK/hyprsunset.conf"
export OMASET_SETTINGS_DIR="$WORK/settings"
export OMASET_BACKENDS_DIR="$WORK/backends"
export OMASET_JOURNAL="$WORK/journal.jsonl"
export OMASET_PREFERENCES="$WORK/preferences.json"
mkdir -p "$OMASET_HYPR_DIR" "$OMASET_SETTINGS_DIR" "$OMASET_BACKENDS_DIR"

clear
lua5.1 "$ROOT/bin/omaset" --help
sleep 1.5
