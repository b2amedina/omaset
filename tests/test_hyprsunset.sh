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

# schedule off by default (no managed block).
capture_out get nightlight_schedule
assert_eq "$OUT" '{"id":"nightlight_schedule","value":false}' "schedule off by default"

# temperature falls back to the default when no schedule is set.
capture_out get nightlight_temperature
assert_eq "$OUT" '{"id":"nightlight_temperature","value":4000}' "temperature defaults to 4000"
capture_out get nightlight_start
assert_eq "$OUT" '{"id":"nightlight_start","value":"20:00"}' "start defaults to 20:00"
capture_out get nightlight_stop
assert_eq "$OUT" '{"id":"nightlight_stop","value":"07:00"}' "stop defaults to 07:00"

# enabling the schedule adds managed night + identity profiles.
capture_out set nightlight_schedule true
assert_contains "$(cat "$CFG")" "temperature = 4000" "managed profile written"
assert_contains "$(cat "$CFG")" "identity = true" "identity profile written"
assert_contains "$(cat "$CFG")" "time = 07:00" "user profile preserved"

capture_out get nightlight_schedule
assert_eq "$OUT" '{"id":"nightlight_schedule","value":true}' "schedule on after set"

# start/stop times are written as their own profiles.
capture_out set nightlight_start 21:30
assert_contains "$(cat "$CFG")" "time = 21:30" "start time written"
capture_out get nightlight_start
assert_eq "$OUT" '{"id":"nightlight_start","value":"21:30"}' "start time read back"

# 12-hour input is accepted and stored canonical.
capture_out set nightlight_stop "6:45 AM"
assert_contains "$(cat "$CFG")" "time = 06:45" "stop time canonicalized"
capture_out get nightlight_stop
assert_eq "$OUT" '{"id":"nightlight_stop","value":"06:45"}' "stop time read back"

# a start equal to the stop is rejected.
capture set nightlight_start 06:45
assert_exit "$CODE" 1 "start == stop rejected"

# reset start restores its default inside the existing block.
capture_out reset nightlight_start
assert_contains "$(cat "$CFG")" "time = 20:00" "start reset to default"

# apply is a no-op under OMASET_NO_APPLY (tests) and reports ok.
capture_out hyprsunset-apply
assert_eq "$OUT" "ok" "hyprsunset-apply ok"

# changing temperature updates the managed profile.
capture_out set nightlight_temperature 3500
assert_contains "$(cat "$CFG")" "temperature = 3500" "temperature updated"
capture_out get nightlight_temperature
assert_eq "$OUT" '{"id":"nightlight_temperature","value":3500}' "temperature read back"

# A rewrite must not swallow the line after the end marker.
printf '# trailing user comment\n' >> "$CFG"
run set nightlight_temperature 3300
assert_contains "$(cat "$CFG")" "# -- omaset:end
# trailing user comment" "handwritten line after block preserved"

# reset temperature reverts to the default.
capture_out reset nightlight_temperature
assert_contains "$(cat "$CFG")" "temperature = 4000" "temperature reset"

# disabling the schedule removes the managed block but keeps user content.
capture_out reset nightlight_schedule
assert_not_contains "$(cat "$CFG")" "temperature" "managed profile removed"
assert_contains "$(cat "$CFG")" "time = 07:00" "user profile intact"

echo "ok"
