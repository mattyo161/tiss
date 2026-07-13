#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for scripts/dt/parse.py — fuzzy date parsing and inference rules.
. "$(dirname "$0")/harness.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "$(basename "$0"): skipped (python3 not installed)"
  rm -rf "$TISS_TEST_TMP"
  exit 0
fi

dtp() { "$TISS_BIN" dt parse "$@"; }

# Basics: ISO, epoch passthrough (both ways), tiss compact form.
assertMatch "ISO date parses" '"ts": "20260712T000000"' "$(dtp 2026-07-12)"
assertEq "epoch to ISO" "2026-01-01T00:00:00Z" "$(dtp --iso 1767225600)"
assertEq "millis epoch" "2026-01-01T00:00:00Z" "$(dtp --iso 1767225600000)"
assertEq "tiss compact form" "20260712T183042" "$(dtp --ts 20260712T183042)"
assertEq "ISO with Z round-trips" 1767225600 "$(dtp --epoch 2026-01-01T00:00:00Z)"

# Args are joined: no quoting needed.
assertEq "unquoted multi-arg input" "20261224T210000" "$(dtp --ts 12/24/26 9:00 PM)"

# Two-digit year century rule: 00-30 -> 2000s, 31-99 -> 1900s.
assertEq "yy<=30 is 2000s" "20261224T210000" "$(dtp --ts 12/24/26 9:00 PM)"
assertEq "yy>30 is 1900s" "19851224T000000" "$(dtp --ts 12/24/85)"

# Weekday overrides the century rule: 12/24/28 defaults to 2028 (a Sunday),
# but a leading Mon forces 1928, when Dec 24 really was a Monday.
assertEq "weekday picks century" "19281224T000000" "$(dtp --ts Mon 12/24/28)"
assertEq "weekday agrees with default century" "20261224T000000" "$(dtp --ts Thu 12/24/26)"

# Missing year: nearest to now. --now freezes the reference for determinism.
jan15_2026=1768500000
assertEq "January sees 12/24 as last year" "20251224T210000" \
  "$(dtp --now $jan15_2026 --ts 12/24 9:00 PM)"
dec10_2026=1797000000
assertEq "December sees 1/24 as next year" "20270124T210000" \
  "$(dtp --now $dec10_2026 --ts 1/24 9:00 PM)"

# Month names, either order.
assertEq "Mon-name day year" "20260704T000000" "$(dtp --ts Jul 4 2026)"
assertEq "day Mon-name year" "20260704T000000" "$(dtp --ts 4 Jul 2026)"

# Weekday mismatch on a full date is flagged, not fatal.
assertMatch "weekday mismatch noted" '"weekday_mismatch": true' "$(dtp Mon 2026-07-12)"

# stdin mode: one input per line, jsonl out.
n="$(printf 'Jul 4 2026\n2026-01-01\n' | dtp | wc -l | tr -d ' ')"
assertEq "stdin mode emits one json per line" 2 "$n"

# Pre-1970 dates produce negative epochs rather than crashing.
assertMatch "pre-epoch date works" '^-' "$(dtp --epoch 1776-07-04)"

# Failures: exit 1, message on stderr, still processes other lines.
assertExit "unparseable input exits 1" 1 dtp "not a date"
mixed="$(printf '2026-01-01\ngarbage\n' | dtp 2>/dev/null | wc -l | tr -d ' ')"
assertEq "mixed input still emits good lines" 1 "$mixed"

finish
