-- Detect the user's preferred time convention from the Omarchy bar clock.
--
-- Omarchy has no global 12/24-hour switch: each clock widget stores its own
-- format in ~/.config/omarchy/shell.json and cycles it on right-click. The
-- "Follow bar clock" time_format preference resolves through here: if the bar
-- clock's format string uses Qt's AM/PM token ("AP" or "ap"), times are shown
-- 12-hour; otherwise 24-hour.

local util = require("omaset.util")
local json = require("omaset.json")

local M = {}

function M.user_file()
  return os.getenv("OMASET_SHELL_CONFIG")
    or (os.getenv("HOME") or "") .. "/.config/omarchy/shell.json"
end

function M.default_file()
  return (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy")
    .. "/config/omarchy/shell.json"
end

-- The clock entry's effective format string, or nil when none is configured.
local function clock_format(file)
  if not util.file_exists(file) then
    return nil
  end
  local parsed = json.decode(util.read_file(file))
  if type(parsed) ~= "table" then
    return nil
  end
  local bar = parsed.bar
  if type(bar) ~= "table" then
    return nil
  end
  local layout = bar.layout
  if type(layout) ~= "table" then
    return nil
  end
  local position = bar.position
  local vertical = position == "left" or position == "right"

  for _, side in ipairs({ "left", "center", "right" }) do
    local entries = layout[side]
    if type(entries) == "table" then
      for _, entry in ipairs(entries) do
        if type(entry) == "table" and entry.id == "omarchy.clock" then
          if vertical then
            return entry.verticalFormat or entry.format
          end
          return entry.format or entry.verticalFormat
        end
      end
    end
  end
  return nil
end

-- Resolve the bar clock's time convention: "12h" when its format carries the
-- AM/PM token, otherwise "24h".
function M.detect()
  local fmt = clock_format(M.user_file())
  if fmt == nil then
    fmt = clock_format(M.default_file())
  end
  if type(fmt) == "string" and (fmt:find("AP", 1, true) or fmt:find("ap", 1, true)) then
    return "12h"
  end
  return "24h"
end

return M
