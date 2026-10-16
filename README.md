# omaset

An Omarchy settings engine: a backend-pluggable model of every setting plus
a JSON protocol that any frontend can drive.

It ships a command-line interface and a keyboard-first settings window (an
Omarchy shell plugin). Run `omaset ui` to open it — or drive every setting
headlessly through the JSON protocol.

Extensible: every setting and panel is declared in a small Lua DSL, so adding
or overriding a setting means dropping in a `.lua` file.

**Status:** engine + CLI + keyboard-first UI (`omaset ui`).

## Usage

```
bin/omaset list [--json]              # panels + settings with current values
bin/omaset schema                     # full schema as JSON (what a UI renders)
bin/omaset get <id> [--plain]         # read one setting
bin/omaset set <id> <val> [--plain]   # write a value; validates + applies
bin/omaset reset <id> [--plain]       # restore a setting to its default
bin/omaset changed [--json]           # settings that differ from defaults
bin/omaset search <query> [--json]    # find settings by id or label
bin/omaset help <id>                  # one setting's type/options/default/current
bin/omaset keys <id>                  # list keys of a keyed setting (workspaces)
bin/omaset ui [open|close|toggle]     # open the keyboard settings window (toggle)
bin/omaset --version
```

Keyed settings take a subject argument, e.g.
`omaset get workspace_layout 2` / `omaset set workspace_layout 3 scrolling`.

To see what values a setting accepts, use `omaset help <id>` (lists `options`
for enums, `min..max` for numbers) or `omaset set <id> --help`, which shows the
`<a|b|c>` form. An invalid enum value lists the valid options in the error.

No installation needed — it runs in place with `luajit` (and `jq` for the
`shell-json` backend).

## Settings window

`omaset ui` opens a keyboard-first settings window (an Omarchy Quickshell
plugin). It renders `omaset schema` and drives `get`/`set`/`reset`, so it
always reflects the same settings the CLI does. See
[ui/README.md](ui/README.md) for install and keybindings.

## Protocol

The JSON output of `schema`/`get`/`set`/`reset`/`changed`/`search` is the
machine-readable contract — see [docs/protocol.md](docs/protocol.md).

## Reset & changed semantics

`reset` reverts **omaset's override** — it removes what omaset wrote and lets
the Omarchy stock default re-emerge. It does not store snapshots: `read_default`
recomputes the default from Omarchy's shipped config on every call.

- `changed` diffs the *effective* value (as read from your config) against that
  stock default, so it sees changes made by hand-editing, `omarchy` commands, or
  hotkeys too.
- `hypr-lua` writes into a managed `-- omaset:begin/end` block, so `reset` only
  removes omaset's block. A hand-written `hl.config(...)` override elsewhere in
  the file is left alone (and would take effect again). To restore *everything*
  to stock, use `omarchy refresh hyprland`.
- `workspace-layout` shares storage with `omarchy hyprland workspace layout
  toggle` (Super+L) — the same `~/.local/state/omarchy/workspace-layouts/*.lua`
  files — so the two are coherent. `reset workspace_layout <n>` deletes one
  rule; `reset workspace_layout --all` clears every persisted rule, including
  workspaces that are not currently open.

## Tests

```
tests/run.sh
```

Black-box tests that drive `bin/omaset` against fixture configs (via
`OMARCHY_PATH`, `OMASET_HYPR_DIR`, `OMASET_SHELL_CONFIG`, `OMASET_NO_APPLY`),
so they never touch the real system. They assert on the public CLI only — safe
to run while refactoring internals.

## How it works

```
bin/omaset              CLI entry (sets up package.path); `omaset ui` opens the window
bin/omaset-ui-reload    reload the plugin + reopen (development)
lib/omaset/
  init.lua              registry + schema + command dispatch
  dsl.lua               panel()/setting() declarative DSL
  discovery.lua         loads share/settings/*.lua (and ~/.config/omaset/settings/)
  types.lua             int/float/bool/enum coercion + range checks
  json.lua              minimal JSON encoder
  util.lua              deep merge/get/set, serializer, shell helpers
  backends/             pluggable backends (self-register via load_dir)
    hypr_lua.lua         reads/writes Hyprland Lua config (looknfeel.lua etc.)
    hypr_window.lua      reads/writes o.window() rules (window indicators)
    shell_json.lua       reads/writes ~/.config/omarchy/shell.json via jq
    omarchy.lua          delegates to an existing omarchy command
    workspace_layout.lua per-workspace layout (keyed by workspace number)
share/settings/         built-in panels (appearance, layout, animations, power, display, windows)
ui/                     the keyboard-first settings window (Quickshell plugin)
```

### The `hypr-lua` backend

- **Read** evaluates the default config (`$OMARCHY_PATH/default/hypr/`) then
  the user config (`~/.config/hypr/`), capturing every `hl.config()` call into
  one merged table — the same order-of-precedence Hyprland itself uses.
- **Write** maintains a single `-- omaset:begin` / `-- omaset:end` block at the
  end of the user file. Only keys changed through omaset live there; the rest
  of your file is never touched. A `.omaset.bak` snapshot is kept on first edit.
- **Validate** after every write with `hyprctl reload` + `hyprctl configerrors`;
  on errors the previous content is restored. Set `OMASET_NO_APPLY=1` to skip
  this (tests, headless).

### The `hypr-window` backend

- Manages `o.window(match, rules)` window rules (Omarchy's own helper) in a
  `-- omaset:begin` / `-- omaset:end` block inside `~/.config/hypr/hyprland.lua`,
  with the same write/validate/revert behaviour as `hypr-lua`.
- Each setting is a **group**: it declares a `match` and named `subsettings`
  (e.g. `border_size`, `rounding`). Sub-settings sharing a `match` compose into
  a single rule. `reset <id> <sub>` drops one field; `reset <id> --all` removes
  the whole rule, so the base `border_size`/`rounding` apply again.
- Defaults are declared in the DSL (there is no Omarchy stock window rule to
  read), so `changed` compares against those declared defaults.

### The `shell-json` backend

- Edits `~/.config/omarchy/shell.json` with `jq`, using the same
  normalize-and-commit approach as Omarchy's own `omarchy-shell-config`, so the
  file keeps its `version`/`bar`/`plugins` shape.
- **Read** merges defaults (`$OMARCHY_PATH/config/omarchy/shell.json`) with the
  user file; **write** is atomic (temp + `mv`) and hot-reloads the running
  shell. Requires `jq` (present on Omarchy).

### Extending with Lua

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

Drop it in `~/.config/omaset/settings/` to add a setting, or redefine a
built-in id to override it.

## Next steps

- `hyprsunset` backend (night light schedule profiles).
- A backup picker / restore view.
- Live previews (compositor/tiling/fullscreen) in the settings window.
- Per-setting descriptions in the schema, surfaced under each row.
