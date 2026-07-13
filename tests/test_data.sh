#!/usr/bin/env bash
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

# No readable partial files mid-write: tmp name never matches a readable variant.
{ echo start; sleep 0.4; echo end; } | saveData slow &
sleep 0.15
visible="$(cd "$TISS_DATA" 2>/dev/null && ls | grep -c '^slow\.gz$' || true)"
assertEq "nothing readable mid-write" 0 "$visible"
wait
assertEq "atomic publish after write" "start end" "$(readData slow | tr '\n' ' ' | sed 's/ $//')"

finish
