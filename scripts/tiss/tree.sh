#!/usr/bin/env bash
# @description Manage overlay script trees (add, remove, list)
# @usage tiss tiss tree <list|add PATH|remove PATH>
# @example tiss tiss tree add ~/work/acme-tiss
# @example tiss tiss tree list
#
# Overlay trees layer private/company commands over the core: most-specific
# first, first match wins. A tree is a directory containing scripts/
# (optional etc/config.sh for defaults, lib/init.sh for helpers). The tree
# stack is stored as TISS_PATH in ~/.config/tiss/config.sh; a TISS_PATH
# environment variable overrides it entirely.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

configFile="$TISS_CONFIG/config.sh"
marker="# tiss:tree-path (managed by 'tiss tiss tree')"

currentTrees() { # overlay roots from the current stack (core excluded)
  tissTrees | while IFS= read -r t; do
    [ "$t" = "$TISS_HOME" ] || printf '%s\n' "$t"
  done
}

writeTrees() { # writeTrees <colon-joined-paths> — persist to user config
  mkdir -p "$TISS_CONFIG"
  local tmp
  tmp="$(mktemp)"
  # Drop the previously managed lines, keep everything else.
  if [ -f "$configFile" ]; then
    grep -v -e "^cfg TISS_PATH " -e "^$marker\$" "$configFile" >"$tmp" || true
  fi
  if [ -n "$1" ]; then
    printf '%s\ncfg TISS_PATH "%s"\n' "$marker" "$1" >>"$tmp"
  fi
  mv "$tmp" "$configFile"
}

cmdList() {
  local tree n tag seen="
" f cmd shadows
  echo "tree stack (most specific first):"
  while IFS= read -r tree; do
    tag="$(treeTagLocal "$tree")"
    n=0
    shadows=0
    while IFS= read -r f; do
      [ -x "$f" ] || continue
      cmd="${f#"$tree"/scripts/}"
      cmd="${cmd%.*}"
      n=$((n + 1))
      case "$seen" in *"
$cmd
"*)
        shadows=$((shadows + 1))
        continue
        ;;
      esac
      seen="$seen$cmd
"
    done < <(find "$tree/scripts" -type f 2>/dev/null | sort)
    if [ "$shadows" -gt 0 ]; then
      printf '  %-40s %s commands (%s shadowed by a higher tree)\n' "$tag" "$n" "$shadows"
    else
      printf '  %-40s %s commands\n' "$tag" "$n"
    fi
  done < <(tissTrees)
  if [ -n "${TISS_PATH:-}" ] && [ ! -f "$configFile" ]; then
    logInfo "TISS_PATH is set from the environment only (nothing persisted yet)"
  fi
}

treeTagLocal() {
  if [ "$1" = "$TISS_HOME" ]; then
    echo "core ($1)"
  else
    echo "$1"
  fi
}

cmdAdd() {
  local path="$1" abs
  abs="$(cd -P "$path" 2>/dev/null && pwd)" || {
    logError "no such directory: $path"
    exit 2
  }
  if [ ! -d "$abs/scripts" ]; then
    logError "'$abs' is not a tiss tree (missing scripts/ directory)"
    logInfo "a tree needs: scripts/ (commands), optionally etc/config.sh and lib/init.sh"
    exit 2
  fi
  local trees="" t
  while IFS= read -r t; do
    [ "$t" = "$abs" ] && {
      logWarn "already registered: $abs"
      exit 0
    }
    trees="$trees:$t"
  done < <(currentTrees)
  # New trees go in front: most recently added = most specific.
  writeTrees "$abs${trees}"
  logInfo "added: $abs (position 1 — overrides everything below it)"
  TISS_PATH="$abs${trees}" cmdListAfterChange
}

cmdRemove() {
  local path="$1" abs trees="" t found=0
  abs="$(cd -P "$path" 2>/dev/null && pwd)" || abs="$path"
  while IFS= read -r t; do
    if [ "$t" = "$abs" ]; then
      found=1
      continue
    fi
    trees="$trees${trees:+:}$t"
  done < <(currentTrees)
  if [ "$found" = 0 ]; then
    logError "not registered: $abs"
    exit 2
  fi
  writeTrees "$trees"
  logInfo "removed: $abs"
  TISS_PATH="$trees" cmdListAfterChange
}

cmdListAfterChange() {
  cmdList
}

case "${1:-list}" in
  -h | --help)
    tissHelp "$0"
    ;;
  list)
    cmdList
    ;;
  add)
    [ -n "${2:-}" ] || {
      logError "usage: $TISS_NAME tiss tree add PATH"
      exit 2
    }
    cmdAdd "$2"
    ;;
  remove | rm)
    [ -n "${2:-}" ] || {
      logError "usage: $TISS_NAME tiss tree remove PATH"
      exit 2
    }
    cmdRemove "$2"
    ;;
  *)
    logError "unknown subcommand '${1}' (list, add PATH, remove PATH)"
    exit 2
    ;;
esac
