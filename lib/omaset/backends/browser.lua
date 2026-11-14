-- Backend for the browser-router configuration (~/.config/browser-router/config.json).
--
-- Exposes the browser settings the Browsers panel renders:
--   browser_<id>_enabled : bool, whether the browser is enabled
--   browser_<id>_label   : string, its display label (nil when unset)
--   browser_rules        : keyed enum, domain -> browser id
--
-- Reads and writes the same JSON the `omaset browser` commands manage, so the
-- CLI, the window, and an agent all see the same state.

local util = require("omaset.util")
local json = require("omaset.json")
local types = require("omaset.types")
local registry = require("omaset.backends")
local browser = require("omaset.browser")

local M = {}

local function apply_enabled()
  local v = os.getenv("OMASET_NO_APPLY")
  return not (v == "1" or v == "true" or v == "yes" or v == "on")
end

-- Parse the browser id out of a setting id.
local function parse_id(setting_id)
  local id = setting_id:match("^browser_(.+)_label$")
  if id then return id, "label" end
  id = setting_id:match("^browser_(.+)_enabled$")
  if id then return id, "enabled" end
  return nil, nil
end

function M.read(setting, key)
  local cfg, err = browser.read()
  if not cfg then return nil end
  local id, kind = parse_id(setting.id)
  if id and kind == "label" then
    return (cfg.labels or {})[id]
  end
  if id and kind == "enabled" then
    return browser.is_enabled(cfg, id)
  end
  if setting.id == "browser_rules" then
    if key == nil then return nil end
    for _, r in ipairs(cfg.rules or {}) do
      if r.domain == key then return r.browser end
    end
    return nil
  end
  return nil
end

function M.read_default(setting, key)
  local id, kind = parse_id(setting.id)
  if id then
    if kind == "enabled" then return false end
    if kind == "label" then return nil end
  end
  if setting.id == "browser_rules" then return nil end
  return nil
end

function M.write(setting, key, value)
  if not apply_enabled() then
    return true
  end
  local cfg, err = browser.read()
  if not cfg then return nil, err end
  local id, kind = parse_id(setting.id)
  if id and kind == "label" then
    browser.set_label(cfg, id, value)
    return browser.write(cfg)
  end
  if id and kind == "enabled" then
    local ok, werr
    if value then
      ok, werr = browser.enable(cfg, id)
    else
      ok, werr = browser.disable(cfg, id)
    end
    if not ok then return nil, werr end
    return browser.write(cfg)
  end
  if setting.id == "browser_rules" then
    if key == nil then
      return nil, "browser_rules requires a domain key"
    end
    if value == nil then
      browser.remove_rule(cfg, { key })
    else
      browser.edit_rule(cfg, key, key, value)
    end
    return browser.write(cfg)
  end
  return nil, "unknown setting: " .. tostring(setting.id)
end

function M.reset(setting, key)
  if not apply_enabled() then
    return true
  end
  local cfg, err = browser.read()
  if not cfg then return nil, err end
  local id, kind = parse_id(setting.id)
  if id and kind == "label" then
    browser.set_label(cfg, id, nil)
    return browser.write(cfg)
  end
  if id and kind == "enabled" then
    browser.disable(cfg, id)
    return browser.write(cfg)
  end
  if setting.id == "browser_rules" then
    if key == nil then
      return nil, "browser_rules requires a domain key"
    end
    browser.remove_rule(cfg, { key })
    return browser.write(cfg)
  end
  return nil, "unknown setting: " .. tostring(setting.id)
end

function M.keys(setting)
  if setting.id ~= "browser_rules" then
    return nil
  end
  local cfg, err = browser.read()
  if not cfg then return {} end
  local out = {}
  local seen = {}
  for _, r in ipairs(cfg.rules or {}) do
    local d = r.domain
    if d and not seen[d] then
      seen[d] = true
      out[#out + 1] = d
    end
  end
  return out
end

function M.keys_all(setting)
  return M.keys(setting)
end

function M.monitors(setting)
  return nil
end

-- An enum must be one of its declared options or a custom value it has held.
function M.validate(setting, value, key, customs)
  return types.check_allowed(setting, value, customs)
end

registry.register("browser", M)

return M