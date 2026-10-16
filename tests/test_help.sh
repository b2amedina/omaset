#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

OUT="$(run help default_layout)"
assert_contains "$OUT" "options: dwindle, master, scrolling" "help default_layout lists options"

OUT="$(run help gaps_in)"
assert_contains "$OUT" "0..30" "help gaps_in shows range"

OUT="$(run set default_layout --help)"
assert_contains "$OUT" "<dwindle|master|scrolling>" "set --help shows value hint"

capture set default_layout bogus
assert_exit "$CODE" 1 "bad enum rejected"
assert_contains "$OUT" "dwindle" "enum error lists valid options"

echo "ok"
