-- Backend that reads/writes Hyprland Lua config files (looknfeel.lua, etc.).
--
-- READ: evaluate the default file (from OMARCHY_PATH) then the user file,
--       capturing every hl.config() call into one merged table. Later calls
--       win, mirroring how Hyprland applies config in order.
--
-- WRITE/RESET: edit the value in place (see omaset.luaedit). The old
--       "-- omaset:begin" managed block is gone: Omarchy's user files are
--       hand-edited templates where a value sits next to the comment that
--       explains it, so omaset now splices the winning hl.config() occurrence
--       (or appends a minimal hl.config({ path = value }) when the value is not
--       yet present) instead of flattening a block at EOF.

local util = require("omaset.util")
local luaedit = require("omaset.luaedit")
local registry = require("omaset.backends")

local M = {}

local function omarchy_path()
  return os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
end

local function user_hypr_dir()
  return os.getenv("OMASET_HYPR_DIR")
    or (os.getenv("HOME") or "") .. "/.config/hypr"
end

local function default_hypr_dir()
  return omarchy_path() .. "/default/hypr"
end

local function noop()
end

-- Evaluate a list of lua files in order, capturing hl.config() into a merged
-- table. Unknown hl.* members are no-ops so config files that call curve(),
-- animation(), etc. still evaluate.
local function eval_config(file_paths)
  local merged = {}
  local hl = setmetatable({
    config = function(t)
      util.deep_merge(merged, t)
    end,
    curve = noop,
    animation = noop,
  }, { __index = function() return noop end })
  local o = setmetatable({}, { __index = function() return noop end })

  local old_hl, old_o = _G.hl, _G.o
  _G.hl = hl
  _G.o = o
  -- Omarchy's own default files may require() their siblings (e.g. 4.5's
  -- input.lua needs default.hypr.keyboard). Put the Omarchy module root on
  -- package.path while evaluating so those requires resolve, then restore.
  local saved_path = package.path
  package.path = omarchy_path() .. "/?.lua;"
    .. omarchy_path() .. "/?/init.lua;" .. saved_path
  for _, path in ipairs(file_paths) do
    if util.file_exists(path) then
      local chunk, err = loadfile(path)
      if chunk then
        local ok, runerr = pcall(chunk)
        if not ok then
          io.stderr:write("omaset: warning: " .. path .. ": " .. tostring(runerr) .. "\n")
        end
      else
        io.stderr:write("omaset: warning: " .. path .. ": " .. tostring(err) .. "\n")
      end
    end
  end
  _G.hl = old_hl
  _G.o = old_o
  package.path = saved_path
  return merged
end

function M.user_file(setting)
  return user_hypr_dir() .. "/" .. setting.file .. ".lua"
end

function M.read(setting, key)
  local files = {
    default_hypr_dir() .. "/" .. setting.file .. ".lua",
    M.user_file(setting),
  }
  local cfg = eval_config(files)
  return util.deep_get(cfg, setting.path)
end

function M.read_default(setting, key)
  local cfg = eval_config({ default_hypr_dir() .. "/" .. setting.file .. ".lua" })
  return util.deep_get(cfg, setting.path)
end

local function apply_enabled()
  local v = os.getenv("OMASET_NO_APPLY")
  return not (v == "1" or v == "true" or v == "yes" or v == "on")
end

-- Reload Hyprland, validate, and revert the file if the config has errors.
-- Returns true on success, or nil plus an error message (after reverting).
local function apply_and_validate(user_file, prev_content)
  if not util.cmd_exists("hyprctl") then
    return true
  end

  util.run_capture("hyprctl reload")

  local out, code = util.run_capture("hyprctl configerrors")
  local err_text = out:gsub("^%s+", ""):gsub("%s+$", "")
  if err_text == "" and code == 0 then
    return true
  end

  util.write_file(user_file, prev_content)
  util.run_capture("hyprctl reload")
  return nil, "config errors after write (change reverted):\n" .. err_text
end

local function commit(user_file, prev_content, new_content)
  -- No-op (e.g. a reset of an already-default value with no uncommented
  -- occurrence) must not touch the file or reload Hyprland.
  if new_content == prev_content then
    return true
  end

  if util.read_file(user_file .. ".omaset.bak") == nil then
    util.write_file(user_file .. ".omaset.bak", prev_content)
  end

  local ok, err = util.write_file(user_file, new_content)
  if not ok then
    return nil, err
  end

  if apply_enabled() then
    local aok, aerr = apply_and_validate(user_file, prev_content)
    if not aok then
      return nil, aerr
    end
  end
  return true
end

function M.write(setting, key, value)
  local user_file = M.user_file(setting)
  local content = util.read_file(user_file) or ""
  local new_content = luaedit.set_value(content, setting.path, value)
  return commit(user_file, content, new_content)
end

function M.reset(setting, key)
  local user_file = M.user_file(setting)
  local content = util.read_file(user_file) or ""
  local def = setting.default
  if def == nil then
    def = M.read_default(setting, key)
  end
  local new_content = luaedit.reset_value(content, setting.path, def)
  return commit(user_file, content, new_content)
end

-- Restore every <file>.omaset.bak snapshot in the user hypr dir back over its
-- target, then reload Hyprland. This is the panic-button restore: it puts each
-- file back to the byte state it had before omaset first wrote to it.
function M.restore()
  local dir = user_hypr_dir()
  local restored = 0
  for _, bak in ipairs(util.list_files(dir, "*.omaset.bak")) do
    local target = bak:gsub("%.omaset%.bak$", "")
    local content = util.read_file(bak)
    if content ~= nil and util.write_file(target, content) then
      restored = restored + 1
    end
  end
  if restored > 0 and apply_enabled() and util.cmd_exists("hyprctl") then
    util.run_capture("hyprctl reload")
  end
  return restored
end

registry.register("hypr-lua", M)

return M
