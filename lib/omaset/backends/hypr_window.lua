-- Backend that reads/writes Hyprland window rules (o.window calls) in place.
--
-- A setting using this backend declares `match` (a table of window-rule match
-- fields, e.g. { fullscreen_state_internal = 1 }) and `subsettings` (named
-- rule fields, e.g. border_size / rounding). Sub-settings sharing a match
-- compose into a single o.window(match, rules) line.
--
-- READ: scan the whole file for the *last* o.window() call whose match equals
--       the setting's match — Hyprland applies window rules in order, so the
--       later call wins — and read the requested field from its rules table.
-- WRITE/RESET: rebuild that one call with the field changed; add a new call at
--       EOF when no matching rule exists.

local util = require("omaset.util")
local types = require("omaset.types")
local luaedit = require("omaset.luaedit")
local registry = require("omaset.backends")

local M = {}

local function user_hypr_dir()
  return os.getenv("OMASET_HYPR_DIR")
    or (os.getenv("HOME") or "") .. "/.config/hypr"
end

local function user_file(setting)
  return user_hypr_dir() .. "/" .. (setting.file or "hyprland") .. ".lua"
end

-- Serialize a flat key -> value-string map to a compact, sorted table literal,
-- matching the shape omaset itself writes.
local function compact_map(m)
  local keys = {}
  for k in pairs(m) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    local keyline
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
      keyline = k
    else
      keyline = "[" .. string.format("%q", tostring(k)) .. "]"
    end
    parts[#parts + 1] = keyline .. " = " .. m[k]
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

-- A flat table of scalar values, serialized to a key -> value-string map.
local function map_from_table(t)
  local m = {}
  for k, v in pairs(t) do m[k] = util.serialize(v, 0) end
  return m
end

-- Canonical form of a flat table of scalar values (used for matches/rules).
local function compact_table(t)
  return compact_map(map_from_table(t))
end

-- Canonical form of the leaves parsed out of a table literal in the file.
local function canonical(leaves, content)
  local m = {}
  for _, leaf in ipairs(leaves) do m[leaf.path] = content:sub(leaf.s, leaf.e) end
  return compact_map(m)
end

-- Parse the o.window(match, rules) call starting at token index i (toks[i] is
-- "o"). Returns its byte span, both argument tables' leaves, and the rules
-- table's closing-brace offset — or nil if the shape is not what we expect.
local function parse_window_call(toks, i)
  if not (toks[i + 1] and toks[i + 1].text == "."
      and toks[i + 2] and toks[i + 2].t == "id" and toks[i + 2].text == "window"
      and toks[i + 3] and toks[i + 3].text == "(") then
    return nil
  end
  local j = i + 4
  if not (toks[j] and toks[j].text == "{") then return nil end
  local match_leaves = {}
  local nj, _ = luaedit.parse_table(toks, j, "", match_leaves)
  j = nj
  if toks[j] and toks[j].text == "," then j = j + 1 end
  if not (toks[j] and toks[j].text == "{") then return nil end
  local rules_leaves = {}
  local rules_open = toks[j].s
  local nj2, rules_close = luaedit.parse_table(toks, j, "", rules_leaves)
  j = nj2
  local stmt_e
  if toks[j] and toks[j].text == ")" then
    stmt_e = toks[j].e
  else
    stmt_e = rules_close or toks[i].e
  end
  return {
    s = toks[i].s, e = stmt_e,
    match_leaves = match_leaves,
    rules_leaves = rules_leaves,
    rules_open = rules_open, rules_close = rules_close,
  }
end

-- The last o.window() call whose match equals `match_str`, or nil.
local function find_window_rule(content, match_str)
  local toks = luaedit.lex(content)
  local found = nil
  local i = 1
  while i <= #toks do
    if toks[i].t == "id" and toks[i].text == "o" then
      local call = parse_window_call(toks, i)
      if call and canonical(call.match_leaves, content) == match_str then
        found = call
      end
    end
    i = i + 1
  end
  return found
end

-- Serialize a single o.window(match, rules) line for a set of field -> value
-- strings.
local function rule_line(match_str, entries)
  return "o.window(" .. match_str .. ", " .. compact_map(entries) .. ")"
end

local function append(content, stmt)
  if content == "" then return stmt .. "\n" end
  if content:sub(-1) ~= "\n" then return content .. "\n\n" .. stmt .. "\n" end
  return content .. "\n" .. stmt .. "\n"
end

-- Remove the statement spanning [s, e] and, when it sits alone on its line, the
-- rest of that line too, so no blank line is left behind.
local function drop_statement(content, s, e)
  local nl = content:find("\n", e, true)
  if nl and content:sub(e + 1, nl - 1):match("^%s*$") then
    return content:sub(1, s - 1) .. content:sub(nl + 1)
  end
  return content:sub(1, s - 1) .. content:sub(e + 1)
end

local function apply_enabled()
  local v = os.getenv("OMASET_NO_APPLY")
  return not (v == "1" or v == "true" or v == "yes" or v == "on")
end

local function apply_and_validate(file, prev_content)
  if not util.cmd_exists("hyprctl") then
    return true
  end
  util.run_capture("hyprctl reload")
  local out, code = util.run_capture("hyprctl configerrors")
  local err_text = out:gsub("^%s+", ""):gsub("%s+$", "")
  if err_text == "" and code == 0 then
    return true
  end
  util.write_file(file, prev_content)
  util.run_capture("hyprctl reload")
  return nil, "config errors after write (change reverted):\n" .. err_text
end

local function commit(file, prev_content, new_content)
  if new_content == prev_content then
    return true
  end
  if util.read_file(file .. ".omaset.bak") == nil then
    util.write_file(file .. ".omaset.bak", prev_content)
  end
  local ok, err = util.write_file(file, new_content)
  if not ok then
    return nil, err
  end
  if apply_enabled() then
    local aok, aerr = apply_and_validate(file, prev_content)
    if not aok then
      return nil, aerr
    end
  end
  return true
end

function M.read(setting, key)
  local content = util.read_file(user_file(setting)) or ""
  local rule = find_window_rule(content, compact_table(setting.match))
  if rule then
    for _, leaf in ipairs(rule.rules_leaves) do
      if leaf.path == key then
        local sub = setting.subsettings and setting.subsettings[key]
        local value = types.coerce(content:sub(leaf.s, leaf.e), sub)
        if value ~= nil then return value end
        return content:sub(leaf.s, leaf.e)
      end
    end
  end
  local sub = setting.subsettings and setting.subsettings[key]
  return sub and sub.default or nil
end

function M.write(setting, key, value)
  local file = user_file(setting)
  local content = util.read_file(file) or ""
  local match_str = compact_table(setting.match)
  local rule = find_window_rule(content, match_str)
  local literal = util.serialize(value, 0)

  local entries = {}
  if rule then
    for _, leaf in ipairs(rule.rules_leaves) do
      entries[leaf.path] = content:sub(leaf.s, leaf.e)
    end
  end
  entries[key] = literal
  local stmt = rule_line(match_str, entries)

  if rule then
    return commit(file, content, luaedit.splice(content, rule.s, rule.e, stmt))
  end
  return commit(file, content, append(content, stmt))
end

function M.reset(setting, key)
  local file = user_file(setting)
  local content = util.read_file(file) or ""
  local match_str = compact_table(setting.match)
  local rule = find_window_rule(content, match_str)
  if not rule then
    return true
  end

  local entries = {}
  for _, leaf in ipairs(rule.rules_leaves) do
    if leaf.path ~= key then
      entries[leaf.path] = content:sub(leaf.s, leaf.e)
    end
  end

  if next(entries) == nil then
    return commit(file, content, drop_statement(content, rule.s, rule.e))
  end
  return commit(file, content, luaedit.splice(content, rule.s, rule.e, rule_line(match_str, entries)))
end

-- The omaset settings window's own float/center rule, driven by the
-- `launch_floating` preference (not a settings-model setting). Enabling adds
-- it; disabling removes it.
local OMASET_MATCH = { class = "^org.quickshell$", title = "^omaset Settings$" }
local OMASET_RULES = { float = true, center = true }

function M.set_omaset_float(enabled)
  local file = user_file({ file = "hyprland" })
  local content = util.read_file(file) or ""
  local match_str = compact_table(OMASET_MATCH)
  local rule = find_window_rule(content, match_str)

  if enabled then
    if rule then
      if canonical(rule.rules_leaves, content) == compact_table(OMASET_RULES) then
        return true
      end
      local stmt = rule_line(match_str, map_from_table(OMASET_RULES))
      return commit(file, content, luaedit.splice(content, rule.s, rule.e, stmt))
    end
    local stmt = rule_line(match_str, map_from_table(OMASET_RULES))
    return commit(file, content, append(content, stmt))
  end

  if rule then
    return commit(file, content, drop_statement(content, rule.s, rule.e))
  end
  return true
end

registry.register("hypr-window", M)

return M
