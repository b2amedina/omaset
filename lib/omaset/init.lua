-- omaset core: settings registry, schema, and backend access.
--
-- The CLI (cli.lua), MCP server (mcp.lua), and RPC server (rpc.lua) are all
-- adapters over this core and service.lua. Nothing in this file formats output
-- or parses command-line arguments.

local json = require("omaset.json")
local dsl = require("omaset.dsl")
local discovery = require("omaset.discovery")
local backends = require("omaset.backends")

local M = {}

local function jnull(v)
  if v == nil then
    return json.null
  end
  return v
end

local function grouped(setting)
  return setting.subsettings ~= nil
end

local function sub_keys(setting)
  local keys = {}
  for k in pairs(setting.subsettings) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- Exposed so the service and CLI adapters share the same group helpers.
M.grouped = grouped
M.sub_keys = sub_keys

-- Sort a panel's settings: keep settings of the same section contiguous, sort
-- each section's settings by id, and order the sections (the nil-section
-- included) by their alphabetically-first member id. Deterministic, so list /
-- schema / search / changed / the UI all agree.
local function sort_panel_settings(settings)
  local groups = {}
  local order = {}
  for _, s in ipairs(settings) do
    local sec = s.section or ""
    if not groups[sec] then
      groups[sec] = {}
      order[#order + 1] = sec
    end
    groups[sec][#groups[sec] + 1] = s
  end
  for _, list in pairs(groups) do
    table.sort(list, function(a, b) return a.id < b.id end)
  end
  table.sort(order, function(a, b) return groups[a][1].id < groups[b][1].id end)
  local out = {}
  for _, sec in ipairs(order) do
    for _, s in ipairs(groups[sec]) do
      out[#out + 1] = s
    end
  end
  return out
end

local root = nil
local user_settings_dir = nil
local user_backends_dir = nil

function M.bootstrap(opts)
  root = opts.root
  user_settings_dir = opts.user_settings_dir
  user_backends_dir = opts.user_backends_dir
end

function M.load_backends()
  for _, err in ipairs(backends.load_dir(root .. "/lib/omaset/backends")) do
    io.stderr:write("omaset: " .. err .. "\n")
  end
  for _, err in ipairs(backends.load_dir(user_backends_dir)) do
    io.stderr:write("omaset: " .. err .. "\n")
  end
end

function M.settings_dirs()
  local dirs = { root .. "/share/settings" }
  if user_settings_dir and user_settings_dir ~= "" then
    dirs[#dirs + 1] = user_settings_dir
  end
  return dirs
end

function M.load()
  M.load_backends()
  dsl.panels = {}
  local errors = discovery.load_dirs(M.settings_dirs())
  for _, err in ipairs(errors) do
    io.stderr:write("omaset: " .. err .. "\n")
  end
  for _, p in ipairs(dsl.panels) do
    p.settings = sort_panel_settings(p.settings)
  end
  return dsl.panels
end

function M.panels()
  return dsl.panels
end

function M.find_setting(id)
  for _, p in ipairs(dsl.panels) do
    for _, s in ipairs(p.settings) do
      if s.id == id then
        return s, p
      end
    end
  end
end

function M.backend_for(setting)
  local backend = backends.get(setting.backend)
  if not backend then
    return nil, "unknown backend '" .. tostring(setting.backend) .. "'"
  end
  return backend
end

function M.read_value(setting, key)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.read(setting, key)
end

function M.write_value(setting, key, value)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.write(setting, key, value)
end

function M.read_default(setting, key)
  if grouped(setting) then
    local sub = key and setting.subsettings[key]
    if sub then
      return sub.default
    end
    return nil
  end
  -- A setting may declare its own default (e.g. an `omarchy` passthrough
  -- toggle whose stock state the backend cannot recompute). It wins over the
  -- backend's read_default.
  if setting.default ~= nil then
    return setting.default
  end
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.read_default(setting, key)
end

function M.reset_value(setting, key)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.reset(setting, key)
end

function M.keys(setting)
  if grouped(setting) then
    return sub_keys(setting)
  end
  local backend = M.backend_for(setting)
  if not backend or not backend.keys then
    return nil
  end
  return backend.keys(setting)
end

function M.keys_all(setting)
  if grouped(setting) then
    return sub_keys(setting)
  end
  local backend = M.backend_for(setting)
  if not backend then
    return nil
  end
  if backend.keys_all then
    return backend.keys_all(setting)
  end
  if backend.keys then
    return backend.keys(setting)
  end
  return nil
end

-- A keyed setting's monitor grouping (e.g. per-monitor workspace layouts on
-- Omarchy 4.5+), or nil when the setting has no monitor dimension.
function M.monitors(setting)
  local backend = M.backend_for(setting)
  if not backend or not backend.monitors then
    return nil
  end
  return backend.monitors(setting)
end

-- Version of the settings schema that `schema` emits, independent of the
-- engine version (M.VERSION): a consumer that renders the schema checks it and
-- refuses a version it does not understand, so an engine and a frontend can
-- evolve separately without silently mis-rendering. Bump it only when the
-- shape changes incompatibly -- additive fields keep the same version.
M.SCHEMA_VERSION = 1

-- A numeric codepoint as its UTF-8 string (panel icons are declared as
-- codepoints so the Lua source stays portable across Lua 5.1).
local function utf8_char(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
  else
    return string.char(0xE0 + math.floor(cp / 0x1000),
      0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
  end
end

function M.schema()
  local out = { schemaVersion = M.SCHEMA_VERSION, panels = {} }
  for _, p in ipairs(dsl.panels) do
    local icon = p.icon
    if type(icon) == "number" then icon = utf8_char(icon) end
    local panel = { id = p.id, title = p.title, icon = icon, settings = {} }
    for _, s in ipairs(p.settings) do
      local entry = {}
      for k, v in pairs(s) do
        if k ~= "get" and k ~= "set" and type(v) ~= "function" then
          entry[k] = v
        end
      end
      if s.keyed or grouped(s) then
        entry.value = json.null
        if grouped(s) then
          entry.grouped = true
          -- Group sub-values are cheap to read (file-based backends), so carry
          -- them in the schema: the UI can render them at their real values
          -- instead of flashing the declared default and then jumping.
          local subvalues = {}
          for _, k in ipairs(sub_keys(s)) do
            subvalues[k] = jnull(M.read_value(s, k))
          end
          entry.subvalues = subvalues
        end
      else
        entry.value = jnull(M.read_value(s))
      end
      panel.settings[#panel.settings + 1] = entry
    end
    out.panels[#out.panels + 1] = panel
  end
  return out
end

M.VERSION = "0.2.3"

return M
