#!/usr/bin/env bash
# @description Switch the tiss checkout to a branch (try a shared feature)
# @usage tiss self checkout [branch]
# @example tiss self checkout feature/new-wrapper
# @example tiss self checkout            # list available branches
# @example tiss self checkout main       # back to normal
# @needs git
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

git -C "$TISS_HOME" rev-parse --git-dir >/dev/null 2>&1 || {
  logError "$TISS_HOME is not a git checkout (installed some other way?)"
  exit 2
}

learnExec git -C "$TISS_HOME" fetch --all --prune

if [ $# -eq 0 ]; then
  current="$(git -C "$TISS_HOME" branch --show-current)"
  logInfo "currently on: ${current:-<detached>}"
  echo "branches:" >&2
  git -C "$TISS_HOME" branch -a --format='  %(refname:short)' | sed 's|origin/||' | sort -u | grep -v '^  HEAD' >&2
  logInfo "switch with: $TISS_NAME self checkout <branch>"
  exit 0
fi

learnExec git -C "$TISS_HOME" checkout "$1"
logInfo "tiss is now on '$1' — back with: $TISS_NAME self checkout main"
