#!/usr/bin/env bash
# @description Terraform apply — ONLY from a plan file made by tf plan
# @usage tiss tf apply
# @example tiss tf plan && tiss tf apply
# @needs terraform
#
# Hard requirement, no escape hatch: apply always runs from a reviewed
# plan. No plan file means a refusal with instructions, not a prompt.
# The plan file is consumed (deleted) after a successful apply — plans
# are single-use by design.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

if [ $# -gt 0 ]; then
  logError "tf apply takes no arguments — it applies the plan file from '$TISS_NAME tf plan'."
  logError "different variables or targets belong on the plan: $TISS_NAME tf plan -var-file=..."
  exit 2
fi

# Newest plan wins; older ones are stale by definition.
plan=""
for f in .tiss/tf-*.plan; do
  [ -f "$f" ] || continue
  if [ -z "$plan" ] || [ "$f" -nt "$plan" ]; then
    plan="$f"
  fi
done

if [ -z "$plan" ]; then
  logError "no plan file. Run '$TISS_NAME tf plan' first — apply always runs from a reviewed plan."
  exit 2
fi

learnExec terraform apply "$plan"
rm -f "$plan" # single-use: state has moved, this plan is spent
logInfo "applied and consumed $plan"
