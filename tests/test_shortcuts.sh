#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal $ in inner shells is intentional
# Tests for shortcuts: definitions, shims, argv[0] routing, PATH stripping.
. "$(dirname "$0")/harness.sh"

export TISS_CONFIG="$TISS_TEST_TMP/config"
export TISS_SHIMS="$TISS_TEST_TMP/shims"

# --- add: definition + shim --------------------------------------------------
"$TISS_BIN" self shortcuts add sd saveData >/dev/null 2>&1
assertFileExists "shortcuts file created" "$TISS_CONFIG/shortcuts"
assertMatch "definition recorded" '^sd = saveData$' "$(cat "$TISS_CONFIG/shortcuts")"
assertEq "shim symlinks to the dispatcher" "$TISS_BIN" "$(readlink "$TISS_SHIMS/sd")"

# re-adding replaces the definition instead of duplicating it
"$TISS_BIN" self shortcuts add sd saveData >/dev/null 2>&1
assertEq "add is idempotent" "1" "$(grep -c '^sd = ' "$TISS_CONFIG/shortcuts")"

# --- shims run the mapped command ----------------------------------------------
"$TISS_BIN" self shortcuts add rd readData >/dev/null 2>&1
echo hello | "$TISS_SHIMS/sd" t1 2>/dev/null
assertEq "shim executes its expansion" "hello" "$("$TISS_SHIMS/rd" t1 2>/dev/null)"

# multi-word expansions merge commands
"$TISS_BIN" self shortcuts add cfgpath self config path >/dev/null 2>&1
assertEq "multi-word expansion routes" "$TISS_CONFIG/config.sh" "$("$TISS_SHIMS/cfgpath" 2>/dev/null)"

# flags pass through to the target script
assertMatch "shim --help reaches the script" 'usage: tiss saveData' "$("$TISS_SHIMS/sd" --help 2>&1)"

# --- @env prefix hoists ahead of the expansion ----------------------------------
mkdir -p "$TISS_CONFIG/env"
echo '# empty test profile' >"$TISS_CONFIG/env/tdev.sh"
"$TISS_BIN" self shortcuts add cfgl self config list >/dev/null 2>&1
assertMatch "leading @env loads before expansion" 'TISS_ENV *tdev' "$("$TISS_SHIMS/cfgl" @tdev 2>/dev/null)"

# --- loop-proofing ---------------------------------------------------------------
# The dispatcher strips the shim dir from PATH before anything runs.
out="$(PATH="$TISS_SHIMS:$PATH" "$TISS_BIN" bash -c \
  'case ":$PATH:" in *":$TISS_SHIMS:"*) echo present ;; *) echo stripped ;; esac' 2>/dev/null)"
assertEq "shim dir stripped from child PATH" "stripped" "$out"

# A shortcut named after a real tool can't recurse: the expansion falls
# through to passthrough, which sees the stripped PATH -> the real tool.
"$TISS_BIN" self shortcuts add echo echo >/dev/null 2>&1
assertEq "shortcut over a passthrough tool doesn't recurse" "hi" \
  "$(PATH="$TISS_SHIMS:$PATH" "$TISS_SHIMS/echo" hi 2>/dev/null)"
"$TISS_BIN" self shortcuts remove echo >/dev/null 2>&1

# --- only shims multiplex: a symlink elsewhere stays a plain alias ---------------
ln -s "$TISS_BIN" "$TISS_TEST_TMP/sd"
assertMatch "alias outside shim dir doesn't expand" '^usage: sd' "$("$TISS_TEST_TMP/sd" 2>/dev/null)"

# --- collision warning, reserved and invalid names -------------------------------
warn="$(TISS_LOG_LEVEL=WARN "$TISS_BIN" self shortcuts add ls lsData 2>&1 >/dev/null)"
assertMatch "collision with a real tool warns" 'shadows' "$warn"
"$TISS_BIN" self shortcuts remove ls >/dev/null 2>&1
assertExit "name 'tiss' refused" 2 "$TISS_BIN" self shortcuts add tiss tf plan
assertExit "invalid characters refused" 2 "$TISS_BIN" self shortcuts add 'a/b' tf plan
assertExit "leading dash refused" 2 "$TISS_BIN" self shortcuts add -x tf plan

