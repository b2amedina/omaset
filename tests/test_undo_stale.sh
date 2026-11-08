#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Journal entries recorded by an older omaset/Omarchy may name a setting that
# no longer exists, or a value that is no longer a valid option. undo must
# skip those with a warning, not replay the invalid value.

assert_eq "$OMASET_JOURNAL" "$TESTDIR/journal.jsonl" "journal path isolated"

# Run under the modes branch, where master_new_status does not exist.
export OMASET_WORKSPACE_MODES=1

# Seed a journal with a stale entry (removed setting) above a good one.
mkdir -p "$(dirname "$OMASET_JOURNAL")"
cat > "$OMASET_JOURNAL" <<'EOF'
{"backend":"hypr-lua","default":"dwindle","id":"default_layout","new":"scrolling","old":"dwindle","op":"set","ts":1700000000}
{"backend":"hypr-lua","default":3,"id":"gaps_in","new":8,"old":3,"op":"set","ts":1700000001}
{"backend":"hypr-lua","default":"slave","id":"master_new_status","new":"master","old":"slave","op":"set","ts":1700000002}
EOF

# Undo the stale (most recent) entry: skipped, journaled out, exit success.
capture_out undo
assert_exit "$CODE" 0 "undo of stale entry exits 0"
OUT="$(run history --json)"
assert_not_contains "$OUT" "master_new_status" "stale entry removed from journal"

# An entry whose recorded value is no longer a valid option is also skipped.
cat > "$OMASET_JOURNAL" <<'EOF'
{"backend":"workspace-layout","id":"workspace_layout","key":"2","new":"master","old":"master","op":"set","ts":1700000003}
EOF
capture_out undo
assert_exit "$CODE" 0 "undo of invalid-value entry exits 0"
OUT="$(run history --json)"
assert_contains "$OUT" '"history":[]' "invalid-value entry removed from journal"

# undo --all skips stale entries and still undoes the good ones.
cat > "$OMASET_JOURNAL" <<'EOF'
{"backend":"hypr-lua","default":"slave","id":"master_new_status","new":"master","old":"slave","op":"set","ts":1700000004}
{"backend":"hypr-lua","default":3,"id":"gaps_in","new":8,"old":3,"op":"set","ts":1700000005}
EOF
capture_out undo --all
assert_exit "$CODE" 0 "undo --all exits 0"
assert_contains "$OUT" '"undone":1' "undo --all undoes the good entry"
OUT="$(run history --json)"
assert_contains "$OUT" '"history":[]' "journal cleared after undo --all"

echo "ok"
