#!/usr/bin/env bash
# @description List registered database connections
# @usage tiss db list
# @example tiss db list
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

dir="$(tissDataDir)/db"
if [ ! -d "$dir" ]; then
  logInfo "no connections yet — add one with: $TISS_NAME db add <name>"
  exit 0
fi

found=0
for f in "$dir"/*; do
  [ -f "$f" ] || continue
  found=1
  name="$(basename "$f")"
  case "$name" in
    *.age) printf '%s\t(encrypted)\n' "${name%%.*}" ;;
    *) printf '%s\t(PLAIN — consider re-adding without --plain)\n' "${name%%.*}" ;;
  esac
done
[ "$found" = 0 ] && logInfo "no connections yet — add one with: $TISS_NAME db add <name>"
exit 0
