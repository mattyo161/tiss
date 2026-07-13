#!/usr/bin/env bash
# @description Save stdin as named data (gzipped by default, optional --encrypt)
# @usage tiss saveData [--no-gzip] [--encrypt] <name>
# @example aws ssm describe-parameters | tiss saveData aws/params
# @example echo "secret" | tiss saveData --encrypt --no-gzip dbserver_creds
#
# Writes go to a tmp file and are renamed atomically on completion, so
# readers never see partial data. The extension chain records what was done
# (params.gz.age = gzipped then encrypted) and readData unwinds it — no
# flags needed on the way back out.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

saveData "$@"
