# Safety, undo & rollback

omaset's first promise is that it will not wreck your config. It never
parses-and-rewrites your files. It only writes into a marked
`-- omaset:begin/end` block (Lua config) or via Omarchy's own `jq` pipeline
(`shell.json`), and keeps a one-time `<file>.omaset.bak` snapshot before its
first write to any config file. Every change is validated and automatically
reverted on failure.

## History and undo

- `omaset history` lists every change omaset has made, oldest first, from an
  append-only journal at `~/.local/state/omaset/journal.jsonl`.
- `omaset undo` undoes the most recent change; `undo --all` replays the journal
  in reverse. Undo restores the recorded previous value, and falls back to
  `reset` when the setting was previously untouched — so "back to default" keeps
  following the Omarchy default rather than pinning a value.

## Rollback

- `omaset rollback` is the panic button: it restores every `<file>.omaset.bak`
  snapshot for each file-writing backend, returning each config file to the state
  it had before omaset first wrote to it. It does not depend on the journal.

## Reset & changed semantics

`reset` reverts **omaset's override** — it removes what omaset wrote and lets the
Omarchy stock default re-emerge. It does not store snapshots: `read_default`
recomputes the default from Omarchy's shipped config on every call.

- `changed` diffs the *effective* value (as read from your config) against that
  stock default, so it sees changes made by hand-editing, `omarchy` commands, or
  hotkeys too. In the settings window, press `c` to open a "Changed" list of
  every differing setting (value → default); Enter jumps to it.
- A setting can declare its own `default` when the backend cannot recompute one —
  the `omarchy` passthrough toggles (`nightlight`, `window-no-gaps`,
  `single-window-square`) declare `default = false` so they participate in
  `changed` too.
- `hypr-lua` writes into a managed `-- omaset:begin/end` block, so `reset` only
  removes omaset's block. A hand-written `hl.config(...)` override elsewhere in
  the file is left alone (and would take effect again). To restore *everything*
  to stock, use `omarchy refresh hyprland`.
- `workspace-layout` shares storage with `omarchy hyprland workspace layout
  toggle` (Super+L) — the same `~/.local/state/omarchy/workspace-layouts/*.lua`
  files — so the two are coherent. `reset workspace_layout <n>` deletes one rule;
  `reset workspace_layout --all` clears every persisted rule, including
  workspaces that are not currently open.
