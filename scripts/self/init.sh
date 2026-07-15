#!/usr/bin/env bash
# @description Emit rc integration (shortcut shims on PATH; `self cd` pushds for real)
# @usage eval "$(tiss self init)"
# @example eval "$(tiss self init)"   # in ~/.zshrc or ~/.bashrc
#
# Emits two things:
#   1. a guarded PATH line putting the shortcut shim dir first, so the
#      names from `tiss self shortcuts` win everywhere (the dispatcher
#      strips the dir back out of child PATHs — shims never leak down)
#   2. a wrapper function named after however you invoke tiss (symlink
#      as `x` and it wraps `x`), intercepting `self cd` to pushd in YOUR
#      shell; everything else forwards to the real binary. popd returns.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

shims="$(tissShims)"
# shellcheck disable=SC2016  # $PATH must reach the user's rc unexpanded
printf 'case ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' "$shims" "$shims"

sed "s/__NAME__/$TISS_NAME/g" <<'WRAP'
__NAME__() {
  if [ "${1:-}" = "self" ] && [ "${2:-}" = "cd" ]; then
    pushd "$(command __NAME__ self cd 2>/dev/null)" || return
  else
    command __NAME__ "$@"
  fi
}
WRAP
