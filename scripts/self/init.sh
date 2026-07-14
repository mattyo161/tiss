#!/usr/bin/env bash
# @description Emit rc integration (makes `tiss self cd` pushd for real)
# @usage eval "$(tiss self init)"
# @example eval "$(tiss self init)"   # in ~/.zshrc or ~/.bashrc
#
# Emits a wrapper function named after however you invoke tiss (symlink
# as `x` and it wraps `x`), intercepting `self cd` to pushd in YOUR
# shell; everything else forwards to the real binary. popd returns.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

sed "s/__NAME__/$TISS_NAME/g" <<'WRAP'
__NAME__() {
  if [ "${1:-}" = "self" ] && [ "${2:-}" = "cd" ]; then
    pushd "$(command __NAME__ self cd 2>/dev/null)" || return
  else
    command __NAME__ "$@"
  fi
}
WRAP
