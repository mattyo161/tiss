#!/usr/bin/env bash
# @description Kill a tmux session by name
# @usage tiss tmux kill <name>
# @example tiss tmux kill deploys
# @needs tmux
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help | "")
    tissHelp "$0"
    exit 0
    ;;
esac

learnExec tmux kill-session -t "$1"
logInfo "killed '$1'."
