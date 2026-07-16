#!/usr/bin/env bash
# @description Time helpers as commands: compact ts, epoch math, conversions
# @usage tiss time [ts|utc [+-DUR]|dur2s DUR|s2dur SECS|ts2js EPOCH|epoch2ts EPOCH]
# @example tiss time ts               # 20260712T183042 — great in filenames
# @example tiss time utc +1w2d       # epoch seconds, one week two days out
# @example tiss time dur2s 1h30m     # 5400
#
# One time standard everywhere (see lib/time.sh): compact local
# timestamps, epoch seconds for math, ISO8601 UTC for exchange, and the
# tiss duration grammar (1w2d3h4m5s; bare number = minutes). Bare
# `tiss time` prints the compact timestamp.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-ts}" in
  -h | --help | help)
    tissHelp "$0"
    ;;
  ts | utc | dur2s | s2dur | ts2js | epoch2ts)
    fn="${1:-ts}"
    [ $# -gt 0 ] && shift
    "$fn" "$@"
    ;;
  *)
    logError "unknown subcommand '${1}' (ts, utc, dur2s, s2dur, ts2js, epoch2ts)"
    exit 2
    ;;
esac
