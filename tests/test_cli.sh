#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --version
OUT="$(run --version)"
assert_eq "$OUT" "omaset 0.2.0" "version string"

# global --help lists commands and advertises --help availability
OUT="$(run --help)"
assert_contains "$OUT" "omaset list" "global help lists list"
assert_contains "$OUT" "omaset changed" "global help lists changed"
assert_contains "$OUT" "Every command accepts --help" "global help advertises --help"

# --help works for every command, not just get/set/reset
for c in list schema changed search keys help ui history undo rollback preferences; do
  OUT="$(run "$c" --help)"
  assert_contains "$OUT" "omaset $c" "$c --help works"
done

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

# Empty result sets must encode as JSON arrays, not empty objects. Lua tables
# are ambiguous, so the encoder needs an explicit array marker for the empty
# case; a downstream consumer (the settings UI) breaks on `{}` where it
# expects `[]`.
OUT="$(run search zzz --json)"
assert_eq "$(echo "$OUT" | jq -r '.results | type')" "array" "empty search results are a JSON array"
assert_eq "$(echo "$OUT" | jq -r '.results | length')" "0" "empty search results are empty"
OUT="$(run changed --json)"
assert_eq "$(echo "$OUT" | jq -r '.changed | type')" "array" "changed results are a JSON array"

echo "ok"
