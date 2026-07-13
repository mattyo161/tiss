#!/usr/bin/env bash
# Tests for lib/rmafter.sh — scheduling, reaping, monitor lifecycle, allowlist.
. "$(dirname "$0")/harness.sh"

export TISS_RMAFTER_INTERVAL=1

# Schedule creates an epoch-prefixed symlink.
f1="$TISS_TEST_TMP/doomed.txt"
echo x >"$f1"
rmAfter 1h "$f1"
links="$(find "$TISS_STATE/rmAfter" -type l | wc -l | tr -d ' ')"
assertEq "schedule creates symlink" 1 "$links"

# Monitor is alive and pidfile tracks the real process.
sleep 0.3
pid="$(cat "$TISS_STATE/rmAfter/.monitor.pid" 2>/dev/null)"
kill -0 "$pid" 2>/dev/null && _report ok "monitor running with live pid" || _report FAIL "pidfile pid $pid not running"

# Second schedule reuses the monitor.
f2="$TISS_TEST_TMP/doomed2.txt"
echo y >"$f2"
rmAfter 1h "$f2"
pid2="$(cat "$TISS_STATE/rmAfter/.monitor.pid")"
assertEq "no duplicate monitor" "$pid" "$pid2"

# Past-due entries are reaped on the next rmAfter call.
f3="$TISS_TEST_TMP/pastdue.txt"
echo z >"$f3"
ln -s "$f3" "$TISS_STATE/rmAfter/1.999.0.1"
f4="$TISS_TEST_TMP/later.txt"
echo w >"$f4"
rmAfter 1h "$f4"
assertFileMissing "past-due reaped on schedule call" "$f3"

# On-time deletion by the monitor.
f5="$TISS_TEST_TMP/ontime.txt"
echo v >"$f5"
rmAfter 1s "$f5"
sleep 2.5
assertFileMissing "monitor deletes on time" "$f5"

# Monitor retires when nothing remains.
find "$TISS_STATE/rmAfter" -type l -delete
sleep 2.5
kill -0 "$pid" 2>/dev/null && _report FAIL "monitor still running when idle" || _report ok "monitor retires when idle"
assertFileMissing "pidfile cleaned on retire" "$TISS_STATE/rmAfter/.monitor.pid"

# Guards.
assertExit "rejects directories" 2 rmAfter 1h "$TISS_TEST_TMP"
assertExit "rejects bad duration" 2 rmAfter bogus "$f1"

# Allowlist: schedule-time rejection.
assertExit "rejects path outside allowlist" 2 rmAfter 1h /etc/hosts

# Allowlist: reap-time refusal (planted symlink). /Users/Shared and /opt are
# outside home+tmp on macOS/linux respectively; use whichever is writable.
victim=""
for cand in /Users/Shared /opt/tmp-tiss-test; do
  mkdir -p "$cand" 2>/dev/null || continue
  [ -w "$cand" ] && victim="$cand/tiss-victim.txt" && break
done
if [ -n "$victim" ]; then
  echo victim >"$victim"
  mkdir -p "$TISS_STATE/rmAfter"
  ln -s "$victim" "$TISS_STATE/rmAfter/1.888.0.1"
  tissReapRmAfter
  assertFileExists "planted symlink target survives" "$victim"
  assertFileMissing "planted schedule dropped" "$TISS_STATE/rmAfter/1.888.0.1"
  rm -f "$victim"
else
  echo "  skip: no writable out-of-allowlist location" >&2
fi

# Custom allowlist.
tmpf="$TISS_TEST_TMP/custom.txt"
echo c >"$tmpf"
assertExit "custom TISS_RMAFTER_PATHS blocks tmp" 2 env TISS_RMAFTER_PATHS="$HOME/nowhere" "$TISS_BIN" rmAfter 1h "$tmpf"

# Cleanup any monitor spawned by later schedules.
mpid="$(cat "$TISS_STATE/rmAfter/.monitor.pid" 2>/dev/null)" && kill "$mpid" 2>/dev/null
finish
