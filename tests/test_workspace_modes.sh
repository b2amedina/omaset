#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

unset OMASET_NO_APPLY
export OMASET_WORKSPACE_MODES=1

FAKE="$(mktemp -d)"
ST="$(mktemp -d)"
MW="$(mktemp -d)"
trap 'rm -rf "$TESTDIR" "$FAKE" "$ST" "$MW"' EXIT

# Fake `omarchy-hyprland-workspace-layout-current`: read the mode from the
# persisted state file, falling back to the default file, then to dwindle.
cat > "$FAKE/omarchy-hyprland-workspace-layout-current" <<EOF
#!/bin/bash
id="\$1"
f="$ST/\$id.lua"
mode=""
if [[ -f "\$f" ]]; then
  mode=\$(sed -n 's/.*mode = "\([a-z]*\)".*/\1/p' "\$f")
fi
if [[ -z "\$mode" && -f "$ST/default.lua" ]]; then
  mode=\$(sed -n 's/.*default = "\([a-z]*\)".*/\1/p' "$ST/default.lua")
fi
echo "\${mode:-dwindle}"
EOF

cat > "$FAKE/omarchy-hyprland-workspace-layout-default" <<EOF
#!/bin/bash
if [[ -f "$ST/default.lua" ]]; then
  sed -n 's/.*default = "\([a-z]*\)".*/\1/p' "$ST/default.lua"
else
  echo dwindle
fi
EOF

# Fake hyprctl: open workspaces (with a negative special id and monitor names)
# and the connected monitors.
cat > "$FAKE/hyprctl" <<'EOF'
#!/bin/bash
if [[ "$1" == "workspaces" && "$2" == "-j" ]]; then
  echo '[{"id":3,"monitor":"eDP-1"},{"id":-98,"monitor":"eDP-1"},{"id":12,"monitor":"DP-10"},{"id":11,"monitor":"DP-10"},{"id":1,"monitor":"eDP-1"}]'
fi
if [[ "$1" == "monitors" && "$2" == "-j" ]]; then
  echo '[{"name":"eDP-1","make":"Lenovo","model":"Panel"},{"name":"DP-10","make":"LG","model":"Ultrawide"}]'
fi
exit 0
EOF
chmod +x "$FAKE"/*

# Monitor -> block state file (what Omarchy's monitor-workspaces writes).
printf '0\teDP-1\tLenovo Panel\n1\tDP-10\tLG Ultrawide\n' > "$MW/monitor-workspaces"

export PATH="$FAKE:$PATH"
export OMASET_WORKSPACE_LAYOUTS_DIR="$ST"
export OMASET_MONITOR_WORKSPACES_FILE="$MW/monitor-workspaces"

# keys lists open workspace ids numerically sorted, dropping negative (special)
# ids, and carries the monitor grouping.
OUT="$(run keys workspace_layout --json)"
assert_eq "$(echo "$OUT" | jq -r '.keys | join(",")')" "1,3,11,12" "keys drops negative ids"
assert_not_contains "$OUT" "-98" "special workspace excluded"
assert_contains "$OUT" '"monitors":[' "keys reports monitors"

# Monitors carry name, block, and their workspaces (first five slots + any
# that exist), matching the bar.
assert_eq "$(echo "$OUT" | jq -r '[.monitors[].name] | join(",")')" "eDP-1,DP-10" "monitor names"
assert_eq "$(echo "$OUT" | jq -r '.monitors[] | select(.name=="eDP-1") | .block')" "0" "eDP-1 block"
assert_eq "$(echo "$OUT" | jq -r '.monitors[] | select(.name=="DP-10") | .workspaces | join(",")')" \
  "11,12,13,14,15" "DP-10 workspaces (first five)"

# A monitor filter returns that monitor's workspaces.
OUT="$(run keys workspace_layout DP-10 --json)"
assert_eq "$(echo "$OUT" | jq -r '.monitor')" "DP-10" "monitor filter echoed"
assert_eq "$(echo "$OUT" | jq -r '.keys | join(",")')" "11,12,13,14,15" "monitor filter keys"

# Unknown monitor is rejected.
capture keys workspace_layout NOPE
assert_exit "$CODE" 1 "unknown monitor rejected"

# Human output lists monitor names when grouped.
OUT="$(run keys workspace_layout)"
assert_contains "$OUT" "eDP-1" "human lists monitor names"
assert_contains "$OUT" "DP-10" "human lists each monitor"

# get reads via the -current command (falls back to dwindle).
capture_out get workspace_layout 2
assert_eq "$OUT" '{"id":"workspace_layout","key":"2","value":"dwindle"}' "get workspace 2 default"

# set persists an o.workspace_mode file.
capture_out set workspace_layout 3 floating
assert_eq "$OUT" '{"id":"workspace_layout","key":"3","ok":true,"value":"floating"}' "set workspace 3"
assert_eq "$(cat "$ST/3.lua")" 'o.workspace_mode({ workspace = "3", mode = "floating" })' "mode persisted"

# get now reports floating for workspace 3.
capture_out get workspace_layout 3
assert_eq "$OUT" '{"id":"workspace_layout","key":"3","value":"floating"}' "get workspace 3 floating"

# Writing the default deletes the file (mirrors the toggle script).
capture_out set workspace_layout 3 dwindle
assert_eq "$OUT" '{"id":"workspace_layout","key":"3","ok":true,"value":"dwindle"}' "set workspace 3 dwindle"
assert_eq "$([ -f "$ST/3.lua" ] && echo present || echo gone)" "gone" "default deletes the file"

# Legacy-format files are overwritten, not misread: seed one, then set.
printf 'hl.workspace_rule({ workspace = "4", layout = "scrolling" })\n' > "$ST/4.lua"
# get goes through -current, which cannot parse the legacy form and falls
# back to dwindle; a subsequent set rewrites it in the new form.
capture_out get workspace_layout 4
assert_eq "$OUT" '{"id":"workspace_layout","key":"4","value":"dwindle"}' "legacy file reads as default"
capture_out set workspace_layout 4 scrolling
assert_eq "$(grep -c 'o.workspace_mode' "$ST/4.lua")" "1" "legacy file overwritten in new form"

# reset removes the file; reset --all ignores default.lua.
run set workspace_layout 5 floating
printf 'o.workspace_mode({ default = "floating" })\n' > "$ST/default.lua"
capture_out reset workspace_layout --all
assert_eq "$OUT" '{"count":2,"id":"workspace_layout","ok":true}' "reset --all resets numeric keys only"
assert_eq "$([ -f "$ST/default.lua" ] && echo present || echo gone)" "present" "default.lua untouched"

# help shows the 4.5 options.
OUT="$(run help workspace_layout)"
assert_contains "$OUT" "dwindle, scrolling, floating" "help shows modes options"
assert_not_contains "$OUT" "master" "help has no master"

echo "ok"
