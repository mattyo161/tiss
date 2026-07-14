#!/usr/bin/env bash
# @description Encrypt stdin to stdout with your tiss identity (age)
# @usage tiss encrypt [--in FILE] [--out FILE]
# @example echo "secret" | tiss encrypt > secret.age
# @example tiss encrypt --in creds.ini --out creds.ini.age
# @needs age
#
# Encryption uses only your PUBLIC key, so this never prompts — safe in
# pipelines and cron. Decryption (tiss decrypt) unlocks once per session.
# First run walks you through creating an identity.
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
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    *)
      logError "unknown argument: $1 (see: $TISS_NAME encrypt --help)"
      exit 2
      ;;
  esac
done

recipients="$(tissRecipients)" || exit 1

args=(-R "$recipients")
[ "$out" != "-" ] && args+=(-o "$out")
[ "$in" != "-" ] && args+=("$in")

exec age "${args[@]}"
