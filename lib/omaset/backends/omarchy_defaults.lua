-- Backend for Omarchy's default applications (Setup > Defaults).
--
-- A declared value goes through its omarchy-default-* command, so Omarchy's own
-- install and notification steps run. A custom value (one of the command's
-- cases does not name, such as a hand-chosen desktop id) is written to the same
-- store that command writes, so it reads back the same way the command reads.
--
-- Setting fields, beside the omarchy backend's command/status/reset:
--   custom.file   : preference file under $HOME, holding the bare value
--   custom.format : "xdg-terminals" writes the xdg-terminal-exec list format
--   custom.xdg    : xdg-settings property to set instead of a file

local util = require("omaset.util")
local types = require("omaset.types")
local registry = require("omaset.backends")

local M = {}

local function apply_enabled()
  local v = os.getenv("OMASET_NO_APPLY")
  return not (v == "1" or v == "true" or v == "yes" or v == "on")
end

local function omarchy()
  return registry.get("omarchy")
end

local function is_declared(setting, value)
  -- Values named in custom_values use the underlying store, not the omarchy
  -- command, even though they appear among the declared options.
  for _, cv in ipairs(setting.custom_values or {}) do
    if tostring(cv) == tostring(value) then
      return false
    end
  end
  for _, v in ipairs(types.option_values(setting)) do
    if tostring(v) == tostring(value) then
      return true
    end
  end
  return false
end

local function xdg_terminals_text(value)
  return "# Terminal emulator preference order for xdg-terminal-exec\n"
    .. "# The first found and valid terminal will be used\n"
    .. value .. "\n"
end

local function write_custom(setting, value)
  local c = setting.custom
  if c.xdg then
    local desktop = c.desktop or value
    local out, code = util.run_capture("env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings set "
      .. c.xdg .. " " .. util.shell_quote(desktop))
    if code ~= 0 then
      return nil, "could not set " .. setting.id .. ": " .. (out or "")
    end
    return true
  end
  local path = (os.getenv("HOME") or "") .. "/" .. c.file
  local dir = path:match("^(.*)/") or "."
  util.run_capture("mkdir -p " .. util.shell_quote(dir))
  local text = value .. "\n"
  if c.format == "xdg-terminals" then
    text = xdg_terminals_text(value)
  end
  return util.write_file(path, text)
end

function M.read(setting, key)
  return omarchy().read(setting, key)
end

function M.read_default(setting, key)
  return setting.default
end

-- A value is one line and does not look like a flag, so it cannot change the
-- command it is passed to. Beyond that any value is allowed: a custom value is
-- what the user, or an agent, chose.
function M.validate(setting, value, key)
  if type(value) ~= "string" or value == "" then
    return nil, "expected a non-empty value for " .. setting.id
  end
  if value:find("[%c]") then
    return nil, "a value for " .. setting.id .. " must be one line"
  end
  if value:sub(1, 1) == "-" then
    return nil, "'" .. value .. "' is not a valid value for " .. setting.id
  end
  return true
end

function M.write(setting, key, value)
  if not apply_enabled() then
    return true
  end
  if is_declared(setting, value) then
    return omarchy().write(setting, key, value)
  end
  return write_custom(setting, value)
end

function M.reset(setting, key)
  return omarchy().reset(setting, key)
end

registry.register("omarchy-defaults", M)

return M
