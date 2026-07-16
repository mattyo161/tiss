#!/usr/bin/env bash
# @description List saved data — a table on your terminal, jsonl in pipes
# @usage tiss lsData [prefix] [--json] [--cache|--cache-only]
# @example tiss lsData                       # human table; cache entries summarized
# @example tiss lsData | jq -r .name         # piped = jsonl (or force with --json)
# @example tiss lsData --cache-only          # just the cacheExec entries
#
# jsonl records are {name, gzip, encrypted, bytes, modified, file}. The
# optional prefix filters by logical name (`tiss lsData aws/`).
# cacheExec entries are excluded by default and summarized on stderr —
# --cache includes them, --cache-only isolates them, and a cache/
# prefix implies inclusion.
# @needs jq
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

lsData "$@"
