#!/usr/bin/env bash
# @description Attach to a tmux session (switches client if already inside)
# @usage tiss tmux attach [name]
# @example tiss tmux attach deploys
# @needs tmux
#
# With no name: attaches if exactly one session exists, lists otherwise.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

name="${1:-}"
if [ -z "$name" ]; then
  count="$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$count" = 1 ]; then
    name="$(tmux list-sessions -F '#{session_name}')"
  else
    logError "which one? sessions:"
    tmux list-sessions -F '  #{session_name} (#{session_windows} windows)' 2>/dev/null >&2 ||
      logInfo "none — create one with: $TISS_NAME tmux new"
    exit 2
  fi
fi

if [ -n "${TMUX:-}" ]; then
  learnExec tmux switch-client -t "$name"
else
  learnExec tmux attach-session -t "$name"
fi
