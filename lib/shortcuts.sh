# shellcheck shell=bash
#
# tiss shortcuts — muscle-memory names for tiss commands (`tfplan` for
# `tiss tf plan`, `saveData` for `tiss saveData`).
#
# Each shortcut is a real executable: a symlink in $TISS_SHIMS pointing
# back at the dispatcher, which recognizes the invocation name (argv[0])
# and prepends the mapped words. No generated stub code — the symlink IS
# the shim, so overlay shadowing, --help and future dispatcher features
# keep working without a resync. The dispatcher strips $TISS_SHIMS from
# PATH at startup, so child scripts and passthrough tools only ever see
# real commands: recursion through a shim is structurally impossible,
# and shortcuts stay a human-fingers layer that never leaks downstream.
#
# Definitions live in $TISS_CONFIG/shortcuts (yours) and each tree's
# etc/shortcuts — one `name = command words` per line, # comments fine.
# Your file wins, then trees most-specific first (config precedence,
# same story). Managed by `tiss self shortcuts add|remove|list|sync`.

tissShims() { # the shim directory (setting: TISS_SHIMS)
  printf '%s\n' "${TISS_SHIMS:-${XDG_DATA_HOME:-$HOME/.local/share}/tiss/shims}"
}

tissShortcutFiles() { # definition files, highest precedence first
  local tree
  [ -f "$TISS_CONFIG/shortcuts" ] && printf '%s\n' "$TISS_CONFIG/shortcuts"
  while IFS= read -r tree; do
    [ -f "$tree/etc/shortcuts" ] && printf '%s\n' "$tree/etc/shortcuts"
  done < <(tissTrees)
  return 0
}

tissShortcutList() { # merged "name<TAB>expansion<TAB>source-file", first definition wins
  local f line name exp seen="
"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line#"${line%%[![:space:]]*}"}" # trim (bash 3.2 safe)
      line="${line%"${line##*[![:space:]]}"}"
      case "$line" in '' | \#*) continue ;; esac
      case "$line" in *=*) ;; *) continue ;; esac
      name="${line%%=*}"
      name="${name%"${name##*[![:space:]]}"}"
      exp="${line#*=}"
      exp="${exp#"${exp%%[![:space:]]*}"}"
      [ -n "$name" ] && [ -n "$exp" ] || continue
      case "$name" in *[!A-Za-z0-9_.-]*) continue ;; esac
      case "$seen" in *"
$name
"*) continue ;; esac # shadowed by a higher-precedence file
      seen="$seen$name
"
      printf '%s\t%s\t%s\n' "$name" "$exp" "$f"
    done <"$f"
  done < <(tissShortcutFiles)
  return 0
}

tissShortcutLookup() { # tissShortcutLookup <name> -> expansion words, or fail
  local name exp _src
  while IFS=$'\t' read -r name exp _src; do
    if [ "$name" = "$1" ]; then
      printf '%s\n' "$exp"
      return 0
    fi
  done < <(tissShortcutList)
  return 1
}