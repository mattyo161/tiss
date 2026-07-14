#!/usr/bin/env bash
# @description Fetch + prune + rebase onto upstream, stash-aware
# @usage tiss git sync
# @example tiss git sync
# @needs git
#
# The daily driver: stashes any dirty work, fetches everything with prune,
# rebases onto your upstream, and restores the stash. Every real command
# is narrated via learnExec so you can see (and learn) what it does. If
# the rebase stops on conflicts, your stash is left safely in place and
# you are told how to finish.
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

stashed=0
if [ -n "$(git status --porcelain)" ]; then
  learnExec git stash push -m "tiss git sync $(ts)"
  stashed=1
fi

learnExec git fetch --all --prune

if upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"; then
  if ! learnExec git rebase "$upstream"; then
    logError "rebase stopped — resolve conflicts, then: git rebase --continue"
    [ "$stashed" = 1 ] && logWarn "your dirty work is stashed; restore later with: git stash pop"
    exit 1
  fi
else
  logInfo "no upstream configured for this branch — fetched only"
fi

if [ "$stashed" = 1 ]; then
  learnExec git stash pop
fi
logInfo "synced."
