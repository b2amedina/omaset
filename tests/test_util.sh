#!/usr/bin/env bash
# util.run_capture: Lua 5.1's pclose() returns true for *any* exit status, so
# the helper must surface the real code through the pipe. These cases pin the
# exit code and the merged stdout+stderr down.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
export ROOT

# Runs a command through util.run_capture; writes the exit code to
# $PROBE_CODE_FILE and the captured output to stdout.
run_probe() {
  PROBE_CODE_FILE="$PROBE_CODE_FILE" lua5.1 - "$1" <<'LUA'
local cmd = arg[1]
package.path = os.getenv("ROOT") .. "/lib/?.lua;" .. os.getenv("ROOT") .. "/lib/?/init.lua;" .. package.path
local util = require("omaset.util")
local out, code = util.run_capture(cmd)
local f = io.open(os.getenv("PROBE_CODE_FILE"), "w")
f:write(tostring(code))
f:close()
io.write(out)
LUA
}

# Assert both the exit code and the captured output for a command whose output
# is predictable.
assert_both() {
  local cmd="$1" want_code="$2" want_out="$3"
  local cf="$TESTDIR/run_capture.code" out
  : > "$cf"
  out="$(PROBE_CODE_FILE="$cf" run_probe "$cmd")"
  assert_eq "$(cat "$cf")" "$want_code" "run_capture exit code for: $cmd"
  assert_eq "$out" "$want_out" "run_capture output for: $cmd"
}

assert_both "exit 0"                0 ""
assert_both "exit 7"                7 ""
assert_both "printf hello"          0 "hello"
assert_both "echo err >&2"          0 "err"
assert_both "printf 'a\nb\n' | grep b" 0 "b"
assert_both "echo boom; exit 3"     3 "boom"

# A missing command is exit 127 (its message goes to the merged output, which
# varies by shell, so only the code is asserted).
cf="$TESTDIR/run_capture.code"
: > "$cf"
PROBE_CODE_FILE="$cf" run_probe "omaset_no_such_command" > /dev/null
assert_eq "$(cat "$cf")" "127" "run_capture reports command-not-found"

echo "ok"
