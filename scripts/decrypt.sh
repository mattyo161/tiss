#!/usr/bin/env bash
# @description Decrypt stdin to stdout with your tiss identity (age)
# @usage tiss decrypt [--in FILE] [--out FILE]
# @example tiss decrypt < secret.age
# @example mysql --defaults-extra-file=<(tiss decrypt --in creds.ini.age)
# @needs age
#
# First decrypt of a session prompts for your identity passphrase, then the
# unlocked identity is cached (0700 per-user tmp dir) so subsequent decrypts
# are instant. `tiss lock` forgets it.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

in="-"
out="-"
while [ $# -gt 0 ]; do
  case "$1" in
    --in)
      in="${2:?--in needs a FILE}"
      shift 2
      ;;
    --out)
      out="${2:?--out needs a FILE}"
      shift 2
      ;;
    -h | --help)
      tissHelp "$0"
      exit 0
      ;;
    *)
      logError "unknown argument: $1 (see: $TISS_NAME decrypt --help)"
      exit 2
      ;;
  esac
done

identity="$(tissUnlockedIdentity)" || exit 1

args=(-d -i "$identity")
[ "$out" != "-" ] && args+=(-o "$out")
[ "$in" != "-" ] && args+=("$in")

exec age "${args[@]}"
