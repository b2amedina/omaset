#!/usr/bin/env bash
# Validate the i18n catalogs against the canonical English (i18n/en.json):
# every registry language has a file, every file parses, covers exactly the
# English keys, preserves %N placeholders, and carries the plural categories
# its language needs (mirroring Omarchy's i18n-test.sh agreement between the
# Lua port and plural.jq).

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

run() {
  lua5.1 "$OMASET" "$@"
}

# 1. Canonical English is up to date with the schema.
if ! "$ROOT/scripts/i18n-extract" --check > /dev/null; then
  fail "i18n/en.json is stale (run scripts/i18n-extract)"
fi

# 2. Catalog checks (Python for JSON/plural logic; Lua policy for categories).
python3 - "$ROOT" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
i18n_dir = root / "i18n"

import os
locales_path = Path(os.environ.get(
    "OMASET_LOCALES_JSON",
    os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"),
                 "default/i18n/locales.json"),
))
if not locales_path.exists():
    locales_path = Path("/usr/share/omarchy/default/i18n/locales.json")
locales = json.loads(locales_path.read_text(encoding="utf-8"))
en = json.loads((i18n_dir / "en.json").read_text(encoding="utf-8"))

def placeholders(text):
    return set(re.findall(r"%(\d+)", text))

def placeholders_of(entry):
    if isinstance(entry, dict):
        found = set()
        for v in entry.values():
            found |= placeholders(v)
        return found
    return placeholders(entry)

def plural_categories(code):
    env = dict(os.environ); env["I18N_CODE"] = code
    out = subprocess.check_output([
        "lua5.1", "-e",
        'package.path="lib/?.lua;lib/?/init.lua;"..package.path;'
        'local i=require("omaset.i18n");'
        'for _,c in ipairs(i.plural_categories(os.getenv("I18N_CODE"))) do io.write(c.."\\n") end',
    ], cwd=root, text=True, env=env)
    return [l.strip() for l in out.splitlines() if l.strip()]

failures = []

# Every registry code has exactly one catalog (and no extras).
files = sorted(p.stem for p in i18n_dir.glob("*.json"))
missing_files = sorted(set(locales) - set(files))
extra_files = sorted(set(files) - set(locales))
if missing_files:
    failures.append(f"missing catalogs: {missing_files}")
if extra_files:
    failures.append(f"extra catalogs (not in locales.json): {extra_files}")

for code in sorted(set(files)):
    path = i18n_dir / f"{code}.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        failures.append(f"{code}: invalid JSON: {e}")
        continue
    expected = set(en)
    actual = set(data)
    if expected != actual:
        miss = sorted(expected - actual)
        stale = sorted(actual - expected)
        detail = []
        if miss:
            detail.append(f"missing {miss[:5]}{'...' if len(miss) > 5 else ''} ({len(miss)})")
        if stale:
            detail.append(f"stale {stale[:5]}{'...' if len(stale) > 5 else ''} ({len(stale)})")
        failures.append(f"{code}: key mismatch: {'; '.join(detail)}")
    # Keys are sorted (the extractor's canonical form).
    if list(data.keys()) != sorted(data.keys()):
        failures.append(f"{code}: keys not sorted")
    cats = plural_categories(code) if code in locales else []
    for key in sorted(expected & actual):
        en_entry = en[key]
        other_entry = data[key]
        if placeholders_of(en_entry) != placeholders_of(other_entry):
            failures.append(f"{code}.{key}: placeholder mismatch: {placeholders_of(en_entry)} vs {placeholders_of(other_entry)}")
        if isinstance(en_entry, dict):
            # Plural objects need every category this language can reach.
            if not isinstance(other_entry, dict):
                if cats == ["other"]:
                    pass  # Single-form languages may keep a plain string.
                else:
                    failures.append(f"{code}.{key}: expected plural object {cats}, got string")
            else:
                for cat in cats:
                    form = other_entry.get(cat)
                    if not isinstance(form, str) or form == "":
                        failures.append(f"{code}.{key}: missing plural category '{cat}'")
                if placeholders_of(en_entry) != placeholders_of(other_entry):
                    pass  # Already reported above.
        # Empty strings fall back to English per the resolver, so they are a
        # strictness failure here: untranslated keys must stay English, not "".
        if other_entry == "":
            failures.append(f"{code}.{key}: empty string")

    # RTL sanity: the locales.json direction flags must be coverable — the
    # window mirrors via LayoutMirroring, so every catalog must exist.
    if code in locales and locales[code].get("direction") == "rtl":
        if code not in files:
            failures.append(f"{code}: RTL catalog missing")

