-- omaset CLI adapter: argv parsing, human/JSON formatting, and dispatch.
-- Every operation is implemented once in service.lua; this file only decides
-- how a command line maps onto it and how the result is printed.

local json = require("omaset.json")
local types = require("omaset.types")
local core = require("omaset")
local service = require("omaset.service")
local journal = require("omaset.journal")
local i18n = require("omaset.i18n")

local grouped = core.grouped
local sub_keys = core.sub_keys

local M = {}

-- Only human-facing strings localize (like omarchy's omarchy-i18n): setting
-- labels, panel/section titles, and status markers. Command names, flags,
-- value tokens, JSON/--plain output, and the MCP contract stay English.

local function tr(key, fallback)
  return i18n.t(key, fallback)
end

local function panel_title(p)
  return tr("panel." .. p.id, p.title)
end

local function section_title(panel_id, s)
  if s.section_key and s.section_key ~= "" then
    return tr("section." .. panel_id .. "." .. s.section_key, s.section)
  end
  return s.section or ""
end

local function setting_label(s)
  return tr("setting." .. s.id, s.label)
end

local function setting_description(s)
  if s.description then
    return tr("setting." .. s.id .. ".description", s.description)
  end
  return nil
end

-- Localized display label for one enum/choice option value.
local function option_label(setting_id, value, fallback)
  return tr("setting." .. setting_id .. ".option." .. tostring(value), fallback)
end

local function default_marker()
  return tr("cli.defaultMarker", "(default)")
end

local function die(msg)
  io.stderr:write("omaset: " .. msg .. "\n")
  os.exit(1)
end

local function plain_value(v)
  if v == nil or v == json.null then
    return "nil"
  end
  return tostring(v)
end

local function setting_row(s, indent)
  local pad = string.rep("  ", indent or 0)
  if s.keyed then
    local marker = tr("cli.keyedMarker", "(keyed: %1)"):gsub("%%1", s.key_label or "key", 1)
    return pad .. string.format("%-24s %s", s.id, marker)
  end
  if grouped(s) then
    local subs = table.concat(sub_keys(s), ", ")
    local marker = tr("cli.groupMarker", "(group: %1)"):gsub("%%1", subs, 1)
    return pad .. string.format("%-24s %s", s.id, marker)
  end
  local v = core.read_value(s)
  return pad .. string.format("%-24s %s", s.id, tostring(v))
end

local function cmd_list(flags)
  core.load()
  if flags["--json"] then
    print(json.encode(core.schema()))
    return
  end
  for _, p in ipairs(core.panels()) do
    print("# " .. panel_title(p))
    local last_section = nil
    for _, s in ipairs(p.settings) do
      if s.section ~= last_section then
        last_section = s.section
        if s.section then
          print("  # " .. section_title(p.id, s))
        end
      end
      print(setting_row(s, 1))
    end
  end
end

local function cmd_schema()
  core.load()
  print(json.encode(service.schema(core)))
end

-- For keyed and grouped settings the first positional after the id is the
-- key/sub; for everything else it is the value.
local function parse_target(s, pos)
  if s.keyed or grouped(s) then
    return pos[2], pos[3]
  end
  return nil, pos[2]
end

local function unknown_setting_msg(id)
  local template = tr("cli.unknownSetting", "unknown setting: %1")
  return template:gsub("%%1", tostring(id), 1)
end

local function cmd_get(flags, pos)
  core.load()
  local s = core.find_setting(pos[1])
  if not s then
    die(unknown_setting_msg(pos[1]))
  end
  local key = parse_target(s, pos)
  local result, err = service.get(core, { id = pos[1], key = key })
  if not result then
    die(err)
  end
  if flags["--plain"] then
    if type(result.value) == "table" and result.value ~= json.null then
      print(json.encode(result.value))
    else
      print(plain_value(result.value))
    end
    return
  end
  local out = { id = result.id }
  if result.key ~= nil then out.key = result.key elseif result.sub ~= nil then out.sub = result.sub end
  out.value = result.value
  print(json.encode(out))
end

local function cmd_set(flags, pos)
  core.load()
  local s = core.find_setting(pos[1])
  if not s then
    die(unknown_setting_msg(pos[1]))
  end
  local key, value_str = parse_target(s, pos)
  local result, err = service.set(core, { id = pos[1], key = key, value = value_str })
  if not result then
    die(err)
  end
  if flags["--plain"] then
    print("ok")
    return
  end
  local out = { id = result.id, value = result.value, ok = true }
  if result.key ~= nil then out.key = result.key elseif result.sub ~= nil then out.sub = result.sub end
  print(json.encode(out))
end

local function cmd_reset(flags, pos)
  core.load()
  local s = core.find_setting(pos[1])
  if not s then
    die(unknown_setting_msg(pos[1]))
  end
  local key = parse_target(s, pos)
  local result, err = service.reset(core, { id = pos[1], key = key, all = flags["--all"] })
  if not result then
    die(err)
  end
  if flags["--plain"] then
    print("ok")
    return
  end
  local out = { id = result.id, ok = true }
  if result.key ~= nil then out.key = result.key elseif result.sub ~= nil then out.sub = result.sub end
  if result.count ~= nil then out.count = result.count end
  print(json.encode(out))
end

local function display_id(r)
  local k = r.key or r.sub
  if k then
    return r.id .. ":" .. k
  end
  return r.id
end

local function cmd_changed(flags)
  core.load()
  local result, err = service.changed(core)
  if not result then
    die(err)
  end
  if flags["--json"] then
    print(json.encode({ changed = result.changed }))
    return
  end
  local marker = default_marker()
  for _, r in ipairs(result.changed) do
    print(string.format("%-24s %s -> %s %s", display_id(r), tostring(r.value), tostring(r.default), marker))
  end
end

local function cmd_search(flags, pos)
  core.load()
  local result, err = service.search(core, { query = pos[1] or "" })
  if not result then
    die(err)
  end
  if flags["--json"] then
    print(json.encode({ results = result.results }))
    return
  end
  for _, r in ipairs(result.results) do
    local val
    if r.keyed then
      val = tr("cli.keyedTag", "(keyed)")
    elseif r.grouped then
      val = tr("cli.groupedTag", "(grouped)")
    else
      val = (r.value == nil or r.value == json.null) and default_marker() or tostring(r.value)
    end
    print(string.format("%-24s %-8s %s", r.id, val, tr("setting." .. r.id, r.label)))
  end
end

local function cmd_keys(flags, pos)
  core.load()
  local result, err = service.keys(core, {
    id = pos[1],
    all = flags["--all"],
    monitor = pos[2],
    detail = false,
  })
  if not result then
    die(err)
  end
  if flags["--json"] then
    local out = { id = result.id, keys = result.keys }
    if result.monitors then out.monitors = result.monitors end
    if result.monitor then out.monitor = result.monitor end
    print(json.encode(out))
    return
  end
  if result.monitors then
    -- Monitor-grouped: no monitor arg lists the monitors; one filters to its
    -- workspaces.
    if result.monitor then
      for _, k in ipairs(result.keys) do
        print(k)
      end
    else
      for _, m in ipairs(result.monitors) do
        print(m.name)
      end
    end
  else
    for _, k in ipairs(result.keys) do
      print(k)
    end
  end
end

local function cmd_ui(pos)
  core.load()
  -- One-shot window override: when this launch's effective language
  -- differs from the desktop language, point the window at it via the
  -- omaset-private ui-language file. Otherwise clear any stale file so
  -- the window always starts on the OS language.
  local effective = i18n.current_language()
  if effective ~= i18n.os_language() then
    local ok, err = i18n.write_ui_override(effective)
    if not ok then
      die(err)
    end
  else
    i18n.clear_ui_override()
  end
  local result, err = service.ui(core, { action = pos[1] or "toggle" })
  if not result then
    -- Keep the override file on failure so the next open still honors
    -- the requested language until the next successful summon clears it.
    die(err)
  end
end

local function entry_label(entry)
  if entry.key then
    return entry.id .. ":" .. entry.key
  elseif entry.sub then
    return entry.id .. "." .. entry.sub
  end
  return entry.id
end

local function show_value(v)
  if v == nil or v == json.null then
    return default_marker()
  end
  return tostring(v)
end

local function cmd_history(flags, pos)
  local result, err = service.history(core, { limit = tonumber(pos[1]) })
  if not result then
    die(err)
  end
  if flags["--json"] then
    print(json.encode({ history = result.history }))
    return
  end
  for _, e in ipairs(result.history) do
    local ts = os.date("%Y-%m-%d %H:%M", e.ts)
    print(string.format("%-16s %-6s %-28s %s -> %s", ts, e.op,
      entry_label(e), show_value(e.old), show_value(e.new)))
  end
end

local function cmd_undo(flags, pos)
  core.load()
  local result, err = service.undo(core, { all = flags["--all"] })
  if not result then
    die(err)
  end
  if flags["--plain"] then
    print("ok")
    return
  end
  if flags["--all"] then
    print(json.encode({ ok = true, undone = result.undone }))
    return
  end
  local out = { id = result.id, ok = true }
  if result.key ~= nil then out.key = result.key end
  if result.sub ~= nil then out.sub = result.sub end
  print(json.encode(out))
end

local function cmd_rollback(flags)
  core.load()
  local result, err = service.rollback(core)
  if not result then
    die(err)
  end
  if flags["--json"] then
    print(json.encode(result))
  else
    print(i18n.tn("cli.rollbackRestored", result.restored, "rollback: restored %1 file(s)"))
  end
end

local function cmd_preferences(flags, pos)
  local sub = pos[1]

  if sub == "get" then
    local key = pos[2]
    if key == nil then
      local t = tr("cli.prefsMissingKey", "preferences %1: missing key")
      die(t:gsub("%%1", "get", 1))
    end
    local result, err = service.preference_get(core, { key = key })
    if not result then
      die(err)
    end
    if flags["--plain"] then
      print(tostring(result.value))
    else
      print(json.encode({ key = key, value = result.value }))
    end
    return
  end

  if sub == "set" then
    local key = pos[2]
    if key == nil then
      local t = tr("cli.prefsMissingKey", "preferences %1: missing key")
      die(t:gsub("%%1", "set", 1))
    end
    if pos[3] == nil then
      local t = tr("cli.prefsMissingValue", "preferences set: missing value for %1")
      die(t:gsub("%%1", tostring(key), 1))
    end
    local result, err = service.preference_set(core, { key = key, value = pos[3] })
    if not result then
      die(err)
    end
    if flags["--plain"] then
      print("ok")
    else
      print(json.encode({ key = key, value = result.value, ok = true }))
    end
    return
  end

  if sub == "reset" then
    local key = pos[2]
    if key == nil then
      local t = tr("cli.prefsMissingKey", "preferences %1: missing key")
      die(t:gsub("%%1", "reset", 1))
    end
    local result, err = service.preference_reset(core, { key = key })
    if not result then
      die(err)
    end
    if flags["--plain"] then
      print("ok")
    else
      print(json.encode({ key = key, value = result.value, ok = true }))
    end
    return
  end

  local result, err = service.preferences(core)
  if not result then
    die(err)
  end
  if flags["--json"] then
    print(json.encode(result))
    return
  end
  for _, s in ipairs(result.preferences) do
    print(string.format("%-24s %-8s (default %s)", s.key, tostring(s.value), tostring(s.default)))
  end
end

local function cmd_ui_float(flags, pos)
  core.load()
  local arg = pos[1]
  local enabled
  if arg == "on" then
    enabled = true
  elseif arg == "off" then
    enabled = false
  else
    local t = tr("cli.uiFloatBadArg", "ui-float: expected on or off (got '%1')")
    die(t:gsub("%%1", tostring(arg or ""), 1))
  end
  local result, err = service.ui_float(core, { enabled = enabled })
  if not result then
    die(err)
  end
  print("ok")
end

local function cmd_hyprsunset_apply(flags, pos)
  core.load()
  local result, err = service.hyprsunset_apply(core)
  if not result then
    die(err)
  end
  print("ok")
end

local function cmd_mcp(flags, pos)
  local mcp = require("omaset.mcp")
  local sub = pos[1]

  if sub == "install" then
    local names = {}
    for i = 2, #pos do
      names[#names + 1] = pos[i]
    end
    local ok, err = mcp.install(names)
    if not ok then
      io.stderr:write("omaset mcp install: " .. tostring(err) .. "\n")
      os.exit(1)
    end
    return
  end

  if sub == "doctor" then
    mcp.doctor()
    return
  end

  if sub ~= nil and sub ~= "serve" and sub ~= "run" then
    local t = tr("cli.mcpBadSubcommand",
      "omaset mcp: unknown subcommand '%1' (expected install, doctor, or none to serve)")
    io.stderr:write(t:gsub("%%1", tostring(sub), 1) .. "\n")
    os.exit(1)
  end

  mcp.serve(core)
end

local function cmd_browser(flags, pos)
  local browser = require("omaset.browser")
  local sub = pos[1]

  if sub == "list" then
    local cfg, err = browser.read()
    if not cfg then die(err or "cannot read browser config") end
    if flags["--json"] then
      print(json.encode(cfg))
      return
    end
    print("Enabled browsers:")
    for _, id in ipairs(cfg.enabled or {}) do
      local label = (cfg.labels or {})[id]
      if label and label ~= "" then
        print("  " .. id .. "  (label: " .. label .. ")")
      else
        print("  " .. id)
      end
    end
    if #(cfg.enabled or {}) == 0 then
      print("  (none)")
    end
    print("Rules:")
    for _, r in ipairs(cfg.rules or {}) do
      local label = (cfg.labels or {})[r.browser]
      local display = (label and label ~= "") and label or r.browser
      print("  " .. (r.domain or "") .. " -> " .. display)
    end
    if #(cfg.rules or {}) == 0 then
      print("  (none)")
    end
    print("Fallback: " .. tostring(cfg.fallback or "chooser"))
    return
  end

  if sub == "enable" then
    if not pos[2] then die("usage: omaset browser enable <id>") end
    local cfg, err = browser.read()
    if not cfg then die(err or "cannot read browser config") end
    local ok, werr = browser.enable(cfg, pos[2])
    if not ok then die(werr) end
    local wok, werr2 = browser.write(cfg)
    if not wok then die(werr2) end
    print(json.encode({ ok = true, id = pos[2] }))
    return
  end

  if sub == "disable" then
    if not pos[2] then die("usage: omaset browser disable <id>") end
    local cfg, err = browser.read()
    if not cfg then die(err or "cannot read browser config") end
    local ok, werr = browser.disable(cfg, pos[2])
    if not ok then die(werr) end
    local wok, werr2 = browser.write(cfg)
    if not wok then die(werr2) end
    print(json.encode({ ok = true, id = pos[2] }))
    return
  end

  if sub == "label" then
    if not pos[2] then die("usage: omaset browser label <id> <label>") end
    local cfg, err = browser.read()
    if not cfg then die(err or "cannot read browser config") end
    local ok, werr = browser.set_label(cfg, pos[2], pos[3])
    if not ok then die(werr) end
    local wok, werr2 = browser.write(cfg)
    if not wok then die(werr2) end
    print(json.encode({ ok = true, id = pos[2], label = pos[3] }))
    return
  end

  if sub == "rule" then
    local rsub = pos[2]
    if rsub == "add" then
      if not pos[3] then die("usage: omaset browser rule add <browser> <domain>...") end
      local cfg, err = browser.read()
      if not cfg then die(err or "cannot read browser config") end
      local domains = {}
      for i = 4, #pos do
        domains[#domains + 1] = pos[i]
      end
      local ok, werr = browser.add_rule(cfg, pos[3], domains)
      if not ok then die(werr) end
      local wok, werr2 = browser.write(cfg)
      if not wok then die(werr2) end
      print(json.encode({ ok = true, browser = pos[3], domains = domains }))
      return
    end
    if rsub == "remove" then
      local domains = {}
      for i = 3, #pos do
        domains[#domains + 1] = pos[i]
      end
      if #domains == 0 then die("usage: omaset browser rule remove <domain>...") end
      local cfg, err = browser.read()
      if not cfg then die(err or "cannot read browser config") end
      browser.remove_rule(cfg, domains)
      local wok, werr = browser.write(cfg)
      if not wok then die(werr) end
      print(json.encode({ ok = true, domains = domains }))
      return
    end
    die("unknown browser subcommand: " .. tostring(rsub) .. " (expected list, add, remove, rule)")
  end

  die("unknown browser subcommand: " .. tostring(sub) .. " (expected list, add, remove, rule)")
end

local function cmd_rpc()
  require("omaset.rpc").serve(core)
end

local function usage_text()
  local groups = {
    {
      "Common commands",
      {
        { "omaset ui", "Open the keyboard settings window (toggle)" },
        { "omaset list", "List panels and settings with current values" },
        { "omaset get <id> [<key>]", "Read a setting" },
        { "omaset set <id> [<key>] <val>", "Write a setting" },
        { "omaset reset <id> [<key>|--all]", "Revert omaset's override" },
        { "omaset search <query>", "Find settings by id or label" },
        { "omaset changed", "Settings that differ from the Omarchy default" },
      },
    },
    {
      "Safety & history",
      {
        { "omaset history [N]", "Recent changes omaset has made" },
        { "omaset undo [--all]", "Undo the last change (or all of them)" },
        { "omaset rollback", "Restore pre-omaset config snapshots" },
      },
    },
    {
      "Preferences",
      {
        { "omaset preferences", "List omaset's own UI preferences" },
        { "omaset preferences get <key>", "Read one preference" },
        { "omaset preferences set <key> <val>", "Write one preference" },
        { "omaset preferences reset <key>", "Reset a preference to default" },
      },
    },
    {
      "MCP & RPC (for frontends)",
      {
        { "omaset browser", "Manage the browser router (list, add, remove, rule)" },
        { "omaset mcp", "Run the MCP server over stdio for agents" },
        { "omaset mcp install [<agent>...]", "Register the server via the agent's own mcp add" },
        { "omaset mcp doctor", "Report which agents are wired up" },
        { "omaset rpc", "Run the JSON-RPC server over stdio for the settings window" },
      },
    },
  }

  local width = 0
  for _, g in ipairs(groups) do
    for _, row in ipairs(g[2]) do
      if #row[1] > width then width = #row[1] end
    end
  end

  local out = {
    "omaset — Omarchy settings engine",
    "",
    "Usage:",
    "  omaset <command> [args...]",
    "  omaset <command> --help",
    "  omaset help <id>",
    "  omaset --lang <code> <command> [args...]   (one-off language override)",
    "  omaset --lang list   (list available language codes)",
    "",
  }
  for _, g in ipairs(groups) do
    out[#out + 1] = g[1] .. ":"
    for _, row in ipairs(g[2]) do
      out[#out + 1] = "  " .. row[1] .. string.rep(" ", width - #row[1] + 2) .. row[2]
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = "Every command accepts --help for command help; omaset --version prints the version."
  return table.concat(out, "\n")
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
  keys = "omaset keys <id> [<monitor>] [--all] [--json]\n  List the keys of a keyed or grouped setting (e.g. workspace numbers). --all includes persisted keys for workspaces not currently open. For monitor-grouped settings (4.5 workspace layouts), a monitor connector name filters to that monitor's workspaces.",
  ui = "omaset ui [open|close|toggle|reload]\n  Open the keyboard settings window (toggle by default). reload restarts the shell and reopens (development). Requires the Omarchy shell plugin to be installed.",
  history = "omaset history [--json] [N]\n  List recent changes omaset has made, oldest first (N limits to the most recent).",
  undo = "omaset undo [--all] [--plain]\n  Undo the most recent change, or --all to revert every change in reverse order.",
  rollback = "omaset rollback [--json]\n  Restore the pre-omaset .bak snapshots of the config files omaset has written.",
  preferences = "omaset preferences [list|get <key>|set <key> <val>|reset <key>] [--json|--plain]\n  List or edit omaset's own UI preferences (not Omarchy settings).",
  ["ui-float"] = "omaset ui-float <on|off>\n  Add or remove the omaset window's float/center rule (driven by the launch_floating preference).",
  ["hyprsunset-apply"] = "omaset hyprsunset-apply\n  Restart hyprsunset so a written night-light schedule takes effect.",
  mcp = "omaset mcp\n  Run the MCP server over stdio for agents.\nomaset mcp install [<agent>...]\n  Register the omaset server with the named agents (all when none are named) by calling their own `mcp add`. Agents whose CLI is not installed are skipped.\nomaset mcp doctor\n  Report which agents are wired to the omaset MCP server.",
  rpc = "omaset rpc\n  Run the JSON-RPC server over stdio for the settings window.",
}

local function value_hint(setting)
  local t = setting.type or "string"
  local choices = types.choice_options(setting)
  if choices then
    local labels = {}
    for _, opt in ipairs(choices) do
      labels[#labels + 1] = option_label(setting.id, opt.value, tostring(opt.label))
    end
    return "<" .. table.concat(labels, "|") .. ">"
  elseif t == "enum" and setting.options then
    local labels = {}
    for _, opt in ipairs(setting.options) do
      labels[#labels + 1] = option_label(setting.id, opt, tostring(opt))
    end
    return "<" .. table.concat(labels, "|") .. ">"
  elseif t == "int" or t == "float" then
    if setting.min ~= nil and setting.max ~= nil then
      return "<" .. tostring(setting.min) .. ".." .. tostring(setting.max) .. ">"
    end
    return t == "int" and "<int>" or "<float>"
  elseif t == "bool" then
    return "<true|false>"
  elseif t == "time" then
    return "<HH:MM|h:mm AM/PM>"
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
  lines[#lines + 1] = setting.id .. " — " .. setting_label(setting)
  local desc = setting_description(setting)
  if desc then
    lines[#lines + 1] = "  " .. desc
  end

  if grouped(setting) then
    lines[#lines + 1] = "  get:     omaset get " .. setting.id .. " [<sub>]"
    lines[#lines + 1] = "  set:     omaset set " .. setting.id .. " <sub> <value>"
    lines[#lines + 1] = "  reset:   omaset reset " .. setting.id .. " <sub> [--all]"
    lines[#lines + 1] = "  sub-settings:"
    for _, k in ipairs(sub_keys(setting)) do
      local sub = setting.subsettings[k]
      local t = sub.type or "string"
      local range = ""
      if (t == "int" or t == "float") and (sub.min ~= nil or sub.max ~= nil) then
        range = " (" .. tostring(sub.min or "-inf") .. ".." .. tostring(sub.max or "inf") .. ")"
      end
      lines[#lines + 1] = "    " .. k .. "  " .. t .. range .. "  default " .. tostring(sub.default)
    end
    return table.concat(lines, "\n")
  end

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
    local choices = types.choice_options(setting)
    if choices then
      local parts = {}
      for _, opt in ipairs(choices) do
        parts[#parts + 1] = tostring(opt.value) .. "="
          .. option_label(setting.id, opt.value, tostring(opt.label))
      end
      lines[#lines + 1] = "  options: " .. table.concat(parts, ", ")
    else
      local parts = {}
      for _, opt in ipairs(setting.options) do
        parts[#parts + 1] = option_label(setting.id, opt, tostring(opt))
      end
      lines[#lines + 1] = "  options: " .. table.concat(parts, ", ")
    end
  end

  if setting.keyed then
    lines[#lines + 1] = "  value:   " .. tr("cli.keyedTag", "(keyed)")
  else
    local current = core.read_value(setting)
    lines[#lines + 1] = "  value:   " .. tostring(current)
    local customs = core.custom_values(setting, nil, current, journal.read_all())
    if #customs > 0 then
      local parts = {}
      for _, v in ipairs(customs) do parts[#parts + 1] = tostring(v) end
      lines[#lines + 1] = "  custom:  " .. table.concat(parts, ", ")
    end
  end
  lines[#lines + 1] = "  default: " .. tostring(core.read_default(setting))
  return table.concat(lines, "\n")
end

local function command_help(cmd, setting)
  if setting then
    local label = setting_label(setting)
    if grouped(setting) then
      if cmd == "get" then
        return "omaset get " .. setting.id .. " [<sub>]\n  " .. label
      elseif cmd == "set" then
        return "omaset set " .. setting.id .. " <sub> <value>\n  " .. label
      elseif cmd == "reset" then
        return "omaset reset " .. setting.id .. " <sub> [--all]\n  " .. label
      end
    elseif cmd == "get" then
      return "omaset get " .. setting.id .. key_arg(setting) .. "\n  " .. label
    elseif cmd == "set" then
      return "omaset set " .. setting.id .. key_arg(setting) .. " " .. value_hint(setting) .. "\n  " .. label
    elseif cmd == "reset" then
      local extra = setting.keyed and " [--all]" or ""
      return "omaset reset " .. setting.id .. key_arg(setting) .. extra .. "\n  " .. label
    end
  end
  local fallback = COMMAND_HELP[cmd]
  if not fallback then
    local t = tr("cli.noHelp", "No help for '%1'.")
    fallback = t:gsub("%%1", tostring(cmd), 1) .. "\n\n" .. usage_text()
  end
  return fallback
end

local function cmd_help(pos)
  core.load()
  local id = pos[1]
  if not id then
    print(usage_text())
    return
  end
  local s = core.find_setting(id)
  if not s then
    die(unknown_setting_msg(id))
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

-- Global --lang handling (mirrors omarchy's OMARCHY_LANGUAGE_FILE idiom):
--   omaset --lang <code> <command> [...]   one-off override for this call
--   omaset --lang list                     list registry codes
--   omaset --lang <code>                   print the resolved language
-- The flag is accepted anywhere in argv and removed before dispatch, so
-- `omaset list --lang fr` and `omaset --lang fr list` both work. Values,
-- JSON output, and the MCP contract are unaffected by the language.
local function parse_lang_global(argv)
  local lang = nil
  local list = false
  local out = {}
  local i = 1
  while i <= #argv do
    local tok = argv[i]
    if tok == "--lang" then
      local val = argv[i + 1]
      if val == nil then
        die("missing value for --lang (expected a language code or 'list')")
      end
      if val == "list" then
        list = true
      else
        lang = val
      end
      i = i + 2
    elseif type(tok) == "string" and tok:sub(1, 7) == "--lang=" then
      local val = tok:sub(8)
      if val == "" then
        die("missing value for --lang (expected a language code or 'list')")
      end
      if val == "list" then
        list = true
      else
        lang = val
      end
      i = i + 1
    else
      out[#out + 1] = tok
      i = i + 1
    end
  end
  return lang, list, out
end

local function cmd_lang_list()
  for _, e in ipairs(i18n.list_languages()) do
    print(string.format("%s\t%s\t%s", e.name, e.code, e.englishName))
  end
end

function M.main(arg)
  local lang, lang_list, cleaned = parse_lang_global(arg)
  if lang_list and #cleaned == 0 then
    cmd_lang_list()
    return
  end
  if lang ~= nil then
    local ok, err = i18n.set_override(lang)
    if not ok then
      die(err)
    end
    local reg = i18n.registry()
    if next(reg) ~= nil and reg[lang] == nil then
      die("unknown language code: " .. tostring(lang))
    end
  end
  if #cleaned == 0 then
    if lang ~= nil then
      print(i18n.current_language())
      return
    end
    print(usage_text())
    return
  end
  arg = cleaned
  local cmd = arg[1]

  if cmd == nil then
    print(usage_text())
    return
  end
  if cmd == "--version" or cmd == "version" then
    print("omaset " .. core.VERSION)
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
      core.load()
      local s = core.find_setting(pos[1])
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
  elseif cmd == "ui" then
    cmd_ui(pos)
  elseif cmd == "history" then
    cmd_history(flags, pos)
  elseif cmd == "undo" then
    cmd_undo(flags, pos)
  elseif cmd == "rollback" then
    cmd_rollback(flags)
  elseif cmd == "preferences" then
    cmd_preferences(flags, pos)
  elseif cmd == "ui-float" then
    cmd_ui_float(flags, pos)
  elseif cmd == "hyprsunset-apply" then
    cmd_hyprsunset_apply(flags, pos)
  elseif cmd == "mcp" then
    cmd_mcp(flags, pos)
  elseif cmd == "browser" then
    cmd_browser(flags, pos)
  elseif cmd == "rpc" then
    cmd_rpc()
  else
    local t = tr("cli.unknownCommand", "unknown command: %1")
    io.stderr:write("omaset: " .. t:gsub("%%1", tostring(cmd), 1) .. "\n\n" .. usage_text() .. "\n")
    os.exit(1)
  end
end

return M
