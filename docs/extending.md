# Extending omaset with Lua

Settings are data, not code in the engine. Adding one is dropping a Lua file;
the engine, the CLI, the window, and the MCP server all pick it up with no
further change.

## Adding a setting

A setting file is just this:

```lua
panel("appearance", "Appearance", function()
  setting({
    id = "gaps_in",
    type = "int",
    label = "Gaps in",
    backend = "hypr-lua",
    file = "looknfeel",
    path = "general.gaps_in",
    min = 0, max = 30,
  })
end)
```

Related settings can be grouped under a presentational header with `section` (it
only affects ordering/labels in the UI — storage and defaults are unchanged):

```lua
section("Groupbar", function()
  setting({ id = "groupbar_height", type = "int", label = "Groupbar height",
    backend = "hypr-lua", file = "looknfeel", path = "group.groupbar.height",
    min = 0, max = 100 })
  -- ...
end)
```

Within a panel, settings are sorted alphabetically by id, with each section's
settings kept contiguous (sections ordered by their first member).

## Where to put it

Drop a file in `~/.config/omaset/settings/`. `discovery.lua` loads the built-in
panels from `share/settings/` first and then your directory, so a user file can
add to the built-in set **or redefine a built-in id to override it** — no fork
required.

## Types and validation

`types.lua` coerces and checks every value before it is written, so a setting
declares its shape and trusts the engine to enforce it:

| `type` | Declares | UI control |
|---|---|---|
| `bool` | — | toggle |
| `int` / `float` | `min`, `max` (and `step` for floats) | slider |
| `enum` | `options = { "a", "b", "c" }` | segmented control |
| `group` | `subsettings` with a shared `match` | header + a row each |
| `keyed` | a key field (e.g. workspace number) | header + a row per key |

## Writing a backend

If your setting does not fit an existing [backend](backends.md), a backend is a
Lua module under `lib/omaset/backends/` that self-registers and implements the
read/write/validate interface for one config format. Everything the engine needs
is passed in — the engine never reaches into your file format itself.

A backend only has to answer two questions: *what is the value now*, and *write
this value without disturbing anything else*. The safeties are shared, not
per-backend: write inside a marked block, snapshot once, validate, revert on
failure. See [safety.md](safety.md) for what the engine guarantees around your
writes, and any of the existing backends in `lib/omaset/backends/` for a
template — `hypr_lua.lua` is the most complete.
