-- Minimal JSON encoder. No external deps.

local M = {}

-- Sentinel that encodes as JSON null (Lua tables cannot hold a nil-valued key).
M.null = {}

-- Marker so a table that is *meant* to be a JSON array encodes as [] even when
-- empty. Lua cannot tell an empty array from an empty map, so `is_array` below
-- only auto-detects non-empty arrays; callers pass their array-typed tables
-- through M.array() to cover the empty case.
local array_mt = {}
array_mt.__is_array = true

function M.array(t)
  return setmetatable(t or {}, array_mt)
end

local function escape(s)
  return s:gsub('[%c\\"]', function(c)
    if c == "\n" then return "\\n" end
    if c == "\r" then return "\\r" end
    if c == "\t" then return "\\t" end
    if c == "\b" then return "\\b" end
    if c == "\f" then return "\\f" end
    if c == "\\" then return "\\\\" end
    if c == '"' then return '\\"' end
    return string.format("\\u%04x", string.byte(c))
  end)
end

local function is_array(t)
  local mt = getmetatable(t)
  if mt and mt.__is_array then return true end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      return false
    end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then
      return false
    end
  end
  return n > 0
end

function M.encode(value)
  local t = type(value)
  if value == nil or value == M.null then
    return "null"
  elseif t == "boolean" then
    return value and "true" or "false"
  elseif t == "number" then
    if value ~= value then
      return "null"
    end
    return string.format("%.14g", value)
  elseif t == "string" then
    return '"' .. escape(value) .. '"'
  elseif t == "table" then
    local parts = {}
    if is_array(value) then
      for i = 1, #value do
        parts[#parts + 1] = M.encode(value[i])
      end
      if #parts == 0 then
        return "[]"
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(value) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = M.encode(tostring(k)) .. ":" .. M.encode(value[k])
    end
    if #parts == 0 then
      return "{}"
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

-- Minimal JSON decoder (used by the change journal). Returns the parsed value,
-- or nil plus an error message. JSON null decodes to M.null so it round-trips
-- through M.encode and stays distinguishable from an absent value.

local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
  end
  return string.char(0xE0 + math.floor(cp / 0x1000),
    0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
end

local function skip_ws(s, i)
  while s:sub(i, i):match("%s") do
    i = i + 1
  end
  return i
end

local function parse_string(s, i)
  i = i + 1
  local t = {}
  while true do
    local c = s:sub(i, i)
    if c == "" then
      error("unterminated string")
    elseif c == '"' then
      return table.concat(t), i + 1
    elseif c == "\\" then
      local e = s:sub(i + 1, i + 1)
      local map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }
      if map[e] then
        t[#t + 1] = map[e]
        i = i + 2
      elseif e == "u" then
        local cp = tonumber(s:sub(i + 2, i + 5), 16)
        if not cp then
          error("bad unicode escape")
        end
        t[#t + 1] = utf8_encode(cp)
        i = i + 6
      else
        error("bad escape")
      end
    else
      t[#t + 1] = c
      i = i + 1
    end
  end
end

local function parse_number(s, i)
  local num = s:sub(i):match("^-?%d+%.?%d*[eE]?[%+%-]?%d*")
  if not num then
    error("bad number")
  end
  return tonumber(num), i + #num
end

local parse_value

local function parse_object(s, i)
  i = i + 1
  local obj = {}
  i = skip_ws(s, i)
  if s:sub(i, i) == "}" then
    return obj, i + 1
  end
  while true do
    i = skip_ws(s, i)
    if s:sub(i, i) ~= '"' then
      error("expected string key")
    end
    local k
    k, i = parse_string(s, i)
    i = skip_ws(s, i)
    if s:sub(i, i) ~= ":" then
      error("expected ':'")
    end
    local v
    v, i = parse_value(s, i + 1)
    obj[k] = v
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "," then
      i = i + 1
    elseif c == "}" then
      return obj, i + 1
    else
      error("expected ',' or '}'")
    end
  end
end

local function parse_array(s, i)
  i = i + 1
  local arr = {}
  i = skip_ws(s, i)
  if s:sub(i, i) == "]" then
    return arr, i + 1
  end
  while true do
    local v
    v, i = parse_value(s, i)
    arr[#arr + 1] = v
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "," then
      i = i + 1
    elseif c == "]" then
      return arr, i + 1
    else
      error("expected ',' or ']'")
    end
  end
end

parse_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '"' then
    return parse_string(s, i)
  elseif c == '{' then
    return parse_object(s, i)
  elseif c == '[' then
    return parse_array(s, i)
  elseif s:sub(i, i + 3) == "true" then
    return true, i + 4
  elseif s:sub(i, i + 4) == "false" then
    return false, i + 5
  elseif s:sub(i, i + 3) == "null" then
    return M.null, i + 4
  end
  return parse_number(s, i)
end

function M.decode(str)
  local ok, res = pcall(function()
    local v, i = parse_value(str, 1)
    i = skip_ws(str, i)
    if i <= #str then
      error("trailing data")
    end
    return v
  end)
  if not ok then
    return nil, res
  end
  return res
end

return M
