#!/usr/bin/env bash
# @description Update tiss to the latest from git
# @usage tiss pull
# @example tiss pull
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

before="$(git -C "$TISS_HOME" rev-parse HEAD)"
learnExec git -C "$TISS_HOME" pull --ff-only
after="$(git -C "$TISS_HOME" rev-parse HEAD)"

if [ "$before" = "$after" ]; then
  logInfo "already up to date ($(git -C "$TISS_HOME" rev-parse --short HEAD))"
else
  logInfo "updated — what came in:"
  git -C "$TISS_HOME" log --oneline "$before..$after" | head -15 >&2
fi
