# shellcheck shell=bash
#
# tiss helper bootstrap — source this at the top of every tiss script:
#
#   source "$TISS_LIB/init.sh"
#
# Loads the full helper suite (logging, tools, time, crypt). Helpers use
# camelCase (logInfo, ensureTool, dur2s) — the tiss house style for sourced
# functions, distinct from directory-routed commands.
#
if [ -z "${TISS_LIB:-}" ]; then
  echo "TISS_LIB is not set — tiss scripts must run via the tiss dispatcher" >&2
  exit 1
fi

. "$TISS_LIB/time.sh"
. "$TISS_LIB/log.sh"
. "$TISS_LIB/meta.sh"
. "$TISS_LIB/tools.sh"
. "$TISS_LIB/crypt.sh"
. "$TISS_LIB/data.sh"
. "$TISS_LIB/rmafter.sh"
. "$TISS_LIB/exec.sh"
