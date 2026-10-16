-- Backend that reads/writes Hyprland Lua config files (looknfeel.lua, etc.).
--
-- READ: evaluate the default file (from OMARCHY_PATH) then the user file,
--       capturing every hl.config() call into one merged table. Later calls
--       win, mirroring how Hyprland applies config in order.
--
-- WRITE: maintain a single "managed block" in the user file, delimited by
--        -- omaset:begin / -- omaset:end. Only keys the user changed through
--        omaset live in that block; everything else in the file is untouched.

local util = require("omaset.util")
local registry = require("omaset.backends")

local M = {}

local BEGIN_MARK = "-- omaset:begin"
local END_MARK = "-- omaset:end"

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

  local old_hl = _G.hl
  _G.hl = hl
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

-- Parse the existing managed block (if any) into a nested table.
local function parse_managed_block(content)
  local managed = {}
  local start = content:find(BEGIN_MARK, 1, true)
  if not start then
    return managed
  end
  local body_start = content:find("\n", start, true)
  if not body_start then
    return managed
  end
  local finish = content:find(END_MARK, body_start, true)
  if not finish then
    return managed
  end
  local body = content:sub(body_start + 1, finish - 1)

  local hl = setmetatable({
    config = function(t)
      util.deep_merge(managed, t)
    end,
  }, { __index = function() return function() end end })

  local chunk = load(body, "=omaset-managed", "t", { hl = hl })
  if chunk then
    pcall(chunk)
  end
  return managed
end

local function build_block(managed)
  return BEGIN_MARK .. "\nhl.config(" .. util.serialize(managed, 1) .. ")\n" .. END_MARK
end

local function replace_or_append(content, block)
  local start = content:find(BEGIN_MARK, 1, true)
  if not start then
    local base = content
    if base ~= "" and base:sub(-1) ~= "\n" then
      base = base .. "\n"
    end
    return base .. "\n" .. block .. "\n"
  end
  local finish = content:find(END_MARK, start, true)
  local line_end = content:find("\n", finish, true)
  if not line_end then
    line_end = #content
  end
  return content:sub(1, start - 1) .. block .. content:sub(line_end + 1)
end

local function remove_block(content)
  local start = content:find(BEGIN_MARK, 1, true)
  if not start then
    return content
  end
  local finish = content:find(END_MARK, start, true)
  if not finish then
    return content
  end
  local line_end = content:find("\n", finish, true)
  if not line_end then
    line_end = #content
  end
  return content:sub(1, start - 1) .. content:sub(line_end + 1)
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

  local managed = parse_managed_block(content)
  util.deep_set(managed, setting.path, value)

  return commit(user_file, content, replace_or_append(content, build_block(managed)))
end

function M.reset(setting, key)
  local user_file = M.user_file(setting)
  local content = util.read_file(user_file) or ""

  local managed = parse_managed_block(content)
  util.deep_unset(managed, setting.path)

  local new_content
  if next(managed) == nil then
    new_content = remove_block(content)
  else
    new_content = replace_or_append(content, build_block(managed))
  end

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
