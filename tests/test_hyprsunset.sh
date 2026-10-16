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

# enabling the schedule adds a managed night profile.
capture_out set nightlight_schedule true
assert_contains "$(cat "$CFG")" "temperature = 4000" "managed profile written"
assert_contains "$(cat "$CFG")" "time = 07:00" "user profile preserved"

capture_out get nightlight_schedule
assert_eq "$OUT" '{"id":"nightlight_schedule","value":true}' "schedule on after set"

# changing temperature updates the managed profile.
capture_out set nightlight_temperature 3500
assert_contains "$(cat "$CFG")" "temperature = 3500" "temperature updated"
capture_out get nightlight_temperature
assert_eq "$OUT" '{"id":"nightlight_temperature","value":3500}' "temperature read back"

# reset temperature reverts to the default.
capture_out reset nightlight_temperature
assert_contains "$(cat "$CFG")" "temperature = 4000" "temperature reset"

# disabling the schedule removes the managed block but keeps user content.
capture_out reset nightlight_schedule
assert_not_contains "$(cat "$CFG")" "temperature" "managed profile removed"
assert_contains "$(cat "$CFG")" "time = 07:00" "user profile intact"

echo "ok"
