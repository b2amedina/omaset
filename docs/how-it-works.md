# How Omaset works

Your config files are the source of truth. Omaset is a small core plus a set of
pluggable **backends**. The core owns one idea — a settings *schema* — and each
backend knows how to read and write one kind of file. Everything a person or an
agent touches — the MCP server, the settings window, the CLI — is a face on top
of that same core, so they never disagree.

The layering is the whole design:

```
bin/omaset              CLI entry (sets up package.path); `omaset ui` opens the window
lib/omaset/
  init.lua              core: registry, schema, loading, read/write/reset
  service.lua           the shared service (get/set/reset/changed/...); CLI,
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
  i18n.lua              language resolution, catalog lookup, plurals, number formatting
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
i18n/                     the shared <language>.json catalogs (see docs/i18n.md)
scripts/i18n-extract     regenerates i18n/en.json from the schema
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

## One core, three ways in

Everything the core knows is reachable as JSON:

```
omaset schema       every panel, setting, current value
omaset get <id>     one setting, value + default
omaset set <id> v   validated, applied, journaled
omaset reset <id>   back to the Omarchy default
omaset changed      settings differing from stock
omaset search <q>   find by id, label, description, title, or option
```

`service.lua` implements those operations once. Your agent calls it through the
[MCP server](agents.md); the [settings window](../ui/README.md) calls it through
`omaset rpc`; the CLI calls it in-process. Add a setting, and all three pick it
up at once — nothing to keep in sync.

The schema always carries English labels (the stable machine contract).
Localization happens at render time: the CLI and the window resolve
`panel.*`/`setting.*` keys through the shared catalogs in `i18n/` (see
[i18n.md](i18n.md)), while JSON, `--plain`, and MCP payloads stay English.

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
