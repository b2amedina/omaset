#!/usr/bin/env bash
# A dropdown emits its option value as a string. DropdownRow must map that back
# to the stored value before committing; committing Number(v) turns string
# tokens (vim, claude, chromium) into NaN and the write fails.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

row="$ROOT/ui/components/DropdownRow.qml"
[[ -f "$row" ]] || fail "missing $row"

grep -q 'Number(v)' "$row" && fail "DropdownRow.qml commits Number(v); string tokens would become NaN"
grep -q 'String(vals\[i\]) === v' "$row" || fail "DropdownRow.qml does not map the emitted value back to row.values"
grep -q 'root.panel.commit(root.row, val)' "$row" || fail "DropdownRow.qml does not commit the mapped value"

echo "ok"
