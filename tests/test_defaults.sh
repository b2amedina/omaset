#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The defaults panel wraps the omarchy-default-* commands and writes custom
# values to the stores those commands use. Fake commands on a temp PATH keep
# Omarchy's file layout and output, and HOME is a scratch directory, so nothing
# touches the real preference files.
unset OMASET_NO_APPLY
FAKE="$(mktemp -d)"
trap 'rm -rf "$TESTDIR" "$FAKE"' EXIT
export HOME="$TESTDIR/home"
mkdir -p "$HOME"
mkdir -p "$FAKE/bin"
export PATH="$FAKE/bin:$PATH"
LOG="$FAKE/calls.log"
: > "$LOG"

AGENT_FILE="$HOME/.config/omarchy/defaults/agent"
DICTATION_FILE="$HOME/.config/omarchy/defaults/dictation"
EDITOR_FILE="$HOME/.local/state/omarchy/defaults/editor"
TERMINAL_FILE="$HOME/.config/xdg-terminals.list"
BROWSER_FILE="$FAKE/browser"

# Preference-file commands: no argument reads the file (or the stock value),
# an argument writes it.
pref_cmd() {
  local name="$1" file="$2" missing="$3"
  cat > "$FAKE/bin/$name" <<EOF
#!/bin/bash
echo "$name \$*" >> "$LOG"
if (( \$# == 0 )); then
  if [[ -f "$file" ]]; then read -r v < "$file"; echo "\$v"; exit 0; fi
  $missing
  exit 0
fi
mkdir -p "\$(dirname "$file")"
printf '%s\n' "\$1" > "$file"
EOF
  chmod +x "$FAKE/bin/$name"
}

pref_cmd omarchy-default-agent "$AGENT_FILE" "exit 0"
pref_cmd omarchy-default-editor "$EDITOR_FILE" "echo nvim"
# Dictation reports an unset backend on stderr and exits non-zero, as Omarchy does.
pref_cmd omarchy-default-dictation "$DICTATION_FILE" "echo 'No dictation backend configured.' >&2; exit 1"

# Terminal: the xdg-terminals list, read by its first non-comment line.
cat > "$FAKE/bin/omarchy-default-terminal" <<EOF
#!/bin/bash
echo "omarchy-default-terminal \$*" >> "$LOG"
if (( \$# == 0 )); then
  if [[ -f "$TERMINAL_FILE" ]]; then grep -v '^#' "$TERMINAL_FILE" | head -n1; else echo foot; fi
  exit 0
fi
mkdir -p "\$(dirname "$TERMINAL_FILE")"
{ echo "# Terminal emulator preference order for xdg-terminal-exec"
  echo "# The first found and valid terminal will be used"
  echo "\$1"; } > "$TERMINAL_FILE"
EOF
chmod +x "$FAKE/bin/omarchy-default-terminal"

# Browser: the XDG default. Known tokens map to their desktop ids, as Omarchy does.
cat > "$FAKE/bin/omarchy-default-browser" <<EOF
#!/bin/bash
echo "omarchy-default-browser \$*" >> "$LOG"
if (( \$# == 0 )); then
  id=\$(cat "$BROWSER_FILE" 2>/dev/null || echo chromium.desktop)
  case "\$id" in
    chromium.desktop) echo chromium ;;
    google-chrome.desktop) echo chrome ;;
    brave-browser.desktop) echo brave ;;
    *) echo "\$id" ;;
  esac
  exit 0
fi
case "\$1" in
  chromium) id=chromium.desktop ;;
  chrome) id=google-chrome.desktop ;;
  brave) id=brave-browser.desktop ;;
  *) id="\$1" ;;
esac
printf '%s\n' "\$id" > "$BROWSER_FILE"
EOF
chmod +x "$FAKE/bin/omarchy-default-browser"

# xdg-settings: records the call and stores the default browser id.
cat > "$FAKE/bin/xdg-settings" <<EOF
#!/bin/bash
echo "xdg-settings \$*" >> "$LOG"
if [[ \$1 == set && \$2 == default-web-browser ]]; then printf '%s\n' "\$3" > "$BROWSER_FILE"; fi
EOF
chmod +x "$FAKE/bin/xdg-settings"

value_of() {
  capture_out get "$1"
  echo "$OUT" | jq -c '.value'
}

custom_options_of() {
  capture_out schema
  echo "$OUT" | jq -c --arg id "$1" '.panels[].settings[] | select(.id==$id) | .customOptions // []'
}

# The defaults panel: five settings in one section.
capture_out schema
SCHEMA="$OUT"
assert_eq "$(echo "$SCHEMA" | jq -r '[.panels[] | select(.id=="defaults") | .settings[].id] | sort | join(",")')" \
  "default_agent,default_browser,default_dictation,default_editor,default_terminal" "defaults panel lists the five settings"
