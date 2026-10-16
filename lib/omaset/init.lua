-- omaset core: settings registry, schema, and command dispatch.

local util = require("omaset.util")
local json = require("omaset.json")
local types = require("omaset.types")
local dsl = require("omaset.dsl")
local discovery = require("omaset.discovery")
local backends = require("omaset.backends")

local M = {}

local function jnull(v)
  if v == nil then
    return json.null
  end
  return v
end

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

function M.read_value(setting, key)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.read(setting, key)
end

function M.write_value(setting, key, value)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.write(setting, key, value)
end

function M.read_default(setting, key)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.read_default(setting, key)
end

function M.reset_value(setting, key)
  local backend, err = M.backend_for(setting)
  if not backend then
    return nil, err
  end
  return backend.reset(setting, key)
end

function M.keys(setting)
  local backend = M.backend_for(setting)
  if not backend or not backend.keys then
    return nil
  end
  return backend.keys(setting)
end

function M.keys_all(setting)
  local backend = M.backend_for(setting)
  if not backend then
    return nil
  end
  if backend.keys_all then
    return backend.keys_all(setting)
  end
  if backend.keys then
    return backend.keys(setting)
  end
  return nil
end

function M.schema()
  local out = { schema_version = 1, panels = {} }
  for _, p in ipairs(dsl.panels) do
    local panel = { id = p.id, title = p.title, settings = {} }
    for _, s in ipairs(p.settings) do
      local entry = {}
      for k, v in pairs(s) do
        if k ~= "get" and k ~= "set" and type(v) ~= "function" then
          entry[k] = v
        end
      end
      if s.keyed then
        entry.value = json.null
      else
        entry.value = jnull(M.read_value(s))
      end
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
  if def == nil then
    return false
  end
  if cur == nil then
    return true
  end
  return cur ~= def
end

local function setting_row(s, indent)
  local pad = string.rep("  ", indent or 0)
  if s.keyed then
    return pad .. string.format("%-24s (keyed: %s)", s.id, s.key_label or "key")
  end
  local v = M.read_value(s)
  return pad .. string.format("%-24s %s", s.id, tostring(v))
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

local function resolve_args(s, pos)
  -- Returns (key, value_str) for a setting, handling keyed settings where the
  -- first positional after the id is the key.
  if s.keyed then
    local key = pos[2]
    local ok, kerr = types.validate_key(s, key)
    if not ok then
      die(kerr)
    end
    return key, pos[3]
  end
  return nil, pos[2]
end

local function cmd_get(flags, pos)
  M.load()
  local s = M.find_setting(pos[1])
  if not s then
    die("unknown setting: " .. tostring(pos[1]))
  end
  local key, _ = resolve_args(s, pos)
  local value = M.read_value(s, key)
  if flags["--plain"] then
    print(tostring(value))
    return
  end
  local out = { id = s.id }
  if key ~= nil then
    out.key = key
  end
  out.value = jnull(value)
  print(json.encode(out))
end

local function cmd_set(flags, pos)
  M.load()
  local s = M.find_setting(pos[1])
  if not s then
    die("unknown setting: " .. tostring(pos[1]))
  end
  local key, value_str = resolve_args(s, pos)
  if value_str == nil then
    die("missing value for setting: " .. s.id)
  end
  local value, err = types.coerce(value_str, s)
  if value == nil then
    die(err)
  end
  local ok, rerr = types.check_range(value, s)
  if not ok then
    die(rerr)
  end
  local wok, werr = M.write_value(s, key, value)
  if not wok then
    die(werr)
  end
  if flags["--plain"] then
    print("ok")
    return
  end
  local out = { id = s.id }
  if key ~= nil then
    out.key = key
  end
  out.value = value
  out.ok = true
  print(json.encode(out))
end

