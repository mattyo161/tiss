#!/usr/bin/env bash
# @description Undo the last commit, keeping its changes staged
# @usage tiss git undo [--yes]
# @example tiss git undo
# @needs git
#
# The "oops" button: soft-resets HEAD~1 so the commit disappears but every
# change stays staged. If the commit is already on a remote branch, tiss
# warns (others may have it) and requires --yes.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

yes=0
case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
  --yes) yes=1 ;;
  "") ;;
  *)
    logError "unknown argument: $1"
    exit 2
    ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || {
  logError "not inside a git repository"
  exit 2
}
git rev-parse HEAD~1 >/dev/null 2>&1 || {
  logError "nothing to undo — HEAD has no parent"
  exit 2
}

subject="$(git log -1 --format=%s)"

if [ -n "$(git branch -r --contains HEAD 2>/dev/null)" ] && [ "$yes" = 0 ]; then
  logError "'$subject' is already on a remote — undoing a published commit rewrites shared history."
  logError "if you are sure: $TISS_NAME git undo --yes"
  exit 2
fi

learnExec git reset --soft HEAD~1
logInfo "undone: '$subject' — its changes are staged and ready."
