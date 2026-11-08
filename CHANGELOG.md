# Changelog

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
