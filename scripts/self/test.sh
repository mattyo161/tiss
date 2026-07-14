#!/usr/bin/env bash
# @description Run the tiss test suite (development checkouts)
# @usage tiss self test
# @example tiss self test
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

exec bash "$TISS_HOME/tests/run.sh"
