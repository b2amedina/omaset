-- Declarative DSL for defining panels and settings.

local M = {}

M.panels = {}

local function panel(id, title, fn)
  local p = { id = id, title = title, settings = {} }
  M.panels[#M.panels + 1] = p
  local prev = M._current
  M._current = p
  if fn then
    fn()
  end
  M._current = prev
  return p
end

local function setting(t)
  local current = M._current
  if not current then
    error("setting() must be called inside a panel() block")
  end
  current.settings[#current.settings + 1] = t
  return t
end

-- Build the sandbox environment for evaluating a settings file.
function M.environment()
  return {
    panel = panel,
    setting = setting,
  }
end

return M
