-- Backend for ~/.config/hypr/hyprsunset.conf (night light schedule).
--
-- Manages a single omaset-owned "night" profile (time + temperature) inside a
-- block delimited by "# -- omaset:begin" / "# -- omaset:end" comments, so the
-- user's own profiles and comments are never touched. Two settings are exposed
-- on it via `path`:
--   schedule    (bool)  whether the night profile is active
--   temperature (int)   the night profile's color temperature in Kelvin

local util = require("omaset.util")
local registry = require("omaset.backends")

local M = {}

local BEGIN_MARK = "# -- omaset:begin"
local END_MARK = "# -- omaset:end"

local DEFAULT_TIME = "20:00"
local DEFAULT_TEMP = 4000

local function config_file()
  return os.getenv("OMASET_HYPRSUNSET_CONFIG")
    or (os.getenv("HOME") or "") .. "/.config/hypr/hyprsunset.conf"
end

-- Parse the managed block (between the markers) into a night profile table
-- { time, temperature }, or nil when there is no managed block.
local function managed_profile(content)
  local start = content:find(BEGIN_MARK, 1, true)
  if not start then
    return nil
  end
  local finish = content:find(END_MARK, start + #BEGIN_MARK, true)
  if not finish then
    return nil
  end
  local body = content:sub(start + #BEGIN_MARK, finish - 1)
  local prof = {}
  local time = body:match("time%s*=%s*([%d:]+)")
  if time then prof.time = time end
  local temp = body:match("temperature%s*=%s*(%d+)")
  if temp then prof.temperature = tonumber(temp) end
  return prof
end

local function build_block(prof)
  local lines = { "profile {" }
  lines[#lines + 1] = "    time = " .. (prof.time or DEFAULT_TIME)
  if prof.temperature then
    lines[#lines + 1] = "    temperature = " .. tostring(prof.temperature)
  end
  lines[#lines + 1] = "}"
  return BEGIN_MARK .. "\n" .. table.concat(lines, "\n") .. "\n" .. END_MARK
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

-- Snapshot the original config once, before omaset's first write, so
-- `rollback` can restore it — the same .omaset.bak convention the hypr-lua and
-- hypr-window backends use.
local function snapshot_once(file)
  if util.read_file(file .. ".omaset.bak") == nil then
    util.write_file(file .. ".omaset.bak", util.read_file(file) or "")
  end
end

local function commit(file, content)
  snapshot_once(file)
  return util.write_file(file, content)
end

function M.read(setting, key)
  local content = util.read_file(config_file()) or ""
  local prof = managed_profile(content)
  if setting.path == "schedule" then
    return prof ~= nil and prof.temperature ~= nil
  end
  if setting.path == "temperature" then
    if prof and prof.temperature then
      return prof.temperature
    end
    return DEFAULT_TEMP
  end
  return nil
end

function M.read_default(setting, key)
  if setting.path == "schedule" then
    return false
  end
  if setting.path == "temperature" then
    return DEFAULT_TEMP
  end
  return nil
end

function M.write(setting, key, value)
  local file = config_file()
  local content = util.read_file(file) or ""
  local prof = managed_profile(content) or { time = DEFAULT_TIME }

  if setting.path == "schedule" then
    if value then
      prof.temperature = prof.temperature or DEFAULT_TEMP
      return commit(file, replace_or_append(content, build_block(prof)))
    end
    if managed_profile(content) == nil then
      return true
    end
    return commit(file, remove_block(content))
  end

  if setting.path == "temperature" then
    prof.temperature = value
    return commit(file, replace_or_append(content, build_block(prof)))
  end

  return nil, "unknown hyprsunset path: " .. tostring(setting.path)
end

function M.reset(setting, key)
  local file = config_file()
  local content = util.read_file(file) or ""

  if setting.path == "schedule" then
    if managed_profile(content) == nil then
      return true
    end
    return commit(file, remove_block(content))
  end

  if setting.path == "temperature" then
    local prof = managed_profile(content)
    if prof and prof.temperature then
      prof.temperature = DEFAULT_TEMP
      return commit(file, replace_or_append(content, build_block(prof)))
    end
    return true
  end

  return nil, "unknown hyprsunset path: " .. tostring(setting.path)
end

-- Restore the pre-omaset snapshot (if any). This is the panic-button restore
-- for the night-light config, matching the other file-writing backends.
function M.restore()
  local file = config_file()
  local content = util.read_file(file .. ".omaset.bak")
  if content == nil then
    return 0
  end
  util.write_file(file, content)
  return 1
end

registry.register("hyprsunset", M)

return M
