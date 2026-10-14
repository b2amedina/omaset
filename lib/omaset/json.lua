-- Minimal JSON encoder. No external deps.

local M = {}

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
  if value == nil then
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
    else
      for k, v in pairs(value) do
        parts[#parts + 1] = M.encode(tostring(k)) .. ":" .. M.encode(v)
      end
    end
    if #parts == 0 then
      return "{}"
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

return M
