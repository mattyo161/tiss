#!/usr/bin/env bash
# @description Muscle-memory shortcuts — bare names that run tiss commands
# @usage tiss shortcuts [list|add NAME COMMAND...|remove NAME|sync|edit|path]
# @example tiss shortcuts add tfplan tf plan
# @example tiss shortcuts add saveData saveData
# @example tiss shortcuts edit
#
# A shortcut makes a tiss command feel native: `tfplan` instead of
# `tiss tf plan` — a real executable on your PATH, so it works in
# scripts, xargs and cron, not just interactive shells. Each name is a
# symlink in $TISS_SHIMS back to the dispatcher, which recognizes the
# invocation name and prepends the mapped words (no generated code,
# nothing to go stale). The dispatcher strips the shim dir from child
# PATHs, so shortcuts can never recurse or shadow tools downstream.
#
# Definitions live in ~/.config/tiss/shortcuts (yours) and each overlay
# tree's etc/shortcuts — `name = command words`, one per line; yours
# win, then trees most-specific first. Put the shim dir on PATH with
# the rc line from:  eval "$(tiss init)"
#
set -euo pipefail
source "$TISS_LIB/init.sh"

shortcutsFile="$TISS_CONFIG/shortcuts"
template="$TISS_HOME/etc/shortcuts.example"
shims="$(tissShims)"
dispatcher="$TISS_HOME/bin/tiss"

seed() { # first touch: start from the commented suggested set
  if [ ! -f "$shortcutsFile" ]; then
    mkdir -p "$TISS_CONFIG"
    cp "$template" "$shortcutsFile"
    logInfo "created $shortcutsFile (suggested set, commented — uncomment to activate)"
  fi
}

sourceTag() { # sourceTag <definition-file> -> user | core | tree name
  case "$1" in
    "$shortcutsFile") echo "user" ;;
    "$TISS_HOME/etc/shortcuts") echo "core" ;;
    *) basename "${1%/etc/shortcuts}" ;;
  esac
}

shimStatus() { # shimStatus <name> -> ok | missing | stale | blocked
  local entry="$shims/$1"
  if [ -L "$entry" ]; then
    if [ "$(readlink "$entry")" = "$dispatcher" ]; then
      echo ok
    else
      case "$(readlink "$entry")" in
        */bin/tiss) echo stale ;; # a tiss shim, but not THIS dispatcher
        *) echo blocked ;;        # someone else's symlink — never touched
      esac
    fi
  elif [ -e "$entry" ]; then
    echo blocked
  else
    echo missing
  fi
}

pathHint() { # nudge when the shim dir isn't on PATH (dispatcher checked)
  [ "${TISS_SHIMS_ON_PATH:-0}" = 1 ] && return 0
  logWarn "shim dir is not on your PATH — add to your rc file:  eval \"\$($TISS_NAME init)\""
}

cmdList() {
  if ! tissShortcutList | grep -q .; then
    logInfo "no shortcuts yet — try:  $TISS_NAME shortcuts add tfplan tf plan"
    return 0
  fi
  printf '%-18s %-34s %-8s %s\n' "NAME" "RUNS" "SHIM" "SOURCE"
  local name exp file
  while IFS=$'\t' read -r name exp file; do
    printf '%-18s %-34s %-8s %s\n' "$name" "$TISS_NAME $exp" "$(shimStatus "$name")" "$(sourceTag "$file")"
  done < <(tissShortcutList)
  echo
  echo "shim dir: $shims"
  pathHint
}

cmdSync() {
  mkdir -p "$shims"
  local entry base name exp link changed=0
  # Prune tiss shims whose shortcut is gone; foreign files are sacred.
  for entry in "$shims"/*; do
    { [ -e "$entry" ] || [ -L "$entry" ]; } || continue
    base="$(basename "$entry")"
    if [ -L "$entry" ]; then
      link="$(readlink "$entry")"
      case "$link" in
        */bin/tiss)
          if ! tissShortcutLookup "$base" >/dev/null; then
            rm -f "$entry"
            logInfo "pruned: $base (no longer defined)"
            changed=1
          fi
          ;;
        *) logWarn "not a tiss shim (left alone): $entry -> $link" ;;
      esac
    else
      logWarn "not a tiss shim (left alone): $entry"
    fi
  done
  # One healthy shim per shortcut.
  while IFS=$'\t' read -r name exp _; do
    entry="$shims/$name"
    case "$(shimStatus "$name")" in
      ok) continue ;;
      blocked)
        logWarn "'$name' is blocked by a foreign file in $shims — remove it yourself if the shortcut should win"
        continue
        ;;
      stale) rm -f "$entry" ;;
    esac
    ln -s "$dispatcher" "$entry"
    logInfo "shim: $name -> $TISS_NAME $exp"
    changed=1
  done < <(tissShortcutList)
  [ "$changed" = 1 ] || logInfo "shims in sync ($shims)"
  pathHint
}

