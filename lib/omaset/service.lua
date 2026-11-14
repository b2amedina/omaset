-- omaset service: the single operation layer behind every frontend.
--
-- The CLI calls these functions in-process; the MCP server and the UI's
-- `omaset rpc` server are thin wire adapters over the same operations. That
-- keeps validation, journaling, and payload shapes in one place: adding or
-- changing a setting touches no frontend-specific copy of the logic.

local json = require("omaset.json")
local util = require("omaset.util")
local i18n = require("omaset.i18n")
local types = require("omaset.types")
local journal = require("omaset.journal")
local preferences = require("omaset.preferences")
local backends = require("omaset.backends")

local M = {}

local function jnull(v)
  if v == nil then
    return json.null
  end
  return v
end

local function find_setting(core, id)
  local s = core.find_setting(id)
  if not s then
    return nil, "unknown setting: " .. tostring(id)
  end
  return s
end

local function resolve_key(core, setting, key)
  if setting.keyed then
    local ok, err = types.validate_key(setting, key)
    if not ok then
      return nil, err
    end
    return key
  end
  if core.grouped(setting) then
    if key == nil then
      return nil
    end
    if not setting.subsettings[key] then
      return nil, "unknown sub-setting '" .. key .. "' for " .. setting.id
        .. " (choose from: " .. table.concat(core.sub_keys(setting), ", ") .. ")"
    end
    return key
  end
  return nil
end

local function spec_for(core, setting, key)
  if core.grouped(setting) then
    return setting.subsettings[key]
  end
  return setting
end

local function record_change(core, op, s, key, old, def, new)
  local entry = { ts = os.time(), op = op, id = s.id, backend = s.backend }
  if s.keyed then
    entry.key = key
  elseif core.grouped(s) then
    entry.sub = key
  end
  entry.old = jnull(old)
  entry.default = jnull(def)
  entry.new = jnull(new)
  journal.record(entry)
end

local function value_changed(cur, def)
  if def == nil then
    return cur ~= nil
  end
  if cur == nil then
    return true
  end
  return cur ~= def
end

-- A CLI string is coerced to the setting's type; a typed JSON value (from MCP
-- or the UI) is validated directly. Both paths normalize before writing.
local function coerce_value(raw, spec)
  if type(raw) == "string" then
    local value, err = types.coerce(raw, spec)
    if value == nil then
      return nil, err
    end
    local ok, rerr = types.check_range(value, spec)
    if not ok then
      return nil, rerr
    end
    return types.normalize(value, spec)
  end
  local ok, err = types.validate(raw, spec)
  if not ok then
    return nil, err
  end
  return types.normalize(raw, spec)
end

-- A journal entry recorded by an older omaset/Omarchy may name a setting
-- that no longer exists, or a value that is no longer a valid option (e.g.
-- "master" after the 4.5 layout change). core.write_value bypasses type
-- validation, so check here: such entries return "skipped" instead of being
-- replayed.
local function undo_stale_reason(core, s, entry)
  local key = entry.key or entry.sub
  if core.grouped(s) and key ~= nil then
    if not (s.subsettings and s.subsettings[key]) then
      return "unknown sub-setting '" .. tostring(key) .. "'"
    end
  end
  return nil
end

local function apply_undo(core, entry)
  local s = core.find_setting(entry.id)
  if not s then
    return "skipped", "unknown setting in journal: " .. tostring(entry.id)
  end
  local stale = undo_stale_reason(core, s, entry)
  if stale then
    return "skipped", stale
  end
  local key = entry.key or entry.sub
  local old = entry.old
  if old == json.null then old = nil end
  local def = entry.default
  if def == json.null then def = nil end
  if entry.op == "set" then
    if old == def then
      return core.reset_value(s, key)
    end
    return core.write_value(s, key, old)
  elseif entry.op == "reset" then
    if old == def then
      return true
    end
    return core.write_value(s, key, old)
  end
  return nil, "unknown journal op: " .. tostring(entry.op)
end

local function pref_spec(key)
  for _, s in ipairs(preferences.SCHEMA) do
    if s.key == key then
      return s
    end
  end
  return nil
end

-- ---- operations --------------------------------------------------------

function M.schema(core)
  return core.schema()
end

