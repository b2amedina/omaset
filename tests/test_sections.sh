#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# A settings file with out-of-order ids and a section, to exercise the
# per-panel sort (sections stay contiguous, settings sorted by id) and the
# section field surfacing in the schema.
cat > "$OMASET_SETTINGS_DIR/sections.lua" <<'LUA'
panel("sectest", "Section Test", function()
  setting({ id = "zeta", type = "bool", label = "Zeta", backend = "hypr-lua", file = "looknfeel", path = "general.gaps_in" })
  section("Alpha group", function()
    setting({ id = "bravo", type = "bool", label = "Bravo", backend = "hypr-lua", file = "looknfeel", path = "general.gaps_in" })
    setting({ id = "alpha_sub", type = "bool", label = "Alpha Sub", backend = "hypr-lua", file = "looknfeel", path = "general.gaps_in" })
  end)
  setting({ id = "alpha", type = "bool", label = "Alpha", backend = "hypr-lua", file = "looknfeel", path = "general.gaps_in" })
end)
LUA

OUT="$(run schema)"

# Section label is surfaced on the setting.
assert_eq "$(echo "$OUT" | jq -r '.panels[] | select(.id=="sectest") | .settings[] | select(.id=="alpha_sub") | .section')" \
  "Alpha group" "section field present"

# Order: unsectioned { alpha, zeta } then "Alpha group" { alpha_sub, bravo }.
assert_eq "$(echo "$OUT" | jq -r '.panels[] | select(.id=="sectest") | [.settings[].id] | join(" ")')" \
  "alpha zeta alpha_sub bravo" "settings sorted with sections contiguous"

# list shows a section heading.
OUT="$(run list)"
assert_contains "$OUT" "# Alpha group" "list shows section heading"

echo "ok"
