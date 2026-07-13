# shellcheck shell=bash
#
# tiss deferred deletion — "this file will self-destruct in 5 minutes".
#
#   rmAfter <duration> <file...>   schedule deletion (durations per dur2s:
#                                  15s, 5m, 1h, 1w1d — bare number = minutes)
#
# How it works (see DESIGN.md): each schedule is a symlink in the rmAfter
# state dir whose name starts with the deletion epoch
# (<epoch>.<pid>.<n>.<rand> -> /abs/path/to/file).
#
# Reaping is driven by a self-managing background monitor, started by
# rmAfter itself and tracked with a pidfile:
#   - rmAfter reaps anything already past due, schedules the new files,
#     then makes sure the monitor is running (pidfile + kill -0 check).
#   - The monitor sleeps until the next deadline (capped at
#     TISS_RMAFTER_INTERVAL, default 60s), reaps, repeats — and exits when
#     no schedules remain, removing its pidfile. No daemon lingers.
#
# The classic pattern this enables:
#   creds="$(mktemp)"; write creds; rmAfter 15s "$creds"
#   mysql --defaults-extra-file="$creds" ...   # works now, gone in ~15s
#
tissStateDir() {
  echo "${TISS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/tiss}"
}

tissRmAfterDir() {
  echo "$(tissStateDir)/rmAfter"
}

# Deletion allowlist: rmAfter will only ever delete files under these
# colon-separated prefixes (TISS_RMAFTER_PATHS overrides). Defaults cover
# the user's home and the usual tmp locations (macOS TMPDIR lives under
# /var/folders). Checked at schedule time (friendly error) AND at reap time
# (defense in depth: a symlink planted in the state dir pointing at
# /etc/anything gets dropped, never followed).
tissRmAfterAllowed() { # tissRmAfterAllowed <abs-path> -> 0 if deletable
  local target="$1" prefix
  local allow="${TISS_RMAFTER_PATHS:-$HOME:${TMPDIR:-/tmp}:/tmp:/private/tmp:/var/folders:/private/var/folders}"
  local IFS=':'
  for prefix in $allow; do
    [ -n "$prefix" ] || continue
    prefix="${prefix%/}"
    case "$target" in "$prefix"/*) return 0 ;; esac
  done
  return 1
}

rmAfter() { # rmAfter <duration> <file...>
  local spec="${1:-}"
  shift || true
  if [ -z "$spec" ] || [ $# -eq 0 ]; then
    logError "usage: rmAfter <duration> <file...>"
    return 2
  fi

  local when
  when="$(utc "+$spec")" || return 2

  local dir
  dir="$(tissRmAfterDir)"
  mkdir -p "$dir"

  # Catch up on anything already past due before adding more.
  tissReapRmAfter

  local f abs n=0
  for f in "$@"; do
    if [ -d "$f" ]; then
      logError "rmAfter: '$f' is a directory — files only"
      return 2
    fi
    [ -e "$f" ] || logWarn "rmAfter: '$f' does not exist yet (scheduling anyway)"
    # Resolve to an absolute path so the symlink survives cwd changes.
    case "$f" in
      /*) abs="$f" ;;
      *) abs="$(cd -P "$(dirname "$f")" && pwd)/$(basename "$f")" ;;
    esac
    if ! tissRmAfterAllowed "$abs"; then
      logError "rmAfter: '$abs' is outside the deletable paths (home + tmp by default; set TISS_RMAFTER_PATHS to customize)"
      return 2
    fi
    # Epoch prefix makes schedules sort chronologically; suffix avoids
    # collisions when scheduling several files in the same second.
    ln -s "$abs" "$dir/$when.$$.$n.$RANDOM"
    n=$((n + 1))
    logDebug "rmAfter: '$abs' will be deleted at $(ts2js "$when")"
  done

  tissEnsureRmAfterMonitor
}

tissReapRmAfter() { # delete past-due files and their schedule symlinks
  local dir
  dir="$(tissRmAfterDir)"
  [ -d "$dir" ] || return 0

  local now link when target
  now="$(date +%s)"
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    when="${link##*/}"
    when="${when%%.*}"
    case "$when" in "" | *[!0-9]*) continue ;; esac
    [ "$when" -le "$now" ] || continue

    target="$(readlink "$link")"
    if ! tissRmAfterAllowed "$target"; then
      # A schedule pointing outside the allowlist never came from rmAfter —
      # drop it and touch nothing.
      logWarn "rmAfter: refusing to delete '$target' (outside deletable paths) — schedule dropped"
    elif [ -d "$target" ]; then
      # Never recursively delete: a directory appearing where a file was
      # scheduled is suspicious — drop the schedule, keep the directory.
      logWarn "rmAfter: skipping '$target' (directory now; was scheduled as a file)"
    elif [ -e "$target" ]; then
      rm -f "$target"
      logDebug "rmAfter: deleted '$target'"
    fi
    rm -f "$link"
  done
  return 0
}

tissRmAfterNextDeadline() { # earliest scheduled epoch, empty if none
  local dir link when next=""
  dir="$(tissRmAfterDir)"
  [ -d "$dir" ] || return 0
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    when="${link##*/}"
    when="${when%%.*}"
    case "$when" in "" | *[!0-9]*) continue ;; esac
    if [ -z "$next" ] || [ "$when" -lt "$next" ]; then
      next="$when"
    fi
  done
  [ -n "$next" ] && echo "$next"
  return 0
}

tissEnsureRmAfterMonitor() { # start the background monitor unless running
  local pidfile pid
  pidfile="$(tissRmAfterDir)/.monitor.pid"
  if [ -f "$pidfile" ]; then
    pid="$(cat "$pidfile" 2>/dev/null)" || pid=""
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0 # already running
    fi
  fi
  # Detach fully (own fds, orphaned subshell) so the monitor outlives the
  # script/pipeline that scheduled the deletion.
  (tissRmAfterMonitorLoop </dev/null >/dev/null 2>&1 &)
  logDebug "rmAfter: monitor started"
}

tissRmAfterMonitorLoop() { # sleep -> reap -> repeat; retire when idle
  local dir pidfile interval next now sleep_s mypid
  dir="$(tissRmAfterDir)"
  pidfile="$dir/.monitor.pid"
  # $$ in a subshell reports the PARENT's pid — we need our own. BASHPID
  # (bash 4+) is exact; the sh -c trick covers macOS's bash 3.2.
  mypid="${BASHPID:-$(sh -c 'echo $PPID')}"
  echo "$mypid" >"$pidfile"
  interval="${TISS_RMAFTER_INTERVAL:-60}"

  while :; do
    # If a concurrent start raced us, the pidfile holds the winner: lose
    # gracefully rather than double-reap forever.
    [ "$(cat "$pidfile" 2>/dev/null)" = "$mypid" ] || return 0

    next="$(tissRmAfterNextDeadline)"
    if [ -z "$next" ]; then
      rm -f "$pidfile" # nothing scheduled — monitor retires
      return 0
    fi

    now="$(date +%s)"
    sleep_s=$((next - now))
    [ "$sleep_s" -gt "$interval" ] && sleep_s="$interval"
    [ "$sleep_s" -lt 1 ] && sleep_s=1
    sleep "$sleep_s"
    tissReapRmAfter
  done
}
