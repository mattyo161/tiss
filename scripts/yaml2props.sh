#!/usr/bin/env bash
# @description Convert YAML to KEY=value props lines
# @usage ... | tiss yaml2props
# @example tiss yaml2props < config.yaml
# @needs jq yq
#
# JSON is the pivot: yq converts YAML to JSON, then json2props stringifies
# it into KEY=value lines. Nested structures survive as compact JSON
# strings (see json2props).
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

yq -p yaml -o json | "$TISS_SCRIPTS/json2props.sh"
