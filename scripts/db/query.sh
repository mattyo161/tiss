#!/usr/bin/env bash
# @description Run SQL against a registered connection, streaming jsonl
# @usage tiss db query <name> <sql> [--raw]
# @example tiss db query staging "select id, name from users limit 10" | jq .name
# @example tiss db query staging "select * from orders" --raw > orders.tsv
# @needs mysql mlr
#
# Output is jsonl by default so results chain straight into jq,
# saveData, json2csv, json2xlsx... --raw emits mysql's native TSV
# (header row included) untouched.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

name=""
sql=""
raw=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      tissHelp "$0"
      exit 0
      ;;
    --raw) raw=1 ;;
    -*)
      logError "unknown argument: $1"
      exit 2
      ;;
    *)
      if [ -z "$name" ]; then
        name="$1"
      else
        sql="$sql${sql:+ }$1"
      fi
      ;;
  esac
  shift
done
if [ -z "$name" ] || [ -z "$sql" ]; then
  logError "usage: $TISS_NAME db query <name> <sql>"
  exit 2
fi

if [ "$raw" = 1 ]; then
  exec mysql --defaults-extra-file=<(readData "db/$name") -B -e "$sql"
fi
mysql --defaults-extra-file=<(readData "db/$name") -B -e "$sql" | mlr --itsv --ojsonl cat
