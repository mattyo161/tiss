#!/usr/bin/env bash
# @description Convert json/jsonl to a markdown table
# @usage tiss json2md [FILE]
# @example tiss csv2json data.csv | tiss json2md
# @needs mlr
#
# Thin façade over miller (mlr): stdin -> stdout, or FILE args like any
# unix filter. jsonl in/out keeps everything pipeable through jq.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

ensureTool mlr || exit 127
exec mlr --ijson --omd cat "$@"
