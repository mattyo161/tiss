#!/usr/bin/env bash
# @description Any aws ssm subcommand — reads cached + encrypted, writes narrated, never cached
# @usage tiss ssm <subcommand> [aws args...]
# @example tiss ssm describe-parameters --max-results 5
# @example tiss ssm put-parameter --name /x --value 1 --type String
# @needs aws
#
# The namespace handler (_self): catches every `tiss ssm ...` that no
# dedicated script owns. It routes by intent —
#   get-* / describe-* / list-*  ->  read-only: fronted by cacheExec
#                                    (encrypted at rest, 1h default)
#   anything else                ->  may mutate: NEVER cached, narrated
#                                    via learnExec so you see what ran
# Tune via config (env always wins): TISS_SSM_CACHE_DURATION,
# TISS_SSM_CACHE_ENCRYPT=0 to disable cache encryption.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

cfg TISS_SSM_CACHE_DURATION 1h
cfg TISS_SSM_CACHE_ENCRYPT 1

case "${1:-}" in
  get-* | describe-* | list-*)
    # Read-only: safe and valuable to cache. AWS_PROFILE/AWS_REGION are
    # part of the cache key automatically.
    runner=(cacheExec --duration "$TISS_SSM_CACHE_DURATION")
    [ "$TISS_SSM_CACHE_ENCRYPT" = 1 ] && runner+=(--encrypt)
    "${runner[@]}" aws ssm "$@"
    ;;
  *)
    # Might mutate state: caching would be dangerous (a repeated
    # put-parameter must actually run). Narrate it instead.
    learnExec aws ssm "$@"
    ;;
esac
