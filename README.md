# omaset

A keyboard-first settings app for Omarchy, focused on what the top-bar panels
don't already expose — gaps, borders, tiling layout, animations, and window
indicators.

Extensible: every setting and panel is declared in a small Lua DSL, so adding
or overriding a setting means dropping in a `.lua` file.

**Status:** CLI MVP. A Quickshell (QML) frontend will layer on top of this
same command, which is why the CLI speaks JSON.

## Usage

```
bin/omaset list            # panels + settings with current values
bin/omaset schema          # full schema as JSON (what the GUI will render)
bin/omaset get <id>        # one setting's value as JSON
bin/omaset set <id> <val>  # write a value; applies via Hyprland's auto-reload
```

No installation needed — it runs in place with `luajit`.

## How it works

```
bin/omaset              CLI entry (sets up package.path)
lib/omaset/
  init.lua              registry + schema + command dispatch
  dsl.lua               panel()/setting() declarative DSL
  discovery.lua         loads share/settings/*.lua (and ~/.config/omaset/settings/)
  types.lua             int/float/bool/enum coercion + range checks
  json.lua              minimal JSON encoder
  util.lua              deep merge/get/set + Lua serializer
  backends/hypr_lua.lua reads/writes Hyprland Lua config (looknfeel.lua etc.)
share/settings/         built-in panels (appearance, layout, animations)
```

### The `hypr-lua` backend

- **Read** evaluates the default config (`$OMARCHY_PATH/default/hypr/`) then
  the user config (`~/.config/hypr/`), capturing every `hl.config()` call into
  one merged table — the same order-of-precedence Hyprland itself uses.
- **Write** maintains a single `-- omaset:begin` / `-- omaset:end` block at the
  end of the user file. Only keys changed through omaset live there; the rest
  of your file is never touched. A `.omaset.bak` snapshot is kept on first edit.

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

- `hyprctl configerrors` validation after write, with revert-on-failure.
- More backends: `shell.json` (idle/lock), `hyprsunset`, `omarchy` CLI.
- Window-indicator settings (full-screen / full-tiled border rules).
- A "changed from defaults" view and a backup picker.
- The Quickshell keyboard-first frontend (consumes `schema`/`get`/`set`).
