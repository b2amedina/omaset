# omaset protocol

The machine-readable contract between the omaset engine and its consumers
(the CLI, the keyboard-first UI, or Omarchy's own commands). Every command
emits valid, deterministic JSON (object keys are sorted).

## Commands

### `schema`

```
{ "panels": [ { "id", "title", "settings": [ ... ] } ] }
```

A `setting` object always has `id`, `type`, `label`, `backend`, and `value`
(the current effective value, `null` if unset), plus a human-readable
`description` when one is declared. Backend- and type-specific fields are
additive:

| type    | extra fields             |
|---------|--------------------------|
| `int`   | `min`, `max` (optional)  |
| `float` | `min`, `max` (optional)  |
| `enum`  | `options` (array)        |
| `bool`  | —                        |
| `string`| —                        |
| `group` | `subsettings` (object)   |

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

Settings whose current value differs from the Omarchy default.

### `search <query> [--json]`

```
{ "results": [ { "id", "panel", "label", "value" }, ... ] }
```

### `keys <id> [--json]`

Lists the keys of a keyed setting (e.g. open workspace numbers), one per line.
`--json` returns `{ "id", "keys": [...] }`.

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

### `list [--json]`

Human text by default; `--json` is identical to `schema`.

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
  Reads `hyprctl workspaces`, persists rules to
  `~/.local/state/omarchy/workspace-layouts/` (like `omarchy hyprland workspace
  layout toggle`), and applies via `hl.workspace_rule`. Default is `"dwindle"`.
