-- Change journal: an append-only JSONL audit log of every setting omaset has
-- changed. Powers `omaset history` and `omaset undo`. Each line is one entry:
--
--   { "ts", "op" ("set"|"reset"), "id", "key"|"sub" (optional),
--     "old", "default", "new", "backend" }
--
-- `old` is the effective value *before* the change and `default` the Omarchy
-- default at that time; `new` is the value after (null on reset). Undo restores
-- `old`, using reset when `old == default` (i.e. the setting was previously
-- untouched) so "back to default" keeps following the Omarchy default rather
-- than pinning a concrete value.

local util = require("omaset.util")
local json = require("omaset.json")

local M = {}

function M.path()
  return os.getenv("OMASET_JOURNAL")
    or (os.getenv("HOME") or "") .. "/.local/state/omaset/journal.jsonl"
end

local function parent(path)
  local dir = path:match("^(.*)/")
  return dir and dir ~= "" and dir or nil
end

function M.record(entry)
  local p = M.path()
  local dir = parent(p)
  if dir then
    os.execute("mkdir -p " .. util.shell_quote(dir))
  end
  local f = io.open(p, "ab")
  if not f then
    return nil, "cannot open journal " .. p
  end
  f:write(json.encode(entry), "\n")
  f:close()
  return true
end

-- Read all entries, oldest first. Malformed lines are skipped.
function M.read_all()
  local f = io.open(M.path(), "rb")
  if not f then
    return {}
  end
  local entries = {}
  for line in f:lines() do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      local v = json.decode(line)
      if type(v) == "table" then
        entries[#entries + 1] = v
      end
    end
  end
  f:close()
  return entries
end

function M.latest()
  local entries = M.read_all()
  return entries[#entries]
end

function M.remove_last()
  local entries = M.read_all()
  if #entries == 0 then
    return false
  end
  table.remove(entries)
  M.rewrite(entries)
  return true
end

function M.clear()
  M.rewrite({})
  return true
end

function M.rewrite(entries)
  local p = M.path()
  local parts = {}
  for _, e in ipairs(entries) do
    parts[#parts + 1] = json.encode(e)
  end
  if #parts == 0 then
    return util.write_file(p, "")
  end
  return util.write_file(p, table.concat(parts, "\n") .. "\n")
end

return M
