#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Preferences are omaset's own config, isolated to a scratch file via
# OMASET_PREFERENCES (set by helpers.sh).

# Defaults apply when no file exists.
capture_out preferences get refresh_interval_sec
assert_eq "$OUT" '{"key":"refresh_interval_sec","value":2}' "default refresh interval"
capture_out preferences get launch_floating
assert_eq "$OUT" '{"key":"launch_floating","value":true}' "default launch floating"

# list reports all, in schema order, plus the engine version.
capture_out preferences --json
assert_eq "$(echo "$OUT" | jq -r '.preferences | length')" "3" "three preferences"
assert_eq "$(echo "$OUT" | jq -r '.preferences[0].key')" "refresh_interval_sec" "ordered first"
assert_eq "$(echo "$OUT" | jq -r '.preferences[0].default')" "2" "default surfaced"
assert_eq "$(echo "$OUT" | jq -r '.version')" "0.2.3" "engine version surfaced"

# set persists and round-trips.
capture_out preferences set refresh_interval_sec 5
assert_eq "$OUT" '{"key":"refresh_interval_sec","ok":true,"value":5}' "set refresh interval"
capture_out preferences get refresh_interval_sec
assert_eq "$OUT" '{"key":"refresh_interval_sec","value":5}' "get after set"

# a second preference coexists.
capture_out preferences set launch_floating false
capture_out preferences get launch_floating
assert_eq "$OUT" '{"key":"launch_floating","value":false}' "set launch floating"

# --json reflects a false boolean override (not the default). This regressed
# when list() used `cond and value or default`, which collapses false -> default.
capture_out preferences --json
assert_eq "$(echo "$OUT" | jq -r '.preferences[] | select(.key=="launch_floating") | .value')" "false" "--json shows false override"

# reset removes the override so the default returns.
capture_out preferences reset refresh_interval_sec
assert_eq "$OUT" '{"key":"refresh_interval_sec","ok":true,"value":2}' "reset returns default"
capture_out preferences get refresh_interval_sec
assert_eq "$OUT" '{"key":"refresh_interval_sec","value":2}' "get after reset"
capture_out preferences get launch_floating
assert_eq "$OUT" '{"key":"launch_floating","value":false}' "other preference unaffected by reset"

# invalid key / value are rejected with a nonzero exit.
capture preferences get nope
assert_exit "$CODE" 1 "unknown preference key rejected"
capture preferences set refresh_interval_sec 999
assert_exit "$CODE" 1 "out-of-range value rejected"
capture preferences set refresh_interval_sec notanumber
assert_exit "$CODE" 1 "non-integer value rejected"

# time_format is an enum defaulting to auto, which resolves against the
# (absent) test shell.json to 24h.
capture_out preferences get time_format
assert_eq "$OUT" '{"key":"time_format","value":"auto"}' "time_format defaults to auto"
capture_out preferences --json
assert_eq "$(echo "$OUT" | jq -r '.preferences[] | select(.key=="time_format") | .resolved')" "24h" "auto resolves to 24h without a bar clock"
assert_eq "$(echo "$OUT" | jq -r '.preferences[] | select(.key=="time_format") | .options | join(",")')" "24h,12h,auto" "time_format lists options"

capture_out preferences set time_format 12h
assert_eq "$OUT" '{"key":"time_format","ok":true,"value":"12h"}' "set time_format"
capture preferences set time_format bogus
assert_exit "$CODE" 1 "invalid enum value rejected"

# A clock format carrying the AM/PM token resolves auto to 12h.
mkdir -p "$TESTDIR"
cat > "$OMASET_SHELL_CONFIG" <<'EOF'
{ "bar": { "position": "top", "layout": { "center": [ { "id": "omarchy.clock", "format": "ddd d MMM h:mm AP" } ] } } }
EOF
capture_out preferences set time_format auto
capture_out preferences --json
assert_eq "$(echo "$OUT" | jq -r '.preferences[] | select(.key=="time_format") | .resolved')" "12h" "auto resolves 12h from bar clock"

capture_out preferences reset time_format
assert_eq "$OUT" '{"key":"time_format","ok":true,"value":"auto"}' "reset time_format"

# --plain prints bare values.
capture_out preferences get launch_floating --plain
assert_eq "$OUT" "false" "get --plain"

echo "ok"
