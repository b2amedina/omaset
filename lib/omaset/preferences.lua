-- omaset's own UI preferences. Deliberately separate from the Omarchy settings
-- model: preferences are omaset-internal config with no "Omarchy stock
-- default", so they never appear in the settings panels, `search`, or
-- `changed`.

local util = require("omaset.util")
local json = require("omaset.json")
local types = require("omaset.types")

local M = {}

M.VERSION = 1

-- Ordered schema. `type` is one of types.lua's (int/float/bool), plus optional
-- min/max for numbers.
M.SCHEMA = {
  {
    key = "refresh_interval_sec",
    type = "int",
    label = "Refresh interval (seconds)",
    description = "How often the settings window re-reads values while visible.",
    default = 2,
    min = 1,
    max = 60,
  },
  {
    key = "launch_floating",
    type = "bool",
    label = "Launch floating",
    description = "Open the settings window floating so it can be moved and resized.",
    default = true,
  },
}

local function path()
  return os.getenv("OMASET_PREFERENCES")
    or (os.getenv("HOME") or "") .. "/.config/omaset/preferences.json"
end

local function spec_for(key)
  for _, s in ipairs(M.SCHEMA) do
    if s.key == key then
      return s
    end
  end
end

-- Stored overrides: only keys the user set explicitly (unset keys fall back to
-- their declared default). A missing or malformed file reads as {}.
local function read_overrides()
  local content = util.read_file(path())
  if not content then
    return {}
  end
  local parsed = json.decode(content)
  if type(parsed) ~= "table" then
    return {}
  end
  local overrides = {}
  for _, s in ipairs(M.SCHEMA) do
    local v = parsed[s.key]
    if v ~= nil and v ~= json.null then
      overrides[s.key] = v
    end
  end
  return overrides
end

local function write_overrides(overrides)
  local data = { version = M.VERSION }
  for k, v in pairs(overrides) do
    data[k] = v
  end
  local p = path()
  local dir = p:match("^(.*)/")
  if dir then
    util.run_capture("mkdir -p " .. util.shell_quote(dir))
  end
  return util.write_file(p, json.encode(data) .. "\n")
end

-- Effective value for one key (override or default).
function M.get(key)
  local spec = spec_for(key)
  if not spec then
    return nil, "unknown preference: " .. tostring(key)
  end
  local overrides = read_overrides()
  local v = overrides[key]
  if v == nil then
    v = spec.default
  end
  return v
end

-- Every preference, in schema order, with its effective value.
function M.list()
  local overrides = read_overrides()
  local out = {}
  for _, s in ipairs(M.SCHEMA) do
    local entry = {}
    for k, v in pairs(s) do
      entry[k] = v
    end
    entry.value = overrides[s.key]
    if entry.value == nil then
      entry.value = s.default
    end
    out[#out + 1] = entry
  end
  return out
end

-- Coerce + validate a string value and persist it. Returns the stored value,
-- or nil plus an error message.
function M.set(key, value_str)
  local spec = spec_for(key)
  if not spec then
    return nil, "unknown preference: " .. tostring(key)
  end
  local value, err = types.coerce(value_str, spec)
  if value == nil then
    return nil, err
  end
  local ok, rerr = types.check_range(value, spec)
  if not ok then
    return nil, rerr
  end
  local overrides = read_overrides()
  overrides[key] = value
  local wok, werr = write_overrides(overrides)
  if not wok then
    return nil, werr
  end
  return value
end

-- Remove a stored override so the declared default applies again. Returns the
-- default, or nil plus an error message.
function M.reset(key)
  local spec = spec_for(key)
  if not spec then
    return nil, "unknown preference: " .. tostring(key)
  end
  local overrides = read_overrides()
  overrides[key] = nil
  local wok, werr = write_overrides(overrides)
  if not wok then
    return nil, werr
  end
  return spec.default
end

return M
