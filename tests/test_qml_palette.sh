#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

mapfile -t offenders < <(grep -rlE '(^|[^.[:alnum:]_])Color\.' "$ROOT/ui" --include='*.qml' || true)
if (( ${#offenders[@]} > 0 )); then
  fail "unqualified Color.* reference; use Commons.Color.*: ${offenders[*]}"
fi

while IFS= read -r file; do
  grep -qx 'import qs\.Commons as Commons' "$file" \
    || fail "$file uses Commons.Color.* without 'import qs.Commons as Commons'"
done < <(grep -rl 'Commons\.Color\.' "$ROOT/ui" --include='*.qml')

echo "ok"
