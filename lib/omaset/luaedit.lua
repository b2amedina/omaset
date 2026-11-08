-- Minimal, comment-preserving editor for Hyprland Lua config files.
--
-- The "managed block" approach was dropped: Omarchy's user files are hand-edited
-- templates where a setting's value sits next to the comment explaining it, so
-- omaset now edits the value where it already lives instead of dumping a block
-- of flattened hl.config() at EOF.
--
-- Guarantees:
--   * read stays effective: the caller evaluates default + user file in order,
--     so later hl.config() calls win (unchanged here).
--   * write edits the winning (last uncommented) hl.config() occurrence of the
--     path in place — comments, indentation, and surrounding keys are untouched.
--   * if no uncommented occurrence exists, a minimal `hl.config({ path = value })`
--     is appended at EOF (the "add it if it doesn't exist" case).
--   * reset writes the default value in place using the same methodology, and is
--     a no-op when there is no uncommented occurrence (a commented example is
--     left alone rather than polluting the file with a default).
--
-- Only scalar leaf values are ever spliced; a path whose value is a table is
-- skipped (none of the built-in settings use table values).

local util = require("omaset.util")

local M = {}

-- Strip the surrounding quotes from a Lua string literal and unescape the few
-- escapes that matter for matching keys. Only used to recover string keys so a
-- dotted path can be compared; values are never re-encoded this way.
local function unquote(s)
  if #s < 2 then return s end
  local q = s:sub(1, 1)
  if not (q == '"' or q == "'") then return s end
  return s:sub(2, -2):gsub("\\.", function(esc)
    local c = esc:sub(2, 2)
    if c == "n" then return "\n"
    elseif c == "t" then return "\t"
    elseif c == "r" then return "\r"
    else return c end
  end)
end

