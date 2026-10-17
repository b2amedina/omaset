#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The hypr-window backend manages o.window() rules in ~/.config/hypr/hyprland.lua
# (fixture via OMASET_HYPR_DIR). Defaults come from the DSL, not a fixture file.

# Aggregate read returns the whole group.
capture_out get fullwidth_style
assert_eq "$OUT" '{"id":"fullwidth_style","value":{"border_size":2,"rounding":0}}' "aggregate default"

# Sub-setting read.
capture_out get fullwidth_style border_size
assert_eq "$OUT" '{"id":"fullwidth_style","sub":"border_size","value":2}' "sub default"

# Setting both sub-settings composes one o.window rule.
capture_out set fullwidth_style border_size 6
assert_eq "$OUT" '{"id":"fullwidth_style","ok":true,"sub":"border_size","value":6}' "set border_size"
run set fullwidth_style rounding 10
file="$(cat "$OMASET_HYPR_DIR/hyprland.lua")"
assert_contains "$file" 'o.window({ fullscreen_state_internal = 1 }, { border_size = 6, rounding = 10 })' "rule composed"

# A second setting group lives alongside the first in the same block.
run set tiled_fullscreen_style border_size 3
file="$(cat "$OMASET_HYPR_DIR/hyprland.lua")"
assert_contains "$file" 'o.window({ fullscreen_state_client = 2, fullscreen_state_internal = 0 }, { border_size = 3 })' "second rule"

# keys lists sub-setting names.
OUT="$(run keys fullwidth_style)"
assert_eq "$OUT" $'border_size\nrounding' "keys lists sub-settings"

# changed reports each differing sub-setting.
OUT="$(run changed)"
assert_contains "$OUT" "fullwidth_style:border_size" "changed lists border_size"
assert_contains "$OUT" "fullwidth_style:rounding" "changed lists rounding"
assert_contains "$OUT" "tiled_fullscreen_style:border_size" "changed lists tiled border"

# reset of one sub keeps the other in the rule.
run reset fullwidth_style border_size
file="$(cat "$OMASET_HYPR_DIR/hyprland.lua")"
assert_contains "$file" 'o.window({ fullscreen_state_internal = 1 }, { rounding = 10 })' "rule retains rounding"

# reset --all clears the whole group's rule.
run reset fullwidth_style --all
file="$(cat "$OMASET_HYPR_DIR/hyprland.lua")"
assert_not_contains "$file" "fullscreen_state_internal = 1" "fullwidth rule removed"

# unknown sub-setting is rejected.
capture get fullwidth_style nope
assert_exit "$CODE" 1 "unknown sub-setting rejected"

# help lists the sub-settings.
OUT="$(run help fullwidth_style)"
assert_contains "$OUT" "border_size  int" "help lists sub-setting"
assert_contains "$OUT" "rounding  int" "help lists second sub-setting"

# search marks grouped settings.
OUT="$(run search fullwidth)"
assert_contains "$OUT" "(grouped)" "search marks grouped"

# ui-float adds/removes the omaset window's own float rule (launch_floating).
capture_out ui-float on
assert_eq "$OUT" "ok" "ui-float on"
file="$(cat "$OMASET_HYPR_DIR/hyprland.lua")"
assert_contains "$file" 'o.window({ class = "^org.quickshell$", title = "^omaset Settings$" }, { center = true, float = true })' "float rule added"

capture_out ui-float on
assert_eq "$OUT" "ok" "ui-float on idempotent"

capture_out ui-float off
assert_eq "$OUT" "ok" "ui-float off"
file="$(cat "$OMASET_HYPR_DIR/hyprland.lua")"
assert_not_contains "$file" "omaset Settings" "float rule removed"

capture ui-float bogus
assert_exit "$CODE" 1 "ui-float invalid arg rejected"

echo "ok"
