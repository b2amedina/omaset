-- Shared helpers for omaset.

local M = {}

function M.file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

function M.read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

function M.write_file(path, content)
  local f = io.open(path, "wb")
  if not f then
    return nil, "cannot open " .. path .. " for writing"
  end
  f:write(content)
  f:close()
  return true
end

function M.shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Run a command, capturing combined stdout+stderr and the exit code.
function M.run_capture(cmd)
  local p = io.popen(cmd .. " 2>&1")
  if not p then
    return nil, nil, "cannot run: " .. cmd
  end
  local out = p:read("*a")
  local ok, why, code = p:close()
  local exit_code
  if ok then
    exit_code = 0
  elseif why == "exit" then
    exit_code = code
  else
    exit_code = 1
  end
  return out, exit_code
end

local cmd_exists_cache = {}

function M.cmd_exists(name)
  if cmd_exists_cache[name] ~= nil then
    return cmd_exists_cache[name]
  end
  local out = M.run_capture("command -v " .. name .. " 2>/dev/null")
  local found = out ~= nil and out:gsub("%s+", "") ~= ""
  cmd_exists_cache[name] = found
  return found
end

-- Deep-merge src into dst (tables recurse, everything else overwrites).
function M.deep_merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      M.deep_merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

-- Get a value by dotted key ("general.gaps_in").
function M.deep_get(t, dotted)
  local cur = t
  for part in string.gmatch(dotted, "[^.]+") do
    if type(cur) ~= "table" then
      return nil
    end
    cur = cur[part]
  end
  return cur
end

-- Set a value by dotted key, creating intermediate tables as needed.
function M.deep_set(t, dotted, value)
  local parts = {}
  for part in string.gmatch(dotted, "[^.]+") do
    parts[#parts + 1] = part
  end
  local cur = t
  for i = 1, #parts - 1 do
    local key = parts[i]
    if type(cur[key]) ~= "table" then
      cur[key] = {}
    end
    cur = cur[key]
  end
  cur[parts[#parts]] = value
  return t
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

-- Serialize a Lua value to source. Only scalars and string-keyed tables are
-- expected in managed config blocks.
function M.serialize(value, indent)
  indent = indent or 0
  local t = type(value)
  if t == "number" or t == "boolean" then
    return tostring(value)
  elseif t == "string" then
    return string.format("%q", value)
  elseif t == "table" then
    local pad = string.rep("  ", indent)
    local pad1 = string.rep("  ", indent + 1)
    local parts = {}
    if is_array(value) then
      for i = 1, #value do
        parts[#parts + 1] = pad1 .. M.serialize(value[i], indent + 1)
      end
    else
      local keys = {}
      for k in pairs(value) do
        keys[#keys + 1] = k
      end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do
        local v = value[k]
        local line
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
          line = pad1 .. k
        else
          line = pad1 .. "[" .. string.format("%q", k) .. "]"
        end
        parts[#parts + 1] = line .. " = " .. M.serialize(v, indent + 1)
      end
    end
    if #parts == 0 then
      return "{}"
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
  end
  return "nil"
end

return M
