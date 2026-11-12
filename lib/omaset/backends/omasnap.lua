local util = require("omaset.util")
local types = require("omaset.types")
local registry = require("omaset.backends")

local M = {}

local NO_FILE = "omaset-no-original-file"

local function config_file()
  local p = os.getenv("OMASET_OMASNAP_CONFIG")
  if not p or p == "" then
    p = os.getenv("OMASNAP_CONFIG")
  end
  if not p or p == "" then
    p = (os.getenv("HOME") or "") .. "/.config/omasnap/omasnap.conf"
  end
  return p
end

local function split_path(path)
  local section, key = tostring(path or ""):match("^([^.]+)%.(.+)$")
  return section, key
end

local function read_raw(section, key)
  local content = util.read_file(config_file())
  if not content then
    return nil
  end
  local current = nil
  for line in content:gmatch("[^\r\n]+") do
    local sec = line:match("^%s*%[([^%]]+)%]%s*$")
    if sec then
      current = sec
    elseif current == section then
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k == key then
        return v
      end
    end
  end
  return nil
end

function M.read(setting, key)
  local section, keyname = split_path(setting.path)
  local raw = read_raw(section, keyname)
  if raw == nil then
    return setting.default
  end
  local value = types.coerce(raw, setting)
  if value == nil then
    return setting.default
  end
  return value
end

function M.read_default(setting, key)
  return setting.default
end

