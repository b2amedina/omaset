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
-- the same operation layer the CLI and the UI's RPC server use. The one
-- non-protocol part is agent registration at the bottom, which shells out to
-- each agent's own `mcp add` rather than editing another tool's config.

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

-- Agent registration. omaset never rewrites another tool's config file: each
-- agent ships its own `mcp add` subcommand, which owns the config format, the
-- scope, and the file's permissions (claude writes ~/.claude.json mode 0600 and
-- keeps it there; a hand-rolled rewrite would have to reimplement all of that).
-- `argv` is the subcommand after the agent binary. `file`/`keys`/`section` are
-- read-only, used by `doctor` to report where the agent keeps the entry.
local function home()
  return os.getenv("HOME") or ""
end

local function xdg_config_home()
  return os.getenv("XDG_CONFIG_HOME") or home() .. "/.config"
end

local AGENTS = {
  opencode = {
    bin = "opencode",
    argv = { "mcp", "add", "--global", "omaset", "--", "omaset", "mcp" },
    file = function() return xdg_config_home() .. "/opencode/opencode.json" end,
    keys = { "mcp.servers.omaset" },
  },
  claude = {
    bin = "claude",
    argv = { "mcp", "add", "-s", "user", "omaset", "--", "omaset", "mcp" },
    file = function() return home() .. "/.claude.json" end,
    keys = { "mcpServers.omaset" },
  },
  gemini = {
    bin = "gemini",
    argv = { "mcp", "add", "-s", "user", "omaset", "omaset", "mcp" },
    file = function() return home() .. "/.gemini/settings.json" end,
    keys = { "mcpServers.omaset" },
  },
  copilot = {
    bin = "copilot",
    argv = { "mcp", "add", "omaset", "--", "omaset", "mcp" },
    file = function()
      return (os.getenv("COPILOT_HOME") or home() .. "/.copilot") .. "/mcp-config.json"
    end,
    keys = { "mcpServers.omaset" },
  },
  codex = {
    bin = "codex",
    argv = { "mcp", "add", "omaset", "--", "omaset", "mcp" },
    file = function()
      return (os.getenv("CODEX_HOME") or home() .. "/.codex") .. "/config.toml"
    end,
    toml = true,
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

-- True when the agent's config already carries an omaset server entry.
local function configured(a)
  local existing = util.read_file(a.file())
  if not existing then
    return false
  end
  if a.toml then
    return existing:find(a.section, 1, true) ~= nil
  end
  local doc = json.decode(existing)
  if type(doc) ~= "table" then
    return false
  end
  for _, key in ipairs(a.keys) do
    if util.deep_get(doc, key) ~= nil then
      return true
    end
  end
  return false
end

local function quote_argv(argv)
  local parts = {}
  for _, arg in ipairs(argv) do
    parts[#parts + 1] = util.shell_quote(arg)
  end
  return table.concat(parts, " ")
end

-- The invocation that registers the server, as a printable one-liner.
local function add_command(a)
  return a.bin .. " " .. table.concat(a.argv, " ")
end

-- `omaset mcp install [agent ...]` — register the omaset server by calling each
-- agent's own `mcp add`, which writes that agent's config in its own format,
-- scope, and permissions. An agent whose CLI is not installed is skipped: there
-- is nothing to configure for it, and omaset does not create config files for
-- tools the user does not have.
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
    return nil, "no agent selected"
  end

  local done, failed = 0, 0
  for _, name in ipairs(targets) do
    local a = AGENTS[name]
    if not util.cmd_exists(a.bin) then
      io.stderr:write("omaset mcp install: " .. name .. ": " .. a.bin
        .. " not installed; skipped\n")
    else
      local out, code = util.run_capture(quote_argv({ a.bin, unpack(a.argv) }))
      if code == 0 then
        done = done + 1
        print(name .. ": " .. a.file())
      elseif configured(a) then
        -- Some agents (copilot) refuse a duplicate entry instead of updating it.
        done = done + 1
        print(name .. ": already configured in " .. a.file())
      else
        failed = failed + 1
        io.stderr:write("omaset mcp install: " .. name .. ": `" .. add_command(a)
          .. "` failed (exit " .. tostring(code) .. ")\n")
        local msg = (out or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if msg ~= "" then
          io.stderr:write(msg .. "\n")
        end
      end
    end
  end

  if failed > 0 then
    return nil, failed .. " agent(s) failed"
  end
  if done == 0 then
    return nil, "no agent configured"
  end
  return true
end

-- `omaset mcp doctor` — report which agents already point at the omaset server.
-- Exit 0 when at least one agent is configured, 1 otherwise.
function M.doctor()
  local configured_count = 0
  for _, name in ipairs(agent_names()) do
    local a = AGENTS[name]
    local state = "missing"
    if not util.cmd_exists(a.bin) then
      -- No agent to serve, even if a stale config entry lingers on disk.
      state = "no cli"
    elseif configured(a) then
      state = "ok"
      configured_count = configured_count + 1
    end
    print(string.format("%-10s %-8s %s", name, state, a.file()))
  end
  os.exit(configured_count > 0 and 0 or 1)
end

return M
