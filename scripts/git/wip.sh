#!/usr/bin/env bash
# @description Commit everything as WIP (hooks skipped) for fast context switching
# @usage tiss git wip [message]
# @example tiss git wip
# @example tiss git wip trying the other approach
# @needs git
#
# Pairs with `tiss git unwip`, which soft-resets the WIP commit back into
# your working tree.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || {
  logError "not inside a git repository"
  exit 2
}

if [ -z "$(git status --porcelain)" ]; then
  logInfo "nothing to wip — working tree is clean."
  exit 0
fi

msg="WIP $(ts)${*:+ — $*}"
learnExec git add -A
learnExec git commit --no-verify -m "$msg"
logInfo "wip'd. restore with: $TISS_NAME git unwip"
