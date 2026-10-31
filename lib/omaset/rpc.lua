-- JSON-RPC 2.0 over stdio for the settings window (and any other local
-- frontend). Newline-delimited requests, one method per line, no handshake:
-- the method names are exactly service.lua's operation names.
--
--   {"jsonrpc":"2.0","id":1,"method":"snapshot","params":{"panel":"layout"}}
--   {"jsonrpc":"2.0","id":1,"result":{...}}
--
-- stdout carries protocol messages only; diagnostics go to stderr.

local json = require("omaset.json")
local service = require("omaset.service")

local M = {}

local function send(out, msg)
  out:write(json.encode(msg) .. "\n")
  out:flush()
end

local function send_error(out, id, code, message)
  send(out, {
    jsonrpc = "2.0",
    id = id,
    error = { code = code, message = message },
  })
end

local function handle(core, out, msg)
  if msg.id == nil then
    return -- notification (no response)
  end
  local id = msg.id
  local method = msg.method

  if method == "ping" then
    send(out, { jsonrpc = "2.0", id = id, result = {} })
    return
  end
  if method == "version" then
    send(out, {
      jsonrpc = "2.0",
      id = id,
      result = { version = core.VERSION, schemaVersion = core.SCHEMA_VERSION },
    })
    return
  end

  local op = service.find(method)
  if not op then
    send_error(out, id, -32601, "method not found: " .. tostring(method))
    return
  end

  local result, err = service.call(core, method, msg.params or {})
  if result == nil then
    send_error(out, id, -32602, err)
  else
    send(out, { jsonrpc = "2.0", id = id, result = result })
  end
end

-- Serve the stdio RPC loop. `core` is the loaded omaset module.
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
      send_error(out, json.null, -32700, "parse error: " .. tostring(err))
    else
      local ok, herr = pcall(handle, core, out, msg)
      if not ok then
        io.stderr:write("omaset rpc: handler error: " .. tostring(herr) .. "\n")
        if msg.id ~= nil then
          send_error(out, msg.id, -32603, tostring(herr))
        end
      end
    end
  end
end

return M
