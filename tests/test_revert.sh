#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Fake hyprctl that reports config errors, so the write must be reverted.
FAKE="$(mktemp -d)"
trap 'rm -rf "$TESTDIR" "$FAKE"' EXIT
cat > "$FAKE/hyprctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "configerrors" ]]; then
  echo "ERROR: invalid value"
  exit 1
fi
exit 0
EOF
chmod +x "$FAKE/hyprctl"

unset OMASET_NO_APPLY
export PATH="$FAKE:$PATH"

capture set gaps_out 99
assert_exit "$CODE" 1 "set fails when config errors"
assert_contains "$OUT" "reverted" "revert message reported"

file="$(cat "$OMASET_HYPR_DIR/looknfeel.lua")"
assert_not_contains "$file" "gaps_out = 99" "bad value not left in file"

# The setting is back to the default after the revert.
capture_out get gaps_out
assert_eq "$OUT" '{"id":"gaps_out","value":7}' "read after revert"

echo "ok"
