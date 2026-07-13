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

# Duration expiry: a stale entry reruns.
echo "old-value" | saveData "cache/$(printf '%s' 'bash -c echo fresh' | tissSha256)" 2>/dev/null
old_file="$(find "$TISS_DATA/cache" -name "$(printf '%s' 'bash -c echo fresh' | tissSha256)*" | head -1)"
touch -t 202001010000 "$old_file"
fresh="$(cacheExec --duration 1h bash -c 'echo fresh' 2>/dev/null)"
assertEq "stale entry reruns command" "fresh" "$fresh"

finish
