# shellcheck shell=bash
#
# tiss deferred deletion — "this file will self-destruct in 5 minutes".
#
#   rmAfter <duration> <file...>   schedule deletion (durations per dur2s:
#                                  15s, 5m, 1h, 1w1d — bare number = minutes)
#   tissReapRmAfter                delete everything past due
#
# How it works (see DESIGN.md): each schedule is a symlink in the rmAfter
# state dir whose name starts with the deletion epoch
# (<epoch>.<pid>.<n>.<rand> -> /abs/path/to/file). The reaper scans the dir,
# deletes past-due targets and their symlinks. The dispatcher runs the
# reaper in the background on EVERY tiss invocation, so cleanup is
# continuous without any daemon — a readdir on an empty dir costs nothing.
#
# The classic pattern this enables:
#   creds="$(mktemp)"; write creds; rmAfter 15s "$creds"
#   mysql --defaults-extra-file="$creds" ...   # works now, gone in 15s
#
tissStateDir() {
  echo "${TISS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/tiss}"
}

tissRmAfterDir() {
  echo "$(tissStateDir)/rmAfter"
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
    # Epoch prefix makes schedules sort chronologically; suffix avoids
    # collisions when scheduling several files in the same second.
    ln -s "$abs" "$dir/$when.$$.$n.$RANDOM"
    n=$((n + 1))
    logDebug "rmAfter: '$abs' will be deleted at $(ts2js "$when")"
  done
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
    if [ -d "$target" ]; then
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
