# Proposal: adopt Omaset as Omarchy 4.6's settings surface

**Repository:** https://github.com/b2amedina/omaset  
**Marketplace verify issue:** https://github.com/omacom/omarchy-plugin-marketplace/issues/14562  
**Current master commit:** `440e51589aa1299b7665353cef4f64047672481a`  
**X posts:** (add permalinks here)  
**Demo video:** https://raw.githubusercontent.com/b2amedina/omaset/master/media/omaset-0.3.0-demo.mp4 (36s walkthrough)

---

## Problem

Omarchy's settings are plain text files. That is a strength for version control and hand-editing, but it creates three gaps:

1. **Agents have no contract.** An agent must parse dotfiles, guess formats, and risk breaking comments or hand-edits.
2. **Humans have no safe surface.** Discovery is grep, changes are manual, and recovery is "hope you remember what you changed."
3. **Some workflows are not exposed at all.** Screenshots (Omasnap) and per-URL browser routing (Browsers) are configurations Omarchy never shipped as commands, so they cannot be managed through the menu.

`omarchy-menu` and `omarchy-launch-config-editor` cover toggles and raw editing, but they do not provide search, validation, undo, or an agent-facing contract.

## Proposal

Adopt **Omaset** as Omarchy 4.6's settings surface.

Omaset does not replace Omarchy's config files — they remain the source of truth. Omaset reads and writes them in place, preserving comments and hand-edits. It exposes the same settings through three faces, with the agent first:

1. **Agent (MCP)** — the primary interface. An agent calls typed tools (`schema`, `search`, `get`, `set`, `reset`, `changed`, `help`, `keys`, `undo`, `history`, preferences) instead of parsing files.
2. **CLI** — `omaset get`, `set`, `changed`, `undo`, `help`, `search`, `keys`, and `omaset browser …` for scripts and automation.
3. **Human (keyboard-first window)** — a searchable, content-sized settings window that uses Omarchy styling, vim keys, exact-value editing, and a `?` help overlay.

The same core backs all three, so the agent, the terminal, and the window always agree on what a setting is and what it is set to.

## Why 4.6

Omarchy 4.5 introduced a desktop that feels familiar to people coming from Windows or macOS. Omaset does the same for settings: a view for humans, while the agent keeps working directly with the files.

Omaset is already 4.5-ready, capability-detected (pre-4.5 installs keep working), and speaks all 50 Omarchy languages. It is a natural next step for 4.6: make settings as approachable as the desktop.

## Beyond toggles

Omaset is not only for flipping values. It manages how things work together and surfaces what Omarchy does not expose:

- **Screenshots (Omasnap)** — editor mode, window, backdrop, autosave, screenshot directory and filename pattern. These are settings Omarchy never shipped as commands.
- **Browsers** — default browser plus per-URL browser routing. If multiple browsers are installed, Omaset routes URLs to the right one and prompts when it cannot decide. Rules key on the stable browser id; labels are optional.
- **Defaults** — agent, terminal, editor, dictation, wrapping Omarchy's `omarchy-default-*` commands, with custom values written to the store each command reads.

## Safety

- **In-place edits.** Omaset edits the value where it already lives. Comments and hand-edits survive.
- **Validated before it lands.** Every write is validated against the live config. If Hyprland will not load it, Omaset puts it back.
- **Reversible.** `changed` shows what differs from stock, `history` shows how it got there, `undo` takes it back. A one-time `.omaset.bak` snapshot supports `rollback`.
- **No permission regressions.** File writes use `mktemp` (exclusive, `0600` from creation), carry an existing target's mode over to the replacement, and report write/close/rename failures instead of claiming success.
- **Bounded subprocesses.** Every subprocess runs under GNU `timeout` with a process group, captures into a `0600` temp file, and caps output. The RPC server wraps each request in a deadline.

## Custom values are first-class

Types check type and range only. Enums accept any string; the backend's `validate` hook decides. Reads never drop a value — an unrecognized value reads back as stored and is offered as a `Custom` choice, so it can be selected again. Re-setting the current value is a no-op, and `undo` no longer skips a value merely because it is not a declared option.

