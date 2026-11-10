# Omaset settings UI

A keyboard-first, schema-driven settings window for Omaset, built as an
Omarchy Quickshell plugin. It renders whatever the schema returns, so adding or
removing a setting in Lua needs no QML changes. The schema carries a
`schemaVersion`, and the window only renders a version it supports: a mismatch
(an engine older or newer than the window) shows an error naming both versions
rather than a partial list of settings.

The window talks to one long-lived `omaset rpc` process over newline-delimited
JSON-RPC 2.0 (see [the protocol](../docs/protocol.md#rpc-Omaset-rpc)). Requests
are matched by id, so values can load in parallel without spawning a process
per setting. A `snapshot` call fetches a panel's schema, preferences, changed
list, and its keyed/grouped values together.

## Launch

The plugin is a **regular window** — it is not a terminal app and does not
open inside a terminal emulator. By default it starts floating and centered
(the `launch_floating` preference), so you can move and resize it with the
mouse; `SUPER+T` (Omarchy's default float/tile toggle) also docks it back into
the tiling layout. The Omarchy shell must be running (it always is in a
session).

```sh
omaset ui              # toggle open / close
omaset ui open         # open
omaset ui close        # close
omaset ui reload       # restart the shell + reopen (development)
```

`omaset ui` is a thin wrapper over the shell IPC; the underlying commands are:

```sh
omarchy-shell shell toggle b2amedina.omaset '{}'   # open / close
omarchy-shell shell summon b2amedina.omaset '{}'   # open only
omarchy-shell shell hide b2amedina.omaset          # close only
```

`omaset ui reload` additionally runs `omarchy restart shell` first, because the
shell's file watcher does not follow symlinks and a plain rescan would not pick
up edits under a symlinked dev checkout.

There is also an optional bar icon (`bar-widget`). It is not added to the bar
by default; enable it by adding `b2amedina.omaset` to `shell.json`'s bar
layout.

## Install

The marketplace install is a single command that clones this repository (the
manifest lives at the repo root, with the QML under `ui/`) and enables it:

```sh
omarchy plugin add https://github.com/b2amedina/omaset.git --enable
```

For development, symlink the repository root into the Omarchy plugins dir (the
panel finds the engine bundled alongside the QML, so no PATH entry is needed):

```sh
ln -s "$PWD" ~/.config/omarchy/plugins/b2amedina.omaset
ln -s "$PWD/bin/omaset" ~/.local/bin/omaset   # optional, for CLI use
```

The shell rescans the plugins dir on change. `OMASET_BIN` (optional) points the
panel at a different `omaset` executable; otherwise it runs the engine bundled
with the plugin at `~/.config/omarchy/plugins/b2amedina.omaset/bin/omaset`.

The window floats because Omaset manages a `o.window(... float/center ...)`
rule for its own window (the `launch_floating` preference); no hand-written
Hyprland rule is required.

## Keys

| Key | Action |
|-----|--------|
| `j` / `k` (or `↑` / `↓`) | move between settings (or sidebar panels) |
| `h` / `l` (or `←` / `→`) | adjust the focused slider or cycle a segmented control |
| `Tab` / `Shift+Tab` | switch sidebar/content pane |
| `Space` / `Enter` | activate the current row (toggle / select / edit a value) |
| `x` | reset the current setting to its default |
| `/` | search (`↑`/`↓` move, `Enter` opens, `Esc` clears) |
| `c` | open the Changed list (`↑`/`↓` move, `Enter` jumps, `Esc` closes) |
| `p` | open Preferences (`↑`/`↓` move, `Space`/`Enter` toggle, `h`/`l` step, `Esc` closes) |
| `Esc` | close (or leave search / changed / preferences) |

A slider can also be set exactly: with it focused, press `Enter` (or click its
value), type the number, and press `Enter` again. `Esc` cancels, and `h`/`l`
still step by one. A time row works the same way: type `HH:MM` or
`h:mm AM/PM`, or use `h`/`l` to step by 15 minutes. Times are shown in the
`time_format` preference's convention (24h, 12h, or follow the bar clock).

The footer shows keyboard hints plus a contextual badge — `N changed` when
settings differ from Omarchy stock, `N settings found` while searching. The
Preferences overlay (`p`) shows the Omaset engine version as a dimmed caption
pinned at its bottom.

## Structure

- `manifest.json` (at the repo root) — plugin metadata (`panel` + `bar-widget`
  kinds).
- `Panel.qml` — the window: sidebar, content, footer, cursor model, search.
- `RpcClient.qml` — persistent `omaset rpc` process, request ids, response
  dispatch, and start-up queue.
- `BarWidget.qml` — optional bar icon that toggles the window.
- `model.js` — pure transforms from schema JSON to renderable rows.
- `components/` — row renderers built on `qs.Ui` (`Toggle`, `PanelSlider`,
  `ButtonGroup`, `BorderSurface`), so theme/colors/shape come from the active
  Omarchy theme automatically (under Ristretto, toggles are square and
  foreground-based).
- `../i18n/` (plugin root, shared with the engine) — the `<language>.json`
  catalogs; the window reads them via `Commons.Translations` and follows
  the desktop language. See [docs/i18n.md](../docs/i18n.md).

## How it maps Omaset settings

| type | control |
|------|---------|
| `bool` | `Toggle` |
| `int`/`float` (bounded) | `PanelSlider` |
| `int`/`float` with choices | segmented `ButtonGroup` (stores the number) |
| `enum` | segmented `ButtonGroup` |
| `time` | inline time field (`HH:MM`, shown per `time_format`) |
| `group` | header + one row per sub-setting |
| `keyed` | header + one row per key (workspaces) |

Values are read via `schema`/`snapshot`/`get` and written via `set`/`reset`
RPC calls; `changed` drives the footer badge.
