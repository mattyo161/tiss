#!/usr/bin/env bash
# @description Print the tiss home dir (with shell integration: pushd there)
# @usage tiss self cd
# @example tiss self cd
#
# A child process can't change your shell's directory — so this prints
# the path, and the shell integration (eval "$(tiss self shell)" in your
# rc) turns `tiss self cd` into a real pushd; popd brings you back.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

echo "$TISS_HOME"
if [ -t 1 ]; then
  logInfo "to make this a real pushd, add to your shell rc:  eval \"\$($TISS_NAME self shell)\""
fi