local function cmd_reset(flags, pos)
  M.load()
  local s = M.find_setting(pos[1])
  if not s then
    die("unknown setting: " .. tostring(pos[1]))
  end

  if flags["--all"] then
    if not s.keyed then
      die("setting is not keyed: " .. s.id)
    end
    local keys = M.keys_all(s) or {}
    local count = 0
    for _, k in ipairs(keys) do
      local rok, rerr = M.reset_value(s, k)
      if rok then
        count = count + 1
      else
        io.stderr:write("omaset: " .. rerr .. "\n")
      end
    end
    if flags["--plain"] then
      print("ok")
    else
      print(json.encode({ id = s.id, ok = true, count = count }))
    end
    return
  end

  local key, _ = resolve_args(s, pos)
  local rok, rerr = M.reset_value(s, key)
  if not rok then
    die(rerr)
  end
  if flags["--plain"] then
    print("ok")
    return
  end
  local out = { id = s.id }
  if key ~= nil then
    out.key = key
  end
  out.ok = true
  print(json.encode(out))
end

local function collect_changed()
  local out = {}
  for _, p in ipairs(dsl.panels) do
    for _, s in ipairs(p.settings) do
      if s.keyed then
        for _, k in ipairs(M.keys(s) or {}) do
          local cur = M.read_value(s, k)
          local def = M.read_default(s, k)
          if value_changed(cur, def) then
            out[#out + 1] = { id = s.id, key = k, panel = p.id, label = s.label, value = cur, default = def }
          end
        end
      else
        local cur = M.read_value(s)
        local def = M.read_default(s)
        if value_changed(cur, def) then
          out[#out + 1] = { id = s.id, panel = p.id, label = s.label, value = cur, default = def }
        end
      end
    end
  end
  return out
end

local function display_id(r)
  if r.key then
    return r.id .. ":" .. r.key
  end
  return r.id
end

local function cmd_changed(flags)
  M.load()
  local changed = collect_changed()
  if flags["--json"] then
    print(json.encode({ changed = changed }))
    return
  end
  for _, r in ipairs(changed) do
    print(string.format("%-24s %s -> %s (default)", display_id(r), tostring(r.value), tostring(r.default)))
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
        local v = s.keyed and nil or M.read_value(s)
        out[#out + 1] = { id = s.id, panel = p.id, label = s.label, value = jnull(v) }
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

local function cmd_keys(flags, pos)
  M.load()
  local s = M.find_setting(pos[1])
  if not s then
    die("unknown setting: " .. tostring(pos[1]))
  end
  if not s.keyed then
    die("setting is not keyed: " .. s.id)
  end
  local keys = M.keys(s)
  if keys == nil then
    die("setting has no keys: " .. s.id)
  end
  if flags["--json"] then
    print(json.encode({ id = s.id, keys = keys }))
    return
  end
  for _, k in ipairs(keys) do
    print(k)
  end
end

local function usage_text()
  local text = [[
omaset — keyboard-first Omarchy settings

Usage:
  omaset list [--json]              list panels and settings with values
  omaset schema                     full schema as JSON
  omaset get <id> [<key>] [--plain]   read a setting
  omaset set <id> [<key>] <val> [--plain]  write a setting
  omaset reset <id> [<key>|--all] [--plain]  revert omaset's override
  omaset changed [--json]           settings that differ from defaults
  omaset search <query> [--json]    find settings by id or label
  omaset help <id>                  show one setting's full spec
  omaset keys <id> [--json]         list keys of a keyed setting

Every command accepts --help (or -h) for command-specific help:
  omaset set --help                 # general help for a command
  omaset set <id> --help            # help for a specific setting
  omaset --version                  # print the version
]]
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local COMMAND_HELP = {
  list = "omaset list [--json]\n  List panels and settings with current values.",
  schema = "omaset schema\n  Print the full schema (panels, settings, current values) as JSON.",
  get = "omaset get <id> [<key>] [--plain]\n  Read one setting. Keyed settings take a key. --plain prints the bare value.",
  set = "omaset set <id> [<key>] <val> [--plain]\n  Write a value, applying and validating via the backend.",
  reset = "omaset reset <id> [<key>|--all] [--plain]\n  Revert omaset's override so the Omarchy default applies. Keyed settings take a key, or --all to reset every key.",
  changed = "omaset changed [--json]\n  List settings whose effective value differs from the Omarchy default.",
  search = "omaset search <query> [--json]\n  Find settings by id or label substring.",
  help = "omaset help <id>\n  Show one setting's full spec (type, options, value, default).",
  keys = "omaset keys <id> [--json]\n  List the keys of a keyed setting (e.g. workspace numbers).",
}

local function value_hint(setting)
  local t = setting.type or "string"
  if t == "enum" and setting.options then
    return "<" .. table.concat(setting.options, "|") .. ">"
  elseif t == "int" or t == "float" then
    if setting.min ~= nil and setting.max ~= nil then
      return "<" .. tostring(setting.min) .. ".." .. tostring(setting.max) .. ">"
    end
    return t == "int" and "<int>" or "<float>"
  elseif t == "bool" then
    return "<true|false>"
  end
  return "<value>"
end

local function key_arg(setting)
  if setting.keyed then
    return " <" .. (setting.key_label or "key") .. ">"
  end
  return ""
end

local function setting_help(setting)
  local lines = {}
  lines[#lines + 1] = setting.id .. " — " .. setting.label

  local ka = key_arg(setting)
  lines[#lines + 1] = "  get:     omaset get " .. setting.id .. ka
  lines[#lines + 1] = "  set:     omaset set " .. setting.id .. ka .. " " .. value_hint(setting)
  lines[#lines + 1] = "  reset:   omaset reset " .. setting.id .. ka

  if setting.keyed then
    lines[#lines + 1] = "  key:     " .. (setting.key_label or "key") .. " (" .. (setting.key_type or "string") .. ")"
  end

  local t = setting.type or "string"
  local type_line = "  type:    " .. t
  if (t == "int" or t == "float") and (setting.min ~= nil or setting.max ~= nil) then
    type_line = type_line .. " (" .. tostring(setting.min or "-inf") .. ".." .. tostring(setting.max or "inf") .. ")"
  end
  lines[#lines + 1] = type_line

  if setting.options then
    lines[#lines + 1] = "  options: " .. table.concat(setting.options, ", ")
  end

  if setting.keyed then
    lines[#lines + 1] = "  value:   (keyed)"
  else
    lines[#lines + 1] = "  value:   " .. tostring(M.read_value(setting))
  end
  lines[#lines + 1] = "  default: " .. tostring(M.read_default(setting))
  return table.concat(lines, "\n")
end

local function command_help(cmd, setting)
  if setting then
    if cmd == "get" then
      return "omaset get " .. setting.id .. key_arg(setting) .. "\n  " .. setting.label
    elseif cmd == "set" then
      return "omaset set " .. setting.id .. key_arg(setting) .. " " .. value_hint(setting) .. "\n  " .. setting.label
    elseif cmd == "reset" then
      local extra = setting.keyed and " [--all]" or ""
      return "omaset reset " .. setting.id .. key_arg(setting) .. extra .. "\n  " .. setting.label
    end
  end
  return COMMAND_HELP[cmd] or ("No help for '" .. tostring(cmd) .. "'.\n\n" .. usage_text())
end

local function cmd_help(pos)
  M.load()
  local id = pos[1]
  if not id then
    print(usage_text())
    return
  end
  local s = M.find_setting(id)
  if not s then
    die("unknown setting: " .. id)
  end
  print(setting_help(s))
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
  if cmd == "--help" or cmd == "-h" then
    print(usage_text())
    return
  end

  local args = { select(2, unpack(arg)) }
  local flags, pos = split_args(args)

  if flags["--help"] or flags["-h"] then
    if cmd == "get" or cmd == "set" or cmd == "reset" then
      M.load()
      local s = M.find_setting(pos[1])
      if s then
        print(command_help(cmd, s))
        return
      end
    end
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
  elseif cmd == "help" then
    cmd_help(pos)
  elseif cmd == "keys" then
    cmd_keys(flags, pos)
  else
    io.stderr:write("omaset: unknown command: " .. tostring(cmd) .. "\n\n" .. usage_text() .. "\n")
    os.exit(1)
  end
end

return M
