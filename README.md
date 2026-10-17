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
bin/omaset history [--json] [N]       # recent changes omaset has made
bin/omaset undo [--all] [--plain]     # undo the last change (or all of them)
bin/omaset rollback [--json]          # restore pre-omaset config snapshots
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

## For agents

omaset is built so an AI agent can drive Omarchy's settings through one JSON
interface instead of editing dotfiles by hand. See
[docs/agents.md](docs/agents.md) for the commands, a worked example, and the
safety model.

## Safety, undo & rollback

omaset never parses-and-rewrites your files. It only writes into a marked
`-- omaset:begin/end` block (Lua config) or via Omarchy's own `jq` pipeline
(`shell.json`), keeps a one-time `<file>.omaset.bak` snapshot before its first
write, and re-validates each write (`hyprctl configerrors`) with an automatic
revert on failure.

- `omaset history` lists every change omaset has made, oldest first, from an
  append-only journal at `~/.local/state/omaset/journal.jsonl`.
- `omaset undo` undoes the most recent change; `undo --all` replays the journal
  in reverse. Undo restores the recorded previous value, and falls back to
  `reset` when the setting was previously untouched (so "back to default" keeps
  following the Omarchy default rather than pinning a value).
- `omaset rollback` is the panic button: it restores every `<file>.omaset.bak`
  snapshot, returning each config file to the state it had before omaset first
  wrote to it. It does not depend on the journal.

## Reset & changed semantics

`reset` reverts **omaset's override** — it removes what omaset wrote and lets
the Omarchy stock default re-emerge. It does not store snapshots: `read_default`
recomputes the default from Omarchy's shipped config on every call.

- `changed` diffs the *effective* value (as read from your config) against that
  stock default, so it sees changes made by hand-editing, `omarchy` commands, or
  hotkeys too. In the settings window, press `c` to open a "Changed" list of
  every differing setting (value → default); Enter jumps to it.
- A setting can declare its own `default` when the backend cannot recompute
  one — the `omarchy` passthrough toggles (`nightlight`, `window-no-gaps`,
  `single-window-square`) declare `default = false` so they participate in
  `changed` too.
- `hypr-lua` writes into a managed `-- omaset:begin/end` block, so `reset` only
  removes omaset's block. A hand-written `hl.config(...)` override elsewhere in
  the file is left alone (and would take effect again). To restore *everything*
  to stock, use `omarchy refresh hyprland`.
- `workspace-layout` shares storage with `omarchy hyprland workspace layout
  toggle` (Super+L) — the same `~/.local/state/omarchy/workspace-layouts/*.lua`
  files — so the two are coherent. `reset workspace_layout <n>` deletes one
  rule; `reset workspace_layout --all` clears every persisted rule, including
  workspaces that are not currently open.

## Preferences

omaset also has a few settings about *itself*, kept separate from the Omarchy
settings above. They live in `~/.config/omaset/preferences.json`, are managed
with `omaset preferences`, and are **not** Omarchy settings: they never appear
in the settings panels, `search`, or `changed`.

- `refresh_interval_sec` — how often the settings window re-reads values while
  visible (default 2, range 1..60).
- `launch_floating` — whether the window opens floating (default true). When
  enabled, omaset floats its own window, so you can remove the hand-written
  `o.window(... float = true ...)` rule for the omaset window from
  `~/.config/hypr/hyprland.lua`.

Edit them from the settings window with `p`, or from the CLI:

```
omaset preferences                            # list
omaset preferences get refresh_interval_sec   # read one
omaset preferences set refresh_interval_sec 5 # write one
omaset preferences reset launch_floating      # back to default
```

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
  dsl.lua               panel()/section()/setting() declarative DSL
  discovery.lua         loads share/settings/*.lua (and ~/.config/omaset/settings/)
  types.lua             int/float/bool/enum coercion + range checks
  json.lua              minimal JSON encoder + decoder (journal round-trip)
  journal.lua           append-only change log for history/undo
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

### The `hyprsunset` backend

- Manages a single omaset-owned night profile (`time` + `temperature`) in a
  `# -- omaset:begin` / `# -- omaset:end` block inside
  `~/.config/hypr/hyprsunset.conf`, so the user's own profiles and comments are
  never touched.
- Exposes two settings: `schedule` (whether the night profile is active) and
  `temperature` (its color temperature in Kelvin, default 4000). Writing the
  temperature creates the profile if it does not exist; resetting the schedule
  removes the block entirely.

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

Related settings can be grouped under a presentational header with `section`
(it only affects ordering/labels in the UI — storage and defaults are
unchanged):

```lua
section("Groupbar", function()
  setting({ id = "groupbar_height", type = "int", label = "Groupbar height",
    backend = "hypr-lua", file = "looknfeel", path = "group.groupbar.height",
    min = 0, max = 100 })
  -- ...
end)
```

Within a panel, settings are sorted alphabetically by id, with each section's
settings kept contiguous (sections ordered by their first member). Drop a file
in `~/.config/omaset/settings/` to add a setting, or redefine a built-in id to
override it.

## Next steps

- A backup picker / restore view.
- Live previews (compositor/tiling/fullscreen) in the settings window.
