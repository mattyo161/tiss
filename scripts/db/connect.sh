#!/usr/bin/env bash
# @description Open a mysql shell using a registered connection
# @usage tiss db connect <name> [mysql args...]
# @example tiss db connect staging
# @example tiss db connect staging --execute "show tables"
# @needs mysql
#
# Credentials stream straight from the encrypted store into mysql via
# process substitution — no plaintext file ever exists. Extra args pass
# through to mysql untouched.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | "")
    tissHelp "$0"
    exit 0
    ;;
esac

name="$1"
shift

exec mysql --defaults-extra-file=<(readData "db/$name") "$@"
