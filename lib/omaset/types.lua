-- Type coercion and validation for setting values coming in from the CLI.

local M = {}

-- Coerce a CLI string into the setting's declared type.
-- Returns the coerced value, or nil plus an error message.
function M.coerce(str, setting)
  local t = setting.type or "string"
  if t == "string" then
    return str
  elseif t == "int" then
    local n = tonumber(str)
    if not n or n % 1 ~= 0 then
      return nil, "expected an integer, got '" .. tostring(str) .. "'"
    end
    return n
  elseif t == "float" then
    local n = tonumber(str)
    if not n then
      return nil, "expected a number, got '" .. tostring(str) .. "'"
    end
    return n
  elseif t == "bool" then
    if str == "true" or str == "1" or str == "yes" or str == "on" then
      return true
    elseif str == "false" or str == "0" or str == "no" or str == "off" then
      return false
    end
    return nil, "expected true/false, got '" .. tostring(str) .. "'"
  elseif t == "enum" then
    local ok = true
    if setting.options then
      ok = false
      for _, opt in ipairs(setting.options) do
        if opt == str then
          ok = true
          break
        end
      end
    end
    if not ok then
      return nil, "'" .. tostring(str) .. "' is not a valid option"
    end
    return str
  end
  return nil, "unknown type '" .. tostring(t) .. "'"
end

-- Validate a coerced value against min/max.
function M.check_range(value, setting)
  if type(value) ~= "number" then
    return true
  end
  if setting.min ~= nil and value < setting.min then
    return false, "value " .. value .. " below minimum " .. setting.min
  end
  if setting.max ~= nil and value > setting.max then
    return false, "value " .. value .. " above maximum " .. setting.max
  end
  return true
end

return M
