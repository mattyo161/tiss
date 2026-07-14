#!/usr/bin/env bash
# @description Convert CSV to jsonl
# @usage tiss csv2json [FILE]
# @example tiss csv2json data.csv | jq .name
# @needs mlr
#
# Thin façade over miller (mlr): stdin -> stdout, or FILE args like any
# unix filter. jsonl in/out keeps everything pipeable through jq.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

ensureTool mlr || exit 127
exec mlr --icsv --ojsonl cat "$@"
