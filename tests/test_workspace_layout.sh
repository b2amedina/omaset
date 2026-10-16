#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The workspace-layout backend shells out to hyprctl, so use a fake and unset
# the no-apply guard.
unset OMASET_NO_APPLY

FAKE="$(mktemp -d)"
ST="$(mktemp -d)"
trap 'rm -rf "$TESTDIR" "$FAKE" "$ST"' EXIT

cat > "$FAKE/hyprctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "workspaces" && "$2" == "-j" ]]; then
  echo '[{"id":1,"tiledLayout":"dwindle"},{"id":2,"tiledLayout":"scrolling"},{"id":3,"tiledLayout":"master"}]'
fi
exit 0
EOF
chmod +x "$FAKE/hyprctl"

export PATH="$FAKE:$PATH"
export OMASET_WORKSPACE_LAYOUTS_DIR="$ST"

# keys lists the open workspace ids.
OUT="$(run keys workspace_layout)"
assert_eq "$OUT" $'1\n2\n3' "keys lists workspace ids"

# get reads a specific workspace's layout.
capture_out get workspace_layout 2
assert_eq "$OUT" '{"id":"workspace_layout","key":"2","value":"scrolling"}' "get workspace 2"

# set persists a rule.
capture_out set workspace_layout 3 scrolling
assert_eq "$OUT" '{"id":"workspace_layout","key":"3","ok":true,"value":"scrolling"}' "set workspace 3"
assert_eq "$(cat "$ST/3.lua")" 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })' "rule persisted"

# changed lists per-workspace deviations.
OUT="$(run changed)"
assert_contains "$OUT" "workspace_layout:2" "changed lists workspace 2"
assert_contains "$OUT" "workspace_layout:3" "changed lists workspace 3"
assert_not_contains "$OUT" "nightlight" "runtime toggle not in changed"

# reset removes the rule.
run reset workspace_layout 3
assert_eq "$([ -f "$ST/3.lua" ] && echo present || echo gone)" "gone" "rule removed on reset"

# key validation.
capture get workspace_layout
assert_exit "$CODE" 1 "missing key rejected"
capture get workspace_layout abc
assert_exit "$CODE" 1 "non-integer key rejected"
capture get workspace_layout '2;rm'
assert_exit "$CODE" 1 "injection-shaped key rejected"

# help shows key type and options.
OUT="$(run help workspace_layout)"
assert_contains "$OUT" "workspace (int)" "help shows key type"
assert_contains "$OUT" "dwindle, master, scrolling" "help shows options"

# help and get/set/reset --help all indicate the required key.
OUT="$(run help workspace_layout)"
assert_contains "$OUT" "get workspace_layout <workspace>" "help shows get usage with key"
assert_contains "$OUT" "set workspace_layout <workspace> <dwindle|master|scrolling>" "help shows set usage with key"

OUT="$(run get workspace_layout --help)"
assert_contains "$OUT" "<workspace>" "get --help shows key"
OUT="$(run set workspace_layout --help)"
assert_contains "$OUT" "<workspace>" "set --help shows key"
OUT="$(run reset workspace_layout --help)"
assert_contains "$OUT" "<workspace>" "reset --help shows key"

echo "ok"
