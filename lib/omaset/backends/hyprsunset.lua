-- Backend for ~/.config/hypr/hyprsunset.conf (night light schedule).
--
-- hyprsunset has no on/off window: it applies whichever profile has the latest
-- activation time, so the schedule is two profiles — a warm `temperature`
-- profile at the start time and an `identity` (no tint) profile at the stop
-- time. omaset edits these in place: the night profile is the one carrying a
-- `temperature`, the stop is the `identity` profile, and the whole file is
-- scanned so a hand-edited profile outside anything omaset wrote is still what
-- `get`/`changed`/the UI report. Four settings are exposed via `path`:
--   schedule    (bool)  whether a night (temperature) profile exists
--   start       (time)  the night profile's start time (HH:MM)
--   stop        (time)  the identity profile's stop time (HH:MM)
--   temperature (int)   the night profile's color temperature in Kelvin

local util = require("omaset.util")
local types = require("omaset.types")
local registry = require("omaset.backends")

local M = {}

local DEFAULT_START = "20:00"
local DEFAULT_STOP = "07:00"
local DEFAULT_TEMP = 4000

local function config_file()
  return os.getenv("OMASET_HYPRSUNSET_CONFIG")
    or (os.getenv("HOME") or "") .. "/.config/hypr/hyprsunset.conf"
end

local function splice(src, s, e, text)
  return src:sub(1, s - 1) .. text .. src:sub(e + 1)
end

-- Find "field = <value>" within [from, to] and return the value's byte span and
-- text, or nil.
local function find_field(content, from, to, field, pat)
  local ws, _, prefix, value = content:find("(" .. field .. "%s*=%s*)(" .. pat .. ")", from)
  if not ws or ws > to then return nil end
  local vs = ws + #prefix
  local ve = vs + #value - 1
  if ve > to then return nil end
  return { s = vs, e = ve, text = value }
end

-- Scan every `profile { ... }` block in the whole file, in order, with the byte
-- span of the block and of each field it contains.
local function scan_profiles(content)
  local profiles = {}
  local pos = 1
  while true do
    local bs, be = content:find("profile%s*{", pos)
    if not bs then break end
    local ce = content:find("}", be + 1, true)
    if not ce then break end
    profiles[#profiles + 1] = {
      block_s = bs, block_e = ce,
      time = find_field(content, be + 1, ce - 1, "time", "[%d:]+"),
      temperature = find_field(content, be + 1, ce - 1, "temperature", "%d+"),
      identity = find_field(content, be + 1, ce - 1, "identity", "%w+"),
    }
    pos = ce + 1
  end
  return profiles
end

local function night_profile(profiles)
  local night
  for _, p in ipairs(profiles) do
    if p.temperature then night = p end
  end
  return night
end

local function identity_profile(profiles)
  local id
  for _, p in ipairs(profiles) do
    if p.identity and (p.identity.text == "true" or p.identity.text == "1") then
      id = p
    end
  end
  return id
end

local function night_lines(start, temperature)
  return "profile {\n    time = " .. start .. "\n    temperature = " .. tostring(temperature) .. "\n}"
end

local function identity_lines(stop)
  return "profile {\n    time = " .. stop .. "\n    identity = true\n}"
end

local function append_profile(content, block)
  if content == "" then return block .. "\n" end
  if content:sub(-1) ~= "\n" then return content .. "\n\n" .. block .. "\n" end
  return content .. "\n" .. block .. "\n"
end

local function remove_profile(content, prof)
  local nl = content:find("\n", prof.block_e, true)
  if nl and content:sub(prof.block_e + 1, nl - 1):match("^%s*$") then
    return content:sub(1, prof.block_s - 1) .. content:sub(nl + 1)
  end
  return content:sub(1, prof.block_s - 1) .. content:sub(prof.block_e + 1)