# --- list --------------------------------------------------------------------------
lst="$("$TISS_BIN" self shortcuts list 2>/dev/null)"
assertMatch "list shows name, expansion, status, source" 'sd +tiss saveData +ok +user' "$lst"

# --- remove ------------------------------------------------------------------------
"$TISS_BIN" self shortcuts remove rd >/dev/null 2>&1
assertFileMissing "removed shortcut's shim pruned" "$TISS_SHIMS/rd"
assertExit "removing an unknown shortcut fails" 2 "$TISS_BIN" self shortcuts remove nope

# --- sync reconciles hand-edits, never touches foreign files ------------------------
echo 'zz = lsData' >>"$TISS_CONFIG/shortcuts"
"$TISS_BIN" self shortcuts sync >/dev/null 2>&1
assertFileExists "hand-added definition gets a shim on sync" "$TISS_SHIMS/zz"
grep -v '^zz ' "$TISS_CONFIG/shortcuts" >"$TISS_CONFIG/shortcuts.new"
mv "$TISS_CONFIG/shortcuts.new" "$TISS_CONFIG/shortcuts"
touch "$TISS_SHIMS/keepme"
ln -s /bin/sh "$TISS_SHIMS/foreignlink"
"$TISS_BIN" self shortcuts sync >/dev/null 2>&1
assertFileMissing "orphaned shim pruned on sync" "$TISS_SHIMS/zz"
assertFileExists "foreign file untouched by sync" "$TISS_SHIMS/keepme"
assertFileExists "foreign symlink untouched by sync" "$TISS_SHIMS/foreignlink"
rm -f "$TISS_SHIMS/keepme" "$TISS_SHIMS/foreignlink"

# --- tree-provided shortcuts ---------------------------------------------------------
tree="$TISS_TEST_TMP/acme"
mkdir -p "$tree/scripts" "$tree/etc"
echo 'acmepath = self config path' >"$tree/etc/shortcuts"
TISS_PATH="$tree" "$TISS_BIN" self shortcuts sync >/dev/null 2>&1
assertFileExists "tree shortcut gets a shim" "$TISS_SHIMS/acmepath"
assertEq "tree shortcut routes" "$TISS_CONFIG/config.sh" "$(TISS_PATH="$tree" "$TISS_SHIMS/acmepath" 2>/dev/null)"
assertExit "removing a tree-owned shortcut errors" 2 \
  env TISS_PATH="$tree" "$TISS_BIN" self shortcuts remove acmepath
echo 'acmepath = self config list' >>"$TISS_CONFIG/shortcuts"
assertMatch "user definition beats the tree's" 'SETTING' "$(TISS_PATH="$tree" "$TISS_SHIMS/acmepath" 2>/dev/null)"
"$TISS_BIN" self shortcuts remove acmepath >/dev/null 2>&1

# --- self init emits the guarded PATH line ---------------------------------------------
emit="$("$TISS_BIN" self init 2>/dev/null)"
assertMatch "self init emits the shim dir" "$TISS_SHIMS" "$emit"
assertMatch "PATH line is guarded" 'case ":\$PATH:"' "$emit"
onpath="$(bash -c "eval \"\$('$TISS_BIN' self init 2>/dev/null)\"
  case \":\$PATH:\" in *\":$TISS_SHIMS:\"*) echo on ;; *) echo off ;; esac")"
assertEq "eval'd rc line puts shim dir on PATH" "on" "$onpath"

# --- doctor --------------------------------------------------------------------------
assertMatch "doctor flags missing PATH line" 'shim dir not on PATH' \
  "$(TISS_LOG_LEVEL=INFO "$TISS_BIN" self doctor 2>&1 || true)"
assertMatch "doctor happy when shims healthy and on PATH" 'ok: shim dir on PATH' \
  "$(TISS_LOG_LEVEL=INFO PATH="$TISS_SHIMS:$PATH" "$TISS_BIN" self doctor 2>&1 || true)"

finish