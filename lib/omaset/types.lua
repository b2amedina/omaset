-- Type coercion and validation for setting values coming in from the CLI.

local M = {}

-- Parse a wall-clock time entered as 24-hour ("20:30", "7:30") or 12-hour
-- ("8:30 PM", "8:30pm", "8:30 p.m.") and return it canonicalized to zero-padded
-- 24-hour "HH:MM". Returns nil when the string is not a valid time. This is the
-- single source of truth shared by coerce/validate/normalize and the hyprsunset
-- backend, so every entry path stores the same canonical form.
function M.parse_time(str)
  local s = tostring(str):gsub("^%s+", ""):gsub("%s+$", "")
  local h, m = s:match("^(%d%d?):(%d%d)$")
  if h then
    local hh, mm = tonumber(h), tonumber(m)
    if hh and hh <= 23 and mm <= 59 then
      return string.format("%02d:%02d", hh, mm)
    end
    return nil
  end
  local h12, m12, ap = s:match("^(%d%d?):(%d%d)%s*([AaPp])%.?[Mm]%.?$")
  if h12 then
    local hh, mm = tonumber(h12), tonumber(m12)
    if hh and hh >= 1 and hh <= 12 and mm <= 59 then
      local pm = (ap == "p" or ap == "P")
      if hh == 12 then
        hh = pm and 12 or 0
      elseif pm then
        hh = hh + 12
      end
      return string.format("%02d:%02d", hh, mm)
    end
    return nil
  end
  return nil
end

-- Canonicalize a value the way the backend will store it. For most types this
-- is a no-op; for `time` it parses and zero-pads so the CLI, the MCP server,
-- and the backend all agree on the same stored string.
function M.normalize(value, setting)
  if (setting.type or "string") == "time" then
    return M.parse_time(value) or value
  end
  return value
end

-- Numeric settings may declare a fixed set of labelled choices, e.g.
-- options = { { value = 0, label = "None" }, { value = 1, label = "Full" } }.
-- Such a setting keeps its numeric type and stored value; the labels are UI
-- and CLI metadata. Returns the option list, or nil for a plain setting.
function M.choice_options(setting)
  if setting and type(setting.options) == "table"
    and type(setting.options[1]) == "table" then
    return setting.options
  end
  return nil
end

-- The stored values a setting's declared options name, plain or labelled.
function M.option_values(setting)
  local out = {}
  for _, o in ipairs(setting.options or {}) do
    if type(o) == "table" then
      out[#out + 1] = o.value
    else
      out[#out + 1] = o
    end
  end
  return out
end

-- Whether an enum value is allowed: one of its declared options, or a custom
-- value the setting has held (`customs`, from the journal and the current
-- value). Backends with enum values they own call this from their validate hook.
function M.is_allowed(setting, value, customs)
  local needle = tostring(value)
  for _, v in ipairs(M.option_values(setting)) do
    if tostring(v) == needle then return true end
  end
  for _, v in ipairs(customs or {}) do
    if tostring(v) == needle then return true end
  end
  return false
end

-- Enum membership for a backend that owns its enum's values, and for settings
-- whose values are closed (preferences). Returns true, or nil plus an error.
function M.check_allowed(setting, value, customs)
  if (setting.type or "string") ~= "enum" or M.is_allowed(setting, value, customs) then
    return true
  end
  local labels = {}
  for _, o in ipairs(setting.options or {}) do
    labels[#labels + 1] = type(o) == "table" and tostring(o.label) or tostring(o)
  end
  return nil, "'" .. tostring(value) .. "' is not an allowed value for "
    .. tostring(setting.id or setting.key) .. " (choose from: "
    .. table.concat(labels, ", ") .. ")"
end

-- Coerce a CLI string into the setting's declared type.
-- Returns the coerced value, or nil plus an error message.
function M.coerce(str, setting)
  local t = setting.type or "string"
  if t == "string" then
    return str
  elseif t == "int" then
    local n = tonumber(str)
    if not n then
      local choices = M.choice_options(setting)
      if choices then
        local needle = tostring(str):lower()
        for _, opt in ipairs(choices) do
          if tostring(opt.label):lower() == needle then
            return opt.value
          end
        end
      end
      return nil, "expected an integer, got '" .. tostring(str) .. "'"
    end
    if n % 1 ~= 0 then
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
    -- Labelled options: accept the stored value, or its label (so the CLI
    -- takes both "dwindle" and "Tiling"). Any other string is kept as-is: a
    -- hand-edited value is a value too, and the backend decides whether to
    -- accept a write of it (see the backend validate hook).
    local needle = tostring(str)
    local choices = M.choice_options(setting)
    if choices then
      for _, opt in ipairs(choices) do
        if tostring(opt.value) == needle then return needle end
      end
      for _, opt in ipairs(choices) do
        if tostring(opt.label):lower() == needle:lower() then return tostring(opt.value) end
      end
    end
    return needle
  elseif t == "time" then
    local canonical = M.parse_time(str)
    if not canonical then
      return nil, "expected HH:MM or h:mm AM/PM, got '" .. tostring(str) .. "'"
    end
    return canonical
  end
  return nil, "unknown type '" .. tostring(t) .. "'"
end

-- Validate a JSON value against a setting's declared type (the typed sibling of
-- coerce, which accepts strings). Returns true, or nil plus an error message.
function M.validate(value, setting)
  local t = setting.type or "string"
  if t == "bool" then
    if type(value) ~= "boolean" then
      return nil, "expected a boolean, got " .. tostring(value)
    end
  elseif t == "int" then
    if type(value) ~= "number" or value % 1 ~= 0 then
      return nil, "expected an integer, got " .. tostring(value)
    end
  elseif t == "float" then
    if type(value) ~= "number" then
      return nil, "expected a number, got " .. tostring(value)
    end
  elseif t == "enum" then
    -- Type only. Whether a string is an allowed value is the backend's call
    -- (its validate hook), so hand-edited values stay valid.
    if type(value) ~= "string" then
      return nil, "expected a string, got " .. tostring(value)
    end
  elseif t == "string" then
    if type(value) ~= "string" then
      return nil, "expected a string, got " .. tostring(value)
    end
  elseif t == "time" then
    if type(value) ~= "string" or M.parse_time(value) == nil then
      return nil, "expected HH:MM or h:mm AM/PM, got " .. tostring(value)
    end
  else
    return nil, "unknown type '" .. tostring(t) .. "'"
  end
  local ok, err = M.check_range(value, setting)
  if not ok then
    return nil, err
  end
  return true
end

-- Validate a keyed setting's key argument.
function M.validate_key(setting, key)
  local label = setting.key_label or "key"
  if key == nil or key == "" then
    return false, "requires a " .. label
  end
  local kt = setting.key_type or "string"
  if kt == "int" then
    if not tostring(key):match("^%d+$") then
      return false, "expected an integer " .. label .. ", got '" .. tostring(key) .. "'"
    end
  elseif kt == "string" then
    if tostring(key):find("[%s'\"`$;&|<>(){}%[%]]") then
      return false, label .. " contains invalid characters"
    end
  end
  return true
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
