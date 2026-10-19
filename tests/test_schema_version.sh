#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The engine and the settings window ship as one plugin but live in separate
# files: the engine stamps `schema` with M.SCHEMA_VERSION, and ui/Panel.qml
# declares the version it knows how to render. If the two drift apart the window
# refuses its own bundled engine, so keep them in lockstep here.
ENGINE="$(run schema | jq -r '.schemaVersion')"
WINDOW="$(sed -n 's/.*supportedSchemaVersion:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
  "$ROOT/ui/Panel.qml" | head -1)"

assert_eq "$ENGINE" "1" "engine schema version is the supported one"
assert_eq "$WINDOW" "$ENGINE" "window supports the engine's schema version"

echo "ok"
