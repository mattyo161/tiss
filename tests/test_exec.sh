#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for lib/exec.sh — learnExec sanitization and cacheExec behavior.
. "$(dirname "$0")/harness.sh"

# Sanitizer.
assertEq "flag value redacted" "mysql --password REDACTED -h db" \
  "$(tissSanitizeCmd mysql --password hunter2 -h db)"
assertEq "flag=value redacted" "curl --token=REDACTED" \
  "$(tissSanitizeCmd curl --token=abc123)"
assertEq "env-style pair redacted" "run TOKEN=REDACTED ok" \
  "$(tissSanitizeCmd run TOKEN=abc ok)"
assertEq "aws access key redacted" "aws REDACTED" \
  "$(tissSanitizeCmd aws AKIAIOSFODNN7EXAMPLE)"
assertEq "normal args untouched" "git clone repo" \
  "$(tissSanitizeCmd git clone repo)"

# learnExec: [LEARN] on stderr, real argv runs, history logged.
out="$(learnExec echo --password real-secret 2>/dev/null)"
assertEq "learnExec runs real argv" "--password real-secret" "$out"
err="$(learnExec echo --password real-secret 2>&1 >/dev/null)"
assertMatch "learnExec redacts display" 'LEARN.*--password REDACTED' "$err"
assertMatch "history log written" '--password REDACTED' "$(cat "$TISS_STATE/history.log")"
assertExit "learnExec passes exit status" 1 learnExec false
assertExit "learnExec usage error" 2 learnExec

# cacheExec: miss then hit.
first="$(cacheExec bash -c 'echo "r=$RANDOM"' 2>/dev/null)"
second="$(cacheExec bash -c 'echo "r=$RANDOM"' 2>/dev/null)"
assertEq "cache hit returns identical output" "$first" "$second"

# --refresh forces rerun.
third="$(cacheExec --refresh bash -c 'echo "r=$RANDOM"' 2>/dev/null)"
[ "$first" != "$third" ] && _report ok "--refresh reruns" || _report FAIL "--refresh returned cached output"

# Env var participates in the key.
dev="$(AWS_PROFILE=dev cacheExec bash -c 'echo "p=$RANDOM"' 2>/dev/null)"
prod="$(AWS_PROFILE=prod cacheExec bash -c 'echo "p=$RANDOM"' 2>/dev/null)"
dev2="$(AWS_PROFILE=dev cacheExec bash -c 'echo "p=$RANDOM"' 2>/dev/null)"
[ "$dev" != "$prod" ] && _report ok "profiles cache separately" || _report FAIL "dev/prod shared a cache entry"
assertEq "same profile hits own cache" "$dev" "$dev2"

# TISS_CACHE_ENV extends the significant set.
a="$(MY_CTX=a TISS_CACHE_ENV=MY_CTX cacheExec bash -c 'echo "c=$RANDOM"' 2>/dev/null)"
b="$(MY_CTX=b TISS_CACHE_ENV=MY_CTX cacheExec bash -c 'echo "c=$RANDOM"' 2>/dev/null)"
[ "$a" != "$b" ] && _report ok "TISS_CACHE_ENV extends key" || _report FAIL "custom env var ignored in key"

# Failures are not cached and propagate.
assertExit "failure propagates" 3 cacheExec bash -c 'echo partial; exit 3'
entries="$(find "$TISS_DATA/cache" -type f | wc -l | tr -d ' ')"
# first/refresh(1 key) + dev + prod + MY_CTX a/b (2) = 5
assertEq "failed command not cached" 5 "$entries"

# --no-cache: bypass entirely — no read, no write, cascades via env.
nc1="$(cacheExec --no-cache bash -c 'echo "nc=$RANDOM"' 2>/dev/null)"
nc2="$(cacheExec --no-cache bash -c 'echo "nc=$RANDOM"' 2>/dev/null)"
[ "$nc1" != "$nc2" ] && _report ok "--no-cache always reruns" || _report FAIL "--no-cache served a cached value"
entries_before="$(find "$TISS_DATA/cache" -type f | wc -l | tr -d ' ')"
cacheExec --no-cache bash -c 'echo x' >/dev/null 2>&1
assertEq "--no-cache writes nothing" "$entries_before" "$(find "$TISS_DATA/cache" -type f | wc -l | tr -d ' ')"
assertEq "--no-cache cascades via env" 1 "$(cacheExec --no-cache bash -c 'echo "$TISS_NO_CACHE"' 2>/dev/null)"
assertEq "TISS_NO_CACHE honored without flag" \
  "$(TISS_NO_CACHE=1 bash -c 'source "$TISS_LIB/init.sh"; cacheExec bash -c "echo \$RANDOM"' 2>/dev/null | grep -c '^[0-9]')" 1

# Scavenging: cache-control flags are picked out of the command's argv.
sc="$(cacheExec echo hello --recache 2>/dev/null)"
assertEq "--recache scavenged, not passed to command" "hello" "$sc"
sc="$(cacheExec --duration 1h echo hi --no-cache there 2>/dev/null)"
assertEq "--no-cache scavenged mid-args" "hi there" "$sc"

# `--` stops scavenging for tools with their own flags.
sc="$(cacheExec --no-cache -- echo build --no-cache . 2>/dev/null)"
assertEq "-- passes the tool's own --no-cache through" "build --no-cache ." "$sc"

# --recache invalidates first: entry dies even when the rerun fails...
seed_key="$(tissCacheKey bash -c 'exit 7')"
echo "stale-value" | saveData "$seed_key" 2>/dev/null
assertExit "recache run fails" 7 cacheExec --recache bash -c 'exit 7'
assertExit "entry gone after failed --recache" 1 readData "$seed_key"
# ...while --refresh keeps the old entry on failure.
seed_key2="$(tissCacheKey bash -c 'exit 9')"
echo "survivor" | saveData "$seed_key2" 2>/dev/null
assertExit "refresh run fails" 9 cacheExec --refresh bash -c 'exit 9'
assertEq "entry survives failed --refresh" "survivor" "$(readData "$seed_key2")"

# Duration expiry: a stale entry reruns.
stale_key="$(tissCacheKey bash -c 'echo fresh')"
echo "old-value" | saveData "$stale_key" 2>/dev/null
old_file="$(find "$TISS_DATA/cache" -name "$(basename "$stale_key")*" | head -1)"
touch -t 202001010000 "$old_file"
fresh="$(cacheExec --duration 1h bash -c 'echo fresh' 2>/dev/null)"
assertEq "stale entry reruns command" "fresh" "$fresh"

finish
