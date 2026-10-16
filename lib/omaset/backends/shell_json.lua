-- Backend for ~/.config/omarchy/shell.json (idle, bar, plugins).
--
-- Uses jq the same way Omarchy's own omarchy-shell-config does: apply a
-- normalize pipeline so the file stays well-shaped, then set the target key,
-- sorted keys, atomic temp+mv.

local util = require("omaset.util")
local types = require("omaset.types")
local registry = require("omaset.backends")

local M = {}

-- Sentinel stored in the .bak when the user had no shell.json before omaset's
-- first write (so rollback deletes the omaset-created file instead of writing
-- an invalid empty JSON document).
local NO_FILE = "omaset-no-original-file"

-- Mirrors omarchy-shell-config's NORMALIZE jq program.
local NORMALIZE = [[
  def object_or_empty: if type == "object" then . else {} end;
  def array_or_empty: if type == "array" then . else [] end;
  object_or_empty
  | .version = 1
  | .bar = (.bar | object_or_empty)
  | .bar.layout = (.bar.layout | object_or_empty)
  | .bar.layout.left = (.bar.layout.left | array_or_empty)
  | .bar.layout.center = (.bar.layout.center | array_or_empty)
  | .bar.layout.right = (.bar.layout.right | array_or_empty)
  | .plugins = (.plugins | array_or_empty)
]]

local function omarchy_path()
  return os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
end

function M.user_file()
  return os.getenv("OMASET_SHELL_CONFIG")
    or (os.getenv("HOME") or "") .. "/.config/omarchy/shell.json"
end

local function default_file()
  return omarchy_path() .. "/config/omarchy/shell.json"
end

-- Read a dotted path from one file as a typed value, or nil if unset.
local function read_path(file, path, setting)
  if not util.file_exists(file) then
    return nil
  end
  local out = util.run_capture(
    "jq -r " .. util.shell_quote("." .. path) .. " " .. util.shell_quote(file))
  local text = out and out:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if text == "" or text == "null" then
    return nil
  end
  local value = types.coerce(text, setting)
  return value
end

function M.read(setting, key)
  local user_val = read_path(M.user_file(), setting.path, setting)
  if user_val ~= nil then
    return user_val
  end
  return read_path(default_file(), setting.path, setting)
end

function M.read_default(setting, key)
  return read_path(default_file(), setting.path, setting)
end

local function apply_enabled()
  local v = os.getenv("OMASET_NO_APPLY")
  return not (v == "1" or v == "true" or v == "yes" or v == "on")
end

local function reload_shell()
  if not util.cmd_exists("omarchy-shell") then
    return
  end
  local _, code = util.run_capture("omarchy-shell shell reloadConfig")
  if code ~= 0 then
    util.run_capture("omarchy-shell -q shell rescanPlugins")
  end
end

-- Run a jq program (with optional leading args) against the effective source
-- file and atomically commit the result to the user config.
local function commit(program, extra_args)
  local user_file = M.user_file()
  local src_file
  if util.file_exists(user_file) and util.read_file(user_file) ~= "" then
    src_file = user_file
  else
    src_file = default_file()
  end

  if util.read_file(user_file .. ".omaset.bak") == nil then
    if util.file_exists(user_file) then
      util.write_file(user_file .. ".omaset.bak", util.read_file(user_file))
    else
      util.write_file(user_file .. ".omaset.bak", NO_FILE)
    end
  end

  local tmp = user_file .. ".tmp"
  util.run_capture("mkdir -p " .. util.shell_quote(user_file:match("^(.*)/") or "."))

  local cmd = "jq -S -e " .. (extra_args or "") .. " " .. util.shell_quote(program)
    .. " " .. util.shell_quote(src_file)
    .. " > " .. util.shell_quote(tmp)
    .. " && mv " .. util.shell_quote(tmp) .. " " .. util.shell_quote(user_file)
  local out, code = util.run_capture(cmd)
  if code ~= 0 then
    os.remove(tmp)
    return nil, "could not update shell.json: " .. (out or "")
  end

  if apply_enabled() then
    reload_shell()
  end
  return true
end

function M.write(setting, key, value)
  local t = setting.type or "string"
  local valarg
  if t == "int" or t == "float" or t == "bool" then
    valarg = "--argjson v " .. tostring(value)
  else
    valarg = "--arg v " .. util.shell_quote(tostring(value))
  end
  return commit(NORMALIZE .. "\n  | ." .. setting.path .. " = $v", valarg)
end

function M.reset(setting, key)
  return commit(NORMALIZE .. "\n  | del(." .. setting.path .. ")")
end

-- Restore the pre-omaset shell.json snapshot (if any) and reload the shell.
-- If omaset created the file from scratch (no original), delete it so the
-- Omarchy default applies again.
function M.restore()
  local user_file = M.user_file()
  local content = util.read_file(user_file .. ".omaset.bak")
  if content == nil then
    return 0
  end
  if content == NO_FILE then
    os.remove(user_file)
  else
    util.write_file(user_file, content)
  end
  if apply_enabled() then
    reload_shell()
  end
  return 1
end

registry.register("shell-json", M)

return M