local function find_section(content, section)
  local headers = {}
  local p = 1
  local n = #content
  while p <= n do
    local nl = content:find("\n", p, true)
    local le = nl or n
    local line = content:sub(p, le)
    local sec = line:match("^%s*%[([^%]]+)%]%s*$")
    if sec then
      headers[#headers + 1] = { section = sec, start = p, line_end = le }
    end
    if not nl then
      break
    end
    p = nl + 1
  end
  for i, h in ipairs(headers) do
    if h.section == section then
      local content_start = h.line_end + 1
      local content_end = n + 1
      if headers[i + 1] then
        content_end = headers[i + 1].start
      end
      return content_start, content_end
    end
  end
  return nil
end

local function find_key(content, section, key)
  local cs, ce = find_section(content, section)
  if not cs then
    return nil
  end
  local p = cs
  while p < ce do
    local nl = content:find("\n", p, true)
    local le = nl or (ce - 1)
    if le >= ce then
      le = ce - 1
    end
    if le < p then
      break
    end
    local line = content:sub(p, le)
    local k = line:match("^%s*([%w_]+)%s*=")
    if k == key then
      local eq = line:find("=", 1, true)
      local i = p + eq
      while i < ce and (content:sub(i, i) == " " or content:sub(i, i) == "\t") do
        i = i + 1
      end
      local endpos = (nl and (nl - 1)) or (ce - 1)
      if endpos >= ce then
        endpos = ce - 1
      end
      local j = endpos
      while j >= i and (content:sub(j, j) == " " or content:sub(j, j) == "\t") do
        j = j - 1
      end
      if j < i then
        return i, i - 1
      end
      return i, j
    end
    if not nl or nl >= ce - 1 then
      break
    end
    p = nl + 1
  end
  return nil
end

local function format_value(value)
  if type(value) == "boolean" then
    return value and "true" or "false"
  end
  return tostring(value)
end

local function set_ini_value(content, section, key, value)
  local cs, ce = find_section(content, section)
  local vs, ve = find_key(content, section, key)
  if vs then
    if ve >= vs then
      return content:sub(1, vs - 1) .. value .. content:sub(ve + 1), true
    end
    return content:sub(1, vs - 1) .. value .. content:sub(vs), true
  end
  if cs then
    local insert_pos = ce
    local prefix = ""
    if insert_pos > 1 and content:sub(insert_pos - 1, insert_pos - 1) ~= "\n" then
      prefix = "\n"
    end
    local addition = prefix .. key .. " = " .. value .. "\n"
    return content:sub(1, insert_pos - 1) .. addition .. content:sub(insert_pos), true
  end
  local base = content
  if base ~= "" and base:sub(-1) ~= "\n" then
    base = base .. "\n"
  end
  if base ~= "" then
    base = base .. "\n"
  end
  return base .. "[" .. section .. "]\n" .. key .. " = " .. value .. "\n", true
end

local function remove_key(content, section, key)
  local cs, ce = find_section(content, section)
  if not cs then
    return content, false
  end
  local vs, ve = find_key(content, section, key)
  if not vs then
    return content, false
  end
  local line_start = vs
  while line_start > 1 and content:sub(line_start - 1, line_start - 1) ~= "\n" do
    line_start = line_start - 1
  end
  local line_end = (ve >= vs) and ve or (vs - 1)
  while line_end < #content and content:sub(line_end + 1, line_end + 1) ~= "\n" do
    line_end = line_end + 1
  end
  if line_end < #content then
    line_end = line_end + 1
  end
  return content:sub(1, line_start - 1) .. content:sub(line_end + 1), true
end

local function snapshot_once(file)
  if util.read_file(file .. ".omaset.bak") == nil then
    if util.file_exists(file) then
      util.write_file(file .. ".omaset.bak", util.read_file(file))
    else
      util.write_file(file .. ".omaset.bak", NO_FILE)
    end
  end
end

local function commit(content)
  local file = config_file()
  local dir = file:match("^(.*)/") or "."
  util.run_capture("mkdir -p " .. util.shell_quote(dir))
  snapshot_once(file)
  local ok, err = util.write_file(file, content)
  if not ok then
    return nil, err
  end
  return true
end

local function validate_value(section, key, value)
  if section == "output" and key == "directory" then
    local v = tostring(value or "")
    if v:gsub("%s", "") == "" then
      return nil, "invalid screenshot directory: must not be empty"
    end
    if v:find("\n") or v:find("\r") then
      return nil, "invalid screenshot directory: must not contain newlines"
    end
    if not (v:sub(1, 1) == "/" or v:sub(1, 1) == "~") then
      return nil, "invalid screenshot directory: must be an absolute or home-relative path (start with / or ~)"
    end
    return true
  end
  if section == "output" and key == "filename" then
    local v = tostring(value or "")
    if v:gsub("%s", "") == "" then
      return nil, "invalid filename pattern: must not be empty"
    end
    if v:find("/", 1, true) or v:find("\\", 1, true) or v:find("\n") or v:find("\r") then
      return nil, "invalid filename pattern: must not contain path separators or newlines"
    end
    local stripped = v
    for token in v:gmatch("{[^}]*}") do
      if token ~= "{date}" and token ~= "{time}" and token ~= "{app}" then
        return nil, "invalid filename pattern: unknown token " .. token
      end
      stripped = stripped:gsub(token, "", 1)
    end
    if stripped:find("{") or stripped:find("}") then
      return nil, "invalid filename pattern: unmatched brace"
    end
    return true
  end
  return true
end

function M.write(setting, key, value)
  local section, keyname = split_path(setting.path)
  if not section or not keyname then
    return nil, "invalid omasnap path: " .. tostring(setting.path)
  end
  local ok, err = validate_value(section, keyname, value)
  if not ok then
    return nil, err
  end
  local file = config_file()
  local content = util.read_file(file) or ""
  local new_content = set_ini_value(content, section, keyname, format_value(value))
  if new_content == content then
    return true
  end
  return commit(new_content)
end

function M.reset(setting, key)
  local section, keyname = split_path(setting.path)
  if not section or not keyname then
    return nil, "invalid omasnap path: " .. tostring(setting.path)
  end
  local file = config_file()
  local content = util.read_file(file) or ""
  local new_content, changed = remove_key(content, section, keyname)
  if not changed then
    return true
  end
  return commit(new_content)
end

function M.restore()
  local file = config_file()
  local content = util.read_file(file .. ".omaset.bak")
  if content == nil then
    return 0
  end
  if content == NO_FILE then
    os.remove(file)
    return 1
  end
  util.write_file(file, content)
  return 1
end

registry.register("omasnap", M)

return M
