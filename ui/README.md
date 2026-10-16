# omaset settings UI

A keyboard-first, schema-driven settings window for omaset, built as an
Omarchy Quickshell plugin. It renders whatever `omaset schema` returns, so
adding or removing a setting in Lua needs no QML changes.

## Launch

The plugin is a **regular floating window** — it is not a terminal app and
does not open inside a terminal emulator. It starts floating and centered, so
you can move and resize it with the mouse; `SUPER+T` (Omarchy's default
float/tile toggle) docks it back into the tiling layout. The Omarchy shell
must be running (it always is in a session).

```sh
omaset-ui              # toggle open / close
omaset-ui open         # open
omaset-ui close        # close
omaset-ui-reload       # restart the shell + reopen (development)
```

`omaset-ui`/`omaset-ui-reload` are thin wrappers over the shell IPC; the
underlying commands are:

```sh
omarchy-shell shell toggle b2amedina.omaset '{}'   # open / close
omarchy-shell shell summon b2amedina.omaset '{}'   # open only
omarchy-shell shell hide b2amedina.omaset          # close only
```

There is also an optional bar icon (`bar-widget`). It is not added to the bar
by default; enable it by adding `b2amedina.omaset` to `shell.json`'s bar
layout.

## Install

The plugin directory is symlinked into the Omarchy plugins dir, and the
`omaset` binary plus the launcher helpers are linked onto `PATH`:

```sh
ln -s "$PWD/ui" ~/.config/omarchy/plugins/b2amedina.omaset
ln -s "$PWD/bin/omaset" ~/.local/bin/omaset
ln -s "$PWD/bin/omaset-ui" ~/.local/bin/omaset-ui
ln -s "$PWD/bin/omaset-ui-reload" ~/.local/bin/omaset-ui-reload
```

The shell rescans the plugins dir on change. `OMASET_BIN` (optional) points
the panel at a different omaset executable; otherwise it runs `omaset` from
`PATH`.

The window floats because of a Hyprland rule matching its class + title (add
this to `~/.config/hypr/hyprland.lua` or an `apps/*.lua` file):

```lua
o.window({ class = "^org.quickshell$", title = "^omaset Settings$" },
  { float = true, center = true })
```

## Keys

| Key | Action |
|-----|--------|
| `j` / `k` | move between settings (or sidebar panels) |
| `h` / `l` | switch sidebar/content pane; on a slider or segmented control, adjust it |
| `Tab` | switch pane |
| `Space` / `Enter` | activate the current row (toggle / select / nudge) |
| `x` | reset the current setting to its default |
| `/` | search (`↑`/`↓` move, `Enter` opens, `Esc` clears) |
| `Esc` | close (or leave search) |

The footer shows keyboard hints plus a contextual badge — `N changed` when
settings differ from Omarchy stock, `N settings found` while searching.

## Structure

- `manifest.json` — plugin metadata (`panel` + `bar-widget` kinds).
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
