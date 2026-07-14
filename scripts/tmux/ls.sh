#!/usr/bin/env bash
# @description List tmux sessions as jsonl (name, windows, attached)
# @usage tiss tmux ls
# @example tiss tmux ls | jq -r 'select(.attached | not) | .name'
# @needs tmux jq
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

tmux list-sessions -F '#{session_name}	#{session_windows}	#{?session_attached,true,false}' 2>/dev/null |
  while IFS=$'\t' read -r name windows attached; do
    jq -cn --arg name "$name" --argjson windows "$windows" --argjson attached "$attached" \
      '{name: $name, windows: $windows, attached: $attached}'
  done
exit 0