-- Lex Lua source into code tokens, skipping whitespace and comments. Each token
-- carries its byte span [s, e] (1-based, inclusive) so values can be spliced
-- without disturbing anything else on the line.
local function lex(src)
  local toks = {}
  local n = #src
  local i = 1
  while i <= n do
    local c = src:sub(i, i)
    if c == " " or c == "\t" or c == "\r" or c == "\n"
        or c == "\f" or c == "\v" then
      i = i + 1
    elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
      if src:sub(i + 2, i + 3) == "[[" then
        local close = src:find("]]", i + 4, true)
        i = close and (close + 2) or (n + 1)
      else
        local nl = src:find("\n", i, true)
        i = nl or (n + 1)
      end
    elseif c:match("[%a_]") then
      local s = i
      i = i + 1
      while i <= n and src:sub(i, i):match("[%w_]") do i = i + 1 end
      toks[#toks + 1] = { t = "id", text = src:sub(s, i - 1), s = s, e = i - 1 }
    elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
      local s = i
      i = i + 1
      while i <= n and src:sub(i, i):match("[%w_%.]") do i = i + 1 end
      toks[#toks + 1] = { t = "num", text = src:sub(s, i - 1), s = s, e = i - 1 }
    elseif c == '"' or c == "'" then
      local q = c
      local s = i
      i = i + 1
      while i <= n do
        local d = src:sub(i, i)
        if d == "\\" then
          i = i + 2
        elseif d == q then
          i = i + 1
          break
        else
          i = i + 1
        end
      end
      toks[#toks + 1] = { t = "str", text = src:sub(s, i - 1), s = s, e = i - 1 }
    else
      local s = i
      i = i + 1
      toks[#toks + 1] = { t = "sym", text = src:sub(s, i - 1), s = s, e = i - 1 }
    end
  end
  return toks
end

-- Parse a table constructor beginning at token index i (toks[i].text == "{").
-- Appends leaf records { path = "a.b.c", s = <value start>, e = <value end> }
-- to `leaves` and returns the index just past the matching "}" plus that "}"'s
-- byte offset (so callers can add fields before it).
local function parse_table(toks, i, prefix, leaves)
  local j = i + 1
  while j <= #toks do
    local tk = toks[j]
    if tk.text == "}" then
      return j + 1, tk.s
    end

    -- Read the key (identifier or quoted string). Bracket keys are skipped.
    local key
    if tk.t == "id" then
      key = tk.text
      j = j + 1
    elseif tk.t == "str" then
      key = unquote(tk.text)
      j = j + 1
    elseif tk.text == "[" then
      j = j + 1
      local depth = 0
      while j <= #toks do
        if toks[j].text == "[" then depth = depth + 1
        elseif toks[j].text == "]" then
          if depth == 0 then break end
          depth = depth - 1
        end
        j = j + 1
      end
      j = j + 1
    end

    -- "=" introduces the value; a bare "{" is a table value without "=".
    if toks[j] and toks[j].text == "=" then
      j = j + 1
      local vt = toks[j]
      if vt and vt.text == "{" then
        j = parse_table(toks, j, key and (prefix .. key .. ".") or prefix, leaves)
      elseif vt and key then
        local e = vt.e
        if vt.text == "-" and toks[j + 1] and toks[j + 1].t == "num" then
          e = toks[j + 1].e
        end
        leaves[#leaves + 1] = { path = prefix .. key, s = vt.s, e = e }
        j = j + 1
      elseif vt then
        j = j + 1
      end
    elseif toks[j] and toks[j].text == "{" and key then
      j = parse_table(toks, j, prefix .. key .. ".", leaves)
    else
      -- Bare array element: no key to map to a dotted path.
      if toks[j] and toks[j].text == "{" then
        j = parse_table(toks, j, prefix, leaves)
      else
        j = j + 1
      end
    end

    -- Consume separators.
    if toks[j] and (toks[j].text == "," or toks[j].text == ";") then
      j = j + 1
    end
  end
  return j, nil
end

-- Find every hl.config(<table>) call in the token stream and collect, in source
-- order, the byte span of each occurrence of the dotted `path`.
local function sites(src, path)
  local toks = lex(src)
  local out = {}
  local i = 1
  while i <= #toks do
    if toks[i].t == "id" and toks[i].text == "hl"
        and toks[i + 1] and toks[i + 1].text == "."
        and toks[i + 2] and toks[i + 2].t == "id" and toks[i + 2].text == "config" then
      local j = i + 3
      if toks[j] and toks[j].text == "(" then j = j + 1 end
      if toks[j] and toks[j].text == "{" then
        local leaves = {}
        parse_table(toks, j, "", leaves)
        for _, leaf in ipairs(leaves) do
          if leaf.path == path then
            out[#out + 1] = { s = leaf.s, e = leaf.e }
          end
        end
      end
    end
    i = i + 1
  end
  return out
end

-- The last (winning) occurrence of `path`, or nil.
local function winning_site(src, path)
  local all = sites(src, path)
  if #all == 0 then return nil end
  return all[#all]
end

-- Replace bytes [s, e] (1-based, inclusive) with `text`.
local function splice(src, s, e, text)
  return src:sub(1, s - 1) .. text .. src:sub(e + 1)
end

-- Append a minimal hl.config({ path = value }) override at EOF.
local function append_override(src, path, value)
  local nested = {}
  util.deep_set(nested, path, value)
  local stmt = "hl.config(" .. util.serialize(nested, 0) .. ")\n"
  if src == "" then
    return stmt
  end
  if src:sub(-1) ~= "\n" then
    return src .. "\n\n" .. stmt
  end
  return src .. "\n" .. stmt
end

-- Set `path` to `value`: edit the winning occurrence in place, else append.
-- Returns the new source and whether it changed.
function M.set_value(src, path, value)
  local site = winning_site(src, path)
  if site then
    local literal = util.serialize(value, 0)
    local replaced = splice(src, site.s, site.e, literal)
    if replaced == src then return src, false end
    return replaced, true
  end
  return append_override(src, path, value), true
end

-- Reset `path` to its default: edit the winning occurrence in place; no-op (and
-- unchanged) when there is no uncommented occurrence to edit.
function M.reset_value(src, path, value)
  local site = winning_site(src, path)
  if not site then
    return src, false
  end
  local literal = util.serialize(value, 0)
  local replaced = splice(src, site.s, site.e, literal)
  if replaced == src then return src, false end
  return replaced, true
end

-- Lower-level primitives for backends that edit a different call shape
-- (hypr-window's o.window(match, rules)):
--   M.lex(src)                     -> code tokens with byte spans
--   M.parse_table(toks, i, prefix) -> appends leaves to `leaves`, returns
--                                     (next index, closing-brace offset)
--   M.splice(src, s, e, text)      -> replace bytes [s,e] with text
M.lex = lex
M.parse_table = parse_table
M.splice = splice

return M