if failures:
    for f in failures:
        print(f"  FAIL: {f}", file=sys.stderr)
    sys.exit(1)
print("i18n catalogs ok")
PY
[[ $? -eq 0 ]] || fail "i18n catalog validation failed"

# 3. UI one-shot override lifecycle: write/read/clear, unknown codes, and
#    that the OS language stays untouched.
export OMASET_UI_LANGUAGE_FILE="$TESTDIR/ui-language"
# Pin the OS language source to a nonexistent file so the test never reads
# the host's real ~/.config/omarchy/language (hermetic regardless of the
# machine's language).
export OMARCHY_LANGUAGE_FILE="$TESTDIR/os-language"

# Run the checks via the public CLI:
#  - --lang <code> with no command prints the resolved code
run_out="$(OMASET_UI_LANGUAGE_FILE="$TESTDIR/ui-language" run --lang fr 2>&1)"
[[ "$run_out" == "fr" ]] || fail "expected --lang fr to print fr, got [$run_out]"
lua5.1 "$OMASET" --lang list > /dev/null 2>&1 || fail "--lang list failed"
[[ ! -f "$TESTDIR/ui-language" ]] || fail "ui-language file should not exist after --lang list"

# Direct module checks for the override helpers (write/clear/read, os vs
# effective, unknown code rejection) — run as a script file so require()
# works the same way bin/omaset does it.
cat > "$TESTDIR/check_i18n_ui.lua" <<'LUA'
local root = os.getenv("ROOT") or "."
package.path = root .. "/lib/?.lua;" .. root .. "/lib/?/init.lua;" .. package.path
local i18n = require("omaset.i18n")
local path = i18n.ui_language_file()
assert(path == os.getenv("OMASET_UI_LANGUAGE_FILE"), "env path wins: " .. tostring(path))
-- OS language is the file alone; OMARCHY_LANGUAGE_FILE points at a
-- nonexistent path, so it falls back to en.
assert(i18n.os_language() == "en", "os_language fell back: " .. i18n.os_language())
-- Write + read an override.
local ok, err = i18n.write_ui_override("fr")
assert(ok == true, "write failed: " .. tostring(err))
assert(i18n.read_ui_override() == "fr", "override not read back")
local f = io.open(path)
assert(f, "override file not created")
local code = f:read("*l")
f:close()
assert(code == "fr", "override file content: " .. tostring(code))
-- Clear removes it.
assert(i18n.clear_ui_override() == true)
assert(i18n.read_ui_override() == nil, "override survived clear")
-- Unknown codes are rejected.
local ok2, err2 = i18n.write_ui_override("xx")
assert(ok2 == nil, "unknown code accepted")
assert(tostring(err2):find("xx"), "error lost the code: " .. tostring(err2))
-- effective follows --lang override; os_language does not.
assert(i18n.set_override("fr") == true)
assert(i18n.current_language() == "fr")
assert(i18n.os_language() == "en")
i18n.set_override(nil)
print("ui override ok")
LUA
ROOT="$ROOT" OMARCHY_PATH="$FIXTURES" lua5.1 "$TESTDIR/check_i18n_ui.lua" > /dev/null 2>&1
[[ $? -eq 0 ]] || fail "i18n ui override lifecycle failed"

# 4. Window wiring: the fresh resolver exists, the forked language is
#    bound to the override, and translations are not symlinked.
[[ -f "$ROOT/ui/UiTranslations.qml" ]] || fail "ui/UiTranslations.qml missing"
grep -q 'language: root.uiLanguage' "$ROOT/ui/Panel.qml" \
  || fail "Panel.qml must bind UiTranslations.language to root.uiLanguage"
grep -q 'ui-language' "$ROOT/ui/Panel.qml" \
  || fail "Panel.qml must watch the ui-language override file"
[[ ! -L "$ROOT/i18n/en.json" ]] || fail "catalogs must not be symlinks"
# tn must look up the entry per layer (pick(map[key], …)), not the whole map.
grep -q 'pick(layers\[i\]\[0\]\[key\]' "$ROOT/ui/UiTranslations.qml" \
  || fail "UiTranslations.tn must look up layers[i][0][key]"
# Engine JSON labels stay English; the window localizes them at render.
grep -q 'root.tr.t("setting." + r.id' "$ROOT/ui/Panel.qml" \
  || fail "Panel.qml changedLabel must localize via tr.t"
grep -q 'root.tr.t("setting." + modelData.id' "$ROOT/ui/Panel.qml" \
  || fail "Panel.qml search delegate must localize via tr.t"

echo "ok"
