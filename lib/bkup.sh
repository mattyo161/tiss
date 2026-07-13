# shellcheck shell=bash
#
# tiss quick backups — protect a file before you touch it, without clutter.
#
#   bkup <file|dir...>   copy each target into a .bkup/ dir alongside it,
#                        named <name>.<mtime-timestamp>, via cp -p
#                        (permissions and timestamps preserved).
#
# The timestamp is the file's MODIFICATION time, not the backup time — so
# backing up an unchanged file is idempotent (same name, skipped), and the
# backup's name tells you which era of the file it holds. Backup paths are
# printed to stdout, one per line, so scripts can capture them:
#
#   before="$(bkup nginx.conf)"    # .bkup/nginx.conf.20260712T183042
#
bkup() { # bkup <file|dir...> -> prints backup path(s)
  if [ $# -eq 0 ]; then
    logError "usage: bkup <file|dir...>"
    return 2
  fi

  local f dir base mts dest rc=0
  for f in "$@"; do
    if [ ! -e "$f" ]; then
      logError "bkup: '$f' does not exist"
      rc=1
      continue
    fi
    f="${f%/}" # trailing slash would confuse dirname/basename
    dir="$(cd -P "$(dirname "$f")" && pwd)"
    base="$(basename "$f")"
    mts="$(epoch2ts "$(tissFileMtime "$f")")"
    dest="$dir/.bkup/$base.$mts"

    mkdir -p "$dir/.bkup"

    if [ -e "$dest" ]; then
      # Same name = same mtime = nothing changed since the last backup.
      logDebug "bkup: '$base' unchanged since last backup"
      printf '%s\n' "$dest"
      continue
    fi

    if [ -d "$f" ]; then
      cp -Rp "$f" "$dest" || {
        logError "bkup: failed to copy directory '$f'"
        rc=1
        continue
      }
    else
      cp -p "$f" "$dest" || {
        logError "bkup: failed to copy '$f'"
        rc=1
        continue
      }
    fi
    logInfo "bkup: $f -> $dest"
    printf '%s\n' "$dest"
  done
  return "$rc"
}
