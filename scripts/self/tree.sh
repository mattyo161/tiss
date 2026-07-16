#!/usr/bin/env bash
# @description Manage overlay script trees (list, add, remove, resolve)
# @usage tiss self tree <list [--json]|add PATH|SPEC [--repo URL] [--branch BR]|remove PATH|NAME|resolve SPEC>
# @example tiss self tree add devops                    # same as: tiss +devops
# @example tiss self tree add prod --repo git@github.com:acme/tiss_packages.git --branch env/prod
# @example tiss self tree resolve devops                # where would this fetch from? (jsonl)
#
# Overlay trees layer private/company commands over the core: most-specific
# first, first match wins. A tree is a directory containing scripts/
# (optional etc/config.sh for defaults, lib/init.sh for helpers). The tree
# stack is stored as TISS_PATH in ~/.config/tiss/config.sh; a TISS_PATH
# environment variable overrides it entirely.
#
# `add` takes a local path OR a package spec (NAME[@VER], OWNER/REPO[@REF],
# URL[@REF]) — short names resolve to branch tree/<name> on the
# distribution repo unless --repo/--branch map them elsewhere; the mapping
# then lives in the clone (origin + tiss.track), inspect it with
# `resolve` or `list --json`. The `tiss +name` prefix is the shorthand.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

configFile="$TISS_CONFIG/config.sh"

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
  # Installed-but-disabled packages are one +name away — surface them.
  local d
  for d in "$(tissTreesDir)"/*; do
    [ -d "$d/scripts" ] || continue
    tissTreeStack | grep -qx "$d" && continue
    printf '  %-40s (installed, disabled — enable: %s +%s)\n' \
      "$(basename "$d")" "$TISS_NAME" "$(basename "$d")"
  done
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

cmdListJson() { # every tree as jsonl: core + registered + installed-but-disabled
  ensureTool jq || exit 127
  local t
  tissTreeInfoJson "$TISS_HOME" true
  while IFS= read -r t; do
    tissTreeInfoJson "$t" true
  done < <(tissTreeStack)
  for t in "$(tissTreesDir)"/*; do
    [ -d "$t/scripts" ] || continue
    tissTreeStack | grep -qx "$t" && continue
    tissTreeInfoJson "$t" false
  done
}

cmdAdd() { # cmdAdd <path|spec> <repo> <branch>
  local spec="$1" repo="$2" branch="$3" abs dir
  # An existing tree directory (and no mapping flags) is a local add.
  if [ -z "$repo$branch" ] && abs="$(cd -P "$spec" 2>/dev/null && pwd)" && [ -d "$abs/scripts" ]; then
    tissTreeEnable "$abs"
    cmdList
    return 0
  fi
  dir="$(tissTreeInstall "$spec" "$repo" "$branch")" || exit 2
  tissTreeEnable "$dir"
  cmdList
}

cmdRemove() {
  local path="$1" abs
  abs="$(cd -P "$path" 2>/dev/null && pwd)" || abs="$path"
  # Accept a bare package name as well as a path.
  [ -d "$abs/scripts" ] || abs="$(tissTreeByName "$path")" || {
    logError "not registered: $path"
    exit 2
  }
  tissTreeDisable "$abs"
  cmdList
}

cmdResolve() { # cmdResolve <spec> <repo> <branch> — where would this fetch from?
  ensureTool jq || exit 127
  tissTreeResolve "$1" "$2" "$3" || exit 2
  local enabled=false ref
  [ "$TREE_INSTALLED" = 1 ] && tissTreeStack | grep -qx "$TREE_DIR" && enabled=true
  ref="$(tissTreeRefCandidates | head -1)"
  jq -cn \
    --arg name "$TREE_NAME" \
    --arg source "$TREE_URL" \
    --arg track "$TREE_TRACK" \
    --arg version "$TREE_VER" \
    --arg ref "$ref" \
    --argjson installed "$([ "$TREE_INSTALLED" = 1 ] && echo true || echo false)" \
    --argjson enabled "$enabled" \
    --arg path "$TREE_DIR" \
    '{name: $name, source: $source, track: $track,
      version: (if $version == "" then null else $version end),
      ref: (if $ref == "" then null else $ref end),
      installed: $installed, enabled: $enabled,
      path: (if $installed then $path else null end)}'
}

# --- argument parsing: SUBCOMMAND [SPEC] [--repo URL] [--branch BR] [--json] ----
sub="${1:-list}"
[ $# -gt 0 ] && shift
spec=""
repo=""
branch=""
json=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      repo="${2:?--repo needs a url}"
      shift
      ;;
    --branch)
      branch="${2:?--branch needs a branch name}"
      shift
      ;;
    --json) json=1 ;;
    -*)
      logError "unknown flag '$1'"
      exit 2
      ;;
    *)
      if [ -n "$spec" ]; then
        logError "one spec at a time (got '$spec' and '$1')"
        exit 2
      fi
      spec="$1"
      ;;
  esac
  shift
done

case "$sub" in
  -h | --help | help)
    tissHelp "$0"
    ;;
  list)
    if [ "$json" = 1 ]; then cmdListJson; else cmdList; fi
    ;;
  add | install)
    [ -n "$spec" ] || {
      logError "usage: $TISS_NAME self tree add PATH | SPEC [--repo URL] [--branch BR]"
      exit 2
    }
    cmdAdd "$spec" "$repo" "$branch"
    ;;
  remove | rm)
    [ -n "$spec" ] || {
      logError "usage: $TISS_NAME self tree remove PATH|NAME"
      exit 2
    }
    cmdRemove "$spec"
    ;;
  resolve)
    [ -n "$spec" ] || {
      logError "usage: $TISS_NAME self tree resolve SPEC [--repo URL] [--branch BR]"
      exit 2
    }
    cmdResolve "$spec" "$repo" "$branch"
    ;;
  *)
    logError "unknown subcommand '$sub' (list [--json], add PATH|SPEC [--repo URL] [--branch BR], remove PATH|NAME, resolve SPEC)"
    exit 2
    ;;
esac
