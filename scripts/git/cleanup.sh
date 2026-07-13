#!/usr/bin/env bash
# @description Delete local branches whose upstream is gone (dry-run by default)
# @usage tiss git cleanup [--yes]
# @example tiss git cleanup          # shows what would be deleted
# @example tiss git cleanup --yes    # actually deletes
# @needs git
#
# Merged-PR hygiene: after `git fetch --prune`, branches whose upstream
# vanished are listed — and deleted only with --yes. The current branch is
# never touched.
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

learnExec git fetch --all --prune

current="$(git branch --show-current)"
gone=""
while IFS= read -r line; do
  branch="${line%% *}"
  case "$line" in
    *"[gone]"*)
      [ "$branch" = "$current" ] && {
        logWarn "current branch '$branch' has a gone upstream — not touching it"
        continue
      }
      gone="$gone$branch
"
      ;;
  esac
done < <(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads)

if [ -z "$gone" ]; then
  logInfo "nothing to clean — no local branches with gone upstreams."
  exit 0
fi

if [ "$yes" = 0 ]; then
  logInfo "would delete (run with --yes to do it):"
  printf '%s' "$gone" | while IFS= read -r b; do
    [ -n "$b" ] && echo "  $b"
  done
  exit 0
fi

printf '%s' "$gone" | while IFS= read -r b; do
  [ -n "$b" ] && learnExec git branch -D "$b"
done
logInfo "cleaned."
