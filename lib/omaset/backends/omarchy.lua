-- Passthrough backend that delegates a setting to an existing omarchy command,
-- so hooks and Omarchy's own logic still fire rather than omaset duplicating it.
--
-- Setting fields:
--   command : shell command run on set (mode "value" replaces {value})
--   status  : optional command whose stdout is the current value (coerced by type)
--   mode    : "value" (default) or "toggle" (run command only if state differs)
--   reset   : optional command to restore the default
--
-- Read/write/reset are skipped under OMASET_NO_APPLY=1 so tests never touch the
-- live system.

local util = require("omaset.util")
local types = require("omaset.types")
local registry = require("omaset.backends")

local M = {}

local function apply_enabled()
  local v = os.getenv("OMASET_NO_APPLY")
  return not (v == "1" or v == "true" or v == "yes" or v == "on")
end

local function run_cmd(cmd)
  local out, code = util.run_capture(cmd)
  return out, code
end

function M.read(setting, key)
  if not apply_enabled() or not setting.status then
    return nil
  end
  local out = util.run_capture(setting.status)
  local text = out and out:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if text == "" then
    return nil
  end
  return types.coerce(text, setting)
end

function M.read_default(setting, key)
  return nil
end

local function substitute(command, value)
  return (command:gsub("{value}", tostring(value)))
end

function M.write(setting, key, value)
  if not apply_enabled() then
    return true
  end

  if setting.mode == "toggle" then
    local current = M.read(setting)
    if current == value then
      return true
    end
    local out, code = run_cmd(setting.command)
    if code ~= 0 then
      return nil, "command failed: " .. (out or "")
    end
    return true
  end

  local cmd = setting.command
  if cmd:find("{value}", 1, true) then
    cmd = substitute(cmd, value)
  end
  local out, code = run_cmd(cmd)
  if code ~= 0 then
    return nil, "command failed: " .. (out or "")
  end
  return true
end

function M.reset(setting, key)
  if not apply_enabled() then
    return true
  end
  if setting.reset then
    local out, code = run_cmd(setting.reset)
    if code ~= 0 then
      return nil, "reset command failed: " .. (out or "")
    end
  end
  return true
end

registry.register("omarchy", M)

return M
