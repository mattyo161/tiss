#!/usr/bin/env bash
# @description Any ajl call (boto3 as jsonl) — reads cached, writes narrated, never cached
# @usage tiss ajl <service> <operation> [args...]
# @example tiss ajl ec2 describe-instances
# @example tiss ajl s3 list-buckets --fetch-tags
# @needs ajl
#
# ajl (github.com/mattyo161/ajl) streams any boto3 operation as jsonl —
# tiss's native dialect — with aws-cli-style args, pagination by default
# and normalized Type/Id/Name/Arn/Tags. This handler adds the ssm-style
# intent routing on top:
#   <svc> get-*/describe-*/list-*  ->  read-only: fronted by cacheExec
#   anything else                  ->  may mutate: NEVER cached, narrated
#                                      via learnExec so you see what ran
# Streaming calls (--params-json) are never cached either: stdin drives
# the call, so identical argv does not mean identical input.
# Tune via config (env always wins): TISS_AJL_CACHE_DURATION,
# TISS_AJL_CACHE_ENCRYPT=1 to encrypt cached results at rest.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

cfg TISS_AJL_CACHE_DURATION 15m
cfg TISS_AJL_CACHE_ENCRYPT 0

streaming=0
for arg in "$@"; do
  [ "$arg" = "--params-json" ] && streaming=1
done

case "${2:-}" in
  get-* | describe-* | list-*)
    if [ "$streaming" = 1 ]; then
      exec ajl "$@"
    fi
    # Read-only: safe and valuable to cache (describe-* throttles hard at
    # scale). AWS_PROFILE/AWS_REGION are part of the cache key automatically.
    runner=(cacheExec --duration "$TISS_AJL_CACHE_DURATION")
    [ "$TISS_AJL_CACHE_ENCRYPT" = 1 ] && runner+=(--encrypt)
    "${runner[@]}" ajl "$@"
    ;;
  *)
    # Might mutate state: caching would be dangerous. Narrate it instead.
    learnExec ajl "$@"
    ;;
esac
