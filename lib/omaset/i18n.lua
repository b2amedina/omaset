-- omaset engine i18n: language resolution, catalog lookup, plurals, and
-- locale number formatting. Mirrors Omarchy's own i18n design:
--
-- * The locale registry is Omarchy's default/i18n/locales.json — omaset
--   never duplicates it (codes, direction, decimal, zeroDigit).
-- * Catalogs are flat i18n/<code>.json files owned by omaset. A key is
--   resolved en -> base -> language, matching Commons.Translations.
-- * Language precedence (first valid wins):
--     --lang override > OMASET_LANGUAGE > OMARCHY_LANGUAGE_FILE file
--     > ~/.config/omarchy/language > en
-- * Plural rules mirror Omarchy's plural.jq / Plural.js exactly, and number
--   formatting mirrors Numbers.js (decimal separator + digit shape), so the
--   engine and the window agree on every language.
--
-- Only human-facing strings localize. Values, command names, flags, JSON
-- and --plain output, and the MCP contract stay English.

local json = require("omaset.json")
local util = require("omaset.util")

local M = {}

-- Catalog/registry caches live here so _reset() (tests) can clear them.
local S = {
  override = nil,      -- code set by --lang (string) or nil
  registry = nil,      -- parsed locales.json or {}
  catalogs = {},       -- code -> { en=..., base=..., lang=..., merged=... }
}

