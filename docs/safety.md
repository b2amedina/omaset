# Safety, undo & rollback

Omaset's first promise is that it will not wreck your config. It never
parses-and-rewrites your files: it edits the one value being changed — in place
where it already lives, or appending a minimal override when it does not — and
keeps a one-time `<file>.omaset.bak` snapshot before its first write to any
config file. (`shell.json` is normalized through Omarchy's own `jq` pipeline and
committed with the same atomic, permission-preserving writer as every other
file.) Every change is validated and automatically reverted on failure.

## Resource bounds

Every subprocess runs through one helper that caps it twice: GNU `timeout`
terminates the command (and its process group) after a deadline, and the output
is written to a `0600` capture file and read back up to a byte cap. The RPC
server wraps each request in a second, whole-request deadline, and the settings
window rejects requests that still have not returned and restarts the worker
rather than replaying a possibly-partial write. `OMASET_CMD_TIMEOUT`,
`OMASET_CMD_MAX_BYTES`, and `OMASET_REQUEST_TIMEOUT` tune the defaults.

## History and undo

- `omaset history` lists every change Omaset has made, oldest first, from an
  append-only journal at `~/.local/state/omaset/journal.jsonl`.
- `omaset undo` undoes the most recent change; `undo --all` replays the journal
  in reverse. Undo restores the recorded previous value, and falls back to
  `reset` when the setting was previously untouched — so "back to default" keeps
  following the Omarchy default rather than pinning a value.

## Rollback

- `omaset rollback` is the panic button: it restores every `<file>.omaset.bak`
  snapshot for each file-writing backend, returning each config file to the state
  it had before Omaset first wrote to it. It does not depend on the journal.

## Reset & changed semantics

`reset` puts a setting back to its Omarchy default — writing the default in
place where Omaset changed it, or dropping the value Omaset appended. It does
not store snapshots: `read_default` recomputes the default from Omarchy's
shipped config on every call.

- `changed` diffs the *effective* value (as read from your config) against that
  stock default, so it sees changes made by hand-editing, `omarchy` commands, or
  hotkeys too. In the settings window, press `c` to open a "Changed" list of
  every differing setting (value → default); Enter jumps to it.
- A setting can declare its own `default` when the backend cannot recompute one —
  the `omarchy` passthrough toggles (`nightlight`, `window-no-gaps`,
  `single-window-square`) declare `default = false` so they participate in
  `changed` too.
- `hypr-lua` edits the value in place, so `reset` writes the stock default back
  where the value lives; a hand-written `hl.config(...)` override for a key Omaset
  never touched is left alone. To restore *everything* to stock, use
  `omarchy refresh hyprland`.
- `workspace-layout` shares storage with `omarchy hyprland workspace layout
  toggle` (Super+L) — the same `~/.local/state/omarchy/workspace-layouts/*.lua`
  files — so the two are coherent. `reset workspace_layout <n>` deletes one rule;
  `reset workspace_layout --all` clears every persisted rule, including
  workspaces that are not currently open.
