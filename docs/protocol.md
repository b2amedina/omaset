# omaset protocol

The machine-readable contract between the omaset engine and its consumers
(the CLI, a future TUI/GUI, or Omarchy's own commands). Every command emits
valid, deterministic JSON (object keys are sorted).

## Versioning

`schema` carries a top-level `schema_version` integer. It increments when the
schema shape changes incompatibly. Consumers should key off it, not on
individual field presence.

## Commands

### `schema`

```
{ "schema_version": 1, "panels": [ { "id", "title", "settings": [ ... ] } ] }
```

A `setting` object always has `id`, `type`, `label`, `backend`, and `value`
(the current effective value, `null` if unset). Backend- and type-specific
fields are additive:

| type    | extra fields             |
|---------|--------------------------|
| `int`   | `min`, `max` (optional)  |
| `float` | `min`, `max` (optional)  |
| `enum`  | `options` (array)        |
| `bool`  | —                        |
| `string`| —                        |

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
- `shell-json` — `~/.config/omarchy/shell.json`; field `path` (dotted key).
- `omarchy` — delegates to an existing `omarchy` command (so hooks fire). Fields
  `command` (run on set; `{value}` is substituted for `mode = "value"`), `status`
  (command whose stdout is the current value), `mode` (`"value"` or `"toggle"`),
  and optional `reset`. `read` returns `null` when there is no `status` command.
