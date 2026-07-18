#!/usr/bin/env bash
# @description Convert TOML to KEY=value props lines
# @usage ... | tiss toml2props
# @example tiss toml2props < config.toml
# @needs jq yq
#
# JSON is the pivot: yq converts TOML to JSON, then json2props stringifies
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

yq -p toml -o json | "$TISS_SCRIPTS/json2props.sh"
