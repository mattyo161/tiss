#!/usr/bin/env bash
# @description Run a command while teaching what ran ([LEARN] line + history log)
# @usage tiss learnExec <command> [args...]
# @example tiss learnExec aws s3 ls s3://bucket/key
#
# Shows the command on stderr (secrets redacted) and appends it to
# $TISS_STATE/history.log, then runs the real thing untouched. Sprinkle it
# through multi-step scripts so users can follow exactly what happens.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

learnExec "$@"
