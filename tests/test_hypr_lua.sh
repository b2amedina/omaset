#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Default read comes from the fixture, not the real system.
capture_out get gaps_in
assert_eq "$OUT" '{"id":"gaps_in","value":3}' "default gaps_in from fixture"

# Write creates the user file and overrides the default.
capture_out set gaps_in 8
assert_eq "$OUT" '{"id":"gaps_in","ok":true,"value":8}' "set gaps_in"
capture_out get gaps_in
assert_eq "$OUT" '{"id":"gaps_in","value":8}' "read after set"

file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_contains "$file" "omaset:begin" "managed block present"
assert_contains "$file" "gaps_in = 8" "gaps_in written to file"

# A second write merges into the same block.
run set rounding 6
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_contains "$file" "gaps_in = 8" "gaps_in retained after second set"
assert_contains "$file" "rounding = 6" "rounding added to same block"

# changed lists both overrides.
OUT="$(run changed)"
assert_contains "$OUT" "gaps_in" "changed lists gaps_in"
assert_contains "$OUT" "rounding" "changed lists rounding"

# reset restores the default.
run reset gaps_in
capture_out get gaps_in
assert_eq "$OUT" '{"id":"gaps_in","value":3}' "read after reset"

# reset the last key removes the block entirely.
run reset rounding
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_not_contains "$file" "omaset:begin" "block removed when empty"

echo "ok"
