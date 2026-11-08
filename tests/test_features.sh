#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The feature gate chooses which settings are registered for the host.
# OMASET_WORKSPACE_MODES forces the branch hermetically (the fixture
# OMARCHY_PATH has no workspace-modes.lua, so the probe would be legacy).

has_id() { # has_id <schema-json> <id>
  echo "$1" | jq -r --arg id "$2" '[.panels[].settings[].id] | index($id) != null'
}

# --- legacy branch (pre-4.5) ---
export OMASET_WORKSPACE_MODES=0
OUT="$(run schema)"
assert_eq "$(has_id "$OUT" "master_new_status")" "true" "legacy has master_new_status"
assert_eq "$(has_id "$OUT" "bar_transparent")" "true" "legacy has bar_transparent"
assert_eq "$(has_id "$OUT" "bar_background")" "false" "legacy has no bar_background"
assert_eq "$(has_id "$OUT" "corners")" "false" "legacy has no corners"
assert_eq "$(has_id "$OUT" "window_transparency")" "false" "legacy has no window_transparency"
assert_eq "$(has_id "$OUT" "dock_position")" "false" "legacy has no dock_position"
assert_eq "$(has_id "$OUT" "dock_autohide")" "false" "legacy has no dock_autohide"
assert_eq "$(echo "$OUT" | jq -r '[.panels[].settings[] | select(.id=="workspace_layout") | .options[]] | join(",")')" \
  "dwindle,master,scrolling" "legacy workspace_layout options"

# --- workspace-modes branch (4.5+) ---
export OMASET_WORKSPACE_MODES=1
OUT="$(run schema)"
assert_eq "$(has_id "$OUT" "master_new_status")" "false" "modes has no master_new_status"
assert_eq "$(has_id "$OUT" "bar_transparent")" "false" "modes has no bar_transparent"
assert_eq "$(has_id "$OUT" "bar_background")" "true" "modes has bar_background"
assert_eq "$(has_id "$OUT" "corners")" "true" "modes has corners"
assert_eq "$(has_id "$OUT" "window_transparency")" "true" "modes has window_transparency"
assert_eq "$(has_id "$OUT" "dock_position")" "true" "modes has dock_position"
assert_eq "$(has_id "$OUT" "dock_autohide")" "true" "modes has dock_autohide"
assert_eq "$(echo "$OUT" | jq -r '[.panels[].settings[] | select(.id=="workspace_layout") | .options[]] | join(",")')" \
  "dwindle,scrolling,floating" "modes workspace_layout options"
assert_eq "$(echo "$OUT" | jq -r '[.panels[].settings[] | select(.id=="default_layout") | .options[]] | join(",")')" \
  "dwindle,scrolling,floating" "modes default_layout options"

echo "ok"
