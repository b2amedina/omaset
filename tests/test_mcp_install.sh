#!/usr/bin/env bash
# `omaset mcp install` / `omaset mcp doctor`: registration goes through each
# agent's own `mcp add` subcommand, so omaset never writes another tool's config
# (and never has to reproduce its format, scope, or file permissions). The fakes
# below record the exact argv omaset passes and write the entry the real CLI
# writes; nothing here touches a real agent config.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

export HOME="$TESTDIR/home"
export XDG_CONFIG_HOME="$TESTDIR/config"
export CALLS="$TESTDIR/calls"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$CALLS"

BIN="$TESTDIR/bin"
mkdir -p "$BIN"
# A PATH without the real agent CLIs: removing a fake below must not fall
# through to an installed claude/codex/... and write a real config.
export PATH="$BIN:/usr/local/bin:/usr/bin:/bin"

CLAUDE="$HOME/.claude.json"
GEMINI="$HOME/.gemini/settings.json"
COPILOT="$HOME/.copilot/mcp-config.json"
CODEX="$HOME/.codex/config.toml"
OC="$XDG_CONFIG_HOME/opencode/opencode.json"

# write_fake <agent> < heredoc: the fake's body, appended to the argv record.
write_fake() {
  local name="$1"
  mkdir -p "$BIN"
  cat > "$BIN/$name"
  chmod +x "$BIN/$name"
}

write_fake claude <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS/claude"
[[ -n "${FAKE_FAIL:-}" ]] && { echo "claude: simulated failure" >&2; exit 3; }
[[ -n "${FAKE_NO_WRITE:-}" ]] && exit 0
f="$HOME/.claude.json"
mkdir -p "$(dirname "$f")"
umask 077
printf '{"mcpServers":{"omaset":{"command":"omaset","args":["mcp"]}}}\n' > "$f"
EOF

write_fake codex <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS/codex"
[[ -n "${FAKE_FAIL:-}" ]] && { echo "codex: simulated failure" >&2; exit 3; }
f="$HOME/.codex/config.toml"
mkdir -p "$(dirname "$f")"
printf '[mcp_servers.omaset]\ncommand = "omaset"\nargs = ["mcp"]\n' > "$f"
EOF

write_fake gemini <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS/gemini"
[[ -n "${FAKE_FAIL:-}" ]] && { echo "gemini: simulated failure" >&2; exit 3; }
f="$HOME/.gemini/settings.json"
mkdir -p "$(dirname "$f")"
printf '{"mcpServers":{"omaset":{"command":"omaset","args":["mcp"]}}}\n' > "$f"
EOF

# copilot refuses a duplicate entry instead of updating it (that is what the
# real CLI does), so `install` must treat that as "already configured".
write_fake copilot <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS/copilot"
f="$HOME/.copilot/mcp-config.json"
if grep -q omaset "$f" 2>/dev/null; then
  echo 'Error: Server "omaset" already exists.' >&2
  exit 1
fi
mkdir -p "$(dirname "$f")"
printf '{"mcpServers":{"omaset":{"command":"omaset","args":["mcp"]}}}\n' > "$f"
EOF

write_fake opencode <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CALLS/opencode"
[[ -n "${FAKE_FAIL:-}" ]] && { echo "opencode: simulated failure" >&2; exit 3; }
f="$XDG_CONFIG_HOME/opencode/opencode.json"
mkdir -p "$(dirname "$f")"
printf '{"mcp":{"servers":{"omaset":{"type":"local"}}}}\n' > "$f"
EOF

# No argument wires every supported agent, each through its own CLI.
capture mcp install
assert_exit "$CODE" 0 "install (all) exits 0"
for name in claude codex copilot gemini opencode; do
  [[ -f "$CALLS/$name" ]] || fail "install did not call $name"
done

