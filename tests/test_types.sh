#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# int above max
capture set gaps_in 999
assert_exit "$CODE" 1 "int above max rejected"

# int below min
capture set gaps_in -1
assert_exit "$CODE" 1 "int below min rejected"

# non-integer
capture set gaps_in abc
assert_exit "$CODE" 1 "non-int rejected"

# enum: invalid rejected, valid accepted
capture set default_layout bogus
assert_exit "$CODE" 1 "bad enum rejected"
capture set default_layout scrolling
assert_exit "$CODE" 0 "valid enum accepted"

# bool: valid accepted, invalid rejected
capture set blur true
assert_exit "$CODE" 0 "bool true accepted"
capture set blur maybe
assert_exit "$CODE" 1 "bad bool rejected"

# time: 24h and 12h accepted and canonicalized, garbage rejected.
capture_out set nightlight_start 21:30
assert_contains "$OUT" '"value":"21:30"' "24h time accepted"
capture_out set nightlight_start "8:30 PM"
assert_contains "$OUT" '"value":"20:30"' "12h time canonicalized"
capture set nightlight_start 25:00
assert_exit "$CODE" 1 "hour out of range rejected"
capture set nightlight_start "8:60 PM"
assert_exit "$CODE" 1 "minute out of range rejected"
capture set nightlight_start noon
assert_exit "$CODE" 1 "garbage time rejected"

# int with labelled choices (follow_mouse): labels and numbers both map to the
# stored int, and values outside the declared set are rejected.
capture_out set follow_mouse full
assert_exit "$CODE" 0 "int choice label accepted"
assert_contains "$OUT" '"value":1' "int choice label maps to value"
capture_out set follow_mouse 2
assert_exit "$CODE" 0 "int choice number accepted"
assert_contains "$OUT" '"value":2' "int choice number stored"
capture set follow_mouse 9
assert_exit "$CODE" 1 "int choice out-of-set rejected"
capture set follow_mouse bogus
assert_exit "$CODE" 1 "int choice bad label rejected"

echo "ok"
