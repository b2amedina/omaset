#!/usr/bin/env bash
# `omaset mcp install` / `omaset mcp doctor`: wire the server into each agent's
# MCP config (merging, idempotently) and report status. Run against a scratch
# HOME so the real user config is never touched.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

export HOME="$TESTDIR/home"
export XDG_CONFIG_HOME="$TESTDIR/config"
mkdir -p "$HOME"

OC="$XDG_CONFIG_HOME/opencode/opencode.json"
CLAUDE="$HOME/.claude.json"
GEMINI="$HOME/.gemini/settings.json"
COPILOT="$HOME/.copilot/mcp-config.json"
CODEX="$HOME/.codex/config.toml"

# No argument wires every supported agent.
capture_out mcp install
assert_exit "$CODE" 0 "install (all) exits 0"
for f in "$OC" "$CLAUDE" "$GEMINI" "$COPILOT" "$CODEX"; do
  [[ -f "$f" ]] || fail "install did not create $f"
done

# opencode uses the `mcp` key with a command array.
assert_eq "$(jq -r '.mcp.omaset.command[0]' "$OC")" "omaset" "opencode command"
assert_eq "$(jq -r '.mcp.omaset.command[1]' "$OC")" "mcp" "opencode args"
assert_eq "$(jq -r '.mcp.omaset.enabled' "$OC")" "true" "opencode enabled"

# The others use `mcpServers` with command + args.
assert_eq "$(jq -r '.mcpServers.omaset.command' "$CLAUDE")" "omaset" "claude command"
assert_eq "$(jq -r '.mcpServers.omaset.args[0]' "$CLAUDE")" "mcp" "claude args"
assert_eq "$(jq -r '.mcpServers.omaset.command' "$GEMINI")" "omaset" "gemini command"
assert_eq "$(jq -r '.mcpServers.omaset.command' "$COPILOT")" "omaset" "copilot command"

# codex gets an idempotent TOML section.
assert_contains "$(cat "$CODEX")" "[mcp_servers.omaset]" "codex section"
assert_contains "$(cat "$CODEX")" 'args = ["mcp"]' "codex args"

# An existing config is merged, not clobbered.
printf '{"model":"x","mcp":{"other":{"command":"y"}}}\n' > "$OC"
capture_out mcp install opencode
assert_eq "$(jq -r '.model' "$OC")" "x" "install preserves existing keys"
assert_eq "$(jq -r '.mcp.other.command' "$OC")" "y" "install preserves sibling entries"
assert_eq "$(jq -r '.mcp.omaset.command[0]' "$OC")" "omaset" "install merges omaset entry"

# Re-installing is idempotent (no duplicate codex section).
capture_out mcp install codex
assert_contains "$OUT" "already configured" "codex reports already configured"
assert_eq "$(grep -c '\[mcp_servers.omaset\]' "$CODEX")" "1" "codex section not duplicated"

# doctor reports each wired agent ok and exits 0.
capture_out mcp doctor
assert_exit "$CODE" 0 "doctor exits 0 when wired"
assert_contains "$OUT" "opencode   ok" "doctor reports opencode ok"
assert_contains "$OUT" "codex      ok" "doctor reports codex ok"

# doctor exits 1 and reports no ok when nothing is wired.
rm -rf "$HOME" "$XDG_CONFIG_HOME"
mkdir -p "$HOME"
capture_out mcp doctor
assert_exit "$CODE" 1 "doctor exits 1 when nothing wired"
assert_not_contains "$OUT" "ok" "doctor reports nothing ok"

# An unknown agent name is rejected and install fails.
capture mcp install bogus
assert_contains "$OUT" "unknown agent 'bogus'" "unknown agent is rejected"
assert_exit "$CODE" 1 "unknown agent exits 1"

echo "ok"
