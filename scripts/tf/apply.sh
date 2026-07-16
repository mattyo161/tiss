#!/usr/bin/env bash
# @description Apply the latest saved plan — same summary and prompt as tf plan
# @usage tiss tf apply [-y|--yes] [--plan FILE] [--all] [dir ...]
# @example tiss tf apply
# @example tiss tf apply --yes
# @example tiss tf apply --all          # every discovered root module
# @needs terraform jq
#
# Reads .tiss/tfplans/latest.json (written by tf plan), shows the SAME icon
# summary the plan ended with, asks y/N, then applies that exact .tfplan —
# it never re-plans. Warns if the plan was already applied; detects stale
# plans; records applied_at back into the run metadata. Override the prompt
# with --yes or TISS_TF_AUTO_APPLY=always.
#
set -o pipefail
source "$TISS_LIB/init.sh"

cfg TISS_TF_AUTO_APPLY ask
cfg TISS_TF_PLAN_TTL 1d

force=false
plan_file=""
ALL=false
DIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    -y | --yes) force=true ;;
    --all) ALL=true ;;
    --plan)
      plan_file="${2:?--plan needs a FILE}"
      shift
      ;;
    -*)
      logError "unknown argument: $1 (targets/vars belong on the plan: $TISS_NAME tf plan -target=...)"
      exit 2
      ;;
    *) DIRS+=("$1") ;;
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
  tfApplyRun "$meta" true "$force"
  exit $?
fi

# Resolve modules: --all discovers, dir args target, default is the cwd.
MODULE_DIRS=()
if [ "$ALL" = true ]; then
  while IFS= read -r d; do
    [ -n "$d" ] && MODULE_DIRS+=("$d")
  done < <(tfDiscoverRootModules)
  [ ${#MODULE_DIRS[@]} -gt 0 ] || {
    logError "no root modules found under $(pwd)"
    exit 1
  }
elif [ ${#DIRS[@]} -gt 0 ]; then
  MODULE_DIRS=("${DIRS[@]}")
else
  MODULE_DIRS=(".")
fi

rc=0
for d in "${MODULE_DIRS[@]}"; do
  (
    cd "$d" 2>/dev/null || {
      logError "no such directory: $d"
      exit 1
    }
    meta="$(tfLatestMeta)"
    if [ ! -f "$meta" ]; then
      logWarn "no saved plan in ${d} — run '$TISS_NAME tf plan' first"
      exit 1
    fi
    tfApplyRun "$meta" true "$force"
  ) || rc=1
done
exit "$rc"
