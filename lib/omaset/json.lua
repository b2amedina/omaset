-- Minimal JSON encoder. No external deps.

local M = {}

-- Sentinel that encodes as JSON null (Lua tables cannot hold a nil-valued key).
M.null = {}

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

return M
