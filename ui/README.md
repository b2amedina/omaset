# omaset settings UI

A keyboard-first, schema-driven settings window for omaset, built as an
Omarchy Quickshell plugin. It renders whatever `omaset schema` returns, so
adding or removing a setting in Lua needs no QML changes.

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

The window floats because omaset manages a `o.window(... float/center ...)`
rule for its own window (the `launch_floating` preference); no hand-written
Hyprland rule is required.

## Keys

| Key | Action |
|-----|--------|
| `j` / `k` (or `↑` / `↓`) | move between settings (or sidebar panels) |
| `h` / `l` (or `←` / `→`) | adjust the focused slider or cycle a segmented control |
| `Tab` / `Shift+Tab` | switch sidebar/content pane |
| `Space` / `Enter` | activate the current row (toggle / select / nudge) |
| `x` | reset the current setting to its default |
| `/` | search (`↑`/`↓` move, `Enter` opens, `Esc` clears) |
| `c` | open the Changed list (`↑`/`↓` move, `Enter` jumps, `Esc` closes) |
| `p` | open Preferences (`↑`/`↓` move, `Space`/`Enter` toggle, `h`/`l` step, `Esc` closes) |
| `Esc` | close (or leave search / changed / preferences) |

The footer shows keyboard hints plus a contextual badge — `N changed` when
settings differ from Omarchy stock, `N settings found` while searching. The
Preferences overlay (`p`) shows the omaset engine version as a dimmed caption
pinned at its bottom.

## Structure

- `manifest.json` (at the repo root) — plugin metadata (`panel` + `bar-widget`
  kinds).
- `Panel.qml` — the window: sidebar, content, footer, process runner, cursor
  model, search.
- `BarWidget.qml` — optional bar icon that toggles the window.
- `model.js` — pure transforms from `omaset schema` JSON to renderable rows.
- `components/` — row renderers built on `qs.Ui` (`Toggle`, `PanelSlider`,
  `ButtonGroup`, `BorderSurface`), so theme/colors/shape come from the active
  Omarchy theme automatically (under Ristretto, toggles are square and
  foreground-based).

## How it maps omaset settings

| type | control |
|------|---------|
| `bool` | `Toggle` |
| `int`/`float` (bounded) | `PanelSlider` |
| `enum` | segmented `ButtonGroup` |
| `group` | header + one row per sub-setting |
| `keyed` | header + one row per key (workspaces) |

Values are read via `omaset schema`/`get` and written via `omaset set`/`reset`;
`omaset changed` drives the footer badge.
