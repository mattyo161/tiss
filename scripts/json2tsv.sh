#!/usr/bin/env bash
# @description Convert json/jsonl to TSV
# @usage tiss json2tsv [FILE]
# @example tiss json2tsv records.json
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
exec mlr --ijson --otsv cat "$@"
