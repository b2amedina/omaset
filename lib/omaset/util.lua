-- Shared helpers for omaset.

local M = {}

-- Default resource bounds for subprocess execution (overridable via env for
-- tests and for hosts that need longer-running tools). A command that exceeds
-- its timeout is terminated together with its process group; captured output is
-- capped so a runaway producer cannot fill memory or disk.
M.DEFAULT_CMD_TIMEOUT = 15
M.DEFAULT_MAX_BYTES = 131072 -- 128 KiB

-- Exit codes GNU timeout(1) reports: 124 when the deadline fired, 137 when it
-- had to escalate to SIGKILL. Either means the command did not finish in time.
local EXIT_TIMEOUT = 124
local EXIT_KILLED = 137

-- An active per-request deadline. The RPC server opens one around each request
-- and run_capture spends from it, so one hung dependency cannot stall the whole
-- request past its budget. Lua here is single-threaded and the RPC server
-- serializes requests, so a single module-level scope is enough.
local request_scope = nil

function M.begin_request(seconds)
  local s = { deadline = os.time() + seconds, timed_out = false, truncated = false }
  request_scope = s
  return s
end

function M.end_request(s)
  if request_scope == s then
    request_scope = nil
  end
end

function M.file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

function M.read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

-- Existing permissions of a path as an octal string ("600"), or nil when it
-- does not exist. Uses stat(1) because the Lua 5.1 interpreter Omarchy ships
-- has no lfs binding.
function M.file_mode(path)
  if not M.file_exists(path) then
    return nil
  end
  local out, code = M.run_capture("stat -c %a " .. M.shell_quote(path))
  if code ~= 0 then
    return nil
  end
  return tostring(out or ""):match("^%s*(%d%d%d%d?)%s*$")
end

function M.write_file(path, content)
  -- Atomic: write to a temp file in the same directory, then rename over the
  -- target so a crash mid-write can't leave a torn file.
  --
  -- The temp file comes from mktemp, which creates it exclusively, under an
  -- unpredictable name, and already mode 0600 — so no partially written
  -- content is ever readable by anyone else, and no predictable shared path is
  -- left for another process to substitute. An existing target's mode is then
  -- carried over to the replacement, so rewriting a private file (an agent
  -- config at 0600, say) can never widen it. Files that did not exist keep
  -- mktemp's 0600.
  local dir = path:match("^(.*)/[^/]+$") or "."
  if dir == "" then
    dir = "/"
  end
  local tmp = M.mktemp(dir .. "/.omaset.XXXXXX")
  if not tmp then
    return nil, "cannot create a temporary file next to " .. path
  end

  local mode = M.file_mode(path)
  local f, err = io.open(tmp, "wb")
  if not f then
    os.remove(tmp)
    return nil, "cannot open " .. path .. " for writing: " .. tostring(err)
  end
  local wrote, werr = f:write(content)
  local closed, cerr = f:close()
  if not wrote or not closed then
    os.remove(tmp)
    return nil, "cannot write " .. path .. ": " .. tostring(werr or cerr or "short write")
  end

  if mode and os.execute("chmod " .. mode .. " " .. M.shell_quote(tmp)) ~= 0 then
    os.remove(tmp)
    return nil, "cannot preserve permissions on " .. path
  end

  local ok, rerr = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return nil, "cannot write " .. path .. ": " .. tostring(rerr)
  end
  return true
end

function M.shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Compile a Lua source string into a chunk running in the given environment.
-- Uses loadstring + setfenv so it works on the vanilla Lua 5.1 interpreter
-- Omarchy ships (the 5.2+ load(str, name, "t", env) form is unavailable there)
-- as well as LuaJIT. Bytecode chunks are rejected to keep the "text only"
-- hardening that load's "t" mode provided.
function M.load_chunk(str, chunkname, env)
  if type(str) ~= "string" then
    return nil, "expected source string"
  end
  if str:sub(1, 4) == "\27Lua" then
    return nil, "bytecode not allowed: " .. (chunkname or "chunk")
  end
  local f, err = loadstring(str, chunkname)
  if not f then
    return nil, err
  end
  setfenv(f, env)
  return f
end

-- Create a private temporary file from a template with mktemp (exclusive,
-- unpredictable name, 0600 before any bytes are written). Returns its path, or
-- nil on failure.
function M.mktemp(template)
  local p = io.popen("mktemp " .. M.shell_quote(template))
  local name = p and p:read("*l")
  if p then
    p:close()
  end
  name = name and name:match("^%s*(.-)%s*$")
  if name == "" or name == nil then
    return nil
  end
  return name
