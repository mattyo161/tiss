#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for lib/data.sh — saveData/readData round-trips and guarantees.
. "$(dirname "$0")/harness.sh"

# Round-trip, default gzip.
echo "hello data store" | saveData greet
assertFileExists "default save is gzipped" "$TISS_DATA/greet.gz"
assertEq "gzip round-trip" "hello data store" "$(readData greet)"

# Resave with different options replaces the variant.
echo "plain now" | saveData --no-gzip greet
assertFileExists "plain variant written" "$TISS_DATA/greet"
assertFileMissing "gz variant removed" "$TISS_DATA/greet.gz"
assertEq "plain round-trip" "plain now" "$(readData greet)"

# Namespaced names.
printf '{"a":1}\n{"a":2}\n' | saveData aws/params
assertEq "namespaced jsonl round-trip" '1 2' "$(readData aws/params | jq -c .a | tr '\n' ' ' | sed 's/ $//')"

# Large input compresses.
yes "the same line over and over" | head -50000 | saveData big
size="$(wc -c <"$TISS_DATA/big.gz" | tr -d ' ')"
[ "$size" -lt 100000 ] && _report ok "big compresses" || _report FAIL "big.gz is $size bytes"
assertEq "big line count survives" 50000 "$(readData big | wc -l | tr -d ' ')"

# Validation.
assertExit "rejects .. traversal" 2 bash -c 'source "$TISS_LIB/init.sh"; echo x | saveData ../evil'
assertExit "rejects absolute path" 2 bash -c 'source "$TISS_LIB/init.sh"; echo x | saveData /abs/path'
assertExit "readData missing name" 1 readData nope

# lsData: jsonl listing with logical names, attribute flags, prefix filter.
ls_out="$(lsData)"
assertEq "lsData lists all entries" 3 "$(printf '%s\n' "$ls_out" | wc -l | tr -d ' ')"
assertMatch "lsData strips extensions to logical name" '"name":"big"' "$ls_out"
assertEq "lsData flags gzip" true "$(printf '%s\n' "$ls_out" | jq -s '.[] | select(.name=="big") | .gzip')"
assertEq "lsData flags plain" false "$(printf '%s\n' "$ls_out" | jq -s '.[] | select(.name=="greet") | .gzip')"
assertEq "lsData prefix filter" "aws/params" "$(lsData aws/ | jq -r .name)"
assertMatch "lsData reports bytes" '"bytes":[0-9]+' "$ls_out"
touch "$TISS_DATA/ghost.tmp.abc123"
assertEq "lsData hides in-flight tmp files" 3 "$(lsData | wc -l | tr -d ' ')"
rm -f "$TISS_DATA/ghost.tmp.abc123"

# cacheExec entries are summarized, not listed (they dominate real data).
echo cached-payload | saveData cache/deadbeef
assertEq "cache entries excluded by default" 3 "$(lsData | wc -l | tr -d ' ')"
assertMatch "cache summary lands on stderr" 'cacheExec entry' \
  "$(TISS_LOG_LEVEL=INFO lsData 2>&1 >/dev/null)"
assertEq "--cache includes them" 4 "$(lsData --cache | wc -l | tr -d ' ')"
assertEq "--cache-only isolates them" "cache/deadbeef" "$(lsData --cache-only | jq -r .name)"
assertEq "a cache/ prefix implies inclusion" "cache/deadbeef" "$(lsData cache/ | jq -r .name)"
assertEq "--json forces jsonl" 3 "$(lsData --json | jq -c . | wc -l | tr -d ' ')"
assertExit "unknown flag is an error" 2 lsData --bogus
assertEq "human bytes helper scales" "1.5KB" "$(tissHumanBytes 1536)"
readData cache/deadbeef >/dev/null && rm -f "$TISS_DATA/cache/deadbeef"*

# No readable partial files mid-write: tmp name never matches a readable variant.
{ echo start; sleep 0.4; echo end; } | saveData slow &
sleep 0.15
[ -f "$TISS_DATA/slow.gz" ] && visible=1 || visible=0
assertEq "nothing readable mid-write" 0 "$visible"
wait
assertEq "atomic publish after write" "start end" "$(readData slow | tr '\n' ' ' | sed 's/ $//')"

finish
