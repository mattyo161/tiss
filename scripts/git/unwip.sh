#!/usr/bin/env bash
# @description Restore the last WIP commit back into the working tree
# @usage tiss git unwip
# @example tiss git unwip
# @needs git
#
# Only touches commits created by `tiss git wip` (subject starts with
# "WIP") — refuses anything else.
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

subject="$(git log -1 --format=%s)"
case "$subject" in
  WIP*) ;;
  *)
    logError "last commit is not a WIP ('$subject') — refusing. Use $TISS_NAME git undo for regular commits."
    exit 2
    ;;
esac

learnExec git reset --soft HEAD~1
learnExec git reset # unstage, back to how the tree was before wip
logInfo "unwip'd: '$subject' is back in your working tree."
