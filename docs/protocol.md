# omaset protocol

The machine-readable contract between the omaset engine and its consumers
(the CLI, the keyboard-first UI, or Omarchy's own commands). Every command
emits valid, deterministic JSON (object keys are sorted).

All JSON payloads stay in English regardless of the UI language (labels,
descriptions, and tool descriptions included) — this is the stable contract
for agents and scripts. Localization happens only where humans read text:
the window (`Commons.Translations`) and the human CLI (`cli.*` catalog).
See [i18n.md](i18n.md).

## Commands

### `schema`

```
{ "schemaVersion": 1, "panels": [ { "id", "title", "settings": [ ... ] } ] }
```

`schemaVersion` versions the shape of this reply, independently of the engine
version (`preferences` carries that). A consumer that renders the schema must
check it and refuse a version it does not understand, rather than render a
partial or wrong list of settings. The version is bumped only on incompatible
shape changes; additive fields keep the same version.

A `setting` object always has `id`, `type`, `label`, `backend`, and `value`
(the current effective value, `null` if unset), plus a human-readable
`description` when one is declared. Backend- and type-specific fields are
additive:

| type    | extra fields             |
|---------|--------------------------|
| `int`   | `min`, `max` (optional)  |
| `float` | `min`, `max` (optional)  |
| `enum`  | `options` (array)        |
| `time`  | —                        |
| `bool`  | —                        |
| `string`| —                        |
| `group` | `subsettings` (object)   |

A numeric `int`/`float` setting may declare `options` as an array of
`{ "value", "label" }` objects instead of `min`/`max`. The stored value stays
the number; the label is display and CLI metadata (for example `follow_mouse`
maps `0=None`, `1=Full`, and so on).

A `time` setting may carry `format` (display pattern) and `hint` (accepted
input forms); both are informational.

**Keyed settings** take a subject/key argument (e.g. a workspace number). They
carry `keyed: true`, `key_label`, and `key_type` (`"int"` or `"string"`), and
their `value` is `null` in the schema. `get`/`set`/`reset` accept an extra
positional for the key, and their JSON output gains a `"key"` field.

**Grouped settings** have `type: "group"` and a `subsettings` object mapping
each sub-name to a sub-setting spec (`type`, `label`, `default`, plus
`min`/`max`/`options` as applicable). Their schema `value` is `null`. `get <id>`
returns the aggregate object; `get <id> <sub>` / `set <id> <sub> <value>` /
`reset <id> <sub>` address one field, and their JSON uses `sub` (not `key`).
`reset <id> --all` clears every sub-field.

Backend-specific fields (e.g. `path`, `file`, `command`) are passed through
as-is and are informational to consumers.

A setting may carry an optional `section` string. It is purely presentational:
settings sharing a section render under one header, and it does not affect how
a value is stored or how its default is computed. Within a panel, settings are
listed alphabetically by `id`, with each section's settings kept contiguous
(sections ordered by their alphabetically-first member).

A setting may also declare a `default` value. When present it is the stock
default for that setting, overriding the backend's `read_default`; it is how a
backend that cannot recompute its own default (e.g. an `omarchy` passthrough
toggle) still participates in `changed`.

### `get <id>`

```
{ "id": "...", "value": ... }
```

`--plain` prints just the bare value (unquoted) instead.

### `set <id> <value>`

```
{ "id": "...", "value": ..., "ok": true }
```

`--plain` prints `ok`. On failure the process exits nonzero and writes the
error to stderr.

### `reset <id>`

```
{ "id": "...", "ok": true }
```

### `changed [--json]`

```
{ "changed": [ { "id", "panel", "label", "value", "default" }, ... ] }
```

Settings whose current value differs from the Omarchy default. Keyed and
grouped entries also carry `key` or `sub` respectively. Settings with no
default (none are shipped anymore, but a custom backend may omit one) are
never reported as changed.

### `search <query> [--json]`

```
{ "results": [ { "id", "panel", "label", "value" }, ... ] }
```

### `keys <id> [<monitor>] [--all] [--json]`

Lists the keys of a keyed setting (e.g. open workspace numbers), one per line.
`--json` returns `{ "id", "keys": [...] }`. A monitor-grouped keyed setting
(4.5 workspace layouts) also returns `"monitors": [ { "name", "block",
"workspaces": [...] } ]`, and passing a monitor connector name filters `keys`
to that monitor's block.

### `history [--json] [N]`

```
{ "history": [ { "ts", "op", "id", "key"|"sub", "old", "default", "new", "backend" }, ... ] }
```

Every change omaset has made, oldest first. `op` is `"set"` or `"reset"`;
`old`/`new` are the effective values before/after (`null` = unset/default);
`default` is the Omarchy default at the time. `N` limits the output to the most
recent entries.

### `undo [--all] [--plain]`

```
{ "id": "...", "ok": true }          # single; gains "key"/"sub" for keyed/grouped settings
```

Undoes the most recent change by re-applying the recorded `old` value (or
`reset` when the setting was previously untouched). `--all` replays the whole
journal in reverse and returns `{ "ok": true, "undone": <count> }`.

### `rollback [--json]`

```
{ "rollback": true, "restored": <n> }
```

Restores every `<file>.omaset.bak` snapshot, returning each config file omaset
has written to the state it had before omaset first touched it, and clears the
journal. Backends without a snapshot (e.g. the `omarchy` passthrough and
`workspace-layout`) are no-ops.

### `preferences [list|get <key>|set <key> <value>|reset <key>]`

```
{ "version": "0.1.0", "preferences": [ { "key", "type", "label", "description", "value", "default", ... } ] }
```

Each preference carries its `type` (and `options`/`min`/`max` as applicable).
The `time_format` preference additionally carries a `resolved` field — the
`24h`/`12h` convention actually used, resolving the `auto` value against the
bar clock's format in shell.json.

omaset's **own** UI preferences, stored in `~/.config/omaset/preferences.json`
(`OMASET_PREFERENCES` overrides the path). They are deliberately *not* Omarchy
settings: they have no backend, they never appear in `schema`/`search`, and
they are never reported by `changed`.

- `list` (default) — every preference with its current value and default;
  `--json` returns the array under `preferences`, alongside the `version` of
  the omaset engine.
- `get <key>` — `{ "key", "value" }` (or `--plain` bare value).
- `set <key> <value>` — validates and persists; `{ "key", "value", "ok" }`.
- `reset <key>` — removes the override so the default applies.

### `list [--json]`

Human text by default; `--json` is identical to `schema`.

## RPC (`omaset rpc`)

The settings window talks to one long-lived `omaset rpc` process over
newline-delimited JSON-RPC 2.0. There is no handshake: each request names one
operation, and the response carries the same JSON the CLI emits.

```
{"jsonrpc":"2.0","id":1,"method":"get","params":{"id":"gaps_in"}}
{"jsonrpc":"2.0","id":1,"result":{"id":"gaps_in","value":5,"default":5}}
```

Operations are the shared service operations: `schema`, `get`, `set`, `reset`,
`changed`, `search`, `help`, `keys`, `history`, `undo`, `rollback`,
`preferences`, `preference_get`, `preference_set`, `preference_reset`, `ui`,
`open_ui`, `ui_float`, `hyprsunset_apply`, and `snapshot`. `ping` and `version`
are transport-level conveniences.

Parameters use the same names as the MCP tools: `id`, `key` (for keyed and
grouped settings), `value`, `query`, `all`, `detail`, `panel`, `action`, and
`enabled`. Values may be JSON-typed (`true`, `3500`, `"20:30"`) or strings the
CLI would accept; validation is identical either way.

Errors use standard JSON-RPC codes: `-32601` for an unknown method, `-32602`
for invalid parameters or a rejected value, `-32700` for an unparseable line,
and `-32603` for an internal handler failure.

### `snapshot`

`snapshot` bundles everything the window needs for one render, so opening a
panel does not fan out into a process per setting:

```
{
  "version": "0.1.0",
  "schemaVersion": 1,
  "schema": { ... },
  "preferences": { ... },
  "changed": [ ... ],
  "panel": "layout",
  "keys": { "workspace_layout": ["1", "2"] },
  "keyed": { "workspace_layout": { "1": "dwindle", "2": "scrolling" } },
  "groups": { "fullwidth_style": { "border_size": 2, "rounding": 0 } }
}
```

`keys`, `keyed`, and `groups` describe the requested `panel` only; pass no
panel to leave them empty. `panel` is `null` when no panel was requested.

## Backends

A setting names a `backend`, and each backend implements `read`, `read_default`,
`write`, and `reset` for its config format. Backends self-register via
`require("omaset.backends").register(name, mod)` and are discovered from
`lib/omaset/backends/` (built-in) and `~/.config/omaset/backends/` (user).

Built-in backends:

- `hypr-lua` — Hyprland Lua config (`~/.config/hypr/*.lua`); fields `file`
  (config basename) and `path` (dotted key).
- `hypr-window` — Hyprland window rules via `o.window()`; fields `file` (config
  basename, default `hyprland`) and `match` (window-rule match table). Used for
  grouped settings; each sub-setting is a field of the emitted rule.
- `shell-json` — `~/.config/omarchy/shell.json`; field `path` (dotted key).
- `omarchy` — delegates to an existing `omarchy` command (so hooks fire). Fields
  `command` (run on set; `{value}` is substituted for `mode = "value"`), `status`
  (command whose stdout is the current value), `mode` (`"value"` or `"toggle"`),
  and optional `reset`. `read` returns `null` when there is no `status` command.
- `workspace-layout` — per-workspace Hyprland layout, keyed by workspace number.
  Shares `~/.local/state/omarchy/workspace-layouts/` with Omarchy. On
  workspace-modes hosts (Omarchy 4.5+) it reads/writes
  `o.workspace_mode({workspace, mode})` via `omarchy-hyprland-workspace-layout-*`;
  on older hosts it uses `hl.workspace_rule` + `hyprctl workspaces`. Default is
  `"dwindle"`.
- `hyprsunset` — night light schedule in `~/.config/hypr/hyprsunset.conf`; field
  `path` (`"schedule"`, `"start"`, `"stop"`, or `"temperature"`). Edits the
  warm `temperature` profile (at `start`) and the `identity` profile (at `stop`)
  in place.
