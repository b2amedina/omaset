-- Backend registry. Backends self-register by name, and load_dir() discovers
-- backend modules in a directory (skipping init.lua).

local util = require("omaset.util")

local M = {}

M.registry = {}

function M.register(name, backend)
  M.registry[name] = backend
  return backend
end

function M.get(name)
  return M.registry[name]
end

function M.names()
  local names = {}
  for k in pairs(M.registry) do
    names[#names + 1] = k
  end
  table.sort(names)
  return names
end

-- Load every backend module in a directory. Each module calls register() as
-- a side effect. Returns a list of error strings.
function M.load_dir(dir)
  local errors = {}
  if not dir or dir == "" then
    return errors
  end
  for _, file in ipairs(util.list_lua_files(dir)) do
    local base = file:match("([^/]+)$") or file
    if base ~= "init.lua" then
      local chunk, err = loadfile(file)
      if not chunk then
        errors[#errors + 1] = file .. ": " .. tostring(err)
      else
        local ok, runerr = pcall(chunk)
        if not ok then
          errors[#errors + 1] = file .. ": " .. tostring(runerr)
        end
      end
    end
  end
  return errors
end

return M
