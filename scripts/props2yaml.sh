#!/usr/bin/env bash
# @description Convert KEY=value props lines (env/.env style) to YAML
# @usage ... | tiss props2yaml
# @example tiss env | tiss props2yaml
# @needs jq yq
#
# JSON is the pivot: chains through props2json, then yq converts JSON to
# YAML. See props2json for the KEY=value parsing rules.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

"$TISS_SCRIPTS/props2json.sh" | yq -p json -o yaml
