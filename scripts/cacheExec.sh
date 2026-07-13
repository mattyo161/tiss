#!/usr/bin/env bash
# @description Run a command through a content-addressed cache (default 1h)
# @usage tiss cacheExec [--duration D] [--refresh] [--encrypt] [--no-gzip] <command...>
# @example tiss cacheExec aws ssm describe-parameters
# @example tiss cacheExec --duration 1d --encrypt aws secretsmanager list-secrets
#
# The cache key is a SHA-256 of the command line plus significant env vars
# (AWS_PROFILE, AWS_REGION, KUBECONFIG, ... — extend with TISS_CACHE_ENV),
# so `AWS_PROFILE=prod` and `AWS_PROFILE=dev` cache separately. Failing
# commands are never cached. Durations per the tiss standard: 30 (minutes),
# 100s, 1h, 1w1d.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

cacheExec "$@"