-- Everything the UI needs for one panel in one call: schema, preferences,
-- changed entries, and that panel's group/keyed values.
function M.snapshot(core, args)
  local out = {
    version = core.VERSION,
    schemaVersion = core.SCHEMA_VERSION,
    schema = core.schema(),
    preferences = M.preferences(core),
    changed = M.changed(core).changed,
  }

  local panel_id = args.panel
  local panel = nil
  if panel_id ~= nil and panel_id ~= json.null then
    for _, p in ipairs(core.panels()) do
      if p.id == panel_id then
        panel = p
        break
      end
    end
  end

  local keys = {}
  local keyed = {}
  local groups = {}
  if panel then
    for _, s in ipairs(panel.settings) do
      if core.grouped(s) then
        local values = {}
        for _, sub in ipairs(core.sub_keys(s)) do
          values[sub] = jnull(core.read_value(s, sub))
        end
        groups[s.id] = values
      elseif s.keyed then
        local names = core.keys(s) or {}
        local values = {}
        for _, k in ipairs(names) do
          values[k] = jnull(core.read_value(s, k))
        end
        keys[s.id] = json.array(names)
        keyed[s.id] = values
      end
    end
  end

  out.panel = jnull(panel_id)
  out.keys = keys
  out.keyed = keyed
  out.groups = groups
  return out
end

