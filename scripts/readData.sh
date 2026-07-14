#!/usr/bin/env bash
# @description Stream named data to stdout (decrypts/decompresses automatically)
# @usage tiss readData <name>
# @example tiss readData aws/params | jq .
# @example mysql --defaults-extra-file=<(tiss readData dbserver_creds)
#
# The stored file's extension chain says how it was written; readData
# unwinds it right-to-left (decrypt, then decompress). Encrypted data
# prompts for your passphrase once per session (see: tiss lock).
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

readData "$@"
