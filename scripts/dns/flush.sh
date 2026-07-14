#!/usr/bin/env bash
# @description Flush the OS DNS cache (knows the macOS and Linux incantations)
# @usage tiss dns flush [--dry-run]
# @example tiss dns flush
# @example tiss dns flush --dry-run   # show what would run
#
# The command nobody remembers, per platform: macOS needs two steps
# (dscacheutil + a HUP to mDNSResponder); Linux depends on the resolver
# in use. learnExec narrates the real commands, so you learn them too.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

dry=0
case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
  --dry-run) dry=1 ;;
  "") ;;
  *)
    logError "unknown argument: $1"
    exit 2
    ;;
esac

runCmds() { # runCmds "<command>"... — narrate+run, or just print (--dry-run)
  local c
  for c in "$@"; do
    if [ "$dry" = 1 ]; then
      echo "$c"
    else
      # shellcheck disable=SC2086  # word-splitting the command is intended
      learnExec $c
    fi
  done
}

case "$(uname -s)" in
  Darwin)
    runCmds "sudo dscacheutil -flushcache" "sudo killall -HUP mDNSResponder"
    ;;
  Linux)
    if command -v resolvectl >/dev/null 2>&1; then
      runCmds "sudo resolvectl flush-caches"
    elif command -v systemd-resolve >/dev/null 2>&1; then
      runCmds "sudo systemd-resolve --flush-caches"
    elif command -v nscd >/dev/null 2>&1; then
      runCmds "sudo nscd -i hosts"
    else
      logError "no known DNS cache service here (looked for resolvectl, systemd-resolve, nscd)"
      exit 1
    fi
    ;;
  *)
    logError "unsupported OS: $(uname -s)"
    exit 1
    ;;
esac
[ "$dry" = 1 ] || logInfo "DNS cache flushed."
