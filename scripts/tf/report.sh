#!/usr/bin/env bash
# @description Report on the latest plan: list, target, md, tree, csv, jsonl, excel
# @usage tiss tf report [--format list|target|md|tree|csv|jsonl|excel|diff] [plan.json...]
# @example tiss tf report
# @example tiss tf report --format target > targets.txt
# @example tiss tf report --format md >> PR_DESCRIPTION.md
# @example tiss tf report --format excel
# @example tiss tf report --format diff */.tiss/tfplans/*.tfplan.json > drift.md
# @needs jq
#
# Reads the .tfplan.json that tf plan saved (never re-plans; terraform not
# required). Formats:
#   list    the end-of-plan icon summary (default)
#   target  -target='addr' per line, quoted — paste onto a plan/apply
#   md      markdown table          tree    module/resource hierarchy
#   csv     via miller              jsonl   raw records for jq
#   excel   formatted spreadsheet via json2xlsx (needs uv)
#   diff    the deep-diff markdown drift report (attribute-level diffs,
#           embedded JSON decoded, nested module <details>, forces-
#           replacement flags) — paste into a PR description
#
set -euo pipefail
source "$TISS_LIB/init.sh"

format="list"
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    --format)
      format="${2:?--format needs a value}"
      shift
      ;;
    *) files+=("$1") ;;
  esac
  shift
done

if [ ${#files[@]} -eq 0 ]; then
  meta="$(tfLatestMeta)"
  [ -f "$meta" ] || {
    logError "no saved plan here — run '$TISS_NAME tf plan' first (or pass a .tfplan.json)"
    exit 2
  }
  files=("$(jq -r '.json_file' "$meta")")
fi

rows() { # aggregate change records across all given plan jsons
  local f
  for f in ${files[@]+"${files[@]}"}; do
    [ -f "$f" ] || {
      logError "no such plan json: $f"
      exit 1
    }
    tfChangesJsonl "$f"
  done
}

case "$format" in
  list)
    for f in ${files[@]+"${files[@]}"}; do
      tfSummary "$f"
    done
    ;;
  target)
    rows | jq -r '"-target='\''\(.address)'\''"'
    ;;
  jsonl)
    rows
    ;;
  md)
    ensureTool mlr || exit 127
    rows | jq -c '{action, address, type, module}' | mlr --ijsonl --omd cat
    ;;
  csv)
    ensureTool mlr || exit 127
    rows | mlr --ijsonl --ocsv cat
    ;;
  tree)
    rows | jq -r '[.action, .address] | @tsv' | sort -t"$(printf '\t')" -k2,2 |
      awk -F'\t' '{
        n = split($2, parts, ".")
        path = ""
        for (i = 1; i <= n; i++) {
          path = path (i > 1 ? "." : "") parts[i]
          if (!(path in seen)) {
            seen[path] = 1
            indent = ""
            for (j = 1; j < i; j++) indent = indent "  "
            if (i == n) printf "%s%s %s\n", indent, ($1=="create"?"✚":$1=="update"?"✎":$1=="delete"?"✘":$1=="replace"?"⟳":$1=="forget"?"⊘":$1=="import"?"↧":$1=="moved"?"➜":"?"), parts[i]
            else printf "%s%s\n", indent, parts[i]
          }
        }
      }'
    ;;
  diff)
    jq -rf "$TISS_LIB/tf-diff.jq" ${files[@]+"${files[@]}"}
    ;;
  excel)
    out="tf-report.$(ts).xlsx"
    rows | "$TISS_HOME/bin/tiss" json2xlsx "$out"
    logInfo "wrote $out"
    ;;
  *)
    logError "unknown format '$format' (list, target, md, tree, csv, jsonl, excel, diff)"
    exit 2
    ;;
esac
