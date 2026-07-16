#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the fresh-box last mile: tissOfferRcActivation wiring the one
# `eval "$(tiss init)"` line into the user's rc. HOME is redirected so
# real rcs are never touched.
. "$(dirname "$0")/harness.sh"

export HOME="$TISS_TEST_TMP/home"
mkdir -p "$HOME"
export SHELL=/bin/bash
touch "$HOME/.bashrc"

run() { # run <TISS_AUTO_INSTALL> <fn> — isolated HOME, real libs
  env HOME="$HOME" SHELL="$SHELL" TISS_AUTO_INSTALL="$1" TISS_LOG_LEVEL=INFO \
    TISS_LIB="$TISS_TEST_ROOT/lib" TISS_NAME=tiss TISS_HOME="$TISS_TEST_ROOT" \
    TISS_DATA="$TISS_DATA" TISS_STATE="$TISS_STATE" TISS_CONFIG="$TISS_TEST_TMP/config" \
    bash -c 'source "$TISS_LIB/init.sh"; "$@"' _ "$2"
}

# never: informs, never writes.
out="$(run never tissOfferRcActivation 2>&1)"
assertMatch "never mode informs" 'new shells need this' "$out"
assertEq "never mode writes nothing" "" "$(cat "$HOME/.bashrc")"

# ask without tty: informs, never writes.
out="$(run ask tissOfferRcActivation 2>&1 </dev/null)"
assertMatch "ask/no-tty informs" 'new shells need this' "$out"
assertEq "ask/no-tty writes nothing" "" "$(cat "$HOME/.bashrc")"

# always: appends the line, backs up the rc first.
run always tissOfferRcActivation >/dev/null 2>&1
assertMatch "activation line appended" 'eval "\$\(tiss init\)"' "$(cat "$HOME/.bashrc")"
assertMatch "marker present" '# tiss activation' "$(cat "$HOME/.bashrc")"
assertEq "rc backed up first" 1 "$(ls -A "$HOME/.bkup" 2>/dev/null | wc -l | tr -d ' ')"

# idempotent: second run adds nothing.
lines="$(wc -l <"$HOME/.bashrc" | tr -d ' ')"
run always tissOfferRcActivation >/dev/null 2>&1
assertEq "idempotent" "$lines" "$(wc -l <"$HOME/.bashrc" | tr -d ' ')"

# pre-existing hand-written line also counts as wired.
printf 'eval "$(tiss init)"\n' >"$HOME/.zshrc"
out="$(env SHELL=/bin/zsh HOME="$HOME" TISS_AUTO_INSTALL=always TISS_LOG_LEVEL=INFO \
  TISS_LIB="$TISS_TEST_ROOT/lib" TISS_NAME=tiss TISS_HOME="$TISS_TEST_ROOT" \
  TISS_DATA="$TISS_DATA" TISS_STATE="$TISS_STATE" TISS_CONFIG="$TISS_TEST_TMP/config" \
  bash -c 'source "$TISS_LIB/init.sh"; tissOfferRcActivation' 2>&1)"
assertEq "hand-written line respected" 1 "$(wc -l <"$HOME/.zshrc" | tr -d ' ')"

# doctor reports the wiring state with the exact fix.
: >"$HOME/.bashrc"
out="$(env HOME="$HOME" SHELL=/bin/bash TISS_LOG_LEVEL=INFO "$TISS_BIN" doctor 2>&1 || true)"
assertMatch "doctor flags missing rc activation" 'rc activation' "$out"
assertMatch "doctor gives the exact line" 'tiss init' "$out"

finish
