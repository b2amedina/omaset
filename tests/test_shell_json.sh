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

# A pre-existing private shell.json must stay private through a write, even
# under a permissive umask (022), and the write must not leave a .tmp sibling.
umask 022
printf '{"version":1,"bar":{"position":"top"},"plugins":[]}\n' > "$OMASET_SHELL_CONFIG"
chmod 600 "$OMASET_SHELL_CONFIG"
capture_out set bar_position bottom
assert_eq "$(stat -c %a "$OMASET_SHELL_CONFIG")" "600" "shell.json keeps 0600 through a write"
assert_eq "$(jq -r '.bar.position' "$OMASET_SHELL_CONFIG")" "bottom" "bar_position updated"
assert_eq "$(find "$TESTDIR" -maxdepth 1 -name 'shell.json.tmp' | wc -l)" "0" "no shell.json.tmp leftover"
assert_eq "$(stat -c %a "$OMASET_SHELL_CONFIG.omaset.bak")" "600" "shell.json backup is 0600"

echo "ok"
