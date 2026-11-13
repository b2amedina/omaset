#!/usr/bin/env bash
# Values that come from hand-edited files are first-class: they read back as
# they are, they are listed as Custom choices, a setting can be switched back to
# them, and validation is type, range, and the backend's own rule.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SHELL_CFG="$OMASET_SHELL_CONFIG"
JOURNAL="$OMASET_JOURNAL"

write_shell() { printf '%s\n' "$1" > "$SHELL_CFG"; }
journal_lines() { [[ -f $JOURNAL ]] && wc -l < "$JOURNAL" || echo 0; }

# A hand-edited enum value reads back as it is, not as unset.
write_shell '{"version":1,"bar":{"position":"center"}}'
assert_eq "$(run get bar_position | jq -r .value)" "center" "hand-edited enum reads as-is"

# The current value is always an allowed value, so writing it again is a no-op.
: > "$JOURNAL"
capture_out set bar_position center
assert_exit "$CODE" 0 "re-setting the current custom value succeeds"
assert_eq "$(journal_lines)" "0" "idempotent set records no change"

# Switching to a stock value makes the custom value a Custom choice.
capture_out set bar_position top
assert_eq "$(run get bar_position | jq -r .value)" "top" "switched to stock value"
capture_out schema
assert_contains "$(echo "$OUT" | jq -c '.panels[].settings[] | select(.id=="bar_position") | .customOptions')" \
  '["center"]' "replaced custom value is listed as a custom option"

# ...so it can be selected again.
capture_out set bar_position center
assert_exit "$CODE" 0 "switch back to the custom value"
assert_eq "$(run get bar_position | jq -r .value)" "center" "custom value restored"

# A value that was never held is still rejected by the backend.
capture set bar_position nowhere
assert_exit "$CODE" 1 "unknown enum value rejected by the backend"
assert_contains "$OUT" "choose from" "rejection lists the choices"

# Hand-edited numbers within range are valid, even outside the declared choices.
write_shell '{"version":1,"idle":{"lock":1234}}'
capture_out set idle_lock 1234
assert_exit "$CODE" 0 "hand-edited number within range is valid"
capture set idle_lock 100000
assert_exit "$CODE" 1 "number above the maximum is rejected"
capture_out help idle_lock
assert_contains "$OUT" "custom:  1234" "help lists the custom number"

# Numeric choices keep their bounds.
capture_out set follow_mouse 2
assert_exit "$CODE" 0 "in-range choice accepted"
capture set follow_mouse 9
assert_exit "$CODE" 1 "out-of-range choice rejected"

# Values reach the omarchy command quoted, so they cannot run commands.
CMDFILE="$TESTDIR/quoted"
cat > "$OMASET_SETTINGS_DIR/quoting.lua" <<EOF
panel("quoting", "Quoting", function()
  setting({
    id = "quoted_value",
    type = "enum",
    label = "Quoted value",
    backend = "omarchy",
    mode = "value",
    command = "printf '%s' {value} > $CMDFILE",
    options = { "plain" },
  })
end)
EOF
env -u OMASET_NO_APPLY lua5.1 "$OMASET" set quoted_value 'a b; touch '"$TESTDIR"'/PWNED' >/dev/null 2>&1
assert_eq "$(cat "$CMDFILE")" "a b; touch $TESTDIR/PWNED" "value passed to the command as one argument"
assert_eq "$(test -e "$TESTDIR/PWNED" && echo yes || echo no)" "no" "shell metacharacters are not executed"

# A setting with no declared default counts as changed once it has a value.
cat > "$OMASET_SETTINGS_DIR/nodefault.lua" <<'SETTINGS'
panel("nodefault", "No default", function()
  setting({
    id = "nodefault_value",
    type = "string",
    label = "No default",
    backend = "shell-json",
    path = "nodefault.value",
  })
end)
SETTINGS
capture_out changed --json
assert_not_contains "$OUT" "nodefault_value" "unset value without a default is not changed"
capture_out set nodefault_value hello
capture_out changed --json
assert_contains "$OUT" '"id":"nodefault_value"' "set value without a default is changed"

echo "ok"
