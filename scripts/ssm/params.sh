#!/usr/bin/env bash
# @description Describe SSM parameters using `ajl` to get full set of parameters
# @usage tiss ssm params [--duration 1h] [--refresh|--recache|--no-cache]
# @example tiss ssm params | jq -r '.Name'
# @example tiss ssm params --no-cache
# @example tiss ssm params --duration 1d
# @needs aws jq
#
# The describe-parameters is notorious for throttling especially when you have a large
# number of parameters. By caching them locally in jsonl format you can quickly scan
# all your parameters, names, determine conventions, check kms keys, etc.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

dur="1h"
refresh=""
cache=1
extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    --duration)
      dur="${2:?--duration needs a value (1h, 1d, 30...)}"
      shift
      ;;
    --refresh) refresh="--refresh" ;;
    --recache) refresh="--recache" ;;
    --no-cache) cache=0 ;;
    *) extra+=("$1") ;; # anything else belongs to aws
  esac
  shift
done

# Front the call with cacheExec unless opted out. Raw aws JSON is what
# gets cached (encrypted at rest); the jq unwrap to jsonl runs per read.
runner=()
if [ "$cache" = 1 ]; then
  runner=(cacheExec --duration "$dur")
  [ -n "$refresh" ] && runner+=(--refresh)
fi

# TODO test performance vs ajl
${runner[@]+"${runner[@]}"} aws ssm describe-parameters ${extra[@]+"${extra[@]}"} | jq -c '.Parameters[]'
