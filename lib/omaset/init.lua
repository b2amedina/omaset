-- omaset core: settings registry, schema, and command dispatch.

local util = require("omaset.util")
local json = require("omaset.json")
local types = require("omaset.types")
local dsl = require("omaset.dsl")
local discovery = require("omaset.discovery")
local backends = require("omaset.backends")

local M = {}

local root = nil
local user_settings_dir = nil
local user_backends_dir = nil

function M.bootstrap(opts)
  root = opts.root
  user_settings_dir = opts.user_settings_dir
  user_backends_dir = opts.user_backends_dir
end

function M.load_backends()
  for _, err in ipairs(backends.load_dir(root .. "/lib/omaset/backends")) do
    io.stderr:write("omaset: " .. err .. "\n")
  end
  for _, err in ipairs(backends.load_dir(user_backends_dir)) do
    io.stderr:write("omaset: " .. err .. "\n")
  end
end

function M.settings_dirs()
  local dirs = { root .. "/share/settings" }
  if user_settings_dir and user_settings_dir ~= "" then
    dirs[#dirs + 1] = user_settings_dir
  end
  return dirs
end

function M.load()
  M.load_backends()
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
  local backend = backends.get(setting.backend)
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

function M.read_default(setting)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.read_default(setting)
end

function M.reset_value(setting)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.reset(setting)
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

M.VERSION = "0.1.0"

local function die(msg)
  io.stderr:write("omaset: " .. msg .. "\n")
  os.exit(1)
end

local function value_changed(cur, def)
  if cur == nil and def == nil then
    return false
  end
  if cur == nil or def == nil then
    return true
  end
  return cur ~= def
end

local function setting_row(s, indent)
  local v = M.read_value(s)
  return string.rep("  ", indent or 0) .. string.format("%-24s %s", s.id, tostring(v))
end

local function cmd_list(flags)
  M.load()
  if flags["--json"] then
    print(json.encode(M.schema()))
    return
  end
  for _, p in ipairs(dsl.panels) do
    print("# " .. p.title)
    for _, s in ipairs(p.settings) do
      print(setting_row(s, 1))
    end
  end
end

local function cmd_schema()
  M.load()
  print(json.encode(M.schema()))
end

local function cmd_get(flags, pos)
  M.load()
  local s = M.find_setting(pos[1])
  if not s then
    die("unknown setting: " .. tostring(pos[1]))
  end
  local value = M.read_value(s)
  if flags["--plain"] then
    print(tostring(value))
  else
    print(json.encode({ id = s.id, value = value }))
  end
end

local function cmd_set(flags, pos)
  M.load()
  local s = M.find_setting(pos[1])
  if not s then
    die("unknown setting: " .. tostring(pos[1]))
  end
  if pos[2] == nil then
    die("missing value for setting: " .. s.id)
  end
  local value, err = types.coerce(pos[2], s)
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
  if flags["--plain"] then
    print("ok")
  else
    print(json.encode({ id = s.id, value = value, ok = true }))
  end
end

local function cmd_reset(flags, pos)
  M.load()
  local s = M.find_setting(pos[1])
  if not s then
    die("unknown setting: " .. tostring(pos[1]))
  end
  local rok, rerr = M.reset_value(s)
  if not rok then
    die(rerr)
  end
  if flags["--plain"] then
    print("ok")
  else
    print(json.encode({ id = s.id, ok = true }))
  end
end

local function collect_changed()
  local out = {}
  for _, p in ipairs(dsl.panels) do
    for _, s in ipairs(p.settings) do
      local cur = M.read_value(s)
      local def = M.read_default(s)
      if value_changed(cur, def) then
        out[#out + 1] = { id = s.id, panel = p.id, label = s.label, value = cur, default = def }
      end
    end
  end
  return out
end

local function cmd_changed(flags)
  M.load()
  local changed = collect_changed()
  if flags["--json"] then
    print(json.encode({ changed = changed }))
    return
  end
  for _, r in ipairs(changed) do
    print(string.format("%-24s %s -> %s (default)", r.id, tostring(r.value), tostring(r.default)))
  end
end

local function cmd_search(flags, pos)
  M.load()
  local q = tostring(pos[1] or ""):lower()
  local out = {}
  for _, p in ipairs(dsl.panels) do
    for _, s in ipairs(p.settings) do
      local hit = (q == "") or s.id:lower():find(q, 1, true)
        or s.label:lower():find(q, 1, true)
      if hit then
        out[#out + 1] = { id = s.id, panel = p.id, label = s.label, value = M.read_value(s) }
      end
    end
  end
  if flags["--json"] then
    print(json.encode({ results = out }))
    return
  end
  for _, r in ipairs(out) do
    print(string.format("%-24s %-8s %s", r.id, tostring(r.value), r.label))
  end
end

local function usage_text()
  local text = [[
omaset — keyboard-first Omarchy settings

Usage:
  omaset list [--json]              list panels and settings with values
  omaset schema                     full schema as JSON
  omaset get <id> [--plain]         read a setting
  omaset set <id> <val> [--plain]   write a setting
  omaset reset <id> [--plain]       restore a setting to default
  omaset changed [--json]           settings that differ from defaults
  omaset search <query> [--json]    find settings by id or label
  omaset --version                  print the version
]]
  text = text:gsub("^%s+", "")
  return text:gsub("%s+$", "")
end

local COMMAND_HELP = {
  list = "omaset list [--json]\n  List panels and settings with current values.",
  schema = "omaset schema\n  Print the full schema (panels, settings, current values) as JSON.",
  get = "omaset get <id> [--plain]\n  Read one setting. --plain prints the bare value.",
  set = "omaset set <id> <val> [--plain]\n  Write a value, applying and validating via the backend.",
  reset = "omaset reset <id> [--plain]\n  Restore a setting to its Omarchy default.",
  changed = "omaset changed [--json]\n  List settings whose value differs from the default.",
  search = "omaset search <query> [--json]\n  Find settings by id or label substring.",
}

local function command_help(cmd)
  return COMMAND_HELP[cmd] or ("No help for '" .. tostring(cmd) .. "'.\n\n" .. usage_text())
end

local function split_args(args)
  local flags = {}
  local pos = {}
  for _, a in ipairs(args) do
    if a:sub(1, 1) == "-" and tonumber(a) == nil then
      flags[a] = true
    else
      pos[#pos + 1] = a
    end
  end
  return flags, pos
end

function M.main(arg)
  local cmd = arg[1]

  if cmd == nil then
    print(usage_text())
    return
  end
  if cmd == "--version" or cmd == "version" then
    print("omaset " .. M.VERSION)
    return
  end
  if cmd == "--help" or cmd == "-h" or cmd == "help" then
    print(usage_text())
    return
  end

  local args = { select(2, unpack(arg)) }
  local flags, pos = split_args(args)

  if flags["--help"] or flags["-h"] then
    print(command_help(cmd))
    return
  end

  if cmd == "list" then
    cmd_list(flags)
  elseif cmd == "schema" then
    cmd_schema()
  elseif cmd == "get" then
    cmd_get(flags, pos)
  elseif cmd == "set" then
    cmd_set(flags, pos)
  elseif cmd == "reset" then
    cmd_reset(flags, pos)
  elseif cmd == "changed" then
    cmd_changed(flags)
  elseif cmd == "search" then
    cmd_search(flags, pos)
  else
    io.stderr:write("omaset: unknown command: " .. tostring(cmd) .. "\n\n" .. usage_text() .. "\n")
    os.exit(1)
  end
end

return M
