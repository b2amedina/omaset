-- omaset browser: manage the browser-router configuration.
--
-- The router is a thin wrapper: it reads ~/.config/browser-router/config.json,
-- routes a URL to the matching browser, and shows an Omarchy picker when no
-- rule matches. omaset owns the file; the router only reads it.
--
-- Config shape:
--   enabled : list of browser ids that are shown in the router
--   labels  : map of browser id -> display label (optional)
--   rules   : list of { browser = id, domains = [...] }
--   fallback: "chooser" or a browser id

local json = require("omaset.json")
local util = require("omaset.util")
local M = {}

-- Omarchy's known browsers: id -> { command, name }. The router resolves
-- through this. `name` is the display name shown in the chooser and rules.
M.KNOWN = {
  chromium       = { command = "chromium",             name = "Chromium" },
  chrome         = { command = "google-chrome-stable", name = "Chrome" },
  brave          = { command = "brave",                name = "Brave" },
  ["brave-origin"] = { command = "brave-origin",       name = "Brave Origin" },
  edge           = { command = "microsoft-edge-stable", name = "Edge" },
  firefox        = { command = "firefox",              name = "Firefox" },
  zen            = { command = "zen-browser",          name = "Zen" },
}

function M.known_ids()
  local out = {}
  for id in pairs(M.KNOWN) do
    out[#out + 1] = id
  end
  table.sort(out)
  return out
end

function M.command_for(id)
  local e = M.KNOWN[id]
  return e and e.command
end

function M.name_for(id)
  local e = M.KNOWN[id]
  return e and e.name or id
end

function M.is_installed(id)
  local cmd = M.command_for(id)
  if not cmd then return false end
  return util.cmd_exists(cmd)
end

-- Install a browser through Omarchy's floating terminal (which handles sudo
-- and shows progress), polling until the binary appears or 5 minutes pass.
-- Returns true on success, or nil plus an error on failure/cancellation.
function M.install(id)
  if not M.KNOWN[id] then
    return nil, "unknown browser: " .. id
  end
  if M.is_installed(id) then
    return true
  end
  local cmd = "omarchy-launch-floating-terminal-with-presentation omarchy-install-browser "
    .. util.shell_quote(id)
  os.execute("nohup " .. cmd .. " >/dev/null 2>&1 &")
  for _ = 1, 150 do  -- 5 minutes
    os.execute("sleep 2")
    if M.is_installed(id) then
      return true
    end
  end
  return nil, id .. " installation did not complete or was cancelled"
end

function M.config_path()
  return (os.getenv("HOME") or "") .. "/.config/browser-router/config.json"
end

local empty_config = { enabled = {}, labels = {}, rules = {}, fallback = "chooser" }

function M.read()
  local path = M.config_path()
  if not util.file_exists(path) then
    return empty_config
  end
  local content = util.read_file(path)
  if not content or content == "" then
    return empty_config
  end
  local ok, doc = pcall(json.decode, content)
  if not ok or type(doc) ~= "table" then
    return nil, "cannot parse " .. path .. ": " .. tostring(doc)
  end
  doc.enabled = doc.enabled or {}
  doc.labels = doc.labels or {}
  doc.rules = doc.rules or {}
  doc.fallback = doc.fallback or "chooser"
  return doc
end

function M.write(cfg)
  local dir = M.config_path():match("^(.*)/") or "."
  util.run_capture("mkdir -p " .. util.shell_quote(dir))
  -- Mark the array-typed fields so empty ones encode as [] rather than {}.
  local out = {
    enabled = json.array(cfg.enabled or {}),
    labels = cfg.labels or {},
    rules = json.array(cfg.rules or {}),
    fallback = cfg.fallback or "chooser",
  }
  local wok, werr = util.write_file(M.config_path(), json.encode(out))
  if not wok then
    return nil, werr
  end
  return true
end

function M.is_enabled(cfg, id)
  for _, b in ipairs(cfg.enabled or {}) do
    if b == id then return true end
  end
  return false
end

function M.enable(cfg, id)
  if not M.KNOWN[id] then
    return nil, "unknown browser: " .. id .. " (choose from: " .. table.concat(M.known_ids(), ", ") .. ")"
  end
  if M.is_enabled(cfg, id) then
    return nil, id .. " is already enabled"
  end
  cfg.enabled[#cfg.enabled + 1] = id
  return true
end

function M.disable(cfg, id)
  local new = {}
  for _, b in ipairs(cfg.enabled or {}) do
    if b ~= id then new[#new + 1] = b end
  end
  if #new == #(cfg.enabled or {}) then
    return nil, id .. " is not enabled"
  end
  cfg.enabled = new
  -- Keep the browser's rules: disabling only hides it from the router. Its
  -- rules remain so re-enabling restores them.
  -- Remove label.
  if cfg.labels then cfg.labels[id] = nil end
  return true
end

function M.set_label(cfg, id, label)
  cfg.labels = cfg.labels or {}
  if label == "" or label == nil then
    cfg.labels[id] = nil
  else
    cfg.labels[id] = label
  end
  return true
end

function M.display_name(cfg, id)
  if cfg.labels and cfg.labels[id] and cfg.labels[id] ~= "" then
    return cfg.labels[id]
  end
  return M.name_for(id)
end

function M.add_rule(cfg, browser_id, domains)
  if not M.is_enabled(cfg, browser_id) then
    return nil, browser_id .. " is not enabled"
  end
  cfg.rules = cfg.rules or {}
  -- Insert at the front so a new rule appears at the top of the list (the
  -- add form sits above the rules). Iterate in reverse to keep order.
  for i = #domains, 1, -1 do
    local d = domains[i]
    local dup = false
    for _, r in ipairs(cfg.rules) do
      if r.domain == d then dup = true; break end
    end
    if not dup then
      table.insert(cfg.rules, 1, { domain = d, browser = browser_id })
    end
  end
  return true
end

function M.remove_rule(cfg, domains)
  local new = {}
  for _, r in ipairs(cfg.rules or {}) do
    local drop = false
    for _, d in ipairs(domains) do
      if r.domain == d then drop = true; break end
    end
    if not drop then
      new[#new + 1] = r
    end
  end
  cfg.rules = new
  return true
end

-- Edit a rule: the domain `domain` becomes `new_domain` mapped to `browser`.
-- Handles both renaming a domain and moving it to a different browser. The
-- rule is updated in place so the list order is preserved.
function M.edit_rule(cfg, domain, new_domain, browser)
  for _, r in ipairs(cfg.rules or {}) do
    if r.domain == domain then
      if new_domain ~= nil and new_domain ~= "" then
        r.domain = new_domain
      end
      if browser ~= nil then
        r.browser = browser
      end
      return true
    end
  end
  -- Domain not found: add it as a new rule.
  if new_domain ~= nil and new_domain ~= "" then
    return M.add_rule(cfg, browser, { new_domain })
  end
  return true
end

return M