assert_eq "$(echo "$SCHEMA" | jq -r '[.panels[] | select(.id=="defaults") | .settings[] | .section] | unique | join(",")')" \
  "Default applications" "defaults settings share one section"

# Initial state: stock values, and agent/dictation unset.
assert_eq "$(value_of default_agent)" "null" "agent unset initially"
assert_eq "$(value_of default_dictation)" "null" "dictation unset initially"
assert_eq "$(value_of default_browser)" '"chromium"' "browser reads the provisioned default"
assert_eq "$(value_of default_editor)" '"nvim"' "editor reads the stock default"
assert_eq "$(value_of default_terminal)" '"foot"' "terminal reads the stock default"

# A declared value goes through its Omarchy command.
capture_out set default_agent claude
assert_eq "$(echo "$OUT" | jq -r '.ok')" "true" "agent set succeeds"
assert_eq "$(cat "$AGENT_FILE")" "claude" "agent written by omarchy-default-agent"
assert_eq "$(value_of default_agent)" '"claude"' "agent reads back"

# Reset removes the preference file, back to unset.
capture_out reset default_agent
assert_eq "$(test -e "$AGENT_FILE" && echo present || echo gone)" "gone" "agent reset removes the preference file"
assert_eq "$(value_of default_agent)" "null" "agent back to unset after reset"

# Dictation: unset stays null even though the command writes to stderr.
capture_out set default_dictation voxtype
assert_eq "$(value_of default_dictation)" '"voxtype"' "dictation reads back"
capture_out reset default_dictation
assert_eq "$(value_of default_dictation)" "null" "dictation reset to unset without error text"

# Editor: set, then reset restores the stock nvim.
capture_out set default_editor vim
assert_eq "$(value_of default_editor)" '"vim"' "editor set"
capture_out reset default_editor
assert_eq "$(test -e "$EDITOR_FILE" && echo present || echo gone)" "gone" "editor reset removes the preference file"
assert_eq "$(value_of default_editor)" '"nvim"' "editor back to stock after reset"

# Terminal: reset removes the xdg-terminals list.
capture_out set default_terminal kitty
assert_eq "$(value_of default_terminal)" '"kitty"' "terminal set"
capture_out reset default_terminal
assert_eq "$(test -e "$TERMINAL_FILE" && echo present || echo gone)" "gone" "terminal reset removes the xdg-terminals list"

# Browser: reset sets the provisioned desktop id with xdg-settings, without installing anything.
capture_out set default_browser brave
assert_eq "$(value_of default_browser)" '"brave"' "browser set"
: > "$LOG"
capture_out reset default_browser
assert_eq "$(value_of default_browser)" '"chromium"' "browser reset restores chromium"
assert_contains "$(cat "$LOG")" "xdg-settings set default-web-browser chromium.desktop" "browser reset uses xdg-settings"
assert_not_contains "$(cat "$LOG")" "omarchy-default-browser chromium" "browser reset does not install through omarchy"

# Custom values: a value no command case names is written to the same store.
capture_out set default_browser browser-router.desktop
assert_exit "$CODE" 0 "custom browser accepted"
assert_eq "$(value_of default_browser)" '"browser-router.desktop"' "custom browser reads back"
assert_contains "$(cat "$LOG")" "xdg-settings set default-web-browser browser-router.desktop" "custom browser set through xdg-settings"

capture_out set default_agent my-agent
assert_exit "$CODE" 0 "custom agent accepted"
assert_eq "$(cat "$AGENT_FILE")" "my-agent" "custom agent written to the preference file"
assert_eq "$(value_of default_agent)" '"my-agent"' "custom agent reads back"

capture_out set default_terminal com.example.Term.desktop
assert_exit "$CODE" 0 "custom terminal accepted"
assert_contains "$(cat "$TERMINAL_FILE")" "com.example.Term.desktop" "custom terminal written to the list"
assert_eq "$(value_of default_terminal)" '"com.example.Term.desktop"' "custom terminal reads back"

# Switching away from a custom value keeps it as a choice, so it can be selected again.
capture_out set default_agent claude
assert_eq "$(custom_options_of default_agent)" '["my-agent"]' "replaced custom agent is listed"
capture_out set default_agent my-agent
assert_eq "$(value_of default_agent)" '"my-agent"' "switched back to the custom agent"

# Custom values that could change a command are refused.
capture set default_agent -rf
assert_exit "$CODE" 1 "value that looks like a flag is refused"
capture set default_editor "$(printf 'a\nb')"
assert_exit "$CODE" 1 "multi-line value is refused"

# A custom value is a change from the stock default.
capture_out reset default_agent
capture_out set default_agent my-agent
capture_out changed --json
assert_contains "$OUT" '"id":"default_agent"' "custom agent counts as changed"
capture_out reset default_agent
capture_out changed --json
assert_not_contains "$OUT" '"id":"default_agent"' "unset agent is not changed"

echo "ok"
