-- Backend for ~/.config/hypr/hyprsunset.conf (night light schedule).
--
-- Manages an omaset-owned schedule inside a block delimited by
-- "# -- omaset:begin" / "# -- omaset:end" comments, so the user's own profiles
-- and comments are never touched. hyprsunset has no on/off window: it applies
-- whichever profile has the latest activation time, so the schedule is two
-- profiles — a warm `temperature` profile at the start time and an `identity`
-- (no tint) profile at the stop time. Four settings are exposed via `path`:
--   schedule    (bool)  whether the schedule is active
--   start       (time)  the schedule's start time (HH:MM)
--   stop        (time)  the schedule's end time (HH:MM)
--   temperature (int)   the night profile's color temperature in Kelvin

local util = require("omaset.util")
local types = require("omaset.types")
local registry = require("omaset.backends")

local M = {}

local BEGIN_MARK = "# -- omaset:begin"
local END_MARK = "# -- omaset:end"

local DEFAULT_START = "20:00"
local DEFAULT_STOP = "07:00"
local DEFAULT_TEMP = 4000

local function config_file()
  return os.getenv("OMASET_HYPRSUNSET_CONFIG")
    or (os.getenv("HOME") or "") .. "/.config/hypr/hyprsunset.conf"
end

-- Parse the managed block (between the markers) into a schedule table
-- { start, stop, temperature }, or nil when there is no managed block. The
-- night profile is the one carrying a `temperature`; the identity profile is
-- the one carrying `identity = true`. A legacy single-profile block (night
-- only) leaves `stop` unset, which callers fill with DEFAULT_STOP.
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
  for pblock in body:gmatch("profile%s*{([^}]*)}") do
    local time = pblock:match("time%s*=%s*([%d:]+)")
    local temp = pblock:match("temperature%s*=%s*(%d+)")
    local idv = pblock:match("identity%s*=%s*(%w+)")
    local identity = idv ~= nil and (idv == "true" or idv == "1")
    if temp then
      prof.temperature = tonumber(temp)
      if time then prof.start = time end
    elseif identity then
      if time then prof.stop = time end
    end
  end
  return prof
end

local function build_block(prof)
  local lines = {
    BEGIN_MARK,
    "profile {",
    "    time = " .. (prof.start or DEFAULT_START),
    "    temperature = " .. tostring(prof.temperature or DEFAULT_TEMP),
    "}",
    "profile {",
    "    time = " .. (prof.stop or DEFAULT_STOP),
    "    identity = true",
    "}",
    END_MARK,
    "",
  }
  return table.concat(lines, "\n")
end

local function replace_or_append(content, block)
  local start = content:find(BEGIN_MARK, 1, true)
  if not start then
    local base = content
    if base ~= "" and base:sub(-1) ~= "\n" then
      base = base .. "\n"
    end
    return base .. "\n" .. block
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
  local prof = managed_profile(content) or {}
  if setting.path == "schedule" then
    return prof.temperature ~= nil
  end
  if setting.path == "start" then
    return prof.start or DEFAULT_START
  end
  if setting.path == "stop" then
    return prof.stop or DEFAULT_STOP
  end
  if setting.path == "temperature" then
    return prof.temperature or DEFAULT_TEMP
  end
  return nil
end

function M.read_default(setting, key)
  if setting.path == "schedule" then
    return false
  end
  if setting.path == "start" then
    return DEFAULT_START
  end
  if setting.path == "stop" then
    return DEFAULT_STOP
  end
  if setting.path == "temperature" then
    return DEFAULT_TEMP
  end
  return nil
end

-- The time that must not collide with the one being written: changing the
-- start may not equal the stop, and vice versa. Missing halves fall back to
-- their defaults so a fresh or legacy block still validates.
local function opposite_time(prof, path)
  if path == "start" then
    return prof.stop or DEFAULT_STOP
  end
  return prof.start or DEFAULT_START
end

function M.write(setting, key, value)
  local file = config_file()
  local content = util.read_file(file) or ""
  local prof = managed_profile(content)
    or { start = DEFAULT_START, stop = DEFAULT_STOP, temperature = DEFAULT_TEMP }

  if setting.path == "schedule" then
    if value then
      return commit(file, replace_or_append(content, build_block(prof)))
    end
    if managed_profile(content) == nil then
      return true
    end
    return commit(file, remove_block(content))
  end

  if setting.path == "start" or setting.path == "stop" then
    local t = types.parse_time(value) or value
    if t == opposite_time(prof, setting.path) then
      return nil, "start and stop times must differ"
    end
    if setting.path == "start" then
      prof.start = t
    else
      prof.stop = t
    end
    return commit(file, replace_or_append(content, build_block(prof)))
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
  local prof = managed_profile(content)

  if setting.path == "schedule" then
    if prof == nil then
      return true
    end
    return commit(file, remove_block(content))
  end

  if setting.path == "start" or setting.path == "stop" then
    if prof == nil then
      return true
    end
    local def = (setting.path == "start") and DEFAULT_START or DEFAULT_STOP
    if def == opposite_time(prof, setting.path) then
      return nil, "cannot reset: the other end is already " .. def
    end
    if setting.path == "start" then
      prof.start = def
    else
      prof.stop = def
    end
    return commit(file, replace_or_append(content, build_block(prof)))
  end

  if setting.path == "temperature" then
    if prof and prof.temperature then
      prof.temperature = DEFAULT_TEMP
      return commit(file, replace_or_append(content, build_block(prof)))
    end
    return true
  end

  return nil, "unknown hyprsunset path: " .. tostring(setting.path)
end

-- Restart the running hyprsunset so it re-reads hyprsunset.conf. hyprsunset
-- parses its config only at startup, so a written schedule does not take
-- effect until the process restarts. Skipped when OMASET_NO_APPLY is set
-- (tests, headless). Prefers Omarchy's own helper, which kills and relaunches
-- via uwsm exactly the way the night-light service does; falls back to the
-- same command sequence when Omarchy's CLI is unavailable.
function M.apply()
  local v = os.getenv("OMASET_NO_APPLY")
  if v == "1" or v == "true" or v == "yes" or v == "on" then
    return true
  end
  if util.cmd_exists("omarchy") then
    local out, code = util.run_capture("omarchy restart hyprsunset")
    if code ~= 0 then
      return nil, "omarchy restart hyprsunset failed: " .. (out or "")
    end
    return true
  end
  util.run_capture("pkill -x hyprsunset")
  local launcher = util.cmd_exists("uwsm-app") and "uwsm-app -- hyprsunset" or "hyprsunset"
  util.run_capture("setsid " .. launcher .. " >/dev/null 2>&1 &")
  return true
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