end

-- Run a command, capturing combined stdout+stderr and the exit code.
--
-- Output is redirected through a private temp file rather than read straight
-- off the popen pipe: a command that daemonizes (e.g. `omarchy toggle
-- nightlight` cold-starting hyprsunset) leaves a background child holding the
-- pipe's write end open, which would make read("*a") block forever. Redirecting
-- to a file means only the foreground shell holds the pipe, so it EOFs as soon
-- as the command finishes and the daemon's stray output goes to the file
-- instead. The file comes from mktemp, so it is already 0600 and never briefly
-- world-readable the way os.tmpname()'s 0644 file would be.
--
-- That leaves the pipe free to carry the exit status, which it has to: Lua
-- 5.1's pclose() returns true for *any* status (the ok/reason/code form only
-- exists from 5.2 on), so reading it off close() would report every command as
-- having succeeded.
--
-- The command runs under GNU timeout, which signals its whole process group
-- when the deadline fires, and under `ulimit -f`, which caps how much it may
-- write before the kernel kills it (the +1 block of headroom is what lets
-- truncation be detected by length). The read is capped to the same limit.
--
-- Returns (out, code[, err[, meta]]) where meta.timeout and meta.truncated flag
-- the two ways a run can be cut short. opts may set `timeout` and `max_bytes`;
-- both fall back to env (OMASET_CMD_TIMEOUT / OMASET_CMD_MAX_BYTES) and then to
-- the defaults above.
function M.run_capture(cmd, opts)
  opts = opts or {}
  local max_bytes = opts.max_bytes
    or tonumber(os.getenv("OMASET_CMD_MAX_BYTES")) or M.DEFAULT_MAX_BYTES
  local timeout = opts.timeout
    or tonumber(os.getenv("OMASET_CMD_TIMEOUT")) or M.DEFAULT_CMD_TIMEOUT

  -- Spend from the active request budget first; once it is exhausted there is
  -- no point in starting another subprocess.
  if request_scope then
    local remaining = request_scope.deadline - os.time()
    if remaining <= 0 then
      request_scope.timed_out = true
      return "", EXIT_TIMEOUT, nil, { timeout = true }
    end
    if remaining < timeout then
      timeout = remaining
    end
  end
  if timeout < 1 then
    timeout = 1
  end

  local tmp = M.mktemp((os.getenv("TMPDIR") or "/tmp") .. "/omaset.XXXXXX")
  if not tmp then
    return nil, nil, "cannot create a capture file", {}
  end

  local blocks = math.ceil(max_bytes / 1024) + 1
  local wrapper = "( ulimit -f " .. blocks
    .. " 2>/dev/null; timeout -k 3 " .. math.floor(timeout)
    .. " sh -c " .. M.shell_quote(cmd) .. " ) > " .. M.shell_quote(tmp)
    .. " 2>&1; echo $?"
  local p = io.popen(wrapper)
  if not p then
    os.remove(tmp)
    return nil, nil, "cannot run: " .. cmd
  end
  local status = p:read("*a") or ""
  p:close()
  -- The trailing number is the exit status; anything before it would be stray
  -- output that escaped the file redirect.
  local code = tonumber(status:match("(%d+)%s*$")) or 1

  local out = ""
  local f = io.open(tmp, "rb")
  if f then
    out = f:read(max_bytes + 1) or ""
    f:close()
  end
  os.remove(tmp)

  local meta = {}
  if code == EXIT_TIMEOUT or code == EXIT_KILLED then
    meta.timeout = true
    if request_scope then
      request_scope.timed_out = true
    end
  end
  if #out > max_bytes then
    meta.truncated = true
    if request_scope then
      request_scope.truncated = true
    end
    out = out:sub(1, max_bytes)
  end
  return out, code, nil, meta
end

