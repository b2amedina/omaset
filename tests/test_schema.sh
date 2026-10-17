#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

OUT="$(run schema)"

echo "$OUT" | jq empty || fail "schema is not valid JSON"

# At least the built-in panels are present.
assert_eq "$(echo "$OUT" | jq -r '.panels | length >= 4')" "true" "at least four panels"

# Known panels exist by id.
for p in appearance layout power display; do
  assert_eq "$(echo "$OUT" | jq -r --arg id "$p" '[.panels[].id] | index($id) != null')" "true" "panel $p present"
done

assert_eq "$(echo "$OUT" | jq -r '[.panels[].settings[] | (has("id") and has("type") and has("value"))] | all')" "true" "settings expose id/type/value"

# Every built-in setting lives in a section (no unsectioned orphans).
assert_eq "$(echo "$OUT" | jq -r '[.panels[].settings[] | (.section != null)] | all')" "true" "every setting has a section"

# Groupbar settings carry the Groupbar section label.
assert_eq "$(echo "$OUT" | jq -r '[.panels[].settings[] | select(.id | startswith("groupbar_")) | .section == "Groupbar"] | all')" "true" "groupbar settings are sectioned"

# The animations panel is gone; animations_enabled lives under Appearance.
assert_eq "$(echo "$OUT" | jq -r '[.panels[].id] | index("animations") == null')" "true" "animations panel removed"
assert_eq "$(echo "$OUT" | jq -r '.panels[] | select(.id=="appearance") | [.settings[].id] | index("animations_enabled") != null')" "true" "animations_enabled in appearance"

# The omarchy passthrough toggles declare a stock default so they count as
# "changed" when on.
for id in nightlight window_no_gaps single_window_square; do
  assert_eq "$(echo "$OUT" | jq -r --arg id "$id" '[.panels[].settings[] | select(.id==$id) | .default] | .[0]')" \
    "false" "$id declares default=false"
done

echo "ok"
