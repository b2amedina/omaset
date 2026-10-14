-- omaset core: settings registry, schema, and command dispatch.

local util = require("omaset.util")
local json = require("omaset.json")
local types = require("omaset.types")
local dsl = require("omaset.dsl")
local discovery = require("omaset.discovery")

local M = {}

M.backends = {
  ["hypr-lua"] = require("omaset.backends.hypr_lua"),
  ["shell-json"] = require("omaset.backends.shell_json"),
}

local root = nil
local user_settings_dir = nil

function M.bootstrap(opts)
  root = opts.root
  user_settings_dir = opts.user_settings_dir
end

function M.settings_dirs()
  local dirs = { root .. "/share/settings" }
  if user_settings_dir and user_settings_dir ~= "" then
    dirs[#dirs + 1] = user_settings_dir
  end
  return dirs
end

function M.load()
  dsl.panels = {}
  local errors = discovery.load_dirs(M.settings_dirs())
  for _, err in ipairs(errors) do
    io.stderr:write("omaset: " .. err .. "\n")
  end
  return dsl.panels
end

function M.find_setting(id)
  for _, p in ipairs(dsl.panels) do
    for _, s in ipairs(p.settings) do
      if s.id == id then
        return s, p
      end
    end
  end
end

function M.backend_for(setting)
  local backend = M.backends[setting.backend]
  if not backend then
    return nil, "unknown backend '" .. tostring(setting.backend) .. "'"
  end
  return backend
end

function M.read_value(setting)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.read(setting)
end

function M.write_value(setting, value)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.write(setting, value)
end

function M.schema()
  local out = { panels = {} }
  for _, p in ipairs(dsl.panels) do
    local panel = { id = p.id, title = p.title, settings = {} }
    for _, s in ipairs(p.settings) do
      local entry = {}
      for k, v in pairs(s) do
        if k ~= "get" and k ~= "set" and type(v) ~= "function" then
          entry[k] = v
        end
      end
      entry.value = M.read_value(s)
      panel.settings[#panel.settings + 1] = entry
    end
    out.panels[#out.panels + 1] = panel
  end
  return out
end

local function die(msg)
  io.stderr:write("omaset: " .. msg .. "\n")
  os.exit(1)
end

local function cmd_list()
  M.load()
  for _, p in ipairs(dsl.panels) do
    print("# " .. p.title)
    for _, s in ipairs(p.settings) do
      local v = M.read_value(s)
      print(string.format("  %-24s %s", s.id, tostring(v)))
    end
  end
end

local function cmd_schema()
  M.load()
  print(json.encode(M.schema()))
end

local function cmd_get(args)
  M.load()
  local s = M.find_setting(args[1])
  if not s then
    die("unknown setting: " .. tostring(args[1]))
  end
  print(json.encode({ id = s.id, value = M.read_value(s) }))
end

local function cmd_set(args)
  M.load()
  local s = M.find_setting(args[1])
  if not s then
    die("unknown setting: " .. tostring(args[1]))
  end
  local value, err = types.coerce(args[2], s)
  if value == nil then
    die(err)
  end
  local ok, rerr = types.check_range(value, s)
  if not ok then
    die(rerr)
  end
  local wok, werr = M.write_value(s, value)
  if not wok then
    die(werr)
  end
  print(json.encode({ id = s.id, value = value, ok = true }))
end

local function usage()
  local text = [[
omaset — keyboard-first Omarchy settings

Usage:
  omaset list            list panels and settings with current values
  omaset schema          print the full schema (JSON)
  omaset get <id>        print a single setting's value (JSON)
  omaset set <id> <val>  write a value and apply it
]]
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  print(text)
end

function M.main(arg)
  local cmd = arg[1]
  local args = { select(2, unpack(arg)) }
  if cmd == "list" then
    cmd_list()
  elseif cmd == "schema" then
    cmd_schema()
  elseif cmd == "get" then
    cmd_get(args)
  elseif cmd == "set" then
    cmd_set(args)
  else
    usage()
  end
end

return M
