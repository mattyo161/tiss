#!/usr/bin/env bash
# @description Get SSM parameters (--name/--names/--path) as jsonl, cached + encrypted
# @usage tiss ssm get (--name N | --names N1,N2 | --path P) [--duration 1h] [--refresh|--recache|--no-cache] [--no-encrypt] [--no-decryption] [aws args...]
# @example tiss ssm get --path /develop | jq -r '.Name + " = " + .Value'
# @example tiss ssm get --name /develop/db/password --no-cache
# @example tiss ssm get --names /a,/b --duration 1d
# @needs aws jq
#
# The canonical tiss wrapper (see docs/cookbook-wrappers.md): one verb
# fronting aws ssm get-parameter / get-parameters / get-parameters-by-path,
# with the tiss defaults baked in --
#   - results stream as jsonl (one parameter per line, jq-ready)
#   - --with-decryption on by default (--no-decryption to disable)
#   - cached via cacheExec --encrypt --duration 1h: repeat calls are
#     instant, cached secrets are encrypted at rest, and AWS_PROFILE /
#     AWS_REGION changes key separate cache entries automatically
# Flags can appear in any order; anything unrecognized passes through to
# aws untouched (e.g. --max-results 5 --recursive).
#
set -euo pipefail
source "$TISS_LIB/init.sh"

mode=""
value=""
dur="1h"
refresh=""
cache=1
enc=1
decrypt=1
extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    --name)
      mode=name
      value="${2:?--name needs a parameter name}"
      shift
      ;;
    --names)
      mode=names
      value="${2:?--names needs a comma-separated list}"
      shift
      ;;
    --path)
      mode=path
      value="${2:?--path needs a path prefix}"
      shift
      ;;
    --duration)
      dur="${2:?--duration needs a value (1h, 1d, 30...)}"
      shift
      ;;
    --refresh) refresh="--refresh" ;;
    --recache) refresh="--recache" ;;
    --no-cache) cache=0 ;;
    --no-encrypt) enc=0 ;;
    --no-decryption) decrypt=0 ;;
    *) extra+=("$1") ;; # anything else belongs to aws
  esac
  shift
done

if [ -z "$mode" ]; then
  logError "one of --name, --names or --path is required (see: $TISS_NAME ssm get help)"
  exit 2
fi

# Map the tiss verb onto the right aws subcommand + jq unwrap.
aws_args=(ssm)
filter=""
case "$mode" in
  name)
    aws_args+=(get-parameter --name "$value")
    filter='.Parameter'
    ;;
  names)
    aws_args+=(get-parameters --names)
    for n in ${value//,/ }; do
      aws_args+=("$n")
    done
    filter='.Parameters[]'
    ;;
  path)
    aws_args+=(get-parameters-by-path --path "$value")
    filter='.Parameters[]'
    ;;
esac
[ "$decrypt" = 1 ] && aws_args+=(--with-decryption)
aws_args+=(${extra[@]+"${extra[@]}"})

# Front the call with cacheExec unless opted out. Raw aws JSON is what
# gets cached (encrypted at rest); the jq unwrap to jsonl runs per read.
runner=()
if [ "$cache" = 1 ]; then
  runner=(cacheExec --duration "$dur")
  [ -n "$refresh" ] && runner+=(--refresh)
  [ "$enc" = 1 ] && runner+=(--encrypt)
fi

${runner[@]+"${runner[@]}"} aws "${aws_args[@]}" | jq -c "$filter"