end

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
  local profiles = scan_profiles(content)
  local night = night_profile(profiles)
  local identity = identity_profile(profiles)

  if setting.path == "schedule" then
    return night ~= nil
  elseif setting.path == "start" then
    return (night and night.time and night.time.text) or DEFAULT_START
  elseif setting.path == "stop" then
    return (identity and identity.time and identity.time.text) or DEFAULT_STOP
  elseif setting.path == "temperature" then
    return (night and night.temperature and tonumber(night.temperature.text)) or DEFAULT_TEMP
  end
  return nil
end

function M.read_default(setting, key)
  if setting.path == "schedule" then
    return false
  elseif setting.path == "start" then
    return DEFAULT_START
  elseif setting.path == "stop" then
    return DEFAULT_STOP
  elseif setting.path == "temperature" then
    return DEFAULT_TEMP
  end
  return nil
end

function M.write(setting, key, value)
  local file = config_file()
  local content = util.read_file(file) or ""
  local profiles = scan_profiles(content)
  local night = night_profile(profiles)
  local identity = identity_profile(profiles)
  local path = setting.path

  if path == "schedule" then
    if value then
      if night then return true end
      local new_content = append_profile(content, night_lines(DEFAULT_START, DEFAULT_TEMP))
      if not identity then
        new_content = append_profile(new_content, identity_lines(DEFAULT_STOP))
      end
      return commit(file, new_content)
    end
    if not night then return true end
    return commit(file, remove_profile(content, night))
  end

  if path == "temperature" then
    if night and night.temperature then
      return commit(file, splice(content, night.temperature.s, night.temperature.e, tostring(value)))
    end
    return commit(file, append_profile(content, night_lines(DEFAULT_START, value)))
  end

  if path == "start" then
    local t = types.parse_time(value) or value
    if t == ((identity and identity.time and identity.time.text) or DEFAULT_STOP) then
      return nil, "start and stop times must differ"
    end
    if night and night.time then
      return commit(file, splice(content, night.time.s, night.time.e, t))
    end
    local temp = (night and night.temperature and tonumber(night.temperature.text)) or DEFAULT_TEMP
    return commit(file, append_profile(content, night_lines(t, temp)))
  end

  if path == "stop" then
    local t = types.parse_time(value) or value
    if t == ((night and night.time and night.time.text) or DEFAULT_START) then
      return nil, "start and stop times must differ"
    end
    if identity and identity.time then
      return commit(file, splice(content, identity.time.s, identity.time.e, t))
    end
    return commit(file, append_profile(content, identity_lines(t)))
  end

  return nil, "unknown hyprsunset path: " .. tostring(path)
end

function M.reset(setting, key)
  local file = config_file()
  local content = util.read_file(file) or ""
  local profiles = scan_profiles(content)
  local night = night_profile(profiles)
  local identity = identity_profile(profiles)
  local path = setting.path

  if path == "schedule" then
    if not night then return true end
    return commit(file, remove_profile(content, night))
  end

  if path == "temperature" then
    if night and night.temperature then
      return commit(file, splice(content, night.temperature.s, night.temperature.e, tostring(DEFAULT_TEMP)))
    end
    return true
  end

  if path == "start" then
    if not night or not night.time then return true end
    local stop = (identity and identity.time and identity.time.text) or DEFAULT_STOP
    if DEFAULT_START == stop then
      return nil, "cannot reset: the other end is already " .. DEFAULT_START
    end
    return commit(file, splice(content, night.time.s, night.time.e, DEFAULT_START))
  end

  if path == "stop" then
    if not identity or not identity.time then return true end
    local start = (night and night.time and night.time.text) or DEFAULT_START
    if DEFAULT_STOP == start then
      return nil, "cannot reset: the other end is already " .. DEFAULT_STOP
    end
    return commit(file, splice(content, identity.time.s, identity.time.e, DEFAULT_STOP))
  end

  return nil, "unknown hyprsunset path: " .. tostring(path)
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
