#!/usr/bin/env bash
# @description Forget the unlocked encryption identity for this session
# @usage tiss lock
# @example tiss lock
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

tissLockSession
logInfo "Session locked — next decrypt will ask for your passphrase."
