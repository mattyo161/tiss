#!/usr/bin/env bash
# @description Terraform plan with plan-file discipline (required by tf apply)
# @usage tiss tf plan [terraform plan args...]
# @example tiss tf plan
# @example tiss tf plan -var-file=prod.tfvars
# @needs terraform
#
# Writes the plan to .tiss/tf-<timestamp>.plan — the only thing
# `tiss tf apply` will accept. Plan files self-destruct after a day
# (plans go stale; a fresh one takes seconds). Everything else passes
# through: `tiss tf init`, `tiss tf state list`, ... run terraform
# directly.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

mkdir -p .tiss
if git rev-parse --git-dir >/dev/null 2>&1; then
  if [ ! -f .gitignore ] || ! grep -q '^\.tiss/$' .gitignore 2>/dev/null; then
    logWarn "add '.tiss/' to .gitignore — plan files can contain sensitive values"
  fi
fi

planfile=".tiss/tf-$(ts).plan"
learnExec terraform plan -out "$planfile" "$@"
rmAfter 1d "$planfile" # plans go stale — self-destruct in a day
logInfo "plan saved: $planfile"
logInfo "review the output above, then: $TISS_NAME tf apply"
