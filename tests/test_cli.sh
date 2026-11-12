#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --version
OUT="$(run --version)"
assert_eq "$OUT" "omaset $VERSION" "version string"

# global --help lists commands and advertises --help availability
OUT="$(run --help)"
assert_contains "$OUT" "omaset list" "global help lists list"
assert_contains "$OUT" "omaset changed" "global help lists changed"
assert_contains "$OUT" "Every command accepts --help" "global help advertises --help"

# --help works for every command, not just get/set/reset
for c in list schema changed search keys help ui history undo rollback preferences ui-float hyprsunset-apply; do
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

# Search matches the resolved language, not just English labels. The engine
# resolves OMASET_LANGUAGE before the desktop language file, so a bare checkout
# without Omarchy installed still reads the shipped catalogs.
OUT="$(OMASET_LANGUAGE=es-MX run search "espacio interior" --json)"
assert_contains "$OUT" '"id":"gaps_in"' "search finds the Spanish label of gaps_in"
assert_eq "$(OMASET_LANGUAGE=en run search "espacio interior" --json | jq -r '.results | length')" "0" \
  "English search does not match a Spanish-only label"

# Accent- and case-insensitive matching ("écart" finds the French "Écart").
OUT="$(OMASET_LANGUAGE=fr run search "ecart" --json)"
assert_contains "$OUT" '"id":"gaps_in"' "search folds accents and case"

# Option labels are searchable (both the stored token's display name and the
# translated one).
OUT="$(run search master --json)"
assert_contains "$OUT" '"id":"workspace_layout"' "search finds an enum option label"
assert_contains "$OUT" '"id":"default_layout"' "search finds a second enum option label"
OUT="$(OMASET_LANGUAGE=es-MX run search "Maestro" --json)"
assert_contains "$OUT" '"id":"workspace_layout"' "search finds a translated option label"

# Panel titles are searchable.
OUT="$(run search appearance --json)"
assert_eq "$(echo "$OUT" | jq -r '[.results[] | select(.panel == "appearance")] | length > 0')" "true" \
  "search matches a panel title"
assert_eq "$(echo "$OUT" | jq -r '[.results[] | select(.panel != "appearance")] | length')" "0" \
  "a panel-title match only returns that panel"

OUT="$(run changed --json)"
assert_eq "$(echo "$OUT" | jq -r '.changed | type')" "array" "changed results are a JSON array"

echo "ok"
