-- Declarative DSL for defining panels and settings.

local M = {}

M.panels = {}

local function panel(id, title, icon, fn)
  -- The icon is optional; a third argument that is a function is the body
  -- (older settings files wrote panel(id, title, fn)).
  if type(icon) == "function" then
    fn = icon
    icon = nil
  end
  local p = { id = id, title = title, icon = icon, settings = {} }
  M.panels[#M.panels + 1] = p
  local prev = M._current
  M._current = p
  if fn then
    fn()
  end
  M._current = prev
  return p
end

-- A purely presentational grouping: settings declared inside a section()
-- block are tagged with that label (and an optional stable key for i18n) and
-- rendered under a header. The section does not change how any setting is
-- stored or how its default is computed.
local function section(title, key, fn)
  -- The key is optional; a second argument that is a function is the body
  -- (older settings files wrote section(title, fn)).
  if type(key) == "function" then
    fn = key
    key = nil
  end
  local prev = M._current_section
  local prev_key = M._current_section_key
  M._current_section = title
  M._current_section_key = key
  if fn then
    fn()
  end
  M._current_section = prev
  M._current_section_key = prev_key
end

local function setting(t)
  local current = M._current
  if not current then
    error("setting() must be called inside a panel() block")
  end
  if M._current_section then
    t.section = M._current_section
  end
  if M._current_section_key then
    t.section_key = M._current_section_key
  end
  current.settings[#current.settings + 1] = t
  return t
end

-- Build the sandbox environment for evaluating a settings file.
function M.environment()
  return {
    panel = panel,
    section = section,
    setting = setting,
    feature = require("omaset.features"),
  }
end

return M
