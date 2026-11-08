#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Default read comes from the fixture, not the real system.
capture_out get gaps_in
assert_eq "$OUT" '{"id":"gaps_in","value":3}' "default gaps_in from fixture"

# Setting a value that has no uncommented occurrence appends a minimal
# hl.config override — no managed block, no markers.
capture_out set gaps_in 8
assert_eq "$OUT" '{"id":"gaps_in","ok":true,"value":8}' "set gaps_in"
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_contains "$file" "gaps_in = 8" "value appended"
assert_contains "$file" "hl.config" "override uses hl.config"
assert_not_contains "$file" "omaset:begin" "no managed block"

# A second write edits that occurrence in place instead of adding another.
run set gaps_in 9
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_contains "$file" "gaps_in = 9" "value edited in place"
assert_not_contains "$file" "gaps_in = 8" "old value gone"

# A different path appends its own override.
run set rounding 6
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_contains "$file" "rounding = 6" "second path appended"

# reset writes the default back in place.
run reset gaps_in
capture_out get gaps_in
assert_eq "$OUT" '{"id":"gaps_in","value":3}' "read after reset"
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_contains "$file" "gaps_in = 3" "default written in place"

# reset of a never-set key is a no-op (no new override, no marker).
before="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
run reset gaps_out
after="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_eq "$before" "$after" "reset of unset key is a no-op"

# A hand-written value is edited in place, keeping the trailing comment and the
# surrounding template comments intact.
cat > "$OMASET_HYPR_DIR/looknfeel.lua" <<'EOF'
-- Keep your personal look'n'feel overrides here.
-- hl.config({
--   general = {
--     -- No gaps between windows.
--     gaps_in = 0,
--   },
-- })
hl.config({
  general = {
    border_size = 2, -- a hand-tuned value
  },
})
EOF
run set border_size 5
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_contains "$file" "border_size = 5" "hand value edited in place"
assert_contains "$file" "-- a hand-tuned value" "trailing comment preserved"
assert_contains "$file" "-- No gaps between windows." "template comment preserved"
assert_not_contains "$file" "omaset:begin" "still no block"

# reset of the hand value writes the default back in place.
run reset border_size
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_contains "$file" "border_size = 1" "hand value reset to default in place"

echo "ok"
