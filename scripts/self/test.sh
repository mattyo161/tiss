#!/usr/bin/env bash
# @description Run the tiss test suite (development checkouts)
# @usage tiss test
# @example tiss test
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

if [ ! -d "$TISS_HOME/tests" ]; then
  logError "no tests/ directory in $TISS_HOME (not a development checkout?)"
  exit 1
fi

rc=0
bash "$TISS_HOME/tests/run.sh" || rc=1

# Enabled trees carry their own tests — run them too (each file gets the
# core harness via TISS_HOME; see any tree's tests/ for the pattern).
while IFS= read -r tree; do
  [ "$tree" = "$TISS_HOME" ] && continue
  [ -d "$tree/tests" ] || continue
  echo "---------------------------------------- $(basename "$tree") tree"
  for t in "$tree/tests"/test_*.sh; do
    [ -f "$t" ] || continue
    bash "$t" || rc=1
  done
done < <(tissTrees)
exit "$rc"
