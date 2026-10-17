#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Preferences are omaset's own config, isolated to a scratch file via
# OMASET_PREFERENCES (set by helpers.sh).

# Defaults apply when no file exists.
capture_out preferences get refresh_interval_sec
assert_eq "$OUT" '{"key":"refresh_interval_sec","value":2}' "default refresh interval"
capture_out preferences get launch_floating
assert_eq "$OUT" '{"key":"launch_floating","value":true}' "default launch floating"

# list reports both, in schema order.
capture_out preferences --json
assert_eq "$(echo "$OUT" | jq -r '.preferences | length')" "2" "two preferences"
assert_eq "$(echo "$OUT" | jq -r '.preferences[0].key')" "refresh_interval_sec" "ordered first"
assert_eq "$(echo "$OUT" | jq -r '.preferences[0].default')" "2" "default surfaced"

# set persists and round-trips.
capture_out preferences set refresh_interval_sec 5
assert_eq "$OUT" '{"key":"refresh_interval_sec","ok":true,"value":5}' "set refresh interval"
capture_out preferences get refresh_interval_sec
assert_eq "$OUT" '{"key":"refresh_interval_sec","value":5}' "get after set"

# a second preference coexists.
capture_out preferences set launch_floating false
capture_out preferences get launch_floating
assert_eq "$OUT" '{"key":"launch_floating","value":false}' "set launch floating"

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

# --plain prints bare values.
capture_out preferences get launch_floating --plain
assert_eq "$OUT" "false" "get --plain"

echo "ok"
