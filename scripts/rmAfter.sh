#!/usr/bin/env bash
# @description Schedule file deletion after a duration (self-destructing files)
# @usage tiss rmAfter <duration> <file...>
# @example tiss rmAfter 15s /tmp/db_creds.ini
# @example tiss rmAfter 1h build.log debug.log
#
# Durations: 15s, 5m, 1h, 1w1d... (bare number = minutes). Scheduling
# returns immediately; a self-managing background monitor (pidfile-tracked,
# started by rmAfter itself) sleeps until deadlines come due, reaps, and
# exits when nothing is left. The file stays usable until its time comes.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help)
    tissHelp "$0"
    exit 0
    ;;
esac

rmAfter "$@"
