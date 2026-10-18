# The omaset CLI

The CLI is the heart of omaset — the settings window and the MCP server are both
thin faces over the same calls. Link the bundled binary onto your PATH to drive
settings from a terminal, a script, or an agent:

```sh
ln -s ~/.config/omarchy/plugins/b2amedina.omaset/bin/omaset ~/.local/bin/omaset
```

## Commands

| Command | What it does |
|---|---|
| `omaset schema` | every panel, every setting, with its current value |
| `omaset get <id>` | read one setting (value + default) |
| `omaset set <id> <value>` | write a value; validates, applies, journals |
| `omaset reset <id>` | revert omaset's override so the default returns |
| `omaset changed` | settings that differ from Omarchy stock |
| `omaset search <query>` | find a setting by id or label |
| `omaset help <id>` | one setting's type, options, range, default, value |
| `omaset keys <id>` | enumerate a keyed/grouped setting's keys |
| `omaset history` | every change omaset has made, oldest first |
| `omaset undo` | undo the most recent change (`--all` replays the journal) |
| `omaset rollback` | restore every config file omaset touched |
| `omaset preferences` | omaset's own settings (see below) |
| `omaset mcp` | run the MCP server (see [agents.md](agents.md)) |
| `omaset ui` | open the settings window |

Every command prints JSON; add `--json` where a command defaults to human text,
or `--plain` to get just the bare value / `ok` (handy in scripts and prompts).

## Keyed settings

Some settings are per-key — per workspace, most often. They take a subject
argument after the id:

```sh
omaset get workspace_layout 2                 # read workspace 2's layout
omaset set workspace_layout 3 scrolling       # set workspace 3
omaset keys workspace_layout --all            # every persisted key
```

## Discovering what a setting accepts

```sh
omaset help <id>            # type, options, min..max, default, current value
omaset set <id> --help      # the <a|b|c> enum form, or a <min..max> range
```

`help` lists `options` for enums and `min..max` for numbers. An invalid enum
value lists the valid options in the error, so a typo tells you what it wanted.

## Preferences

omaset has a few settings about *itself*, kept separate from the Omarchy settings
above. They live in `~/.config/omaset/preferences.json`, are managed with
`omaset preferences`, and are **not** Omarchy settings: they never appear in the
settings panels, `search`, or `changed`.

- `refresh_interval_sec` — how often the settings window re-reads values while
  visible (default 2, range 1..60).
- `launch_floating` — whether the window opens floating (default true). omaset
  manages this by adding/removing an `o.window(... float/center ...)` rule for
  its own window in the managed block of `~/.config/hypr/hyprland.lua`, so no
  hand-written rule is needed. Takes effect on the next open.

Edit them from the settings window with `p`, or from the CLI:

```
omaset preferences                            # list
omaset preferences get refresh_interval_sec   # read one
omaset preferences set refresh_interval_sec 5 # write one
omaset preferences reset launch_floating      # back to default
```
