-- Capability detection: what can the installed Omarchy actually do?
--
-- omaset never asks "what version am I on" — there is no reliable version
-- query (`omarchy --version` is an unknown command and
-- /usr/share/omarchy/version does not track releases). Instead it probes for
-- the files/binaries a feature needs. A probe is side-effect free and the
-- answer is cached, so it runs once per process.
--
-- `OMASET_WORKSPACE_MODES` (`1`/`0`) overrides the probe so tests can force
-- either branch regardless of the host.

local util = require("omaset.util")

local M = {}

local function omarchy_path()
  return os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
end

-- Whether the installed Omarchy uses the 4.5-style floating workspace modes
-- (default/hypr/workspace-modes.lua + omarchy-hyprland-workspace-layout-*).
-- This is the single capability gate: settings files only register the
-- layouts, bar model, and additive 4.5 options the host supports, and the
-- workspace-layout backend uses it to pick its mechanics.
function M.workspace_modes()
  if M._workspace_modes == nil then
    local o = os.getenv("OMASET_WORKSPACE_MODES")
    if o == "1" or o == "true" or o == "yes" or o == "on" then
      M._workspace_modes = true
    elseif o == "0" or o == "false" or o == "no" or o == "off" then
      M._workspace_modes = false
    else
      -- Probe the installed Omarchy tree only (not PATH), so the answer
      -- follows OMARCHY_PATH and stays hermetic under test fixtures.
      M._workspace_modes =
        util.file_exists(omarchy_path() .. "/default/hypr/workspace-modes.lua")
    end
  end
  return M._workspace_modes
end

-- Reset cached probes (tests only).
function M._reset()
  M._workspace_modes = nil
end

return M
