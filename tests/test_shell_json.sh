#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

capture_out get idle_lock
assert_eq "$OUT" '{"id":"idle_lock","value":120}' "default idle_lock from fixture"

capture_out set idle_lock 600
assert_eq "$OUT" '{"id":"idle_lock","ok":true,"value":600}' "set idle_lock"
capture_out get idle_lock
assert_eq "$OUT" '{"id":"idle_lock","value":600}' "read after set"

# Shape is preserved (version, bar.position).
assert_eq "$(jq -r '.version' "$OMASET_SHELL_CONFIG")" "1" "version preserved"
assert_eq "$(jq -r '.bar.position' "$OMASET_SHELL_CONFIG")" "top" "bar.position preserved"
assert_eq "$(jq -r '.idle.lock' "$OMASET_SHELL_CONFIG")" "600" "idle.lock written"

OUT="$(run changed)"
assert_contains "$OUT" "idle_lock" "changed lists idle_lock"

run reset idle_lock
capture_out get idle_lock
assert_eq "$OUT" '{"id":"idle_lock","value":120}' "read after reset"

echo "ok"
