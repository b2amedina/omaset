-- MCP (Model Context Protocol) server exposing omaset's settings as typed
-- tools over stdio. Agents (Claude Code, Codex, opencode, Gemini, Copilot)
-- can discover, read, and change Omarchy settings without shelling out to the
-- CLI or editing dotfiles by hand.
--
-- Wire format: newline-delimited JSON-RPC 2.0. stdout carries MCP messages
-- only; every diagnostic goes to stderr (the spec allows UTF-8 on stderr and
-- forbids non-MCP output on stdout). The process must never os.exit() on a
-- bad message: errors are reported as JSON-RPC error responses.
--
-- Protocol: the legacy `initialize` handshake (protocol versions through
-- 2025-11-25), which is what current agents speak. A best-effort
-- `server/discover` is also answered so 2026-07-28+ (stateless) clients can
-- negotiate.

local util = require("omaset.util")
local json = require("omaset.json")
local types = require("omaset.types")
local journal = require("omaset.journal")

local M = {}

-- Protocol versions this server speaks, oldest first. `initialize` echoes the
-- client's version when it is in this set, otherwise responds with the newest.
local SUPPORTED = { "2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25" }
local LATEST = SUPPORTED[#SUPPORTED]

-- Panels loaded once at server start (set in serve); tools iterate this.
local panels = nil

local function jnull(v)
  if v == nil then
    return json.null
  end
  return v
end

local function grouped(setting)
  return setting.subsettings ~= nil
end

local function sub_keys(setting)
  local keys = {}
  for k in pairs(setting.subsettings) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- Resolve the key/sub argument for a keyed or grouped setting. Returns the key
-- (or nil when the caller does not need one) plus an error message.
local function resolve_key(setting, key)
  if setting.keyed then
    local ok, kerr = types.validate_key(setting, key)
    if not ok then
      return nil, kerr
    end
    return key
  end
  if grouped(setting) then
    if key == nil then
      return nil
    end
    if not setting.subsettings[key] then
      return nil, "unknown sub-setting '" .. key .. "' for " .. setting.id
        .. " (choose from: " .. table.concat(sub_keys(setting), ", ") .. ")"
    end
    return key
  end
  return nil
end

local function record_change(core, op, s, key, old, def, new)
  local entry = { ts = os.time(), op = op, id = s.id, backend = s.backend }
  if s.keyed then
    entry.key = key
  elseif grouped(s) then
    entry.sub = key
  end
  entry.old = jnull(old)
  entry.default = jnull(def)
  entry.new = jnull(new)
  journal.record(entry)
end

local function find_setting(core, id)
  local s = core.find_setting(id)
  if not s then
    return nil, "unknown setting: " .. tostring(id)
  end
  return s
end

-- Each tool returns a CallToolResult table ({ content, structuredContent }) or
-- nil plus an error message (reported as a JSON-RPC error). The text content is
-- the JSON of the payload itself, so agents that only surface content.text
-- still see the real data rather than a summary string.
local function tool_result(data)
  return {
    content = { { type = "text", text = json.encode(data) } },
    structuredContent = data,
  }
end

local function tool_schema(core)
  return tool_result(core.schema())
end

local function tool_search(core, args)
  local q = tostring(args.query or ""):lower()
  local out = {}
  for _, p in ipairs(panels) do
    for _, s in ipairs(p.settings) do
      local hit = (q == "") or s.id:lower():find(q, 1, true)
        or s.label:lower():find(q, 1, true)
        or (s.description or ""):lower():find(q, 1, true)
      if hit then
        local entry = { id = s.id, panel = p.id, label = s.label }
        if s.description then entry.description = s.description end
        if s.type then entry.type = s.type end
        if s.keyed then
          entry.keyed = true
        elseif grouped(s) then
          entry.grouped = true
        else
          entry.value = jnull(core.read_value(s))
        end
        out[#out + 1] = entry
      end
    end
  end
  return tool_result({ results = json.array(out) })
end

local function tool_get(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end
  local key, kerr = resolve_key(s, args.key)
  if kerr then
    return nil, kerr
  end
  local value
  if grouped(s) and key == nil then
    value = {}
    for _, k in ipairs(sub_keys(s)) do
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
  return tool_result(out)
end

local function tool_set(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end
  local key, kerr = resolve_key(s, args.key)
  if kerr then
    return nil, kerr
  end
  local spec = s
  if grouped(s) then
    if key == nil then
      return nil, "missing sub-setting for setting: " .. s.id
        .. " (choose from: " .. table.concat(sub_keys(s), ", ") .. ")"
    end
    spec = s.subsettings[key]
  end
  if args.value == nil then
    return nil, "missing value for setting: " .. s.id
  end
  local vok, verr = types.validate(args.value, spec)
  if not vok then
    return nil, verr
  end
  local old = core.read_value(s, key)
  local def = core.read_default(s, key)
  local wok, werr = core.write_value(s, key, args.value)
  if not wok then
    return nil, werr
  end
  record_change(core, "set", s, key, old, def, args.value)
  local out = { id = s.id }
  if key ~= nil then
    if s.keyed then out.key = key else out.sub = key end
  end
  out.value = args.value
  out.ok = true
  return tool_result(out)
end

local function tool_reset(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end
  if args.all then
    if not (s.keyed or grouped(s)) then
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
        return nil, rerr
      end
    end
    local out = { id = s.id, ok = true, count = count }
    return tool_result(out)
  end

  local key, kerr = resolve_key(s, args.key)
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
  local out = { id = s.id }
  if key ~= nil then
    if s.keyed then out.key = key else out.sub = key end
  end
  out.ok = true
  return tool_result(out)
end

local function tool_changed(core, args)
  local out = {}
  for _, p in ipairs(panels) do
    for _, s in ipairs(p.settings) do
      if s.keyed then
        for _, k in ipairs(core.keys(s) or {}) do
          local cur = core.read_value(s, k)
          local def = core.read_default(s, k)
          if cur ~= def then
            out[#out + 1] = { id = s.id, key = k, panel = p.id, label = s.label, value = cur, default = def }
          end
        end
      elseif grouped(s) then
        for _, k in ipairs(sub_keys(s)) do
          local cur = core.read_value(s, k)
          local def = core.read_default(s, k)
          if cur ~= def then
            out[#out + 1] = { id = s.id, sub = k, panel = p.id, label = s.label, value = cur, default = def }
          end
        end
      else
        local cur = core.read_value(s)
        local def = core.read_default(s)
        if cur ~= def then
          out[#out + 1] = { id = s.id, panel = p.id, label = s.label, value = cur, default = def }
        end
      end
    end
  end
  return tool_result({ changed = json.array(out) })
end

local function tool_help(core, args)
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
  if s.keyed then
    out.keyed = true
    if s.key_label then out.key_label = s.key_label end
    if s.key_type then out.key_type = s.key_type end
  elseif grouped(s) then
    out.grouped = true
    out.subsettings = {}
    for _, k in ipairs(sub_keys(s)) do
      local sub = s.subsettings[k]
      out.subsettings[k] = { type = sub.type }
      if sub.default ~= nil then out.subsettings[k].default = sub.default end
      if sub.options then out.subsettings[k].options = json.array(sub.options) end
    end
  else
    out.value = jnull(core.read_value(s))
    out.default = jnull(core.read_default(s))
  end
  return tool_result(out)
end

local function tool_keys(core, args)
  local s, err = find_setting(core, args.id)
  if not s then
    return nil, err
  end

  if grouped(s) then
    local entries = json.array({})
    for _, k in ipairs(sub_keys(s)) do
      entries[#entries + 1] = { sub = k, value = jnull(core.read_value(s, k)), default = jnull(core.read_default(s, k)) }
    end
    return tool_result({ id = s.id, grouped = true, entries = entries })
  end

  if s.keyed then
    local keys
    if args.all then
      keys = core.keys_all(s)
    else
      keys = core.keys(s)
    end
    keys = keys or {}
    local entries = json.array({})
    for _, k in ipairs(keys) do
      entries[#entries + 1] = { key = k, value = jnull(core.read_value(s, k)), default = jnull(core.read_default(s, k)) }
    end
    return tool_result({ id = s.id, keyed = true, entries = entries })
  end

  return nil, "setting is not keyed or grouped: " .. s.id
end

local function tool_undo(core, args)
  local entries = journal.read_all()
  if #entries == 0 then
    return tool_result({ ok = true, undone = 0 })
  end
  local entry = entries[#entries]
  local s = core.find_setting(entry.id)
  if not s then
    return nil, "unknown setting in journal: " .. tostring(entry.id)
  end
  local key = entry.key or entry.sub
  local old = entry.old
  if old == json.null then old = nil end
  local def = entry.default
  if def == json.null then def = nil end
  local ok
  if entry.op == "set" then
    if old == def then
      ok = core.reset_value(s, key)
    else
      ok = core.write_value(s, key, old)
    end
  elseif entry.op == "reset" then
    if old == def then
      ok = true
    else
      ok = core.write_value(s, key, old)
    end
  else
    return nil, "unknown journal op: " .. tostring(entry.op)
  end
  if not ok then
    return nil, "undo failed for " .. tostring(entry.id)
  end
  journal.remove_last()
  local out = { id = entry.id, ok = true }
  if entry.key then out.key = entry.key end
  if entry.sub then out.sub = entry.sub end
  return tool_result(out)
end

local function tool_open_ui(core, args)
  local cmd = "omarchy-shell shell summon b2amedina.omaset '{}'"
  local ok = os.execute(cmd)
  if ok ~= 0 then
    return nil, "could not reach the Omarchy shell (is it running?)"
  end
  return tool_result({ ok = true })
end

local TOOLS = {
  {
    name = "schema",
    description = "Return omaset's full schema: every panel and setting with its id, label, description, type, options, range, and current value.",
    inputSchema = { type = "object", properties = {} },
    run = tool_schema,
  },
  {
    name = "search",
    description = "Find settings by id, label, or description substring.",
    inputSchema = { type = "object", properties = { query = { type = "string", description = "Substring to match" } }, required = { "query" } },
    run = tool_search,
  },
  {
    name = "get",
    description = "Read one setting's current value and default. Keyed settings take a key; grouped settings take an optional sub-setting name.",
    inputSchema = { type = "object", properties = { id = { type = "string" }, key = { type = "string" } }, required = { "id" } },
    run = tool_get,
  },
  {
    name = "set",
    description = "Write a setting value (validated against its type, options, and range; applied via its backend). Keyed/grouped settings take a key.",
    inputSchema = { type = "object", properties = { id = { type = "string" }, value = {}, key = { type = "string" } }, required = { "id", "value" } },
    run = tool_set,
  },
  {
    name = "reset",
    description = "Revert omaset's override for a setting so the Omarchy default applies. Keyed/grouped settings take a key, or all=true to reset every key.",
    inputSchema = { type = "object", properties = { id = { type = "string" }, key = { type = "string" }, all = { type = "boolean" } }, required = { "id" } },
    run = tool_reset,
  },
  {
    name = "changed",
    description = "List settings whose effective value differs from the Omarchy default.",
    inputSchema = { type = "object", properties = {} },
    run = tool_changed,
  },
  {
    name = "help",
    description = "Show one setting's full spec: description, type, options, range, default, and current value.",
    inputSchema = { type = "object", properties = { id = { type = "string" } }, required = { "id" } },
    run = tool_help,
  },
  {
    name = "keys",
    description = "Enumerate a keyed or grouped setting's keys with each key's current value and default. For keyed settings, all=true also lists persisted keys (e.g. workspaces that are not currently open).",
    inputSchema = { type = "object", properties = { id = { type = "string" }, all = { type = "boolean" } }, required = { "id" } },
    run = tool_keys,
  },
  {
    name = "undo",
    description = "Undo omaset's most recent setting change.",
    inputSchema = { type = "object", properties = {} },
    run = tool_undo,
  },
  {
    name = "open_ui",
    description = "Open the omaset settings window so the user can see or verify changes.",
    inputSchema = { type = "object", properties = {} },
    run = tool_open_ui,
  },
}

local function call_tool(core, name, args)
  for _, t in ipairs(TOOLS) do
    if t.name == name then
      return t.run(core, args or {})
    end
  end
  return nil, "unknown tool: " .. tostring(name)
end

local function tool_list()
  local out = {}
  for _, t in ipairs(TOOLS) do
    out[#out + 1] = { name = t.name, description = t.description, inputSchema = t.inputSchema }
  end
  return out
end

local function send(out, msg)
  out:write(json.encode(msg) .. "\n")
  out:flush()
end

local function handle(core, out, msg)
  local method = msg.method
  if msg.id == nil or (method ~= nil and method:match("^notifications/")) then
    return -- notification (no response)
  end
  local id = msg.id

  if method == "initialize" then
    local params = msg.params or {}
    local requested = params.protocolVersion
    local version = LATEST
    for _, v in ipairs(SUPPORTED) do
      if v == requested then
        version = v
        break
      end
    end
    send(out, {
      jsonrpc = "2.0", id = id,
      result = {
        protocolVersion = version,
        capabilities = { tools = {} },
        serverInfo = { name = "omaset", version = core.VERSION or "0.0.0" },
      },
    })
  elseif method == "ping" then
    send(out, { jsonrpc = "2.0", id = id, result = {} })
  elseif method == "server/discover" then
    send(out, {
      jsonrpc = "2.0", id = id,
      result = {
        resultType = "complete",
        protocolVersion = LATEST,
        supportedVersions = json.array(SUPPORTED),
        capabilities = { tools = {} },
        serverInfo = { name = "omaset", version = core.VERSION or "0.0.0" },
      },
    })
  elseif method == "tools/list" then
    send(out, { jsonrpc = "2.0", id = id, result = { tools = json.array(tool_list()) } })
  elseif method == "tools/call" then
    local params = msg.params or {}
    local result, err = call_tool(core, params.name, params.arguments)
    if not result then
      send(out, { jsonrpc = "2.0", id = id, error = { code = -32602, message = err } })
    else
      send(out, { jsonrpc = "2.0", id = id, result = result })
    end
  else
    send(out, { jsonrpc = "2.0", id = id, error = { code = -32601, message = "method not found: " .. tostring(method) } })
  end
end

-- Serve the stdio MCP loop. `core` is the loaded omaset module.
function M.serve(core)
  panels = core.load()
  local out = io.stdout
  while true do
    local line = io.read("*l")
    if not line then
      break
    end
    local msg, err = json.decode(line)
    if not msg then
      io.stderr:write("omaset mcp: ignoring unparseable message: " .. tostring(err) .. "\n")
    else
      local ok, herr = pcall(handle, core, out, msg)
      if not ok then
        io.stderr:write("omaset mcp: handler error: " .. tostring(herr) .. "\n")
      end
    end
  end
end

-- Agent registration: how to wire the server into each supported agent's MCP
-- config. `key` is the dotted JSON path to the server entry; `value` is the
-- server definition (command/args arrays marked so they encode as JSON arrays).
local function xdg_config_home()
  return os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") or "") .. "/.config"
end

local AGENTS = {
  opencode = {
    file = function() return xdg_config_home() .. "/opencode/opencode.json" end,
    key = { "mcp", "omaset" },
    value = { type = "local", command = json.array({ "omaset", "mcp" }), enabled = true },
  },
  claude = {
    file = function() return (os.getenv("HOME") or "") .. "/.claude.json" end,
    key = { "mcpServers", "omaset" },
    value = { command = "omaset", args = json.array({ "mcp" }) },
  },
  gemini = {
    file = function() return (os.getenv("HOME") or "") .. "/.gemini/settings.json" end,
    key = { "mcpServers", "omaset" },
    value = { command = "omaset", args = json.array({ "mcp" }) },
  },
  copilot = {
    file = function()
      return (os.getenv("COPILOT_HOME") or (os.getenv("HOME") or "") .. "/.copilot") .. "/mcp-config.json"
    end,
    key = { "mcpServers", "omaset" },
    value = { type = "local", command = "omaset", args = json.array({ "mcp" }) },
  },
  codex = {
    toml = true,
    file = function() return (os.getenv("HOME") or "") .. "/.codex/config.toml" end,
    section = "[mcp_servers.omaset]",
  },
}

local function agent_names()
  local names = {}
  for k in pairs(AGENTS) do
    names[#names + 1] = k
  end
  table.sort(names)
  return names
end

local function ensure_parent(path)
  local dir = path:match("^(.*)/")
  if dir then
    os.execute("mkdir -p " .. util.shell_quote(dir))
  end
end

-- `omaset mcp install [agent ...]` — write the omaset server entry into each
-- named agent's MCP config (all agents when none are named). JSON configs are
-- read, merged, and re-written; the Codex TOML section is appended idempotently.
function M.install(names)
  local targets = {}
  if #names == 0 then
    targets = agent_names()
  else
    for _, n in ipairs(names) do
      if AGENTS[n] then
        targets[#targets + 1] = n
      else
        io.stderr:write("omaset mcp install: unknown agent '" .. n .. "' (choose from: "
          .. table.concat(agent_names(), ", ") .. ")\n")
      end
    end
  end
  if #targets == 0 then
    os.exit(1)
  end

  for _, name in ipairs(targets) do
    local a = AGENTS[name]
    local file = a.file()
    ensure_parent(file)

    if a.toml then
      local existing = util.read_file(file) or ""
      if existing:find(a.section, 1, true) then
        print(name .. ": already configured in " .. file)
      else
        local block = existing
        if block ~= "" and block:sub(-1) ~= "\n" then
          block = block .. "\n"
        end
        block = block .. "\n" .. a.section .. "\ncommand = \"omaset\"\nargs = [\"mcp\"]\n"
        util.write_file(file, block)
        print(name .. ": " .. file)
      end
    else
      local existing = util.read_file(file)
      local doc = {}
      if existing then
        local parsed, perr = json.decode(existing)
        if parsed and type(parsed) == "table" then
          doc = parsed
        else
          io.stderr:write("omaset mcp install: " .. file .. " is not valid JSON (" .. tostring(perr)
            .. "); skipped " .. name .. "\n")
          doc = nil
        end
      end
      if doc then
        util.deep_set(doc, table.concat(a.key, "."), a.value)
        util.write_file(file, json.encode(doc) .. "\n")
        print(name .. ": " .. file)
      end
    end
  end
end

-- `omaset mcp doctor` — report which agents already point at the omaset server.
-- Exit 0 when at least one agent is configured, 1 otherwise.
function M.doctor()
  local configured = 0
  for _, name in ipairs(agent_names()) do
    local a = AGENTS[name]
    local file = a.file()
    local present = false
    if a.toml then
      local existing = util.read_file(file) or ""
      present = existing:find(a.section, 1, true) ~= nil
    else
      local existing = util.read_file(file)
      if existing then
        local doc = json.decode(existing)
        present = doc and type(doc) == "table"
          and util.deep_get(doc, table.concat(a.key, ".")) ~= nil
      end
    end
    print(string.format("%-10s %-8s %s", name, present and "ok" or "missing", file))
    if present then
      configured = configured + 1
    end
  end
  os.exit(configured > 0 and 0 or 1)
end

return M
