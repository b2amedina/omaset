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
--
-- This file is only a wire adapter: every tool is dispatched to service.lua,
-- the same operation layer the CLI and the UI's RPC server use.

local util = require("omaset.util")
local json = require("omaset.json")
local service = require("omaset.service")

local M = {}

-- Protocol versions this server speaks, oldest first. `initialize` echoes the
-- client's version when it is in this set, otherwise responds with the newest.
local SUPPORTED = { "2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25" }
local LATEST = SUPPORTED[#SUPPORTED]

-- The text content is the JSON of the payload itself, so agents that only
-- surface content.text still see the real data rather than a summary string.
local function tool_result(data)
  return {
    content = { { type = "text", text = json.encode(data) } },
    structuredContent = data,
  }
end

local function call_tool(core, name, args)
  local op = service.find(name)
  if not op or op.mcp == false then
    return nil, "unknown tool: " .. tostring(name)
  end
  return service.call(core, name, args or {})
end

local function tool_list()
  local out = {}
  for _, op in ipairs(service.operations()) do
    if op.mcp ~= false then
      out[#out + 1] = {
        name = op.name,
        description = op.description,
        inputSchema = op.inputSchema,
      }
    end
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
      send(out, { jsonrpc = "2.0", id = id, result = tool_result(result) })
    end
  else
    send(out, { jsonrpc = "2.0", id = id, error = { code = -32601, message = "method not found: " .. tostring(method) } })
  end
end

-- Serve the stdio MCP loop. `core` is the loaded omaset module.
function M.serve(core)
  core.load()
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
