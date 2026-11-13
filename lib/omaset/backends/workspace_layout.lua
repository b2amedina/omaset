-- Backend for per-workspace Hyprland layout, keyed by workspace number.
--
-- Two mechanics depending on the installed Omarchy (see omaset.features):
--
--   * workspace modes (4.5+):  layout is `o.workspace_mode({workspace, mode})`
--     state files in ~/.local/state/omarchy/workspace-layouts/<n>.lua, read via
--     `omarchy-hyprland-workspace-layout-current <n>` and the default via
--     `omarchy-hyprland-workspace-layout-default`. Writing a mode equal to
--     the default deletes the file (mirrors the toggle script).
--   * legacy (pre-4.5): `hl.workspace_rule({workspace, layout})` state files,
--     read from `hyprctl workspaces -j .tiledLayout`.
--
-- RESET deletes the persisted file and restores the default.

local util = require("omaset.util")
local types = require("omaset.types")
local registry = require("omaset.backends")
local features = require("omaset.features")

local M = {}

local function apply_enabled()
  local v = os.getenv("OMASET_NO_APPLY")
  return not (v == "1" or v == "true" or v == "yes" or v == "on")
end

local function modes()
  return features.workspace_modes()
end

local function layouts_dir()
  return os.getenv("OMASET_WORKSPACE_LAYOUTS_DIR")
    or (os.getenv("HOME") or "") .. "/.local/state/omarchy/workspace-layouts"
end

local function state_file(key)
  return layouts_dir() .. "/" .. tostring(key) .. ".lua"
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function run_current(key)
  local out = util.run_capture(
    "omarchy-hyprland-workspace-layout-current " .. util.shell_quote(tostring(key)))
  return trim(out)
end

local function run_default()
  local out = util.run_capture("omarchy-hyprland-workspace-layout-default")
  return trim(out)
end

local function apply_mode_rule(key, value)
  -- Persist first (authoritative), then aim for a live apply. A failed eval
  -- (e.g. config not reloaded yet) leaves the persisted file to take effect
  -- at the next reload, mirroring omarchy-hyprland-workspace-layout-toggle.
  local rule = 'o.workspace_mode({ workspace = "' .. tostring(key) .. '", mode = "' .. tostring(value) .. '" })'
  local out, code = util.run_capture("hyprctl eval " .. util.shell_quote(rule))
  if code ~= 0 then
    io.stderr:write("omaset: warning: could not apply workspace layout live ("
      .. tostring(key) .. " -> " .. tostring(value) .. "); it takes effect on next reload"
      .. (out and out ~= "" and (" (" .. trim(out) .. ")") or "") .. "\n")
  end
end

local function apply_legacy_rule(key, layout)
  local rule = 'hl.workspace_rule({ workspace = "' .. tostring(key) .. '", layout = "' .. tostring(layout) .. '" })'
  local _, code = util.run_capture("hyprctl eval " .. util.shell_quote(rule))
  if code ~= 0 then
    util.run_capture("hyprctl keyword workspace " .. util.shell_quote(tostring(key) .. ", layout:" .. tostring(layout)))
  end
end

function M.read(setting, key)
  if not apply_enabled() or key == nil then
    return nil
  end
  if modes() then
    local text = run_current(key)
    if text == "" then
      return nil
    end
    return text
  end
  local out = util.run_capture(
    "hyprctl workspaces -j | jq -r --arg k " .. util.shell_quote(tostring(key))
      .. " '.[] | select(.id == ($k|tonumber)) | .tiledLayout'")
  local text = trim(out)
  if text == "" then
    return nil
  end
  return text
end

function M.read_default(setting, key)
  if modes() then
    local text = run_default()
    if text == "" then
      return "dwindle"
    end
    return text
  end
  return "dwindle"
end

-- An enum must be one of its declared options or a custom value it has held.
function M.validate(setting, value, key, customs)
  return types.check_allowed(setting, value, customs)
end

function M.write(setting, key, value)
  if not apply_enabled() then
    return true
  end

  if modes() then
    local dir = layouts_dir()
    util.run_capture("mkdir -p " .. util.shell_quote(dir))
    local def = M.read_default(setting, key)
    if tostring(value) == tostring(def) then
      os.remove(state_file(key))
    else
      util.write_file(state_file(key),
        "o.workspace_mode({ workspace = \"" .. tostring(key) .. "\", mode = \"" .. tostring(value) .. "\" })\n")
    end
    apply_mode_rule(key, value)
    return true
  end

  local dir = layouts_dir()
  util.run_capture("mkdir -p " .. util.shell_quote(dir))
  util.write_file(state_file(key),
    "hl.workspace_rule({ workspace = \"" .. tostring(key) .. "\", layout = \"" .. tostring(value) .. "\" })\n")

  apply_legacy_rule(key, value)
  return true
end

function M.reset(setting, key)
  if not apply_enabled() then
    return true
  end

  if modes() then
    os.remove(state_file(key))
    apply_mode_rule(key, M.read_default(setting, key))
    return true
  end

  os.remove(state_file(key))
  apply_legacy_rule(key, "dwindle")
  return true
