#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The journal is isolated to the test directory.
assert_eq "$OMASET_JOURNAL" "$TESTDIR/journal.jsonl" "journal path isolated"

# A set appends a journal entry recording old/new/default.
capture_out set gaps_in 8
assert_eq "$OUT" '{"id":"gaps_in","ok":true,"value":8}' "set gaps_in"

OUT="$(run history --json)"
assert_contains "$OUT" '"op":"set"' "history records a set op"
assert_contains "$OUT" '"id":"gaps_in"' "history references gaps_in"
assert_contains "$OUT" '"old":3' "history records the previous value"
assert_contains "$OUT" '"new":8' "history records the new value"

# Undo of a first set removes the override (back to default).
capture_out undo
assert_eq "$OUT" '{"id":"gaps_in","ok":true}' "undo output"
capture_out get gaps_in
assert_eq "$OUT" '{"id":"gaps_in","value":3}' "value restored after undo"
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_not_contains "$file" "omaset:begin" "undo removed the managed block"

# Two changes undo one at a time, most recent first.
run set gaps_in 10
run set rounding 6
capture_out undo
assert_eq "$OUT" '{"id":"rounding","ok":true}' "undo undoes the most recent change"
capture_out undo
assert_eq "$OUT" '{"id":"gaps_in","ok":true}' "second undo undoes the earlier change"
capture_out get gaps_in
assert_eq "$OUT" '{"id":"gaps_in","value":3}' "gaps_in back to default after both undos"

# The journal is empty once everything is undone.
OUT="$(run history --json)"
assert_contains "$OUT" '"history":[]' "history empty after all undos"

# rollback restores the pre-omaset .bak snapshot.
run set rounding 6
[ -f "$OMASET_HYPR_DIR/looknfeel.lua.omaset.bak" ] || fail "bak file created on first write"
echo "-- garbage --" >> "$OMASET_HYPR_DIR/looknfeel.lua"
capture_out rollback
assert_exit "$CODE" 0 "rollback exits 0"
file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_not_contains "$file" "-- garbage --" "rollback removed the manual edit"
assert_not_contains "$file" "omaset:begin" "rollback restored pre-omaset state"

echo "ok"