-- ---- locale registry (Omarchy's, never duplicated) -----------------------

local function registry_path()
  return os.getenv("OMASET_LOCALES_JSON")
    or (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy")
    .. "/default/i18n/locales.json"
end

local function load_registry()
  if S.registry ~= nil then
    return S.registry
  end
  local content = util.read_file(registry_path())
  local parsed = content and json.decode(content)
  if type(parsed) ~= "table" or next(parsed) == nil then
    -- Tests point OMARCHY_PATH at fixtures without locales.json; the
    -- registry is read-only, so fall back to the installed copy.
    local fallback = "/usr/share/omarchy/default/i18n/locales.json"
    if registry_path() ~= fallback then
      local alt = util.read_file(fallback)
      local alt_parsed = alt and json.decode(alt)
      if type(alt_parsed) == "table" and next(alt_parsed) ~= nil then
        parsed = alt_parsed
      end
    end
  end
  if type(parsed) ~= "table" then
    parsed = {}
  end
  S.registry = parsed
  return parsed
end

local function valid_code(code)
  if type(code) ~= "string" or code == "" then
    return false
  end
  if code:match("^[a-z]+$") then
    local len = #code
    return len >= 2 and len <= 3
  end
  local base, region = code:match("^([a-z]+)%-([A-Z][A-Z])$")
  if base and region then
    return #base >= 2 and #base <= 3
  end
  return false
end

local function is_known(code)
  if not valid_code(code) then
    return false
  end
  local reg = load_registry()
  if next(reg) == nil then
    -- Registry unreadable (bare checkout without Omarchy installed): accept
    -- the shape so catalogs still resolve; codes are validated in tests.
    return true
  end
  return reg[code] ~= nil
end

-- ---- language resolution --------------------------------------------------

local function language_file_path()
  local f = os.getenv("OMARCHY_LANGUAGE_FILE")
  if f and f ~= "" then
    return f
  end
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then
    return xdg .. "/omarchy/language"
  end
  return (os.getenv("HOME") or "") .. "/.config/omarchy/language"
end

local function read_language_file()
  local content = util.read_file(language_file_path())
  if not content then
    return nil
  end
  local code = content:match("^[^\n]*")
  if code then
    code = code:gsub("%s+", "")
    if code ~= "" then
      return code
    end
  end
  return nil
end

function M.set_override(code)
  if code ~= nil and not valid_code(code) then
    return nil, "invalid language code: " .. tostring(code)
  end
  S.override = code
  S.catalogs = {}
  return true
end

function M.get_override()
  return S.override
end

function M.current_language()
  if S.override ~= nil then
    if is_known(S.override) then
      return S.override
    end
    return "en"
  end
  local env = os.getenv("OMASET_LANGUAGE")
  if env and is_known(env) then
    return env
  end
  local from_file = read_language_file()
  if from_file and is_known(from_file) then
    return from_file
  end
  return "en"
end

-- The desktop language: the file alone, with no --lang/env override. The
-- settings window follows this by default; `omaset ui` writes a one-shot
-- override (ui_language_file) when the effective language differs, and the
-- window reads it for that launch only.
function M.os_language()
  local from_file = read_language_file()
  if from_file and is_known(from_file) then
    return from_file
  end
  return "en"
end

-- One-shot window override file (omaset-private, never the OS language
-- file). The UI reads it at open; `omaset ui` writes or clears it
-- before summoning, so a launch always starts from the OS language
-- unless this exact launch was overridden.
function M.ui_language_file()
  local f = os.getenv("OMASET_UI_LANGUAGE_FILE")
  if f and f ~= "" then
    return f
  end
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then
    return xdg .. "/omaset/ui-language"
  end
  return (os.getenv("HOME") or "") .. "/.config/omaset/ui-language"
end

function M.write_ui_override(code)
  if not is_known(code) then
    return nil, "unknown language code: " .. tostring(code)
  end
  local path = M.ui_language_file()
  local dir = path:match("^(.*)/")
  if dir and dir ~= "" then
    util.run_capture("mkdir -p " .. util.shell_quote(dir))
  end
  return util.write_file(path, code .. "\n")
end

function M.clear_ui_override()
  os.remove(M.ui_language_file())
  return true
end

function M.read_ui_override()
  local content = util.read_file(M.ui_language_file())
  if not content then
    return nil
  end
  local code = content:match("^[^\n]*")
  if code then
    code = code:gsub("%s+", "")
    if code ~= "" and is_known(code) then
      return code
    end
  end
  return nil
end

-- Test-only resets.
function M._reset()
  S.override = nil
  S.registry = nil
  S.catalogs = {}
end

function M.base_language(code)
  code = code or M.current_language()
  local base = code:match("^[^%-]+")
  return base or code
end

-- ---- catalogs -------------------------------------------------------------

-- Locate the i18n catalog directory. Env wins; otherwise derive the repo
-- root from this file's own path so a symlinked bin/omaset still finds the
-- catalogs next to lib/.
local function root_from_source()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  local root = src:match("^(.*)/lib/omaset/i18n%.lua$")
  if root then
    return root
  end
  if src:match("^lib/omaset/i18n%.lua$") then
    return "."
  end
  local root2 = src:match("^(.+)/lib/omaset/i18n%.lua$")
  if root2 then
    return root2
  end
  return nil
end

function M.catalog_dir()
  local d = os.getenv("OMASET_I18N_DIR")
  if d and d ~= "" then
    return d
  end
  local root = os.getenv("OMASET_ROOT") or root_from_source()
  if root then
    local candidate = root .. "/i18n"
    if util.file_exists(candidate .. "/en.json") then
      return candidate
    end
    candidate = root .. "/ui/i18n"
    if util.file_exists(candidate .. "/en.json") then
      return candidate
    end
    return root .. "/i18n"
  end
  return "i18n"
end

local function parse_catalog_file(code)
  local path = M.catalog_dir() .. "/" .. code .. ".json"
  local content = util.read_file(path)
  if not content then
    return {}
  end
  local parsed = json.decode(content)
  if type(parsed) ~= "table" then
    return {}
  end
  return parsed
end

local function catalogs_for(code)
  code = code or M.current_language()
  local cached = S.catalogs[code]
  if cached then
    return cached
  end
  local en = parse_catalog_file("en")
  local base_code = M.base_language(code)
  local base = {}
  local lang = {}
  if code == "en" then
    lang = en
    base = en
  else
    if base_code ~= code and base_code ~= "en" then
      base = parse_catalog_file(base_code)
    else
      base = {}
    end
    lang = parse_catalog_file(code)
  end
  local merged = {}
  for k, v in pairs(en) do merged[k] = v end
  for k, v in pairs(base) do merged[k] = v end
  for k, v in pairs(lang) do merged[k] = v end
  local entry = { en = en, base = base, lang = lang, merged = merged }
  S.catalogs[code] = entry
  return entry
end

function M.registry()
  return load_registry()
end

function M.locale_settings(code)
  code = code or M.current_language()
  local reg = load_registry()
  local e = reg[code]
  if type(e) ~= "table" then
    return { formatLocale = "en-US", decimal = ".", zeroDigit = "0", direction = "ltr" }
  end
  return {
    formatLocale = e.formatLocale or "en-US",
    decimal = e.decimal or ".",
    zeroDigit = e.zeroDigit or "0",
    direction = e.direction or "ltr",
  }
end

function M.decimal()
  return M.locale_settings().decimal
end

function M.zero_digit()
  return M.locale_settings().zeroDigit
end

function M.is_rtl()
  return M.locale_settings().direction == "rtl"
end

function M.format_locale()
  return M.locale_settings().formatLocale
end

function M.list_languages()
  local reg = load_registry()
  local out = {}
  for code, e in pairs(reg) do
    if type(e) == "table" and type(e.name) == "string" then
      out[#out + 1] = { code = code, name = e.name, englishName = e.englishName or e.name }
    end
  end
  table.sort(out, function(a, b)
    if a.code == "en" then return true end
    if b.code == "en" then return false end
    return (a.englishName or a.code) < (b.englishName or b.code)
  end)
  return out
end

-- ---- number formatting (ports Numbers.js) ---------------------------------

local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
  end
  return string.char(0xE0 + math.floor(cp / 0x1000),
    0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
end

-- Codepoint of the first character in s (zeroDigit is one character).
local function first_codepoint(s)
  local b1 = s:byte(1)
  if not b1 then
    return nil
  end
  if b1 < 0x80 then
    return b1
  elseif b1 < 0xE0 then
    local b2 = s:byte(2)
    if not b2 then return b1 end
    return (b1 - 0xC0) * 0x40 + (b2 - 0x80)
  end
  local b2 = s:byte(2) or 0x80
  local b3 = s:byte(3) or 0x80
  return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
end

function M.format_number(value, decimals)
  local n = tonumber(value)
  if n == nil then
    return tostring(value)
  end
  local text
  if decimals ~= nil then
    text = string.format("%." .. tostring(decimals) .. "f", n)
  else
    text = string.format("%.14g", n)
  end
  local settings = M.locale_settings()
  local decimal = settings.decimal
  if decimal and decimal ~= "." then
    local dot = text:find(".", 1, true)
    if dot then
      text = text:sub(1, dot - 1) .. decimal .. text:sub(dot + 1)
    end
  end
  local zero_digit = settings.zeroDigit
  if zero_digit and zero_digit ~= "0" then
    local zero_cp = first_codepoint(zero_digit)
    if zero_cp then
      text = text:gsub("[0-9]", function(c)
        return utf8_encode(zero_cp + (c:byte(1) - 48))
      end)
    end
  end
  return text
end

-- ---- plurals (ports Plural.js / plural.jq) ---------------------------------

local function within(v, lo, hi)
  return v >= lo and v <= hi
end

function M.plural_category(code, count)
  local n = math.abs(math.floor(tonumber(count) or 0))
  local n10 = n % 10
  local n100 = n % 100
  local millions = (n ~= 0 and n % 1000000 == 0)
  code = tostring(code or "")
  local function one_of(...)
    for _, c in ipairs({ ... }) do
      if c == code then return true end
    end
    return false
  end
  if one_of("ja", "ko", "zh-CN", "zh-TW", "th", "vi", "id", "ms") then
    return "other"
  elseif one_of("hi", "bn", "fa", "si") then
    return (n <= 1) and "one" or "other"
  elseif one_of("fr", "pt-BR") then
    return (n <= 1) and "one" or (millions and "many" or "other")
  elseif one_of("ca", "es-MX", "it", "pt") then
    return (n == 1) and "one" or (millions and "many" or "other")
  elseif code == "fil" then
    return (n10 == 4 or n10 == 6 or n10 == 9) and "other" or "one"
  elseif code == "is" then
    return (n10 == 1 and n100 ~= 11) and "one" or "other"
  elseif one_of("cs", "sk") then
    return (n == 1) and "one" or (within(n, 2, 4) and "few" or "other")
  elseif code == "pl" then
    if n == 1 then return "one" end
    return (within(n10, 2, 4) and not within(n100, 12, 14)) and "few" or "many"
  elseif one_of("ru", "uk") then
    if n10 == 1 and n100 ~= 11 then return "one" end
    return (within(n10, 2, 4) and not within(n100, 12, 14)) and "few" or "many"
  elseif one_of("hr", "sr") then
    if n10 == 1 and n100 ~= 11 then return "one" end
    return (within(n10, 2, 4) and not within(n100, 12, 14)) and "few" or "other"
  elseif code == "sl" then
    if n100 == 1 then return "one" end
    if n100 == 2 then return "two" end
    return within(n100, 3, 4) and "few" or "other"
  elseif code == "lt" then
    if within(n100, 11, 19) then return "other" end
    return n10 == 1 and "one" or (n10 >= 2 and "few" or "other")
  elseif code == "lv" then
    if n10 == 0 or within(n100, 11, 19) then return "zero" end
    return n10 == 1 and "one" or "other"
  elseif code == "ro" then
    if n == 1 then return "one" end
    return (n == 0 or within(n100, 1, 19)) and "few" or "other"
  elseif code == "ar" then
    if n <= 2 then return ({ "zero", "one", "two" })[n + 1] end
    return within(n100, 3, 10) and "few" or (within(n100, 11, 99) and "many" or "other")
  elseif code == "he" then
    return (n == 1) and "one" or (n == 2 and "two" or "other")
  elseif code == "ga" then
    if n <= 2 then
      if n == 0 then return "other" end
      if n == 1 then return "one" end
      return "two"
    end
    return within(n, 3, 6) and "few" or (within(n, 7, 10) and "many" or "other")
  end
  return (n == 1) and "one" or "other"
end

local PLURAL_ORDER = { "zero", "one", "two", "few", "many", "other" }

function M.plural_categories(code)
  local seen = { other = true }
  for n = 0, 1000 do
    seen[M.plural_category(code, n)] = true
  end
  seen[M.plural_category(code, 1000000)] = true
  local out = {}
  for _, name in ipairs(PLURAL_ORDER) do
    if seen[name] then
      out[#out + 1] = name
    end
  end
  return out
end

local function pick_plural(entry, code, count)
  if type(entry) == "string" then
    return entry
  end
  if type(entry) ~= "table" then
    return nil
  end
  local form = entry[M.plural_category(code, count)]
  if type(form) == "string" and form ~= "" then
    return form
  end
  if type(entry.other) == "string" and entry.other ~= "" then
    return entry.other
  end
  return nil
end

-- ---- lookup ---------------------------------------------------------------

-- Raw template for key, with %1 holes (caller substitutes via format).
-- Falls back to `fallback` when the key is untranslated, then to the key.
function M.t(key, fallback)
  local merged = catalogs_for().merged
  local value = merged[key]
  if type(value) == "string" and value ~= "" then
    return value
  end
  if type(value) == "table" then
    if type(value.other) == "string" and value.other ~= "" then
      return value.other
    end
    if fallback ~= nil then
      return fallback
    end
    return key
  end
  if fallback ~= nil then
    return fallback
  end
  return key
end

local function subst(template, args)
  if not template then
    return template
  end
  local out = tostring(template)
  -- Sentinels avoid double-substitution when an argument itself contains
  -- a %N sequence (mirrors omarchy-i18n).
  for i, a in ipairs(args) do
    if a ~= nil then
      local formatted
      if type(a) == "number" then
        formatted = M.format_number(a)
      else
        formatted = tostring(a)
      end
      out = out:gsub("%%" .. i, string.char(1) .. tostring(i) .. string.char(2), 1)
      -- stash formatted for the second pass
      args[i] = formatted
    end
  end
  for i = 1, #args do
    if args[i] ~= nil then
      local needle = string.char(1) .. tostring(i) .. string.char(2)
      local value = args[i]
      out = out:gsub(needle, function() return value end, 1)
    end
  end
  return out
end

-- Substituted string for key (percent args are locale-formatted numbers).
function M.format(key, fallback, ...)
  local args = { ... }
  return subst(M.t(key, fallback), args)
end

-- Plural-aware lookup: picks the form for `count`, then substitutes %1
-- with the locale-formatted count (extra args fill %2..). The layer that
-- carries the entry decides which language's rules apply.
function M.tn(key, count, fallback, ...)
  local lang = M.current_language()
  local base = M.base_language(lang)
  local cats = catalogs_for(lang)
  local layers = {
    { cats.lang, lang },
    { cats.base, base },
    { cats.en, "en" },
  }
  local template = nil
  for _, layer in ipairs(layers) do
    local entry = layer[1][key]
    if entry ~= nil then
      template = pick_plural(entry, layer[2], count)
      if template then
        break
      end
    end
  end
  if not template then
    if fallback ~= nil then
      if type(fallback) == "table" then
        template = pick_plural(fallback, lang, count) or fallback.other or ""
      else
        template = fallback
      end
    else
      template = key
    end
  end
  local args = { count }
  for _, a in ipairs({ ... }) do
    args[#args + 1] = a
  end
  return subst(template, args)
end

return M