end

-- Sort workspace-number keys numerically (as strings, so "2" precedes "10").
local function sort_keys(keys)
  table.sort(keys, function(a, b)
    return (tonumber(a) or 0) < (tonumber(b) or 0)
  end)
end

function M.keys(setting)
  if not apply_enabled() then
    return {}
  end
  local out = util.run_capture("hyprctl workspaces -j | jq -r '.[].id'")
  local keys = {}
  for line in (out or ""):gmatch("[^\n]+") do
    local text = trim(line)
    local n = tonumber(text)
    -- Special and named workspaces report negative ids; layout only applies to
    -- positive-numbered workspaces (mirrors the bar and workspace-modes.lua).
    if n and n > 0 then
      keys[#keys + 1] = tostring(n)
    end
  end
  sort_keys(keys)
  return keys
end

-- Per-monitor workspaces (workspace modes only). Each monitor owns a block of
-- SLOTS global workspace ids, numbered block*SLOTS+1 .. block*SLOTS+SLOTS, the
-- same scheme Omarchy's monitor-workspaces.lua and the bar use.
local SLOTS = 10

local function state_home()
  return os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") or "") .. "/.local/state"
end

local function monitor_workspaces_file()
  return os.getenv("OMASET_MONITOR_WORKSPACES_FILE")
    or state_home() .. "/omarchy/monitor-workspaces"
end

-- A monitor's block from its open workspaces, for when the state file has no
-- connector entry yet (first config load after a plug-in).
local function active_block(monitor_name)
  local out = util.run_capture("hyprctl workspaces -j | jq -r --arg m "
    .. util.shell_quote(monitor_name) .. " '.[] | select(.monitor == $m and .id > 0) | .id'")
  local ids = {}
  for line in (out or ""):gmatch("[^\n]+") do
    local text = trim(line)
    local n = tonumber(text)
    if n then ids[#ids + 1] = n end
  end
  if #ids == 0 then
    return nil
  end
  table.sort(ids)
  return math.floor((ids[1] - 1) / SLOTS)
end

-- The workspace ids a monitor's block shows, the same shape the bar renders:
-- the first five slots, plus any other workspace in the block that is open.
-- Sorted, as global ids. Persisted-but-closed layouts are intentionally not
-- listed, so this matches the bar.
local function block_workspaces(setting, block)
  local ids = {}
  local seen = {}
  local function add(id)
    if not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end

  for slot = 1, 5 do
    add(block * SLOTS + slot)
  end

  local out = util.run_capture("hyprctl workspaces -j | jq -r '.[].id'")
  for line in (out or ""):gmatch("[^\n]+") do
    local text = trim(line)
    local id = tonumber(text)
    if id and id > 0 and math.floor((id - 1) / SLOTS) == block then
      add(id)
    end
  end

  table.sort(ids)
  local workspaces = {}
  for _, id in ipairs(ids) do
    workspaces[#workspaces + 1] = tostring(id)
  end
  return workspaces
end

-- Connected monitors with their workspace blocks, ordered by block.
-- Returns nil when the setting has no monitor dimension (not workspace modes).
function M.monitors(setting)
  if not modes() or not apply_enabled() then
    return nil
  end

  -- connector -> block, from the file Omarchy's monitor-workspaces.lua writes.
  local connector_to_block = {}
  local content = util.read_file(monitor_workspaces_file()) or ""
  for line in content:gmatch("[^\n]+") do
    local block, connector = line:match("^(%d+)\t([^\t]*)")
    if block and connector and connector ~= "" then
      connector_to_block[connector] = tonumber(block)
    end
  end

  local out = util.run_capture("hyprctl monitors -j | jq -r '.[].name'")
  local monitors = {}
  local used = {}
  for line in (out or ""):gmatch("[^\n]+") do
    local name = trim(line)
    if name ~= "" then
      local block = connector_to_block[name] or active_block(name)
      if block == nil then
        block = 0
        while used[block] do block = block + 1 end
      end
      used[block] = true

      monitors[#monitors + 1] = {
        name = name,
        block = block,
        workspaces = block_workspaces(setting, block),
      }
    end
  end
  table.sort(monitors, function(a, b) return a.block < b.block end)
  if #monitors == 0 then
    return nil
  end
  return monitors
end

-- All persisted keys (state files), including workspaces that are not
-- currently open. Used by `reset <id> --all`.
function M.keys_all(setting)
  if not apply_enabled() then
    return {}
  end
  local keys = {}
  for _, file in ipairs(util.list_lua_files(layouts_dir())) do
    local base = file:match("([^/]+)%.lua$")
    -- The workspace-modes default lives in default.lua; it is not a
    -- workspace and must never be treated as a key.
    if base and base:match("^%d+$") then
      keys[#keys + 1] = base
    end
  end
  sort_keys(keys)
  return keys
end

registry.register("workspace-layout", M)

return M
