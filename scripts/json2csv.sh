#!/usr/bin/env bash
# @description Convert json/jsonl to CSV
# @usage tiss json2csv [FILE]
# @example tiss readData aws/params | tiss json2csv > params.csv
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
exec mlr --ijson --ocsv cat "$@"
