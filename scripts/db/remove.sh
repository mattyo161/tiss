#!/usr/bin/env bash
# @description Remove a registered database connection
# @usage tiss db remove <name>
# @example tiss db remove staging
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
dir="$(tissDataDir)/db"
removed=0
for f in "$dir/$name" "$dir/$name".*; do
  [ -f "$f" ] && rm -f "$f" && removed=1
done
if [ "$removed" = 1 ]; then
  logInfo "removed 'db/$name'"
else
  logError "no connection named '$name' (see: $TISS_NAME db list)"
  exit 2
fi
