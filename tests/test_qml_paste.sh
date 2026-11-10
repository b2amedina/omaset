#!/usr/bin/env bash
# Every value editor must go through ui/components/ValueField.qml, which blocks
# the native paste paths before Qt reaches the clipboard. A raw TextField or
# TextInput anywhere else in ui/ reintroduces the unbounded paste read.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

value_field="$ROOT/ui/components/ValueField.qml"
[[ -f "$value_field" ]] || fail "missing $value_field"

# The wrapper itself is the one place a TextField is allowed.
offenders="$(grep -rlE '\b(TextField|TextInput)\b' "$ROOT/ui" --include='*.qml' \
  | grep -vxF "$value_field" || true)"
if [[ -n "$offenders" ]]; then
  fail "raw TextField/TextInput outside ValueField.qml: $(echo "$offenders" | tr '\n' ' ')"
fi

# And it must actually block paste: every keyboard paste path (StandardKey.Paste
# covers Ctrl+V, Shift+Insert, the dedicated Paste key, and platform bindings)
# plus the middle/right mouse buttons that drive primary-selection and
# context-menu paste.
grep -q 'StandardKey\.Paste' "$value_field" || fail "ValueField.qml does not block keyboard paste"
grep -q 'Qt.MiddleButton' "$value_field" || fail "ValueField.qml does not block middle-click paste"

echo "ok"
