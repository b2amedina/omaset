# Shared helpers for omaset tests. Sourced by each test_*.sh.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OMASET="$ROOT/bin/omaset"
FIXTURES="$ROOT/tests/fixtures/omarchy"

# Each test file gets its own scratch directory, isolated from the real system
# and from every other test.
TESTDIR="$(mktemp -d)"
trap 'rm -rf "$TESTDIR"' EXIT

export OMARCHY_PATH="$FIXTURES"
export OMASET_NO_APPLY=1
export OMASET_HYPR_DIR="$TESTDIR/hypr"
export OMASET_SHELL_CONFIG="$TESTDIR/shell.json"
export OMASET_HYPRSUNSET_CONFIG="$TESTDIR/hyprsunset.conf"
export OMASET_SETTINGS_DIR="$TESTDIR/settings"
export OMASET_BACKENDS_DIR="$TESTDIR/backends"
export OMASET_JOURNAL="$TESTDIR/journal.jsonl"
mkdir -p "$OMASET_HYPR_DIR" "$OMASET_SETTINGS_DIR" "$OMASET_BACKENDS_DIR"

# Run omaset, stdout to the caller.
run() {
  luajit "$OMASET" "$@"
}

# Run omaset, capturing merged stdout+stderr into $OUT and exit code into $CODE.
capture() {
  OUT="$(luajit "$OMASET" "$@" 2>&1)"
  CODE=$?
}

# Run omaset, capturing stdout only into $OUT and exit code into $CODE.
capture_out() {
  OUT="$(luajit "$OMASET" "$@" 2>/dev/null)"
  CODE=$?
}

fail() {
  echo "  FAIL: $*" >&2
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "${3:-assert_eq}: want [$2] got [$1]"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "${3:-assert_contains}: [$2] not in output"
}

assert_not_contains() {
  [[ "$1" != *"$2"* ]] || fail "${3:-assert_not_contains}: [$2] unexpectedly in output"
}

assert_exit() {
  [[ "$1" -eq "$2" ]] || fail "${3:-assert_exit}: want exit $2 got $1"
}
