# Backends

A backend is the only part of Omaset that knows a config format. It exposes a
small read/write/validate interface for one area, and the engine treats them all
identically. They self-register from `lib/omaset/backends/`, so a settings file
can point at any of them — or at a new one — without the core changing.

**Validation.** A backend that owns an enum's values implements an optional
`validate(setting, value, key, customs)` hook. `customs` lists the values the
setting has held (declared options are checked separately). `hypr-lua`,
`workspace-layout`, `shell-json`, and `omasnap` use `types.check_allowed`;
`omarchy` has no hook, so its command decides. Reads never drop a value: an
enum read returns what the file holds, even if it is not an allowed value.

Every file-writing backend keeps a one-time `<file>.omaset.bak` snapshot before
its first write, validates after writing, and restores the previous content if
validation fails. Each edits the value in place where it already lives, and
appends a minimal override when it does not. Details in [safety.md](safety.md).

## Migrating from 0.1.0

0.1.0 wrote Omaset's changes into `-- omaset:begin` / `-- omaset:end` blocks
(`# -- omaset:begin` / `# -- omaset:end` in `hyprsunset.conf`). 0.2.0 edits
values in place instead. Existing blocks keep working — reads evaluate the whole
file, so the values inside them are still read and edited in place — but the
marker lines are now inert comments. To tidy your files, delete the marker
lines and leave the values between them as they are.

## `hypr-lua`

Reads and writes Hyprland's Lua config.

- **Read** evaluates the default config (`$OMARCHY_PATH/default/hypr/`) then the
  user config (`~/.config/hypr/`), capturing every `hl.config()` call into one
  merged table — the same order of precedence Hyprland itself uses.
- **Write** edits the *winning* `hl.config()` occurrence of the setting in place
  (the last uncommented one — the value that is actually in effect), keeping the
  surrounding comments and keys untouched. If the value has no occurrence yet, a
  minimal `hl.config({ path = value })` override is appended at the end of the
  file.
- **Reset** writes the stock default back in place using the same rule, and is a
  no-op when the value has no occurrence (a commented example is left alone).
- **Validate** after every write with `hyprctl reload` + `hyprctl configerrors`;
  on errors the previous content is restored. Set `OMASET_NO_APPLY=1` to skip
  this (tests, headless).

This is the backend behind most of *Appearance* (gaps, borders, rounding, blur,
shadow, groupbar).

## `hypr-window`

Manages `o.window(match, rules)` window rules (Omarchy's own helper) in
`~/.config/hypr/hyprland.lua`.

- Each setting is a **group**: it declares a `match` and named `subsettings`
  (e.g. `border_size`, `rounding`). Sub-settings sharing a `match` compose into
  a single rule.
- **Read** scans the whole file for the *last* `o.window()` call whose match
  equals the setting's match — Hyprland applies window rules in order, so the
  later call wins — and reads the field from its rules table.
- **Write** rebuilds that one call with the field changed (or adds a new call at
  EOF when no matching rule exists). **Reset** drops one field, or the whole
  rule when it becomes empty (`reset --all`), so the base `border_size`/`rounding`
  apply again.
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

Manages the night-light schedule in `~/.config/hypr/hyprsunset.conf`, editing
the relevant `profile { ... }` block in place.

- hyprsunset has no on/off window: it applies whichever profile has the latest
  activation time. So the schedule is two profiles — a warm `temperature`
  profile at the start time and an `identity = true` (no tint) profile at the
  stop time.
- Exposes four settings: `schedule` (whether a night `temperature` profile
  exists), `start` (`HH:MM`, default 20:00), `stop` (`HH:MM`, default 07:00),
  and `temperature` (Kelvin, default 4000). Enabling the schedule adds a night
  profile (and an identity profile when none exists); writing any schedule field
  edits the matching profile in place and thereby enables the schedule. The
  whole file is scanned, so a hand-edited profile is what `get` reports. Start
  and stop may not be equal.
- `apply()` restarts the running hyprsunset so a written schedule takes effect —
  hyprsunset parses its config only at startup. The settings window calls this
  once on close, not on every write.
- Keeps a `<file>.omaset.bak` snapshot before its first write, so `rollback`
  restores the original file like the other file-writing backends.

## `omarchy`

Delegates to an existing `omarchy` command instead of editing a file, for
settings Omarchy already owns a knob for. The passthrough toggles
(`nightlight`, `window-no-gaps`, `single-window-square`) go through here; they
declare `default = false` so they still participate in `changed`.

- **Read** runs `status` and coerces its output to the setting's type. An enum
  value outside the declared options is shown as-is rather than as unset.
- **Write** runs `command` with `{value}` substituted.
- **Reset** runs `reset`, when declared.

## `workspace-layout`

Per-workspace tiling layout, keyed by workspace number.

- Shares storage with Omarchy's own `omarchy hyprland workspace layout toggle`
  (Super+L) — the same `~/.local/state/omarchy/workspace-layouts/*.lua` files —
  so the two are coherent. On workspace-modes hosts (Omarchy 4.5+) the files
  carry `o.workspace_mode({workspace, mode})` and reads go through
  `omarchy-hyprland-workspace-layout-current`/`-default`; older hosts use
  `hl.workspace_rule`. Which mechanics apply is chosen by the
  `features.workspace_modes()` probe.
- `reset workspace_layout <n>` deletes one rule; `reset workspace_layout --all`
  clears every persisted rule, including workspaces that are not currently open.
  Writing a mode equal to the default deletes the file.
- On workspace-modes hosts the setting is **monitor-grouped**: workspaces are
  numbered in blocks of ten per monitor (laptop 1–10, next monitor 11–20, …).
  `keys workspace_layout` lists the monitors (`name`, `block`, and their
  workspaces — the first five slots plus any that exist, like the bar);
  `keys workspace_layout <connector>` filters to one
  monitor. The block mapping comes from Omarchy's own
  `~/.local/state/omarchy/monitor-workspaces` file. Special/named workspaces
  (negative ids) are never listed.

## Writing a new one

A backend is a Lua module that self-registers and implements read/write for the
settings that name it. See [extending.md](extending.md) for the interface and a
skeleton.

## `omasnap`

Manages `~/.config/omasnap/omasnap.conf` (INI). Every key is optional; reads
fall back to the setting's declared default when absent, writes edit the value
in place (or append a minimal `[section]`/`key = value` override), and a
one-time `.omaset.bak` snapshot supports `rollback`. No apply step is needed
because Omasnap reads the file on each invocation.
