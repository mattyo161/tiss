# shellcheck shell=bash
#
# tiss test harness — tiny on purpose: plain bash, no framework to install.
#
# Each tests/test_*.sh file sources this, gets isolated TISS_DATA/TISS_STATE
# under a throwaway tmp dir, and uses the assert helpers. Run everything
# with tests/run.sh (or `tiss tiss test` from a checkout).
#
set -u

TISS_TEST_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TISS_BIN="$TISS_TEST_ROOT/bin/tiss"

# Isolated, throwaway state per test file.
TISS_TEST_TMP="$(mktemp -d)"
export TISS_DATA="$TISS_TEST_TMP/data"
export TISS_STATE="$TISS_TEST_TMP/state"
export TISS_AUTO_INSTALL=never
export TISS_LOG_LEVEL=ERROR

_pass=0
_fail=0

_report() { # _report <ok|FAIL> <message>
  if [ "$1" = ok ]; then
    _pass=$((_pass + 1))
  else
    _fail=$((_fail + 1))
    echo "  FAIL: $2" >&2
  fi
}

assertEq() { # assertEq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    _report ok "$1"
  else
    _report FAIL "$1 — expected '$2', got '$3'"
  fi
}

assertMatch() { # assertMatch <description> <grep -E pattern> <actual>
  if printf '%s' "$3" | grep -Eq -e "$2"; then
    _report ok "$1"
  else
    _report FAIL "$1 — '$3' does not match /$2/"
  fi
}

assertExit() { # assertExit <description> <expected-status> <command...>
  local desc="$1" want="$2" got=0
  shift 2
  "$@" >/dev/null 2>&1 || got=$?
  assertEq "$desc" "$want" "$got"
}

assertFileExists() {
  if [ -e "$2" ]; then _report ok "$1"; else _report FAIL "$1 — missing '$2'"; fi
}

assertFileMissing() {
  if [ ! -e "$2" ]; then _report ok "$1"; else _report FAIL "$1 — '$2' still exists"; fi
}

finish() { # print summary, clean up, exit non-zero on any failure
  rm -rf "$TISS_TEST_TMP"
  echo "$(basename "$0"): $_pass passed, $_fail failed"
  [ "$_fail" -eq 0 ]
}

# Source the helper suite for direct lib testing.
export TISS_LIB="$TISS_TEST_ROOT/lib"
export TISS_NAME=tiss
# shellcheck disable=SC1091
. "$TISS_LIB/init.sh"