assert_eq "$(cat "$CALLS/claude")" "mcp add -s user omaset -- omaset mcp" "claude argv"
assert_eq "$(cat "$CALLS/codex")" "mcp add omaset -- omaset mcp" "codex argv"
assert_eq "$(cat "$CALLS/copilot")" "mcp add omaset -- omaset mcp" "copilot argv"
assert_eq "$(cat "$CALLS/gemini")" "mcp add -s user omaset omaset mcp" "gemini argv"
assert_eq "$(cat "$CALLS/opencode")" "mcp add --global omaset -- omaset mcp" "opencode argv"

# omaset leaves the agent's own file byte-for-byte alone: the CLI wrote it, the
# CLI keeps it, mode included.
printf '{"mcpServers":{"omaset":{"command":"omaset"},"other":{"command":"y"}},"secret":1}\n' > "$CLAUDE"
chmod 600 "$CLAUDE"
before_sum="$(cksum < "$CLAUDE")"
before_mode="$(stat -c %a "$CLAUDE")"
FAKE_NO_WRITE=1 capture mcp install claude
assert_exit "$CODE" 0 "install exits 0 when the CLI succeeds"
assert_eq "$(cksum < "$CLAUDE")" "$before_sum" "install leaves the config untouched"
assert_eq "$(stat -c %a "$CLAUDE")" "$before_mode" "install preserves the config mode"

# Re-installing is idempotent even when the CLI rejects a duplicate entry.
capture_out mcp install copilot
assert_exit "$CODE" 0 "re-install exits 0 when the entry exists"
assert_contains "$OUT" "copilot: already configured" "re-install reports already configured"
assert_eq "$(jq -r '.mcpServers | keys[]' "$COPILOT")" "omaset" "no duplicate copilot entry"

# doctor reports each wired agent ok and exits 0.
capture_out mcp doctor
assert_exit "$CODE" 0 "doctor exits 0 when wired"
assert_contains "$OUT" "claude     ok" "doctor reports claude ok"
assert_contains "$OUT" "opencode   ok" "doctor reports opencode ok"
assert_contains "$OUT" "codex      ok" "doctor reports codex ok"

# doctor reads the current opencode schema (mcp.servers), not the legacy
# mcp.<name> shape that no longer loads.
printf '{"mcp":{"omaset":{"command":["omaset","mcp"]}}}\n' > "$OC"
capture_out mcp doctor
assert_contains "$OUT" "opencode   missing" "doctor ignores the legacy opencode shape"

# doctor exits 1 and reports no ok when nothing is wired.
rm -f "$CLAUDE" "$GEMINI" "$COPILOT" "$CODEX" "$OC"
capture mcp doctor
assert_exit "$CODE" 1 "doctor exits 1 when nothing wired"
assert_not_contains "$OUT" "ok" "doctor reports nothing ok"

# An agent whose CLI is absent is skipped, and no config is invented for it.
rm -f "$BIN/codex"
capture mcp install codex
assert_exit "$CODE" 1 "an absent CLI exits 1"
assert_contains "$OUT" "codex not installed; skipped" "absent CLI is reported"
[[ -e "$CODEX" ]] && fail "install created a config for an absent agent"

# A stale config for an agent whose CLI is gone reports "no cli", not "ok".
printf '[mcp_servers.omaset]\n' > "$CODEX"
capture_out mcp doctor
assert_contains "$OUT" "codex      no cli" "doctor reports no cli when the agent is gone"

# A failing `mcp add` surfaces the CLI's own error and fails the run.
rm -f "$GEMINI"
FAKE_FAIL=1 capture mcp install gemini
assert_exit "$CODE" 1 "a failing mcp add exits 1"
assert_contains "$OUT" "gemini: simulated failure" "the CLI error is surfaced"
assert_contains "$OUT" "gemini mcp add -s user omaset omaset mcp" "the failing command is named"

# An unknown agent name is rejected and install fails.
capture mcp install bogus
assert_contains "$OUT" "unknown agent 'bogus'" "unknown agent is rejected"
assert_exit "$CODE" 1 "unknown agent exits 1"

echo "ok"
