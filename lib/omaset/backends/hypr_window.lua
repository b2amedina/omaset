-- Backend that reads/writes Hyprland window rules (o.window calls) as a
-- managed block, one rule per setting group.
--
-- A setting using this backend declares `match` (a table of window-rule match
-- fields, e.g. { fullscreen_state_internal = 1 }) and `subsettings` (named
-- rule fields, e.g. border_size / rounding). All sub-settings sharing the
-- same match compose into a single o.window(match, rules) line.

local util = require("omaset.util")
local registry = require("omaset.backends")

local M = {}

local BEGIN_MARK = "-- omaset:begin"
local END_MARK = "-- omaset:end"

local function user_hypr_dir()
  return os.getenv("OMASET_HYPR_DIR")
    or (os.getenv("HOME") or "") .. "/.config/hypr"
end

local function user_file(setting)
  return user_hypr_dir() .. "/" .. (setting.file or "hyprland") .. ".lua"
end

-- Serialize a flat table (scalar values only) to a compact, sorted literal.
local function compact_table(t)
  local parts = {}
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local line
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
      line = k
    else
      line = "[" .. string.format("%q", k) .. "]"
    end
    parts[#parts + 1] = line .. " = " .. util.serialize(t[k], 0)
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Parse the managed block into an ordered list of { match, rules } pairs by
-- evaluating it with a capturing o.window().
local function parse_rules(content)
  local rules = {}
  local start = content:find(BEGIN_MARK, 1, true)
  if not start then
    return rules
  end
  local body_start = content:find("\n", start, true)
  if not body_start then
    return rules
  end
  local finish = content:find(END_MARK, body_start, true)
  if not finish then
    return rules
  end
  local body = content:sub(body_start + 1, finish - 1)

  local o = {
    window = function(match, r)
      rules[#rules + 1] = { match = match, rules = r }
    end,
  }
  local chunk = util.load_chunk(body, "=omaset-window", { o = o })
  if chunk then
    pcall(chunk)
  end
  return rules
end

local function find_rule(rules, match_str)
  for _, r in ipairs(rules) do
    if compact_table(r.match) == match_str then
      return r
    end
  end
  return nil
end

local function build_block(rules)
  local lines = { BEGIN_MARK }
  for _, r in ipairs(rules) do
    lines[#lines + 1] = "o.window(" .. compact_table(r.match) .. ", " .. compact_table(r.rules) .. ")"
  end
  lines[#lines + 1] = END_MARK
  return table.concat(lines, "\n") .. "\n"
end

local function replace_or_append(content, block)
  local start = content:find(BEGIN_MARK, 1, true)
  if not start then
    local base = content
    if base ~= "" and base:sub(-1) ~= "\n" then
      base = base .. "\n"
    end
    return base .. "\n" .. block
  end
  local finish = content:find(END_MARK, start, true)
  local line_end = content:find("\n", finish, true)
  if not line_end then
    line_end = #content
  end
  return content:sub(1, start - 1) .. block .. content:sub(line_end + 1)
end

local function remove_block(content)
  local start = content:find(BEGIN_MARK, 1, true)
  if not start then
    return content
  end
  local finish = content:find(END_MARK, start, true)
  if not finish then
    return content
  end
  local line_end = content:find("\n", finish, true)
  if not line_end then
    line_end = #content
  end
  return content:sub(1, start - 1) .. content:sub(line_end + 1)
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
  local rule = find_rule(parse_rules(content), compact_table(setting.match))
  if rule and rule.rules[key] ~= nil then
    return rule.rules[key]
  end
  local sub = setting.subsettings and setting.subsettings[key]
  return sub and sub.default or nil
end

function M.write(setting, key, value)
  local file = user_file(setting)
  local content = util.read_file(file) or ""
  local rules = parse_rules(content)
  local rule = find_rule(rules, compact_table(setting.match))
  if not rule then
    rule = { match = setting.match, rules = {} }
    rules[#rules + 1] = rule
  end
  rule.rules[key] = value
  return commit(file, content, replace_or_append(content, build_block(rules)))
end

function M.reset(setting, key)
  local file = user_file(setting)
  local content = util.read_file(file) or ""
  local rules = parse_rules(content)
  local rule = find_rule(rules, compact_table(setting.match))
  if not rule then
    return true
  end
  rule.rules[key] = nil
  if next(rule.rules) == nil then
    for i, r in ipairs(rules) do
      if r == rule then
        table.remove(rules, i)
        break
      end
    end
  end
  local new_content
  if #rules == 0 then
    new_content = remove_block(content)
  else
    new_content = replace_or_append(content, build_block(rules))
  end
  return commit(file, content, new_content)
end

-- The omaset settings window's own float/center rule, driven by the
-- `launch_floating` preference (not a settings-model setting). Enabling writes
-- it into the managed block; disabling removes it. The window then floats or
-- tiles based purely on this rule rather than a hand-written one.
local OMASET_MATCH = { class = "^org.quickshell$", title = "^omaset Settings$" }
local OMASET_RULES = { float = true, center = true, tag = "-default-opacity", opacity = "1 1" }

function M.set_omaset_float(enabled)
  local file = user_file({ file = "hyprland" })
  local content = util.read_file(file) or ""
  local rules = parse_rules(content)
  local match_str = compact_table(OMASET_MATCH)
  local idx
  for i, r in ipairs(rules) do
    if compact_table(r.match) == match_str then
      idx = i
      break
    end
  end
  local changed = false
  if enabled then
    if idx then
      if compact_table(rules[idx].rules) ~= compact_table(OMASET_RULES) then
        rules[idx].rules = OMASET_RULES
        changed = true
      end
    else
      rules[#rules + 1] = { match = OMASET_MATCH, rules = OMASET_RULES }
      changed = true
    end
  elseif idx then
    table.remove(rules, idx)
    changed = true
  end
  if not changed then
    return true
  end
  local new_content
  if #rules == 0 then
    new_content = remove_block(content)
  else
    new_content = replace_or_append(content, build_block(rules))
  end
  return commit(file, content, new_content)
end

registry.register("hypr-window", M)

return M
