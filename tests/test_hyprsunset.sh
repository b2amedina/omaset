#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

CFG="$OMASET_HYPRSUNSET_CONFIG"

cat > "$CFG" <<'EOF'
# user's own profile
profile {
    time = 07:00
    identity = true
}
EOF

# schedule off by default (no temperature profile anywhere).
capture_out get nightlight_schedule
assert_eq "$OUT" '{"id":"nightlight_schedule","value":false}' "schedule off by default"

# temperature/start/stop fall back to defaults when nothing is set.
capture_out get nightlight_temperature
assert_eq "$OUT" '{"id":"nightlight_temperature","value":4000}' "temperature defaults"
capture_out get nightlight_start
assert_eq "$OUT" '{"id":"nightlight_start","value":"20:00"}' "start defaults"
capture_out get nightlight_stop
assert_eq "$OUT" '{"id":"nightlight_stop","value":"07:00"}' "stop defaults"

# enabling appends a night profile; the user's identity profile stays as the
# stop and there is no managed block.
capture_out set nightlight_schedule true
assert_contains "$(cat "$CFG")" "temperature = 4000" "night profile written"
assert_contains "$(cat "$CFG")" "identity = true" "identity profile present"
assert_contains "$(cat "$CFG")" "time = 07:00" "user profile preserved"
assert_not_contains "$(cat "$CFG")" "# -- omaset" "no managed block markers"
capture_out get nightlight_schedule
assert_eq "$OUT" '{"id":"nightlight_schedule","value":true}' "schedule on after set"

# start/stop/temperature edit in place.
capture_out set nightlight_start 21:30
assert_contains "$(cat "$CFG")" "time = 21:30" "start written"
capture_out set nightlight_stop "6:45 AM"
assert_contains "$(cat "$CFG")" "time = 06:45" "stop canonicalized"
capture_out get nightlight_stop
assert_eq "$OUT" '{"id":"nightlight_stop","value":"06:45"}' "stop read back"

# a start equal to the stop is rejected.
capture set nightlight_start 06:45
assert_exit "$CODE" 1 "start == stop rejected"

# reset start restores its default in place.
capture_out reset nightlight_start
assert_contains "$(cat "$CFG")" "time = 20:00" "start reset"

# apply is a no-op under OMASET_NO_APPLY (tests) and reports ok.
capture_out hyprsunset-apply
assert_eq "$OUT" "ok" "hyprsunset-apply ok"

# changing temperature updates the night profile in place.
capture_out set nightlight_temperature 3500
assert_contains "$(cat "$CFG")" "temperature = 3500" "temperature updated"
capture_out get nightlight_temperature
assert_eq "$OUT" '{"id":"nightlight_temperature","value":3500}' "temperature read back"
capture_out reset nightlight_temperature
assert_contains "$(cat "$CFG")" "temperature = 4000" "temperature reset"

# disabling removes the night profile but keeps the user's profile.
capture_out reset nightlight_schedule
assert_not_contains "$(cat "$CFG")" "temperature" "night profile removed"
assert_contains "$(cat "$CFG")" "identity = true" "user profile intact"
capture_out get nightlight_schedule
assert_eq "$OUT" '{"id":"nightlight_schedule","value":false}' "schedule off after reset"

# whole-file read: a hand-written temperature profile is what get reports.
cat > "$CFG" <<'EOF'
profile {
    time = 22:00
    temperature = 3200
}
EOF
capture_out get nightlight_temperature
assert_eq "$OUT" '{"id":"nightlight_temperature","value":3200}' "hand-edited temperature read"
capture_out get nightlight_schedule
assert_eq "$OUT" '{"id":"nightlight_schedule","value":true}' "hand-edited schedule read"
capture_out get nightlight_start
assert_eq "$OUT" '{"id":"nightlight_start","value":"22:00"}' "hand-edited start read"

echo "ok"
