# Changelog

## 0.3.0 — 2026-11-11

- Top-bar settings icon tooltip now reads "Omarchy Settings" instead of "omaset Settings".
- `tiled_fullscreen_style` gains a `rounding` subsetting, so tiled full-screen windows
  can have corner radius like full-width windows.
- New `scripts/omaset-defaults` helper applies preferred window styling (full-width
  border/rounding 4, tiled full-screen border 4/rounding 0) and ensures the bar
  widget is present on the right when missing.
- README documents that the bar widget is enabled automatically with `--enable`
  and how to run the defaults helper.
- i18n: translated the omasnap settings keys and the new tiled-fullscreen rounding
  keys across all 50 language catalogs (not just English fallbacks).
- Custom values are first-class: an enum accepts any string and validation is
  the backend's job. Reads never drop a value — an unrecognized value reads
  back as stored and is offered as a "Custom" choice, so it can be selected
  again. Re-setting the current value is a no-op, and undo no longer skips a
  value merely because it isn't a declared option.
- New Defaults panel wraps Omarchy's default-application commands (agent,
  browser, terminal, editor, dictation). Declared values go through the
  omarchy-default-* command; custom values are written to the store that
  command reads. Reset restores the provisioned state — browser reset sets
  chromium.desktop via xdg-settings and never installs.
- New Browsers panel: the default browser plus a browser-router config panel
  (browser list, labels, domain routing rules), translated across all 50
  language catalogs. omaset owns the JSON config and browser-router is a thin
  wrapper; rules key on the stable browser id and show the label (or name) in
  the UI. Search matches rule domains, and the hidden browser_* settings stay
  in the schema for CLI/MCP (tracked=false).
- The browser-router section is editable only while "Browser router" is the
  default browser; otherwise it is dimmed and keyboard navigation skips it.
  Disabled rows are generic (schema disabledWhen drives row interactivity
  app-wide) and re-evaluate immediately when the default changes.
- After any selection, keyboard focus returns to the row so j/k/h/l keep
  navigating, and a dropdown can no longer leave the key catcher blocked when
  its row is rebuilt mid-selection.
- Marketplace listing refreshed: the description now leads with the treasure-hunt
  hook and the "Omarchy way, made visible" line; the README top section is
  rewritten in DHH voice and frames Omaset as surfacing what Omarchy hides and
  orchestrating how tools work together; preview.png is recaptured from the
  settings window.


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
- The output cap now uses POSIX 512-byte `ulimit -f` blocks (it was sizing for
  1024-byte blocks, so `max_bytes` actually capped at half the requested size)
  and truncation is now actually detected. The test suite's intentional
  overshoot probe sets `OMASET_IGNORE_XFSZ` so it doesn't dump core and trip a
  "Process crashed" notification; in production a capped producer still dies
  with SIGXFSZ as the real error.
- Search is now language-aware: it matches the resolved language's labels,
  descriptions, panel and section titles, and option labels in addition to the
  English source strings, folding case and diacritics (`écart` finds `Écart`).
  The window passes its own language so `omaset ui --lang fr` searches French,
  and the result payload stays English-keyed for the machine contract.
- The RPC worker's failed-start settlement is quickshell 0.3.2-compatible: it
  settles the pre-start queue via `onRunningChanged` (which fires when a failed
  start flips `running` back to false), since 0.3.2's `Process` has no
  `errorOccurred` signal.

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