cmdAdd() {
  local name="$1"
  shift
  case "$name" in
    "" | [.-]* | *[!A-Za-z0-9_.-]*)
      logError "invalid shortcut name '$name' (letters, digits, _ . - only; can't start with . or -)"
      exit 2
      ;;
    tiss | "$TISS_NAME")
      logError "'$name' would shadow the dispatcher itself"
      exit 2
      ;;
  esac
  if tissReserved "$name"; then
    logError "'$name' is part of the reserved tiss lexicon — shortcuts can't take it"
    exit 2
  fi
  local real
  # PATH executables only (type -P): the sourced tiss helpers live as
  # functions in THIS shell and would self-trigger via command -v.
  if real="$(type -P "$name")"; then
    logWarn "'$name' shadows $real (the shim dir goes first on PATH, so your shortcut wins)"
  fi
  mkdir -p "$TISS_CONFIG"
  local tmp
  tmp="$(mktemp)"
  if [ -f "$shortcutsFile" ]; then
    # Replace an existing definition of this name, keep everything else.
    awk -v n="$name" -F= '{ s = $1; gsub(/^[ \t]+|[ \t]+$/, "", s) } s != n { print }' \
      "$shortcutsFile" >"$tmp"
  fi
  printf '%s = %s\n' "$name" "$*" >>"$tmp"
  mv "$tmp" "$shortcutsFile"
  logInfo "added: $name = $*"
  cmdSync
}

cmdRemove() {
  local name="$1" n exp file
  if [ -f "$shortcutsFile" ] \
    && awk -v n="$name" -F= '{ s = $1; gsub(/^[ \t]+|[ \t]+$/, "", s) } s == n { found = 1 } END { exit !found }' \
      "$shortcutsFile"; then
    local tmp
    tmp="$(mktemp)"
    awk -v n="$name" -F= '{ s = $1; gsub(/^[ \t]+|[ \t]+$/, "", s) } s != n { print }' \
      "$shortcutsFile" >"$tmp"
    mv "$tmp" "$shortcutsFile"
    logInfo "removed: $name"
    cmdSync
    return 0
  fi
  # Not yours to delete? Point at the owner instead of failing blind.
  while IFS=$'\t' read -r n exp file; do
    if [ "$n" = "$name" ]; then
      logError "'$name' is defined by $(sourceTag "$file") ($file) — edit that file, or shadow it: $TISS_NAME shortcuts add $name ..."
      exit 2
    fi
  done < <(tissShortcutList)
  logError "no shortcut '$name'"
  exit 2
}

case "${1:-list}" in
  -h | --help | help)
    tissHelp "$0"
    ;;
  list)
    cmdList
    ;;
  sync)
    cmdSync
    ;;
  path)
    seed
    echo "$shortcutsFile"
    ;;
  edit)
    seed
    "${EDITOR:-vi}" "$shortcutsFile"
    cmdSync # hand-edits reconcile immediately
    ;;
  add)
    [ $# -ge 3 ] || {
      logError "usage: $TISS_NAME shortcuts add NAME COMMAND..."
      exit 2
    }
    shift
    cmdAdd "$@"
    ;;
  remove | rm)
    [ -n "${2:-}" ] || {
      logError "usage: $TISS_NAME shortcuts remove NAME"
      exit 2
    }
    cmdRemove "$2"
    ;;
  *)
    logError "unknown subcommand '${1}' (list, add NAME COMMAND..., remove NAME, sync, edit, path)"
    exit 2
    ;;
esac