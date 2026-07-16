#!/usr/bin/env bash
# @description Convert a JSON object (or jsonl of objects) to KEY=value props lines
# @usage ... | tiss json2props
# @example tiss env --json | tiss json2props
# @example aws sts get-caller-identity | tiss json2props
# @needs jq
#
# Non-string values are emitted as compact JSON (nested objects/arrays
# survive a round-trip through props2json as strings).
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

jq -r 'to_entries[] | .key + "=" + (.value | if type == "string" then . else tojson end)'
