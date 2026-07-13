#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for lib/bkup.sh — mtime-named backups.
. "$(dirname "$0")/harness.sh"

work="$TISS_TEST_TMP/work"
mkdir -p "$work/sub"
cd "$work" || exit 1

# Basic backup preserves perms and mtime.
echo "v1 config" >app.conf
chmod 640 app.conf
touch -t 202601011200 app.conf
b1="$(bkup app.conf 2>/dev/null)"
assertMatch "backup named by mtime" 'app\.conf\.20260101T120000$' "$b1"
assertFileExists "backup exists" "$b1"
assertEq "mtime preserved" "$(tissFileMtime app.conf)" "$(tissFileMtime "$b1")"

# Idempotent for unchanged files.
b2="$(bkup app.conf 2>/dev/null)"
assertEq "unchanged file returns same path" "$b1" "$b2"
assertEq "still one backup" 1 "$(ls .bkup | wc -l | tr -d ' ')"

# Modified file gets a second generation.
echo "v2 config" >app.conf
touch -t 202607011200 app.conf
bkup app.conf >/dev/null 2>&1
assertEq "two generations coexist" 2 "$(ls .bkup | wc -l | tr -d ' ')"

# Directories copy recursively.
echo x >sub/inner.txt
bkup sub >/dev/null 2>&1
inner="$(find .bkup -path '*sub.*/inner.txt' | wc -l | tr -d ' ')"
assertEq "directory backup includes contents" 1 "$inner"

# Multiple files in one call.
echo a >f1.txt
echo b >f2.txt
n="$(bkup f1.txt f2.txt 2>/dev/null | wc -l | tr -d ' ')"
assertEq "multiple files backed up" 2 "$n"

# Missing file errors but continues exit code.
assertExit "missing file exits 1" 1 bkup nope.txt
assertExit "usage error" 2 bkup

finish
