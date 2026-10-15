#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

OUT="$(run schema)"

echo "$OUT" | jq empty || fail "schema is not valid JSON"

# At least the built-in panels are present.
assert_eq "$(echo "$OUT" | jq -r '.panels | length >= 4')" "true" "at least four panels"

# Known panels exist by id.
for p in appearance layout animations power display; do
  assert_eq "$(echo "$OUT" | jq -r --arg id "$p" '[.panels[].id] | index($id) != null')" "true" "panel $p present"
done

assert_eq "$(echo "$OUT" | jq -r '[.panels[].settings[] | (has("id") and has("type") and has("value"))] | all')" "true" "settings expose id/type/value"

echo "ok"
