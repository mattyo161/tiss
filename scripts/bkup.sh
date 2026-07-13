#!/usr/bin/env bash
# @description Back up files/dirs into a sibling .bkup/ dir, named by mtime
# @usage tiss bkup <file|dir...>
# @example tiss bkup nginx.conf
# @example tiss bkup ~/.zshrc ~/.tmux.conf
#
# Copies with cp -p (permissions + timestamps preserved) into .bkup/ next
# to each target, named <name>.<mtime-timestamp>. Unchanged files are
# skipped (same mtime = same backup name). Prints backup paths to stdout.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

bkup "$@"
