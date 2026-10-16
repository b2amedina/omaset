-- Backend for per-workspace Hyprland layout, keyed by workspace number.
--
-- READ:  runtime layout of an open workspace (hyprctl workspaces -j).
-- WRITE: persist a rule to ~/.local/state/omarchy/workspace-layouts/<n>.lua
--        (mirrors omarchy-hyprland-workspace-layout-toggle) then apply it via
--        hl.workspace_rule, falling back to hyprctl keyword workspace.
-- RESET: delete the persisted rule and apply the default (dwindle).

local util = require("omaset.util")
local registry = require("omaset.backends")

local M = {}

local function apply_enabled()
  local v = os.getenv("OMASET_NO_APPLY")
  return not (v == "1" or v == "true" or v == "yes" or v == "on")
end

local function layouts_dir()
  return os.getenv("OMASET_WORKSPACE_LAYOUTS_DIR")
    or (os.getenv("HOME") or "") .. "/.local/state/omarchy/workspace-layouts"
end

local function state_file(key)
  return layouts_dir() .. "/" .. tostring(key) .. ".lua"
end

local function apply_rule(key, layout)
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
  local out = util.run_capture(
    "hyprctl workspaces -j | jq -r --arg k " .. util.shell_quote(tostring(key))
      .. " '.[] | select(.id == ($k|tonumber)) | .tiledLayout'")
  local text = out and out:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if text == "" then
    return nil
  end
  return text
end

function M.read_default(setting, key)
  return "dwindle"
end

function M.write(setting, key, value)
  if not apply_enabled() then
    return true
  end

  local dir = layouts_dir()
  util.run_capture("mkdir -p " .. util.shell_quote(dir))
  util.write_file(state_file(key),
    "hl.workspace_rule({ workspace = \"" .. tostring(key) .. "\", layout = \"" .. tostring(value) .. "\" })\n")

  apply_rule(key, value)
  return true
end

function M.reset(setting, key)
  if not apply_enabled() then
    return true
  end

  os.remove(state_file(key))
  apply_rule(key, "dwindle")
  return true
end

function M.keys(setting)
  if not apply_enabled() then
    return {}
  end
  local out = util.run_capture("hyprctl workspaces -j | jq -r '.[].id'")
  local keys = {}
  for line in (out or ""):gmatch("[^\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then
      keys[#keys + 1] = trimmed
    end
  end
  return keys
end

registry.register("workspace-layout", M)

return M
