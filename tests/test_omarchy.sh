#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The omarchy passthrough backend runs real commands, so unset the no-apply
# guard and point it at a fake toggle+status command instead.
unset OMASET_NO_APPLY

FAKE="$(mktemp -d)"
SETDIR="$(mktemp -d)"
trap 'rm -rf "$TESTDIR" "$FAKE" "$SETDIR"' EXIT
STATE="$FAKE/state"

cat > "$FAKE/fakecmd" <<EOF
#!/bin/bash
if [[ "\$1" == "--status" ]]; then
  cat "$STATE" 2>/dev/null || echo false
else
  if [[ "\$(cat "$STATE" 2>/dev/null)" == true ]]; then
    echo false > "$STATE"
  else
    echo true > "$STATE"
  fi
fi
EOF
chmod +x "$FAKE/fakecmd"

cat > "$SETDIR/flag.lua" <<EOF
panel("test", "Test", function()
  setting({
    id = "flag",
    type = "bool",
    label = "Flag",
    backend = "omarchy",
    mode = "toggle",
    command = "$FAKE/fakecmd",
    status = "$FAKE/fakecmd --status",
  })
end)
EOF

export OMASET_SETTINGS_DIR="$SETDIR"

# Initial state is false.
capture_out get flag
assert_eq "$OUT" '{"id":"flag","value":false}' "initial flag false"

# Toggle on.
capture_out set flag true
assert_eq "$OUT" '{"id":"flag","ok":true,"value":true}' "set flag true"
capture_out get flag
assert_eq "$OUT" '{"id":"flag","value":true}' "flag now true"

# Redundant set is a no-op (state unchanged).
capture_out set flag true
assert_eq "$(cat "$STATE")" "true" "state unchanged after redundant set"

# Toggle off.
capture_out set flag false
capture_out get flag
assert_eq "$OUT" '{"id":"flag","value":false}' "flag now false"

echo "ok"
