#!/usr/bin/env bash
# Run every test_*.sh in this directory, reporting a pass/fail summary.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/tests"

failures=0
count=0

for t in test_*.sh; do
  count=$((count + 1))
  if bash "$t" > /tmp/omaset-test.out 2>&1; then
    echo "PASS  $t"
  else
    echo "FAIL  $t"
    sed 's/^/      /' /tmp/omaset-test.out
    failures=$((failures + 1))
  fi
done

echo
echo "$((count - failures))/$count passed"
rm -f /tmp/omaset-test.out

exit $((failures > 0 ? 1 : 0))
