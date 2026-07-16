#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the format conversion façades (mlr) and the json2xlsx leaf.
. "$(dirname "$0")/harness.sh"

if ! command -v mlr >/dev/null 2>&1; then
  echo "$(basename "$0"): skipped (mlr not installed)"
  rm -rf "$TISS_TEST_TMP"
  exit 0
fi

csv=$'name,qty,price\nwidget,1200,19.99\ngadget,7,3.5'

# csv -> jsonl
jsonl="$(printf '%s\n' "$csv" | "$TISS_BIN" csv2json)"
assertEq "csv2json emits jsonl records" 2 "$(printf '%s\n' "$jsonl" | wc -l | tr -d ' ')"
assertEq "csv2json types numbers" 1200 "$(printf '%s\n' "$jsonl" | jq -s '.[0].qty')"

# round trip back to csv
back="$(printf '%s\n' "$jsonl" | "$TISS_BIN" json2csv)"
assertEq "json2csv round-trips" "$csv" "$back"

# tsv both ways
tsv="$(printf '%s\n' "$jsonl" | "$TISS_BIN" json2tsv)"
assertMatch "json2tsv tab-separates" "name$(printf '\t')qty" "$tsv"
assertEq "tsv2json round-trips" "$jsonl" "$(printf '%s\n' "$tsv" | "$TISS_BIN" tsv2json)"

# markdown table
md="$(printf '%s\n' "$jsonl" | "$TISS_BIN" json2md)"
assertMatch "json2md emits table header" '^\| name \| qty \| price \|' "$md"
assertMatch "json2md emits separator" '\| --- \| --- \| --- \|' "$md"

# xlsx leaf (needs uv; skip quietly where absent, e.g. CI runners)
if command -v uv >/dev/null 2>&1; then
  out="$TISS_TEST_TMP/report.xlsx"
  printf '%s\n' "$jsonl" | "$TISS_BIN" json2xlsx "$out" 2>/dev/null
  assertFileExists "json2xlsx writes file" "$out"
  magic="$(head -c 2 "$out")"
  assertEq "xlsx is a zip container" "PK" "$magic"
else
  echo "  skip: uv not installed, json2xlsx untested" >&2
fi

# --- props <-> json ---------------------------------------------------------------
assertEq "props2json splits on the FIRST =" '{"A":"1","B":"x=y"}' \
  "$(printf 'A=1\nB=x=y\n# comment\n\n' | "$TISS_BIN" props2json 2>/dev/null)"
assertEq "json2props stringifies non-strings" 'N=42' \
  "$(printf '{"N":42}' | "$TISS_BIN" json2props 2>/dev/null)"
assertEq "props/json round-trip" 'A=1
B=x=y' "$(printf 'A=1\nB=x=y\n' | "$TISS_BIN" props2json 2>/dev/null | "$TISS_BIN" json2props 2>/dev/null)"

finish
