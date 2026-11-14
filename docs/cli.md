# The Omaset CLI

The CLI, the MCP server, and the settings window are all thin faces over the
same shared service (`lib/omaset/service.lua`). Link the bundled binary onto
your PATH to drive settings from a terminal, a script, or an agent:

```sh
ln -s ~/.config/omarchy/plugins/b2amedina.omaset/bin/omaset ~/.local/bin/omaset
```

## Commands

| Command | What it does |
|---|---|
| `omaset schema` | every panel, every setting, with its current value |
| `omaset get <id>` | read one setting (value + default) |
| `omaset set <id> <value>` | write a value; validates, applies, journals |
| `omaset reset <id>` | put the setting back to its default |
| `omaset changed` | settings that differ from Omarchy stock |
| `omaset search <query>` | find a setting by id, label, description, title, or option |
| `omaset help <id>` | one setting's type, options, range, default, value |
| `omaset keys <id>` | enumerate a keyed/grouped setting's keys |
| `omaset history` | every change Omaset has made, oldest first |
| `omaset undo` | undo the most recent change (`--all` replays the journal) |
| `omaset rollback` | restore every config file Omaset touched |
| `omaset preferences` | Omaset's own settings (see below) |
| `omaset ui-float <on|off>` | float/center the settings window |
| `omaset hyprsunset-apply` | restart hyprsunset so a schedule takes effect |
| `omaset mcp` | run the MCP server (see [agents.md](agents.md)) |
| `omaset mcp install [<agent>...]` | register the server via each agent's own `mcp add` |
| `omaset mcp doctor` | report which agents are wired up |
| `omaset rpc` | run the JSON-RPC server the settings window uses |
| `omaset ui` | open the settings window |
| `omaset browser list` | show enabled browsers, routing rules, and fallback |
| `omaset browser enable <id>` | enable a browser for routing |
| `omaset browser disable <id>` | disable a browser (keeps its rules) |
| `omaset browser install <id>` | install a browser and enable it |
| `omaset browser set-label <id> <label>` | set or clear a browser's display label |
| `omaset browser rule-add <browser> <domain...>` | add domains to a browser's rules |
| `omaset browser rule-remove <domain...>` | remove domains from routing rules |
| `omaset browser rule-edit <domain> <new-domain> <browser>` | rename or move a rule |

Every command prints JSON; add `--json` where a command defaults to human text,
or `--plain` to get just the bare value / `ok` (handy in scripts and prompts).
JSON and `--plain` output always stay English — only human text localizes.

## Language

```
omaset --lang <code> <command> [args...]   # one-off override for this call
omaset --lang list                          # list available language codes
omaset --lang <code>                        # print the resolved language
```

The code comes from Omarchy's registry (`omarchy language list`) and
follows the desktop language by default: `--lang` > `OMASET_LANGUAGE` >
`~/.config/omarchy/language` > `en`. The flag is accepted anywhere in the
argument list (`omaset list --lang fr` works too). `omaset ui --lang fr`
is the one-shot window override: it renders the settings window in French
for that launch only (`~/.config/omaset/ui-language`, cleared on the next
plain `omaset ui`). See [i18n.md](i18n.md)
for what localizes (labels and status strings) and what does not (command
names, flags, values, JSON, MCP).

## Keyed settings

Some settings are per-key — per workspace, most often. They take a subject
argument after the id:

```sh
omaset get workspace_layout 2                 # read workspace 2's layout
omaset set workspace_layout 3 scrolling       # set workspace 3
omaset keys workspace_layout                  # list monitors (4.5: per-monitor workspaces)
omaset keys workspace_layout DP-10            # that monitor's workspaces (global ids)
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

Omaset has a few settings about *itself*, kept separate from the Omarchy settings
above. They live in `~/.config/omaset/preferences.json`, are managed with
`omaset preferences`, and are **not** Omarchy settings: they never appear in the
settings panels, `search`, or `changed`.

- `refresh_interval_sec` — how often the settings window re-reads values while
  visible (default 2, range 1..60).
- `launch_floating` — whether the window opens floating (default true). Omaset
  manages this by adding/removing an `o.window(... float/center ...)` rule for
  its own window in `~/.config/hypr/hyprland.lua`, so no hand-written rule is
  needed. Takes effect on the next open.
- `time_format` — how times are displayed in the settings window (`24h`, `12h`,
  or `auto` to follow the bar clock's format in shell.json; default `auto`).
  Storage is always 24-hour `HH:MM`.

Edit them from the settings window with `p`, or from the CLI:

```
omaset preferences                            # list
omaset preferences get refresh_interval_sec   # read one
omaset preferences set refresh_interval_sec 5 # write one
omaset preferences reset launch_floating      # back to default
```