function M.search(core, args)
  local q = tostring(args.query or "")
  if q:gsub("%s+$", "") == "" then
    q = ""
  end
  local lang = args.lang
  if lang == nil or lang == "" then
    lang = i18n.current_language()
  end
  local fq = util.fold(q)

  -- Collect matches for one setting. Each candidate carries the position of
  -- the folded query, whether it is an exact match, and a ranking tier; the
  -- best score across candidates ranks the setting.
  local function add(hits, text, tier)
    if text == nil then
      return
    end
    text = tostring(text)
    if text == "" then
      return
    end
    local ftext = util.fold(text)
    local pos = ftext:find(fq, 1, true)
    if pos then
      hits[#hits + 1] = { pos = pos, exact = (ftext == fq), tier = tier }
    end
  end

  local out = {}
  local order = 0
  for _, p in ipairs(core.panels()) do
    for _, s in ipairs(p.settings) do
      local hits = {}
      add(hits, s.id, 90)
      add(hits, s.label, 70)
      add(hits, i18n.t_lang(lang, "setting." .. s.id, s.label), 70)
      add(hits, s.description, 30)
      add(hits, i18n.t_lang(lang, "setting." .. s.id .. ".description", s.description), 30)
      add(hits, p.title, 40)
      add(hits, i18n.t_lang(lang, "panel." .. p.id, p.title), 40)
      add(hits, s.section, 40)
      if s.section_key then
        add(hits, i18n.t_lang(lang, "section." .. p.id .. "." .. s.section_key, s.section), 40)
      end
      for _, opt in ipairs(s.options or {}) do
        local value, olabel
        if type(opt) == "table" then
          value, olabel = opt.value, opt.label
        else
          value, olabel = opt, opt
        end
        add(hits, olabel, 50)
        add(hits, i18n.t_lang(lang, "setting." .. s.id .. ".option." .. tostring(value), olabel), 50)
      end
      -- Keyed settings: match against their keys too (e.g. browser-router
      -- rule domains), so a domain search finds its rule.
      if s.keyed then
        for _, k in ipairs(core.keys(s) or {}) do
          add(hits, k, 60)
        end
      end
      if s.subsettings then
        for sub, spec in pairs(s.subsettings) do
          add(hits, spec.label, 70)
          add(hits, i18n.t_lang(lang, "setting." .. s.id .. "." .. sub, spec.label), 70)
          add(hits, spec.description, 30)
          add(hits, i18n.t_lang(lang, "setting." .. s.id .. "." .. sub .. ".description", spec.description), 30)
        end
      end

      if q == "" or #hits > 0 then
        local entry = { id = s.id, panel = p.id, label = s.label }
        if s.description then entry.description = s.description end
        if s.type then entry.type = s.type end
        if s.keyed then
          entry.keyed = true
        elseif core.grouped(s) then
          entry.grouped = true
        else
          entry.value = jnull(core.read_value(s))
        end
        order = order + 1
        entry._order = order
        entry._score = 0
        for _, h in ipairs(hits) do
          local sc = h.tier
          if h.pos == 1 then sc = sc + 10 end
          if h.exact then sc = sc + 10 end
          if sc > entry._score then entry._score = sc end
        end
        out[#out + 1] = entry
      end
    end
  end

  if q ~= "" then
    table.sort(out, function(a, b)
      if a._score ~= b._score then
        return a._score > b._score
      end
      return a._order < b._order
    end)
  end
  for _, e in ipairs(out) do
    e._order = nil
    e._score = nil
  end

  return { results = json.array(out) }
end

function M.get(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end
  local key, kerr = resolve_key(core, s, args.key)
  if kerr then
    return nil, kerr
  end

  local value
  if core.grouped(s) and key == nil then
    value = {}
    for _, k in ipairs(core.sub_keys(s)) do
      value[k] = core.read_value(s, k)
    end
  else
    value = core.read_value(s, key)
  end
  local def = core.read_default(s, key)

  local out = { id = s.id }
  if key ~= nil then
    if s.keyed then out.key = key else out.sub = key end
  end
  out.value = jnull(value)
  out.default = jnull(def)
  return out
end

function M.set(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end
  local key, kerr = resolve_key(core, s, args.key)
  if kerr then
    return nil, kerr
  end
  if core.grouped(s) and key == nil then
    return nil, "missing sub-setting for setting: " .. s.id
      .. " (choose from: " .. table.concat(core.sub_keys(s), ", ") .. ")"
  end
  if args.value == nil or args.value == json.null then
    return nil, "missing value for setting: " .. s.id
  end

  local spec = spec_for(core, s, key)
  local value, verr = coerce_value(args.value, spec)
  if value == nil then
    return nil, verr
  end

  local old = core.read_value(s, key)
  local out = { id = s.id, value = value, ok = true }
  if key ~= nil then
    if s.keyed then out.key = key else out.sub = key end
  end
  -- Setting a value the setting already holds is a successful no-op, so
  -- re-selecting the current Custom choice does not rewrite the config.
  if old ~= nil and tostring(old) == tostring(value) then
    return out
  end

  local backend = core.backend_for(s)
  if backend and backend.validate then
    local customs = core.custom_values(s, core.grouped(s) and key or nil, old,
      journal.read_all())
    local vok, verr = backend.validate(s, value, key, customs)
    if not vok then
      return nil, verr
    end
  end

  local def = core.read_default(s, key)
  local wok, werr = core.write_value(s, key, value)
  if not wok then
    return nil, werr
  end
  record_change(core, "set", s, key, old, def, value)
  return out
end

function M.reset(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end

  if args.all then
    if not (s.keyed or core.grouped(s)) then
      return nil, "setting is not keyed: " .. s.id
    end
    local keys = core.keys_all(s) or {}
    local count = 0
    for _, k in ipairs(keys) do
      local old = core.read_value(s, k)
      local def = core.read_default(s, k)
      local rok, rerr = core.reset_value(s, k)
      if rok then
        count = count + 1
        if old ~= def then
          record_change(core, "reset", s, k, old, def, nil)
        end
      else
        io.stderr:write("omaset: " .. rerr .. "\n")
      end
    end
    return { id = s.id, ok = true, count = count }
  end

  local key, kerr = resolve_key(core, s, args.key)
  if kerr then
    return nil, kerr
  end
  local old = core.read_value(s, key)
  local def = core.read_default(s, key)
  local rok, rerr = core.reset_value(s, key)
  if not rok then
    return nil, rerr
  end
  if old ~= def then
    record_change(core, "reset", s, key, old, def, nil)
  end

  local out = { id = s.id, ok = true }
  if key ~= nil then
    if s.keyed then out.key = key else out.sub = key end
  end
  return out
end

function M.changed(core)
  local out = {}
  for _, p in ipairs(core.panels()) do
    for _, s in ipairs(p.settings) do
      -- Settings marked `tracked = false` are not base Omarchy state (e.g.
      -- the browser-router config omaset owns), so they never show as changed.
      if s.tracked == false then
        -- skip
      elseif s.keyed then
        for _, k in ipairs(core.keys(s) or {}) do
          local cur = core.read_value(s, k)
          local def = core.read_default(s, k)
          if value_changed(cur, def) then
            out[#out + 1] = { id = s.id, key = k, panel = p.id, label = s.label, value = cur, default = def }
          end
        end
      elseif core.grouped(s) then
        for _, k in ipairs(core.sub_keys(s)) do
          local cur = core.read_value(s, k)
          local def = core.read_default(s, k)
          if value_changed(cur, def) then
            out[#out + 1] = { id = s.id, sub = k, panel = p.id, label = s.label, value = cur, default = def }
          end
        end
      else
        local cur = core.read_value(s)
        local def = core.read_default(s)
        if value_changed(cur, def) then
          out[#out + 1] = { id = s.id, panel = p.id, label = s.label, value = cur, default = def }
        end
      end
    end
  end
  return { changed = json.array(out) }
end

function M.help(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end
  local out = { id = s.id, label = s.label }
  if s.description then out.description = s.description end
  if s.type then out.type = s.type end
  if s.options then out.options = json.array(s.options) end
  if s.min ~= nil then out.min = s.min end
  if s.max ~= nil then out.max = s.max end
  if s.format then out.format = s.format end
  if s.hint then out.hint = s.hint end
  if s.keyed then
    out.keyed = true
    if s.key_label then out.key_label = s.key_label end
    if s.key_type then out.key_type = s.key_type end
  elseif core.grouped(s) then
    out.grouped = true
    out.subsettings = {}
    for _, k in ipairs(core.sub_keys(s)) do
      local sub = s.subsettings[k]
      out.subsettings[k] = { type = sub.type }
      if sub.default ~= nil then out.subsettings[k].default = sub.default end
      if sub.options then out.subsettings[k].options = json.array(sub.options) end
    end
  else
    local current = core.read_value(s)
    out.value = jnull(current)
    out.default = jnull(core.read_default(s))
    local customs = core.custom_values(s, nil, current, journal.read_all())
    if #customs > 0 then out.customOptions = json.array(customs) end
  end
  return out
end

-- `detail` adds current values/defaults (the MCP/UI shape); the CLI asks for
-- names only.
function M.keys(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end
  local detail = args.detail ~= false

  if core.grouped(s) then
    local names = core.sub_keys(s)
    local out = { id = s.id, grouped = true, keys = json.array(names) }
    if detail then
      local entries = {}
      for _, k in ipairs(names) do
        entries[#entries + 1] = {
          sub = k,
          value = jnull(core.read_value(s, k)),
          default = jnull(core.read_default(s, k)),
        }
      end
      out.entries = json.array(entries)
    end
    return out
  end

  if s.keyed then
    local monitors = core.monitors(s)
    local names
    local has_monitor_arg = args.monitor ~= nil and args.monitor ~= json.null

    if has_monitor_arg then
      local mon = nil
      if monitors then
        for _, m in ipairs(monitors) do
          if m.name == args.monitor then
            mon = m
            break
          end
        end
      end
      if not mon then
        local avail = {}
        if monitors then
          for _, m in ipairs(monitors) do
            avail[#avail + 1] = m.name
          end
        end
        return nil, "unknown monitor '" .. tostring(args.monitor) .. "'"
          .. (#avail > 0 and (" (choose from: " .. table.concat(avail, ", ") .. ")") or "")
      end
      names = mon.workspaces
    else
      names = (args.all and core.keys_all(s) or core.keys(s)) or {}
    end

    local out = { id = s.id, keyed = true }
    if monitors then
      out.monitors = json.array(monitors)
      if has_monitor_arg then out.monitor = args.monitor end
    end
    out.keys = json.array(names)
    if detail then
      local entries = {}
      for _, k in ipairs(names) do
        entries[#entries + 1] = {
          key = k,
          value = jnull(core.read_value(s, k)),
          default = jnull(core.read_default(s, k)),
        }
      end
      out.entries = json.array(entries)
    end
    return out
  end

  return nil, "setting is not keyed or grouped: " .. s.id
end

function M.undo(core, args)
  local entries = journal.read_all()
  if args.all then
    local undone = 0
    local errors = {}
    for i = #entries, 1, -1 do
      local ok, err = apply_undo(core, entries[i])
      if ok == "skipped" then
        io.stderr:write("omaset: warning: skipping stale journal entry: "
          .. tostring(err) .. "\n")
      elseif ok then
        undone = undone + 1
      else
        errors[#errors + 1] = tostring(err)
      end
    end
    journal.clear()
    local out = { ok = true, undone = undone }
    if #errors > 0 then
      out.errors = json.array(errors)
    end
    return out
  end

  if #entries == 0 then
    return { ok = true, undone = 0 }
  end
  local entry = entries[#entries]
  local ok, err = apply_undo(core, entry)
  if ok == "skipped" then
    io.stderr:write("omaset: warning: skipping stale journal entry: "
      .. tostring(err) .. "\n")
    journal.remove_last()
    return { ok = true, undone = 0, skipped = true, id = entry.id }
  end
  if not ok then
    return nil, err
  end
  journal.remove_last()
  local out = { id = entry.id, ok = true }
  if entry.key then out.key = entry.key end
  if entry.sub then out.sub = entry.sub end
  return out
end

function M.history(core, args)
  local entries = journal.read_all()
  local limit = tonumber(args.limit)
  if limit and limit < #entries then
    local recent = {}
    for i = #entries - limit + 1, #entries do
      recent[#recent + 1] = entries[i]
    end
    entries = recent
  end
  return { history = json.array(entries) }
end

function M.rollback(core)
  local total = 0
  for _, name in ipairs(backends.names()) do
    local b = backends.get(name)
    if b.restore then
      local n = b.restore()
      total = total + (n or 0)
    end
  end
  journal.clear()
  return { rollback = true, restored = total }
end

function M.preferences(core)
  return {
    version = core.VERSION,
    preferences = json.array(preferences.list()),
  }
end

function M.preference_get(core, args)
  local spec = pref_spec(args.key)
  if not spec then
    return nil, "unknown preference: " .. tostring(args.key)
  end
  local v, err = preferences.get(args.key)
  if v == nil and err then
    return nil, err
  end
  local out = { key = args.key, value = jnull(v), default = jnull(spec.default) }
  if spec.type then out.type = spec.type end
  if spec.options then out.options = json.array(spec.options) end
  if spec.min ~= nil then out.min = spec.min end
  if spec.max ~= nil then out.max = spec.max end
  return out
end

function M.preference_set(core, args)
  local spec = pref_spec(args.key)
  if not spec then
    return nil, "unknown preference: " .. tostring(args.key)
  end
  if args.value == nil or args.value == json.null then
    return nil, "missing value for preference: " .. tostring(args.key)
  end
  local raw = args.value
  if type(raw) == "boolean" then
    raw = raw and "true" or "false"
  elseif type(raw) ~= "string" then
    raw = tostring(raw)
  end
  local v, err = preferences.set(args.key, raw)
  if v == nil then
    return nil, err
  end
  return { key = args.key, value = v, ok = true }
end

function M.preference_reset(core, args)
  local spec = pref_spec(args.key)
  if not spec then
    return nil, "unknown preference: " .. tostring(args.key)
  end
  local v, err = preferences.reset(args.key)
  if v == nil and err then
    return nil, err
  end
  return { key = args.key, value = v, ok = true }
end

function M.ui(core, args)
  local action = args.action or "toggle"
  local shell_cmd
  if action == "open" or action == "summon" then
    shell_cmd = "omarchy-shell shell summon b2amedina.omaset '{}'"
  elseif action == "close" or action == "hide" then
    shell_cmd = "omarchy-shell shell hide b2amedina.omaset"
  elseif action == "toggle" then
    shell_cmd = "omarchy-shell shell toggle b2amedina.omaset '{}'"
  elseif action == "reload" then
    os.execute("omarchy restart shell")
    shell_cmd = "omarchy-shell shell summon b2amedina.omaset '{}'"
  else
    return nil, "ui: expected open, close, toggle, or reload (got '" .. action .. "')"
  end
  local ok = os.execute(shell_cmd)
  if ok ~= 0 then
    return nil, "ui: could not reach the Omarchy shell (is it running?)"
  end
  return { ok = true }
end

function M.open_ui(core)
  return M.ui(core, { action = "open" })
end

function M.ui_float(core, args)
  local b = backends.get("hypr-window")
  if not b or not b.set_omaset_float then
    return nil, "hypr-window backend does not manage the omaset window rule"
  end
  local enabled = args.enabled
  if type(enabled) == "string" then
    enabled = (enabled == "on" or enabled == "true" or enabled == "1")
  end
  if enabled == nil then
    return nil, "ui-float: missing enabled"
  end
  local ok, err = b.set_omaset_float(enabled)
  if not ok then
    return nil, err
  end
  return { ok = true }
end

function M.hyprsunset_apply(core)
  local b = backends.get("hyprsunset")
  if not b or not b.apply then
    return nil, "hyprsunset backend does not support apply"
  end
  local ok, err = b.apply()
  if not ok then
    return nil, err
  end
  return { ok = true }
end

-- ---- registry ----------------------------------------------------------

local OPS = {
  {
    name = "schema",
    description = "Return omaset's full schema: every panel and setting with its id, label, description, type, options, range, and current value.",
    inputSchema = { type = "object", properties = {} },
    run = function(core)
      return M.schema(core)
    end,
  },
  {
    name = "snapshot",
    mcp = false,
    description = "Return schema, preferences, changed entries, and one panel's group/keyed values in one payload.",
    inputSchema = {
      type = "object",
      properties = { panel = { type = "string", description = "Panel id whose group/keyed values to include." } },
    },
    run = function(core, args)
      return M.snapshot(core, args)
    end,
  },
  {
    name = "search",
    description = "Find settings by id, label, description, panel or section title, or option label, in English or the resolved language.",
    inputSchema = {
      type = "object",
      properties = {
        query = { type = "string", description = "Substring to match (case- and accent-insensitive)" },
        lang = { type = "string", description = "Language code to also match in (defaults to the resolved language)" },
      },
      required = { "query" },
    },
    run = function(core, args)
      return M.search(core, args)
    end,
  },
  {
    name = "get",
    description = "Read one setting's current value and default. Keyed settings take a key; grouped settings take an optional sub-setting name.",
    inputSchema = {
      type = "object",
      properties = { id = { type = "string" }, key = { type = "string" } },
      required = { "id" },
    },
    run = function(core, args)
      return M.get(core, args)
    end,
  },
  {
    name = "set",
    description = "Write a setting value (validated against its type, options, and range; applied via its backend). Keyed/grouped settings take a key.",
    inputSchema = {
      type = "object",
      properties = { id = { type = "string" }, value = {}, key = { type = "string" } },
      required = { "id", "value" },
    },
    run = function(core, args)
      return M.set(core, args)
    end,
  },
  {
    name = "reset",
    description = "Revert omaset's override for a setting so the Omarchy default applies. Keyed/grouped settings take a key, or all=true to reset every key.",
    inputSchema = {
      type = "object",
      properties = { id = { type = "string" }, key = { type = "string" }, all = { type = "boolean" } },
      required = { "id" },
    },
    run = function(core, args)
      return M.reset(core, args)
    end,
  },
  {
    name = "changed",
    description = "List settings whose effective value differs from the Omarchy default.",
    inputSchema = { type = "object", properties = {} },
    run = function(core)
      return M.changed(core)
    end,
  },
  {
    name = "help",
    description = "Show one setting's full spec: description, type, options, range, default, and current value.",
    inputSchema = {
      type = "object",
      properties = { id = { type = "string" } },
      required = { "id" },
    },
    run = function(core, args)
      return M.help(core, args)
    end,
  },
  {
    name = "keys",
    description = "Enumerate a keyed or grouped setting's keys with each key's current value and default. For keyed settings, all=true also lists persisted keys (e.g. workspaces that are not currently open). Monitor-grouped keyed settings (4.5 workspace layouts) also return a monitors array, and a monitor (connector name) filters keys to that monitor's block.",
    inputSchema = {
      type = "object",
      properties = {
        id = { type = "string" },
        all = { type = "boolean" },
        monitor = { type = "string", description = "Filter a monitor-grouped keyed setting to one monitor's workspaces, by connector name." },
      },
      required = { "id" },
    },
    run = function(core, args)
      return M.keys(core, { id = args.id, all = args.all, monitor = args.monitor, detail = true })
    end,
  },
  {
    name = "undo",
    description = "Undo omaset's most recent setting change, or all=true to revert every change.",
    inputSchema = {
      type = "object",
      properties = { all = { type = "boolean" } },
    },
    run = function(core, args)
      return M.undo(core, args)
    end,
  },
  {
    name = "history",
    description = "List recent changes omaset has made, oldest first.",
    inputSchema = {
      type = "object",
      properties = { limit = { type = "integer", description = "Only the most recent N entries." } },
    },
    run = function(core, args)
      return M.history(core, args)
    end,
  },
  {
    name = "rollback",
    mcp = false,
    description = "Restore the pre-omaset config snapshots for every backend that keeps one.",
    inputSchema = { type = "object", properties = {} },
    run = function(core)
      return M.rollback(core)
    end,
  },
  {
    name = "preferences",
    description = "List omaset's own preferences (not Omarchy settings) with their type, options, range, default, and current value.",
    inputSchema = { type = "object", properties = {} },
    run = function(core)
      return M.preferences(core)
    end,
  },
  {
    name = "preference_get",
    description = "Read one omaset preference's current value and default.",
    inputSchema = {
      type = "object",
      properties = { key = { type = "string" } },
      required = { "key" },
    },
    run = function(core, args)
      return M.preference_get(core, args)
    end,
  },
  {
    name = "preference_set",
    description = "Write an omaset preference (validated against its type, options, and range).",
    inputSchema = {
      type = "object",
      properties = { key = { type = "string" }, value = {} },
      required = { "key", "value" },
    },
    run = function(core, args)
      return M.preference_set(core, args)
    end,
  },
  {
    name = "preference_reset",
    description = "Reset an omaset preference to its default.",
    inputSchema = {
      type = "object",
      properties = { key = { type = "string" } },
      required = { "key" },
    },
    run = function(core, args)
      return M.preference_reset(core, args)
    end,
  },
  {
    name = "ui",
    description = "Open, close, toggle, or reload the omaset settings window.",
    inputSchema = {
      type = "object",
      properties = {
        action = { type = "string", enum = { "open", "close", "toggle", "reload" } },
      },
    },
    run = function(core, args)
      return M.ui(core, args)
    end,
  },
  {
    name = "open_ui",
    description = "Open the omaset settings window so the user can see or verify changes.",
    inputSchema = { type = "object", properties = {} },
    run = function(core)
      return M.open_ui(core)
    end,
  },
  {
    name = "ui_float",
    description = "Apply the launch_floating preference to the omaset window rule.",
    inputSchema = {
      type = "object",
      properties = { enabled = { type = "boolean" } },
      required = { "enabled" },
    },
    run = function(core, args)
      return M.ui_float(core, args)
    end,
  },
  {
    name = "hyprsunset_apply",
    description = "Restart hyprsunset so a written night-light schedule takes effect.",
    inputSchema = { type = "object", properties = {} },
    run = function(core)
      return M.hyprsunset_apply(core)
    end,
  },
  {
    name = "browser_list",
    description = "List configured browsers, rules, and fallback.",
    inputSchema = { type = "object", properties = {} },
    run = function(core)
      local browser = require("omaset.browser")
      return browser.read()
    end,
  },
  {
    name = "browser_enable",
    description = "Enable a browser for routing.",
    inputSchema = { type = "object", properties = { id = { type = "string" } }, required = { "id" } },
    run = function(core, args)
      local browser = require("omaset.browser")
      local cfg, err = browser.read()
      if not cfg then return nil, err end
      local ok, werr = browser.enable(cfg, args.id)
      if not ok then return nil, werr end
      local wok, werr2 = browser.write(cfg)
      if not wok then return nil, werr2 end
      return { ok = true, id = args.id }
    end,
  },
  {
    name = "browser_install",
    description = "Install a browser (Omarchy's floating terminal) and enable it.",
    inputSchema = { type = "object", properties = { id = { type = "string" } }, required = { "id" } },
    run = function(core, args)
      local browser = require("omaset.browser")
      local iok, ierr = browser.install(args.id)
      if not iok then return nil, ierr end
      local cfg, err = browser.read()
      if not cfg then return nil, err end
      local ok, werr = browser.enable(cfg, args.id)
      if not ok then return nil, werr end
      local wok, werr2 = browser.write(cfg)
      if not wok then return nil, werr2 end
      return { ok = true, id = args.id }
    end,
  },
  {
    name = "browser_disable",
    description = "Disable a browser (keeps its rules; hides it from the router).",
    inputSchema = { type = "object", properties = { id = { type = "string" } }, required = { "id" } },
    run = function(core, args)
      local browser = require("omaset.browser")
      local cfg, err = browser.read()
      if not cfg then return nil, err end
      local ok, werr = browser.disable(cfg, args.id)
      if not ok then return nil, werr end
      local wok, werr2 = browser.write(cfg)
      if not wok then return nil, werr2 end
      return { ok = true, id = args.id }
    end,
  },
  {
    name = "browser_set_label",
    description = "Set or clear a browser's display label.",
    inputSchema = { type = "object", properties = { id = { type = "string" }, label = { type = "string" } }, required = { "id" } },
    run = function(core, args)
      local browser = require("omaset.browser")
      local cfg, err = browser.read()
      if not cfg then return nil, err end
      browser.set_label(cfg, args.id, args.label)
      local wok, werr = browser.write(cfg)
      if not wok then return nil, werr end
      return { ok = true, id = args.id, label = args.label }
    end,
  },
  {
    name = "browser_rule_add",
    description = "Add domains to a browser's routing rules.",
    inputSchema = { type = "object", properties = { browser = { type = "string" }, domains = { type = "array", items = { type = "string" } } }, required = { "browser", "domains" } },
    run = function(core, args)
      local browser = require("omaset.browser")
      local cfg, err = browser.read()
      if not cfg then return nil, err end
      local ok, werr = browser.add_rule(cfg, args.browser, args.domains)
      if not ok then return nil, werr end
      local wok, werr2 = browser.write(cfg)
      if not wok then return nil, werr2 end
      return { ok = true, browser = args.browser, domains = args.domains }
    end,
  },
  {
    name = "browser_rule_remove",
    description = "Remove domains from routing rules.",
    inputSchema = { type = "object", properties = { domains = { type = "array", items = { type = "string" } } }, required = { "domains" } },
    run = function(core, args)
      local browser = require("omaset.browser")
      local cfg, err = browser.read()
      if not cfg then return nil, err end
      browser.remove_rule(cfg, args.domains)
      local wok, werr = browser.write(cfg)
      if not wok then return nil, werr end
      return { ok = true, domains = args.domains }
    end,
  },
  {
    name = "browser_rule_edit",
    description = "Edit a rule: rename a domain or move it to a different browser.",
    inputSchema = { type = "object", properties = { domain = { type = "string" }, newDomain = { type = "string" }, browser = { type = "string" } }, required = { "domain" } },
    run = function(core, args)
      local browser = require("omaset.browser")
      local cfg, err = browser.read()
      if not cfg then return nil, err end
      local ok, werr = browser.edit_rule(cfg, args.domain, args.newDomain, args.browser)
      if not ok then return nil, werr end
      local wok, werr2 = browser.write(cfg)
      if not wok then return nil, werr2 end
      return { ok = true }
    end,
  },
  {
    name = "browser_status",
    description = "List all known browsers with installed, enabled, and label status.",
    inputSchema = { type = "object", properties = {} },
    run = function(core)
      local browser = require("omaset.browser")
      local cfg, err = browser.read()
      if not cfg then return nil, err end
      local out = {}
      for _, id in ipairs(browser.known_ids()) do
        out[#out + 1] = {
          id = id,
          name = browser.name_for(id),
          command = browser.command_for(id),
          installed = browser.is_installed(id),
          enabled = browser.is_enabled(cfg, id),
          label = browser.display_name(cfg, id),
        }
      end
      return { browsers = out }
    end,
  },
}

function M.operations()
  return OPS
end

function M.find(name)
  for _, op in ipairs(OPS) do
    if op.name == name then
      return op
    end
  end
end

function M.call(core, name, args)
  local op = M.find(name)
  if not op then
    return nil, "unknown operation: " .. tostring(name)
  end
  local ok, result, err = pcall(op.run, core, args or {})
  if not ok then
    return nil, tostring(result)
  end
  return result, err
end

return M
