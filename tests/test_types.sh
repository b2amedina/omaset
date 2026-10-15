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
capture set layout bogus
assert_exit "$CODE" 1 "bad enum rejected"
capture set layout scrolling
assert_exit "$CODE" 0 "valid enum accepted"

# bool: valid accepted, invalid rejected
capture set blur true
assert_exit "$CODE" 0 "bool true accepted"
capture set blur maybe
assert_exit "$CODE" 1 "bad bool rejected"

echo "ok"
