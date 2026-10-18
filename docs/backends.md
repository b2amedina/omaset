# Backends

A backend is the only part of omaset that knows a config format. It exposes a
small read/write/validate interface for one area, and the engine treats them all
identically. They self-register from `lib/omaset/backends/`, so a settings file
can point at any of them — or at a new one — without the core changing.

Every file-writing backend follows the same rules: write only inside a marked
`-- omaset:begin` / `-- omaset:end` block, keep a one-time `<file>.omaset.bak`
snapshot before the first write, validate after writing, and restore the previous
content if validation fails. Details in [safety.md](safety.md).

## `hypr-lua`

Reads and writes Hyprland's Lua config.

- **Read** evaluates the default config (`$OMARCHY_PATH/default/hypr/`) then the
  user config (`~/.config/hypr/`), capturing every `hl.config()` call into one
  merged table — the same order of precedence Hyprland itself uses.
- **Write** maintains a single `-- omaset:begin` / `-- omaset:end` block at the
  end of the user file. Only keys changed through omaset live there; the rest of
  your file is never touched.
- **Validate** after every write with `hyprctl reload` + `hyprctl configerrors`;
  on errors the previous content is restored. Set `OMASET_NO_APPLY=1` to skip
  this (tests, headless).

This is the backend behind most of *Appearance* (gaps, borders, rounding, blur,
shadow, groupbar).

## `hypr-window`

Manages `o.window(match, rules)` window rules (Omarchy's own helper) in a
`-- omaset:begin` / `-- omaset:end` block inside `~/.config/hypr/hyprland.lua`,
with the same write/validate/revert behaviour as `hypr-lua`.

- Each setting is a **group**: it declares a `match` and named `subsettings`
  (e.g. `border_size`, `rounding`). Sub-settings sharing a `match` compose into
  a single rule.
- `reset <id> <sub>` drops one field; `reset <id> --all` removes the whole rule,
  so the base `border_size`/`rounding` apply again.
- Defaults are declared in the DSL (there is no Omarchy stock window rule to
  read), so `changed` compares against those declared defaults.

This is what lets you give full-width or tiled-fullscreen windows a distinct
border and rounding so they are easy to identify — the *Windows* panel.

## `shell-json`

Edits `~/.config/omarchy/shell.json` with `jq`, using the same
normalize-and-commit approach as Omarchy's own `omarchy-shell-config`, so the file
keeps its `version`/`bar`/`plugins` shape.

- **Read** merges defaults (`$OMARCHY_PATH/config/omarchy/shell.json`) with the
  user file.
- **Write** is atomic (temp + `mv`) and hot-reloads the running shell.
- Requires `jq` (present on Omarchy).

The *Bar* panel (position, transparency) is the main user of this.

## `hyprsunset`

Manages a single omaset-owned night profile (`time` + `temperature`) in a
`# -- omaset:begin` / `# -- omaset:end` block inside
`~/.config/hypr/hyprsunset.conf`, so your own profiles and comments are never
touched.

- Exposes two settings: `schedule` (whether the night profile is active) and
  `temperature` (its color temperature in Kelvin, default 4000). Writing the
  temperature creates the profile if it does not exist; resetting the schedule
  removes the block entirely.
- Keeps a `<file>.omaset.bak` snapshot before its first write, so `rollback`
  restores the original file like the other file-writing backends.

## `omarchy`

Delegates to an existing `omarchy` command instead of editing a file, for
settings Omarchy already owns a knob for. The passthrough toggles
(`nightlight`, `window-no-gaps`, `single-window-square`) go through here; they
declare `default = false` so they still participate in `changed`.

## `workspace-layout`

Per-workspace tiling layout, keyed by workspace number.

- Shares storage with Omarchy's own `omarchy hyprland workspace layout toggle`
  (Super+L) — the same `~/.local/state/omarchy/workspace-layouts/*.lua` files —
  so the two are coherent.
- `reset workspace_layout <n>` deletes one rule; `reset workspace_layout --all`
  clears every persisted rule, including workspaces that are not currently open.

## Writing a new one

A backend is a Lua module that self-registers and implements read/write for the
settings that name it. See [extending.md](extending.md) for the interface and a
skeleton.
