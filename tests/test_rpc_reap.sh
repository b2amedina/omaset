#!/usr/bin/env bash
# RPC restart must reap the worker and every backend operation it spawned, not
# just the worker's own process group. Backend operations go through
# util.run_capture, which wraps the command in GNU `timeout` WITHOUT
# `--foreground`; timeout then calls setpgid(0,0), putting the command in its
# own process group. A group-only signal (`kill -- -pid`) would miss it. The
# worker runs under `setsid`, so it is a session leader and every descendant —
# including timeout's separate group — shares its session; cleanup must signal
# the whole session (`pkill -s`), which this test exercises against the real
# run_capture wrapper shape.

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

rpcclient="$ROOT/ui/RpcClient.qml"
[[ -f "$rpcclient" ]] || fail "missing $rpcclient"

# --- Static: the client must launch a session leader and reap by session ---
grep -q 'setsid' "$rpcclient" \
  || fail "RpcClient.qml does not launch the worker under setsid"
grep -q 'pkill -TERM -s' "$rpcclient" \
  || fail "RpcClient.qml does not reap by session (pkill -TERM -s)"
grep -q 'pkill -KILL -s' "$rpcclient" \
  || fail "RpcClient.qml has no session-kill escalation (pkill -KILL -s)"
grep -q 'onRunningChanged' "$rpcclient" \
  || fail "RpcClient.qml reaper has no failed-start settlement"

# --- Functional: session kill reaches the run_capture (timeout) group ---
worker_script="$TESTDIR/worker.sh"
child_pidfile="$TESTDIR/child.pid"
cat > "$worker_script" <<EOF
#!/bin/bash
# Mimic util.run_capture: timeout WITHOUT --foreground creates its own group,
# and the command's PID is written out so the test can inspect its PGID/SID.
( ulimit -f 8192 2>/dev/null; timeout -k 3 300 sh -c 'echo \$\$ > "$child_pidfile"; exec sleep 300' ) >/dev/null 2>&1
EOF
chmod +x "$worker_script"

# The worker is a session leader (SID == PID), exactly like the RpcClient launch.
setsid "$worker_script" &
worker_pid=$!
trap 'pkill -KILL -s "$worker_pid" 2>/dev/null' EXIT

# Wait for the worker to spawn its timeout-wrapped command.
for _ in $(seq 1 100); do
  [[ -s "$child_pidfile" ]] && break
  sleep 0.05
done
[[ -s "$child_pidfile" ]] || fail "run_capture-shaped command did not start"
child_pid="$(cat "$child_pidfile")"

# Premise the fix rests on: the timeout group differs from the worker's group,
# but shares the worker's session.
worker_pgid="$(ps -o pgid= -p "$worker_pid" | tr -d ' ')"
child_pgid="$(ps -o pgid= -p "$child_pid" | tr -d ' ')"
worker_sid="$(ps -o sid= -p "$worker_pid" | tr -d ' ')"
child_sid="$(ps -o sid= -p "$child_pid" | tr -d ' ')"
[[ "$worker_sid" == "$child_sid" ]] \
  || fail "run_capture child not in the worker session (SID $worker_sid vs $child_sid)"
[[ "$worker_pgid" != "$child_pgid" ]] \
  || fail "expected timeout to give the command its own process group"

# Reap the worker's session the way RpcClient.qml does: TERM, brief grace, KILL.
pkill -TERM -s "$worker_sid" 2>/dev/null
for _ in $(seq 1 50); do
  pkill -0 -s "$worker_sid" 2>/dev/null || break
  sleep 0.05
done
pkill -KILL -s "$worker_sid" 2>/dev/null

sleep 0.3
if pkill -0 -s "$worker_sid" 2>/dev/null; then
  fail "session $worker_sid still alive after reaping"
fi

echo "ok"
