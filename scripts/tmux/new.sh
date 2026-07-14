#!/usr/bin/env bash
# @description Create a tmux session (and jump in, if you're at a terminal)
# @usage tiss tmux new [name]
# @example tiss tmux new deploys
# @needs tmux
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

name="${1:-tiss-$(ts)}"
learnExec tmux new-session -d -s "$name"
if [ -n "${TMUX:-}" ]; then
  learnExec tmux switch-client -t "$name"
elif [ -t 0 ] && [ -t 1 ]; then
  learnExec tmux attach-session -t "$name"
else
  logInfo "created '$name' (detached) — join with: $TISS_NAME tmux attach $name"
fi
