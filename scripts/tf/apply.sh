#!/usr/bin/env bash
# @description Apply the latest saved plan — same summary and prompt as tf plan
# @usage tiss tf apply [-y|--yes] [--plan FILE]
# @example tiss tf apply
# @example tiss tf apply --yes
# @needs terraform jq
#
# Reads .tiss/tfplans/latest.json (written by tf plan), shows the SAME icon
# summary the plan ended with, asks y/N, then applies that exact .tfplan —
# it never re-plans. Warns if the plan was already applied; detects stale
# plans; records applied_at back into the run metadata. Override the prompt
# with --yes or TISS_TF_AUTO_APPLY=always.
#
set -uo pipefail
source "$TISS_LIB/init.sh"

cfg TISS_TF_AUTO_APPLY ask
cfg TISS_TF_PLAN_TTL 1d

force=false
plan_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    -y | --yes) force=true ;;
    --plan)
      plan_file="${2:?--plan needs a FILE}"
      shift
      ;;
    *)
      logError "unknown argument: $1 (targets/vars belong on the plan: $TISS_NAME tf plan -target=...)"
      exit 2
      ;;
  esac
  shift
done
[ "$TISS_TF_AUTO_APPLY" = always ] && force=true

if [ -n "$plan_file" ]; then
  [ -f "$plan_file" ] || {
    logError "no such plan file: $plan_file"
    exit 1
  }
  meta="${plan_file%.tfplan}.run.json"
  [ -f "$meta" ] || {
    logError "no run metadata next to the plan: $meta (was it made by '$TISS_NAME tf plan'?)"
    exit 1
  }
else
  meta="$(tfLatestMeta)"
  [ -f "$meta" ] || {
    logError "no saved plan here — run '$TISS_NAME tf plan' first (apply always runs from a reviewed plan)"
    exit 2
  }
fi

tfApplyRun "$meta" true "$force"