-- List files in a directory matching a find-style -name pattern (e.g. "*.lua"),
-- sorted by path. Returns {} on error.
function M.list_files(dir, pattern)
  local cmd = "find " .. M.shell_quote(dir) .. " -maxdepth 1 -name "
    .. M.shell_quote(pattern) .. " -type f 2>/dev/null | sort"
  local p = io.popen(cmd)
  if not p then
    return {}
  end
  local files = {}
  for line in p:lines() do
    files[#files + 1] = line
  end
  p:close()
  return files
end

-- List *.lua files in a directory, sorted by path. Returns {} on error.
function M.list_lua_files(dir)
  return M.list_files(dir, "*.lua")
end

local cmd_exists_cache = {}

function M.cmd_exists(name)
  if cmd_exists_cache[name] ~= nil then
    return cmd_exists_cache[name]
  end
  local out = M.run_capture("command -v " .. name .. " 2>/dev/null")
  local found = out ~= nil and out:gsub("%s+", "") ~= ""
  cmd_exists_cache[name] = found
  return found
end

-- Deep-merge src into dst (tables recurse, everything else overwrites).
function M.deep_merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      M.deep_merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

-- Get a value by dotted key ("general.gaps_in").
function M.deep_get(t, dotted)
  local cur = t
  for part in string.gmatch(dotted, "[^.]+") do
    if type(cur) ~= "table" then
      return nil
    end
    cur = cur[part]
  end
  return cur
end

-- Remove a value by dotted key, pruning empty intermediate tables.
function M.deep_unset(t, dotted)
  local parts = {}
  for part in string.gmatch(dotted, "[^.]+") do
    parts[#parts + 1] = part
  end
  local stack = {}
  local cur = t
  for i = 1, #parts - 1 do
    if type(cur[parts[i]]) ~= "table" then
      return t
    end
    stack[#stack + 1] = { table = cur, key = parts[i] }
    cur = cur[parts[i]]
  end
  if type(cur) == "table" then
    cur[parts[#parts]] = nil
  end
  for i = #stack, 1, -1 do
    local entry = stack[i]
    local child = entry.table[entry.key]
    if child == nil or next(child) == nil then
      entry.table[entry.key] = nil
    else
      break
    end
  end
  return t
end

-- Set a value by dotted key, creating intermediate tables as needed.
function M.deep_set(t, dotted, value)
  local parts = {}
  for part in string.gmatch(dotted, "[^.]+") do
    parts[#parts + 1] = part
  end
  local cur = t
  for i = 1, #parts - 1 do
    local key = parts[i]
    if type(cur[key]) ~= "table" then
      cur[key] = {}
    end
    cur = cur[key]
  end
  cur[parts[#parts]] = value
  return t
end

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      return false
    end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then
      return false
    end
  end
  return n > 0
end

-- Encode a codepoint as UTF-8 (used by the search fold to emit the few
-- non-Latin-1 base letters; the rest fold to single ASCII bytes).
local function utf8_char(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
  else
    return string.char(0xE0 + math.floor(cp / 0x1000),
      0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
  end
end

-- Search text folding: lowercase and strip diacritics so a query matches a
-- label regardless of case or accents ("écart" finds "Écart", "abstände" finds
-- "Abstände"). `FOLD_CP` maps a codepoint to its folded single codepoint
-- (Latin-1 Supplement + Latin Extended-A accented letters to their base ASCII
-- letter, Greek tonos forms to the plain lowercase letter); `FOLD_STR` covers
-- the few ligatures that fold to more than one character. Cyrillic and Greek
-- uppercase are folded arithmetically in fold_codepoint. Scripts without case
-- (CJK, Arabic, Hebrew, Indic, Thai, …) pass through unchanged, which is
-- already correct for them.
local FOLD_CP = {
  -- Latin-1 Supplement.
  [0x00C0] = 0x61, [0x00C1] = 0x61, [0x00C2] = 0x61, [0x00C3] = 0x61,
  [0x00C4] = 0x61, [0x00C5] = 0x61, [0x00C7] = 0x63, [0x00C8] = 0x65,
  [0x00C9] = 0x65, [0x00CA] = 0x65, [0x00CB] = 0x65, [0x00CC] = 0x69,
  [0x00CD] = 0x69, [0x00CE] = 0x69, [0x00CF] = 0x69, [0x00D0] = 0x64,
  [0x00D1] = 0x6E, [0x00D2] = 0x6F, [0x00D3] = 0x6F, [0x00D4] = 0x6F,
  [0x00D5] = 0x6F, [0x00D6] = 0x6F, [0x00D8] = 0x6F, [0x00D9] = 0x75,
  [0x00DA] = 0x75, [0x00DB] = 0x75, [0x00DC] = 0x75, [0x00DD] = 0x79,
  [0x00E0] = 0x61, [0x00E1] = 0x61, [0x00E2] = 0x61, [0x00E3] = 0x61,
  [0x00E4] = 0x61, [0x00E5] = 0x61, [0x00E7] = 0x63, [0x00E8] = 0x65,
  [0x00E9] = 0x65, [0x00EA] = 0x65, [0x00EB] = 0x65, [0x00EC] = 0x69,
  [0x00ED] = 0x69, [0x00EE] = 0x69, [0x00EF] = 0x69, [0x00F0] = 0x64,
  [0x00F1] = 0x6E, [0x00F2] = 0x6F, [0x00F3] = 0x6F, [0x00F4] = 0x6F,
  [0x00F5] = 0x6F, [0x00F6] = 0x6F, [0x00F8] = 0x6F, [0x00F9] = 0x75,
  [0x00FA] = 0x75, [0x00FB] = 0x75, [0x00FC] = 0x75, [0x00FD] = 0x79,
  [0x00FF] = 0x79,
  -- Latin Extended-A.
  [0x0100] = 0x61, [0x0101] = 0x61, [0x0102] = 0x61, [0x0103] = 0x61,
  [0x0104] = 0x61, [0x0105] = 0x61, [0x0106] = 0x63, [0x0107] = 0x63,
  [0x0108] = 0x63, [0x0109] = 0x63, [0x010A] = 0x63, [0x010B] = 0x63,
  [0x010C] = 0x63, [0x010D] = 0x63, [0x010E] = 0x64, [0x010F] = 0x64,
  [0x0110] = 0x64, [0x0111] = 0x64, [0x0112] = 0x65, [0x0113] = 0x65,
  [0x0114] = 0x65, [0x0115] = 0x65, [0x0116] = 0x65, [0x0117] = 0x65,
  [0x0118] = 0x65, [0x0119] = 0x65, [0x011A] = 0x65, [0x011B] = 0x65,
  [0x011C] = 0x67, [0x011D] = 0x67, [0x011E] = 0x67, [0x011F] = 0x67,
  [0x0120] = 0x67, [0x0121] = 0x67, [0x0122] = 0x67, [0x0123] = 0x67,
  [0x0124] = 0x68, [0x0125] = 0x68, [0x0126] = 0x68, [0x0127] = 0x68,
  [0x0128] = 0x69, [0x0129] = 0x69, [0x012A] = 0x69, [0x012B] = 0x69,
  [0x012C] = 0x69, [0x012D] = 0x69, [0x012E] = 0x69, [0x012F] = 0x69,
  [0x0130] = 0x69, [0x0131] = 0x69, [0x0134] = 0x6A, [0x0135] = 0x6A,
  [0x0136] = 0x6B, [0x0137] = 0x6B, [0x0138] = 0x6B, [0x0139] = 0x6C,
  [0x013A] = 0x6C, [0x013B] = 0x6C, [0x013C] = 0x6C, [0x013D] = 0x6C,
  [0x013E] = 0x6C, [0x013F] = 0x6C, [0x0140] = 0x6C, [0x0141] = 0x6C,
  [0x0142] = 0x6C, [0x0143] = 0x6E, [0x0144] = 0x6E, [0x0145] = 0x6E,
  [0x0146] = 0x6E, [0x0147] = 0x6E, [0x0148] = 0x6E, [0x0149] = 0x6E,
  [0x014A] = 0x6E, [0x014B] = 0x6E, [0x014C] = 0x6F, [0x014D] = 0x6F,
  [0x014E] = 0x6F, [0x014F] = 0x6F, [0x0150] = 0x6F, [0x0151] = 0x6F,
  [0x0154] = 0x72, [0x0155] = 0x72, [0x0156] = 0x72, [0x0157] = 0x72,
  [0x0158] = 0x72, [0x0159] = 0x72, [0x015A] = 0x73, [0x015B] = 0x73,
  [0x015C] = 0x73, [0x015D] = 0x73, [0x015E] = 0x73, [0x015F] = 0x73,
  [0x0160] = 0x73, [0x0161] = 0x73, [0x0162] = 0x74, [0x0163] = 0x74,
  [0x0164] = 0x74, [0x0165] = 0x74, [0x0166] = 0x74, [0x0167] = 0x74,
  [0x0168] = 0x75, [0x0169] = 0x75, [0x016A] = 0x75, [0x016B] = 0x75,
  [0x016C] = 0x75, [0x016D] = 0x75, [0x016E] = 0x75, [0x016F] = 0x75,
  [0x0170] = 0x75, [0x0171] = 0x75, [0x0172] = 0x75, [0x0173] = 0x75,
  [0x0174] = 0x77, [0x0175] = 0x77, [0x0176] = 0x79, [0x0177] = 0x79,
  [0x0178] = 0x79, [0x0179] = 0x7A, [0x017A] = 0x7A, [0x017B] = 0x7A,
  [0x017C] = 0x7A, [0x017D] = 0x7A, [0x017E] = 0x7A, [0x017F] = 0x73,
  -- Greek tonos/dialytika forms fold to the plain lowercase letter.
  [0x0386] = 0x03B1, [0x0388] = 0x03B5, [0x0389] = 0x03B7, [0x038A] = 0x03B9,
  [0x038C] = 0x03BF, [0x038E] = 0x03C5, [0x038F] = 0x03C9, [0x0390] = 0x03B9,
  [0x03AC] = 0x03B1, [0x03AD] = 0x03B5, [0x03AE] = 0x03B7, [0x03AF] = 0x03B9,
  [0x03B0] = 0x03C5, [0x03CA] = 0x03B9, [0x03CB] = 0x03C5, [0x03CC] = 0x03BF,
  [0x03CD] = 0x03C5, [0x03CE] = 0x03C9,
}

local FOLD_STR = {
  [0x00C6] = "ae", [0x00E6] = "ae", [0x00DE] = "th", [0x00FE] = "th",
  [0x00DF] = "ss", [0x0132] = "ij", [0x0133] = "ij", [0x0152] = "oe",
  [0x0153] = "oe",
}

local function fold_codepoint(cp)
  local multi = FOLD_STR[cp]
  if multi then
    return multi
  end
  local base = FOLD_CP[cp]
  if base then
    return utf8_char(base)
  end
  if cp >= 0x41 and cp <= 0x5A then -- A-Z
    return string.char(cp + 0x20)
  end
  if cp >= 0x0410 and cp <= 0x042F then -- Cyrillic А-Я
    return utf8_char(cp + 0x20)
  end
  if cp >= 0x0400 and cp <= 0x040F then -- Cyrillic Ѐ-Џ (incl. Ё)
    return utf8_char(cp + 0x50)
  end
  if cp >= 0x0391 and cp <= 0x03A1 then -- Greek Α-Ρ
    return utf8_char(cp + 0x20)
  end
  if cp >= 0x03A3 and cp <= 0x03A9 then -- Greek Σ-Ω
    return utf8_char(cp + 0x20)
  end
  if cp == 0x03AA or cp == 0x03AB then -- Greek Ϊ Ϋ
    return utf8_char(cp + 0x20)
  end
  return nil
end

-- Fold a string for search: lowercase + strip diacritics across the scripts
-- the shipped catalogs use. Never errors; malformed bytes pass through.
function M.fold(s)
  if type(s) ~= "string" then
    return ""
  end
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local cp, len
    if b < 0x80 then
      cp, len = b, 1
    elseif b < 0xC0 then
      cp, len = b, 1 -- stray continuation byte: keep as-is
    elseif b < 0xE0 then
      cp = (b - 0xC0) * 0x40 + (s:byte(i + 1) or 0x80) - 0x80
      len = 2
    elseif b < 0xF0 then
      cp = (b - 0xE0) * 0x1000
        + ((s:byte(i + 1) or 0x80) - 0x80) * 0x40
        + (s:byte(i + 2) or 0x80) - 0x80
      len = 3
    else
      cp, len = b, 1 -- astral lead byte and beyond: keep bytes as-is
    end
    local folded = fold_codepoint(cp)
    out[#out + 1] = folded or s:sub(i, i + len - 1)
    i = i + len
  end
  return table.concat(out)
end

-- Serialize a Lua value to source. Only scalars and string-keyed tables are
-- expected in managed config blocks.
function M.serialize(value, indent)
  indent = indent or 0
  local t = type(value)
  if t == "number" or t == "boolean" then
    return tostring(value)
  elseif t == "string" then
    return string.format("%q", value)
  elseif t == "table" then
    local pad = string.rep("  ", indent)
    local pad1 = string.rep("  ", indent + 1)
    local parts = {}
    if is_array(value) then
      for i = 1, #value do
        parts[#parts + 1] = pad1 .. M.serialize(value[i], indent + 1)
      end
    else
      local keys = {}
      for k in pairs(value) do
        keys[#keys + 1] = k
      end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do
        local v = value[k]
        local line
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
          line = pad1 .. k
        else
          line = pad1 .. "[" .. string.format("%q", k) .. "]"
        end
        parts[#parts + 1] = line .. " = " .. M.serialize(v, indent + 1)
      end
    end
    if #parts == 0 then
      return "{}"
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
  end
  return "nil"
end

return M
