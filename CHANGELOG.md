# Changelog

## 0.2.3 — 2026-11-10

- Marketplace listing refreshed: the description now leads with the concrete
  window/CLI/MCP line, the slogan moves to the banner, the preview image drops
  prose entirely, and the copy swaps "undoable" for "checked before it lands".
- `shell.json` is no longer rewritten through its own `> .tmp` + `mv` dance.
  The jq pipeline's output is validated as a whole JSON document and committed
  through the shared `util.write_file()` atomic writer, so a private
  `0600` shell.json can no longer be widened to `0644` under a permissive umask,
  and no `shell.json.tmp` sibling is ever left next to the config.
- `run_capture` now bounds every subprocess: it runs under GNU `timeout`
  (which signals the whole process group) so a hung dependency cannot block the
  worker, captures into a `mktemp` file that is `0600` from creation instead of
  `os.tmpname()`'s world-readable file, and caps the output it reads back. The
  RPC server wraps each request in a deadline that every subprocess spends from,
  so a `snapshot` fanning out into many reads cannot stall past its budget.
- The settings window rejects RPC requests that outlive their deadline and
  restarts the `omaset rpc` worker rather than replaying an uncertain write.
  The pre-start queue is bounded, a failed start settles queued work, and a
  worker that ignores SIGTERM is killed after a grace period before its
  replacement starts. Failed writes revert their optimistic value and surface a
  transient notice in the footer instead of silently leaving the row wrong.
- Numeric and time editors go through one `ValueField` component that blocks
  every native paste path — StandardKey.Paste (Ctrl+V, Shift+Insert, the
  dedicated Paste key, and platform bindings) plus middle/right click — before
  Qt's unbounded clipboard read can stall the shell's GUI thread.
- Settings writes no longer touch file permissions: `util.write_file()` creates
  its temporary file with `mktemp` (exclusive, unpredictable name, already
  `0600` before any content is written), carries an existing target's mode over
  to the replacement, and reports write, close, and rename failures instead of
  claiming success. A private file rewritten by omaset can no longer end up
  group- or world-readable.
- `omaset mcp install` registers the server through each agent's own `mcp add`
  subcommand instead of rewriting its config file, so the agent keeps ownership
  of its format, scope, and file permissions (rewriting `~/.claude.json` through
  a temp file used to widen it from `0600` to `0644`). Agents whose CLI is not
  installed are skipped rather than given a config file they never asked for.
- `run_capture` now returns real exit codes on Lua 5.1, whose `pclose()`
  reports success for any status; failed `jq`, `hyprctl`, and `omarchy` calls
  were previously reported as successes.

## 0.2.1 — 2026-11-09

- Speaks all 50 Omarchy languages — every label, description, and option.
- A `--lang <code>` / `OMASET_LANGUAGE` override; JSON and MCP output stay English.
- Right-to-left mirroring for Arabic, Persian, Hebrew, and Urdu.
- The settings view scrolls when you wheel over a slider.
- New `scripts/i18n-extract` extractor and `tests/test_i18n.sh` validation.
- Localization guide and per-release checklist in `docs/i18n.md`.

## 0.2.0 — 2026-11-08

- Omarchy 4.5 support — floating workspaces, per-monitor workspace blocks,
  window corners, the dock, and the new bar background.
- Capability detection instead of a version check, so pre-4.5 installs keep
  working.
- Edit in place — no more managed `-- omaset:begin/end` blocks; comments and
  hand-edits stay put.
- Readable idle presets — `5 min`, `1 hour`, … instead of raw seconds.
- Dropdowns for many-choice settings, with a labelled Custom entry for
  off-preset values.
- A night-light schedule with start/stop times and a temperature.
- Time values accept both `HH:MM` and `h:mm AM/PM`.
- A `time_format` preference — 24h, 12h, or follow the bar clock.
- One shared core for the MCP server, the settings window, and the CLI.
- Preferences and normalized time values exposed over MCP.
- Full Spanish (es-MX) localization.
- A content-sized settings window that respects your screen.
- A `?` keybindings help overlay.
- Exact-value editing on sliders and time rows.
- Preserve legacy (pre-4.5) enum values instead of blanking them.
- Fixed Qt 6.12 palette colors; group sliders show their real values; keyed
  settings prefetch.

## 0.1.0 — 2026-10-18

Initial release.
