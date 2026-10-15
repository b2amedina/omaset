#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --version
OUT="$(run --version)"
assert_eq "$OUT" "omaset 0.1.0" "version string"

# global --help lists commands
OUT="$(run --help)"
assert_contains "$OUT" "omaset list" "global help lists list"
assert_contains "$OUT" "omaset changed" "global help lists changed"

# per-command --help
OUT="$(run set --help)"
assert_contains "$OUT" "omaset set" "set --help"

# unknown command exits nonzero
capture bogus
assert_exit "$CODE" 1 "unknown command exit code"
assert_contains "$OUT" "unknown command" "unknown command message"

# unknown setting exits nonzero
capture get nope
assert_exit "$CODE" 1 "unknown setting exit code"

# set with missing value exits nonzero
capture set gaps_in
assert_exit "$CODE" 1 "missing value exit code"

echo "ok"
