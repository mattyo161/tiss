#!/usr/bin/env bash
# @description List saved data entries as jsonl (name, size, gzip/encrypted, age)
# @usage tiss lsData [prefix]
# @example tiss lsData | jq -r .name
# @example tiss lsData db/ | jq 'select(.encrypted | not)'
# @needs jq
#
# One JSON object per entry: {name, gzip, encrypted, bytes, modified,
# file}. The optional prefix filters by logical name, so namespaces list
# naturally: `tiss lsData aws/`.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

lsData "$@"
