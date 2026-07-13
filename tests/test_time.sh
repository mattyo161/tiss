#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for lib/time.sh — durations and timestamp conversions.
. "$(dirname "$0")/harness.sh"

assertEq "dur2s combined units" 709200 "$(dur2s 1w1d5h)"
assertEq "dur2s bare number is minutes" 600 "$(dur2s 10)"
assertEq "dur2s explicit seconds" 100 "$(dur2s 100s)"
assertEq "dur2s single week" 604800 "$(dur2s 1w)"
assertEq "dur2s all units" $((604800 + 2 * 86400 + 3 * 3600 + 4 * 60 + 5)) "$(dur2s 1w2d3h4m5s)"
assertExit "dur2s rejects garbage" 1 dur2s bogus
assertExit "dur2s rejects empty" 1 dur2s ""

assertMatch "ts is compact timestamp" '^[0-9]{8}T[0-9]{6}$' "$(ts)"

now="$(date +%s)"
utc_now="$(utc)"
[ $((utc_now - now)) -le 1 ] && _report ok "utc" || _report FAIL "utc now drifted: $utc_now vs $now"
assertEq "utc +1d offset" 86400 "$(($(utc +1d) - $(utc)))"
assertEq "utc -1h offset" -3600 "$(($(utc -1h) - $(utc)))"

assertEq "ts2js epoch to ISO8601 UTC" "2026-01-01T00:00:00Z" "$(ts2js 1767225600)"
assertMatch "epoch2ts compact form" '^[0-9]{8}T[0-9]{6}$' "$(epoch2ts 1767225600)"

finish
