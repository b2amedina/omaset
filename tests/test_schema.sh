#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

OUT="$(run schema)"

echo "$OUT" | jq empty || fail "schema is not valid JSON"

assert_eq "$(echo "$OUT" | jq -r '.panels | length')" "4" "four panels"

assert_eq "$(echo "$OUT" | jq -r '[.panels[].settings[] | (has("id") and has("type") and has("value"))] | all')" "true" "settings expose id/type/value"

echo "ok"
