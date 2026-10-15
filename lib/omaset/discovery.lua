-- Discover and evaluate settings files (the extension point).

local dsl = require("omaset.dsl")
local util = require("omaset.util")

local M = {}

-- Evaluate a single settings file into the current DSL registry.
function M.load_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil, "cannot open " .. path
  end
  local content = f:read("*a")
  f:close()

  local env = dsl.environment()
  local chunk, err = load(content, "@" .. path, "t", env)
  if not chunk then
    return nil, path .. ": " .. tostring(err)
  end
  local ok, runerr = pcall(chunk)
  if not ok then
    return nil, path .. ": " .. tostring(runerr)
  end
  return true
end

-- Load every *.lua in the given directories, in order.
-- Later directories can extend or override settings defined earlier.
function M.load_dirs(dirs)
  local errors = {}
  for _, dir in ipairs(dirs) do
    if dir then
      for _, file in ipairs(util.list_lua_files(dir)) do
        local ok, err = M.load_file(file)
        if not ok then
          errors[#errors + 1] = err
        end
      end
    end
  end
  return errors
end

return M