This means hand-edited configs are respected, not overwritten or blanked.

## Keyboard-first

The window is keyboard-first and uses Omarchy styling:

- `j`/`k` (or arrows) move between settings or sidebar panels
- `h`/`l` (or arrows) adjust sliders or cycle controls
- `Tab`/`Shift+Tab` switch sidebar/content pane
- `Space`/`Enter` activate or edit
- `/` search any setting
- `c` changed list, `p` preferences, `x` reset, `Esc` close

On a slider or time row, press `Enter`, type a value, press `Enter` again. `Esc` cancels.

## Extensibility

Omaset is built on one small core and a set of backends that share a common interface. The engine never needs to know configuration details. A backend self-registers from `lib/omaset/backends/` and implements read/write/validate for its area.

Add a setting or a backend, and the window, the CLI, and the agent all pick it up. That is the whole design.

## Internationalization

Every label, description, and option in all 50 Omarchy languages. Right-to-left mirroring for Arabic, Persian, Hebrew, and Urdu. Search matches the resolved language's labels, descriptions, titles, and option labels, folding case and diacritics. JSON and MCP output stay English (the stable contract).

## Integration path (low-risk)

**Phase 1 — Blessed plugin in 4.6 (recommended first step)**
- Ship Omaset as a default-enabled plugin with Omarchy 4.6.
- Proves adoption and gathers real-world feedback without a large core merge.

**Phase 2 — Monorepo integration (if accepted)**
- Migrate under Omarchy conventions:
  - `omarchy-` command naming or a new `omarchy settings` group
  - `$OMARCHY_PATH` instead of `HOME`-derived paths
  - Omarchy's i18n system instead of parallel catalogs
  - Oligarchy acceptance tests + unit tests
  - Migrations for existing configs (in-place, comment-preserving)
  - Packaging and platform support (x86 + all aarch64 families)

**Phase 3 — Default entry point**
- Make Omaset the default "Settings" route from `omarchy-menu`, replacing raw config editing for common tasks while keeping `omarchy-launch-config-editor` for advanced users.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Lua 5.1 runtime** | Justify the dependency (Omaset already ships as a plugin with it) or reimplement the core in bash/Quickshell during Phase 2. |
| **Overlap with `omarchy-menu` / config editor** | Position Omaset as the safe/searchable/agent surface, not a duplicate GUI. Raw editing remains available. |
| **Scope** | Phase 1 is a blessed plugin, not a core merge. Phase 2 breaks into reviewable PRs. |
| **i18n burden** | Phase 2 migrates to Omarchy's translation pipeline; 50 catalogs are already validated by `tests/test_i18n.sh`. |
| **Security** | Automated validation + security baseline passed (only `privilege` capability, expected for browser install at `lib/omaset/browser.lua:54`). Four buckets (permissions, subprocess bounds, worker lifecycle, input boundaries) are covered by the test suite. |
| **Maintenance** | Backends are self-registering and share one interface; new areas land without core changes. |

## Demo

https://raw.githubusercontent.com/b2amedina/omaset/master/media/omaset-0.3.0-demo.mp4 — 36s: intro → Browsers → Screenshot → Power & Idle → Changed → CLI → help → value prop. (GitHub may not inline-play MP4; download or open in a new tab.)

## Links

- **Repository:** https://github.com/b2amedina/omaset
- **Marketplace verify issue:** https://github.com/omacom/omarchy-plugin-marketplace/issues/14562
- **Current commit:** `440e51589aa1299b7665353cef4f64047672481a`
- **X posts:** (add permalinks here)
- **Demo video:** https://raw.githubusercontent.com/b2amedina/omaset/master/media/omaset-0.3.0-demo.mp4 (36s walkthrough)

## Ask

Adopt Omaset as a **blessed, default-enabled plugin in Omarchy 4.6**, with a path to full integration in 4.7+. This gives Omarchy a settings surface that is safe, searchable, keyboard-first, agent-accessible, and extensible — without abandoning the config-file philosophy that makes Omarchy transparent.
