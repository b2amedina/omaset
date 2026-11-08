# How omaset works

omaset is a small engine plus a set of pluggable **backends**. The engine owns
one idea — a settings *schema* — and everything else is a face on top of it: the
CLI, the settings window, and the MCP server all read and write the same schema
through one shared operation layer.

The layering is the whole design:

```
bin/omaset              CLI entry (sets up package.path); `omaset ui` opens the window
lib/omaset/
  init.lua              core: registry, schema, loading, read/write/reset
  service.lua           one operation layer (get/set/reset/changed/...); CLI,
                        MCP, and RPC all call this
  cli.lua               argv parsing + human/JSON formatting + dispatch
  rpc.lua               JSON-RPC 2.0 over stdio for the settings window
  mcp.lua               MCP wire adapter over service + agent registration
  dsl.lua               panel()/section()/setting() declarative DSL
  features.lua          capability probes (e.g. workspace modes / 4.5+)
  discovery.lua         loads share/settings/*.lua (and ~/.config/omaset/settings/)
  types.lua             int/float/bool/enum/time coercion + range checks
  json.lua              minimal JSON encoder + decoder (journal, preferences)
  journal.lua           append-only change log for history/undo
  preferences.lua       omaset's own UI preferences (separate from settings)
  clock_format.lua      resolves the bar clock's 12h/24h format from shell.json
  util.lua              deep merge/get/set, serializer, shell helpers
  backends/             pluggable backends (self-register via load_dir)
    hypr_lua.lua         reads/writes Hyprland Lua config (looknfeel.lua etc.)
    hypr_window.lua      reads/writes o.window() rules (window indicators)
    shell_json.lua       reads/writes ~/.config/omarchy/shell.json via jq
    omarchy.lua          delegates to an existing omarchy command
    workspace_layout.lua per-workspace layout (keyed by workspace number)
    hyprsunset.lua       night light schedule (hyprsunset.conf)
share/settings/         built-in panels (appearance, layout, input, behavior,
                        bar, power, display, windows)
ui/                     the keyboard-first settings window (Quickshell plugin)
```

## The schema

A setting is declared, never hard-coded. A settings file is a Lua script over a
tiny DSL: `panel()` opens an area, `setting()` declares one knob, and optional
`section()` headers group settings that belong together.

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

`discovery.lua` loads every file in `share/settings/` (plus
`~/.config/omaset/settings/`, so a user file can add to or override the built-in
set), and `dsl.lua` turns the declarations into the registry the engine serves.
`types.lua` owns coercion and validation — an `int` with `min`/`max`, an `enum`
with `options` — so a bad value is rejected before anything is written.

Within a panel, settings are sorted alphabetically by id, with each section's
settings kept contiguous (sections ordered by their first member).

A `schema` reply is versioned (`schemaVersion`), so a frontend can refuse a shape
it does not understand instead of rendering a partial or wrong list. The settings
window checks it against the version it supports and shows an error when the
engine and the window are out of step.

## One operation layer, four faces

Everything the engine knows is reachable as JSON:

```
omaset schema       every panel, setting, current value
omaset get <id>     one setting, value + default
omaset set <id> v   validated, applied, journaled
omaset reset <id>   revert omaset's override
omaset changed      settings differing from stock
omaset search <q>   find by id or label
```

`service.lua` implements those operations once. The CLI calls it in-process and
formats the result; the [settings window](../ui/README.md) calls it through
`omaset rpc`; the [MCP server](agents.md) exposes it as tools. Adding a setting
changes what all of them offer at once; there is nothing to keep in sync.

See [docs/protocol.md](protocol.md) for the shapes each command returns, and
[the UI README](../ui/README.md) for the RPC transport.

## Change tracking

Every write is appended to a journal at
`~/.local/state/omaset/journal.jsonl` — the previous value, the new one, and
enough context to reverse it. `omaset history` lists it, `omaset undo` reverses
the last entry, and `undo --all` replays it backwards. Because the journal
records *effective* values, `changed` also sees changes made by hand-editing or
by Omarchy's own commands and hotkeys.

The safety guarantees around those writes — in-place edits, validation, and the
`rollback` panic button — are in [safety.md](safety.md).

## Backends

Each area is implemented by a backend that knows one config format and nothing
else. Backends self-register, so the engine never learns about a new area until
a settings file names it. See [backends.md](backends.md) for each one, and
[extending.md](extending.md) to write your own.
