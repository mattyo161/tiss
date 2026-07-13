# shellcheck shell=bash
#
# tiss time helpers — one standard for timestamps and durations, everywhere.
#
#   ts                    compact timestamp: 20260712T183042 (great in filenames)
#   utc [+-]<duration>    epoch seconds now, optionally offset: utc +1w2d
#   dur2s <duration>      duration -> seconds: 1w1d5h -> 622800
#   ts2js <epoch>         epoch -> ISO8601 UTC: 2026-07-12T18:30:42Z
#
# Duration format (used by cacheExec --duration, rmAfter, utc, ...):
#   <n>w weeks, <n>d days, <n>h hours, <n>m minutes, <n>s seconds,
#   combined freely ("1w1d5h"); a bare number means MINUTES ("10" = 10m).
#
ts() {
  date +"%Y%m%dT%H%M%S"
}

dur2s() { # dur2s <duration> -> seconds
  local spec="${1:-}"
  if [ -z "$spec" ]; then
    echo "dur2s: missing duration" >&2
    return 1
  fi
  # Bare number = minutes (design convention: `10` is 10 minutes, `100s` is seconds)
  case "$spec" in
    *[!0-9]*) ;;
    *)
      echo $((spec * 60))
      return 0
      ;;
  esac
  if ! printf '%s' "$spec" | grep -Eq '^([0-9]+[wdhms])+$'; then
    echo "dur2s: invalid duration '$spec' (want e.g. 1w2d3h4m5s, or bare minutes)" >&2
    return 1
  fi
  local total=0 pair n u
  for pair in $(printf '%s' "$spec" | sed -E 's/([0-9]+[wdhms])/\1 /g'); do
    n="${pair%?}"
    u="${pair#"$n"}"
    case "$u" in
      w) total=$((total + n * 604800)) ;;
      d) total=$((total + n * 86400)) ;;
      h) total=$((total + n * 3600)) ;;
      m) total=$((total + n * 60)) ;;
      s) total=$((total + n)) ;;
    esac
  done
  echo "$total"
}

utc() { # utc [+-]<duration> -> epoch seconds, optionally offset from now
  local now
  now="$(date +%s)"
  if [ $# -eq 0 ]; then
    echo "$now"
    return 0
  fi
  local spec="$1" sign=1
  case "$spec" in
    -*) sign=-1 spec="${spec#-}" ;;
    +*) spec="${spec#+}" ;;
  esac
  local secs
  secs="$(dur2s "$spec")" || return 1
  echo $((now + sign * secs))
}

ts2js() { # ts2js <epoch> -> ISO8601 UTC (works with BSD and GNU date)
  local epoch="${1:?usage: ts2js <epoch>}"
  date -u -r "$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null ||
    date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%SZ"
}
