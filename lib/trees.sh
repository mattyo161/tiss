# shellcheck shell=bash
#
# tiss tree packages — overlay trees as installable, git-distributed units.
#
# A package is an overlay tree (scripts/ + optional etc/, lib/, tests/)
# hosted in git. The mapping name -> (repo, tracked branch) lives IN THE
# CLONE — git origin plus a `tiss.track` git-config entry — so there is
# no registry file to drift out of sync; `tiss self tree resolve <name>`
# shows exactly where a name fetches from. Uninstalled short names fall
# back to the convention: branch tree/<name> on the distribution repo
# (TISS_TREES_REPO, default: the repo tiss itself was cloned from).
# owner/repo and full URLs name third-party trees — the whole repo is
# the tree and the tracked branch is its default branch (HEAD).
#
# The version rule, one sentence: @<ver> resolves to the ref
# `<tracked-branch>@<ver>`, falling back to `<ver>` literally; @latest
# is the tracked branch's head (always fetches). Bare +name with the
# clone already present touches NO network.
#
#   tiss +devops [cmd...]     install if missing, enable, route on
#   tiss -devops [cmd...]     disable (clone kept on disk), route on
#   tiss self tree add prod --repo URL --branch env/prod   custom mapping
#
# Clones land in $TISS_TREES (~/.local/share/tiss/trees/<name>); enabled
# means present in the TISS_PATH stack, persisted through the managed
# config line `tiss self tree` writes.

tissTreesDir() { # where package clones live (setting: TISS_TREES)
  printf '%s\n' "${TISS_TREES:-${XDG_DATA_HOME:-$HOME/.local/share}/tiss/trees}"
}

tissTreesRepo() { # the distribution repo for short names, or fail
  if [ -n "${TISS_TREES_REPO:-}" ]; then
    printf '%s\n' "$TISS_TREES_REPO"
    return 0
  fi
  git -C "$TISS_HOME" remote get-url origin 2>/dev/null
}

tissTreeTrackOf() { # tissTreeTrackOf <dir> — best-effort tracked branch of a clone
  git -C "$1" config tiss.track 2>/dev/null && return 0
  git -C "$1" symbolic-ref --short -q HEAD && return 0
  # Single-branch clones remember their branch in the fetch refspec even
  # when an @version checkout left the head detached (pre-tiss.track clones).
  local spec
  spec="$(git -C "$1" config --get remote.origin.fetch 2>/dev/null)" || spec=""
  case "$spec" in
    +refs/heads/\**) ;; # full clone — no single tracked branch
    +refs/heads/*)
      spec="${spec#+refs/heads/}"
      printf '%s\n' "${spec%%:*}"
      return 0
      ;;
  esac
  echo HEAD
}

# tissTreeResolve <spec> [repo-override] [branch-override]
# Resolve a spec (name[@ver] | owner/repo[@ver] | url[@ver]) to globals:
#   TREE_NAME  local alias (also the clone dir name)
#   TREE_VER   requested version ("" = none, "latest" = track head)
#   TREE_URL   repo it fetches from
#   TREE_TRACK tracked branch (HEAD = the repo's default branch)
#   TREE_DIR   clone location;  TREE_INSTALLED  1 if the clone exists
# Precedence: explicit overrides > the installed clone's own mapping >
# owner/repo|url form > distribution-repo convention.
tissTreeResolve() {
  local spec="$1" repo="${2:-}" branch="${3:-}"
  TREE_VER=""
  case "$spec" in
    *@*)
      # Split only when the tail after the LAST @ looks like a version —
      # git@github.com:... URLs contain @ but their tails have : or /.
      TREE_VER="${spec##*@}"
      case "$TREE_VER" in
        */* | *:*) TREE_VER="" ;;
        *) spec="${spec%@*}" ;;
      esac
      ;;
  esac
  case "$spec" in
    *://* | git@*)
      TREE_NAME="$(basename "$spec" .git)"
      repo="${repo:-$spec}"
      ;;
    */*)
      TREE_NAME="${spec##*/}"
      repo="${repo:-https://github.com/$spec}"
      ;;
    *)
      TREE_NAME="$spec"
      ;;
  esac
  TREE_DIR="$(tissTreesDir)/$TREE_NAME"
  TREE_INSTALLED=0
  [ -d "$TREE_DIR/.git" ] && TREE_INSTALLED=1

  if [ "$TREE_INSTALLED" = 1 ]; then
    # The clone is the mapping; explicit overrides re-map it (in install).
    TREE_URL="${repo:-$(git -C "$TREE_DIR" remote get-url origin 2>/dev/null || true)}"
    TREE_TRACK="${branch:-$(tissTreeTrackOf "$TREE_DIR")}"
  elif [ -n "$repo" ]; then
    TREE_URL="$repo"
    TREE_TRACK="${branch:-HEAD}"
  else
    TREE_URL="$(tissTreesRepo)" || true
    if [ -z "${TREE_URL:-}" ]; then
      logError "no distribution repo for tree '$TREE_NAME' — set one: cfg TISS_TREES_REPO <url>"
      return 2
    fi
    TREE_TRACK="${branch:-tree/$TREE_NAME}"
  fi
  return 0
}

tissTreeRefCandidates() { # concrete refs to try for TREE_VER, one per line
  case "$TREE_VER" in
    "" | latest)
      [ "$TREE_TRACK" = "HEAD" ] || printf '%s\n' "$TREE_TRACK"
      ;;
    *)
      [ "$TREE_TRACK" = "HEAD" ] || printf '%s\n' "$TREE_TRACK@$TREE_VER"
      printf '%s\n' "$TREE_VER"
      ;;
  esac
}

tissTreeInstall() { # tissTreeInstall <spec> [repo] [branch] -> print clone dir
  local spec="$1" repoArg="${2:-}" branchArg="${3:-}"
  tissTreeResolve "$spec" "$repoArg" "$branchArg" || return 2
  local dir="$TREE_DIR" ref found
  if [ "$TREE_INSTALLED" = 1 ]; then
    if [ -n "$repoArg" ] || [ -n "$branchArg" ]; then
      # Explicit re-mapping: rewrite the clone's stored mapping, then
      # align the checkout with wherever it now points.
      ensureTool git || return 127
      git -C "$dir" remote set-url origin "$TREE_URL"
      git -C "$dir" config tiss.track "$TREE_TRACK"
      logInfo "re-mapped tree '$TREE_NAME' -> $TREE_URL @ $TREE_TRACK"
      [ -n "$TREE_VER" ] || TREE_VER="latest"
    fi
    # Make an inferred mapping sticky (pre-tiss.track clones self-heal).
    if [ "$TREE_TRACK" != "HEAD" ] && ! git -C "$dir" config tiss.track >/dev/null 2>&1; then
      git -C "$dir" config tiss.track "$TREE_TRACK"
    fi
    if [ -n "$TREE_VER" ]; then
      # Only an explicit @version (or a re-map) touches the network.
      ensureTool git || return 127
      found=0
      while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        if git -C "$dir" fetch -q origin "$ref" 2>/dev/null; then
          found=1
          break
        fi
      done < <(tissTreeRefCandidates)
      if [ "$found" = 0 ]; then
        logError "no ref for '$TREE_NAME@$TREE_VER' in $TREE_URL (tried:$(tissTreeRefCandidates | tr '\n' ' ' | sed 's/ $//; s/^/ /'))"
        return 2
      fi
      logInfo "tree '$TREE_NAME' -> $ref"
      git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD || return 2
    fi
  else
    ensureTool git || return 127
    logInfo "installing tree '$TREE_NAME' from $TREE_URL ($TREE_TRACK${TREE_VER:+@$TREE_VER})..."
    mkdir -p "$(tissTreesDir)"
    found=0
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      if git clone -q --depth 1 --branch "$ref" --single-branch "$TREE_URL" "$dir" 2>/dev/null; then
        found=1
        break
      fi
    done < <(tissTreeRefCandidates)
    if [ "$found" = 0 ]; then
      # No candidates at all means track=HEAD with no version: plain clone.
      if [ -z "$(tissTreeRefCandidates)" ]; then
        git clone -q --depth 1 "$TREE_URL" "$dir" 2>/dev/null || {
          logError "could not clone $TREE_URL"
          return 2
        }
      else
        logError "could not clone '$TREE_NAME' from $TREE_URL (tried:$(tissTreeRefCandidates | tr '\n' ' ' | sed 's/ $//; s/^/ /'))"
        logError "packages live on branches named tree/<name> — scaffold one: ${TISS_NAME:-tiss} self tree new $TREE_NAME"
        return 2
      fi
    fi
    git -C "$dir" config tiss.track "$TREE_TRACK"
  fi
  if [ ! -d "$dir/scripts" ]; then
    logError "'$TREE_NAME' is not a tiss tree (no scripts/ directory in $dir)"
    return 2
  fi
  printf '%s\n' "$dir"
}

tissTreeInfoJson() { # tissTreeInfoJson <dir> <enabled-json-bool> -> one jsonl row
  local dir="$1" enabled="$2" src="" track="" ref="" kind="local" n
  if [ -d "$dir/.git" ]; then
    src="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    track="$(tissTreeTrackOf "$dir")"
    [ "$track" = "HEAD" ] && track=""
    ref="$(git -C "$dir" describe --tags --exact-match 2>/dev/null \
      || git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  case "$dir" in "$(tissTreesDir)"/*) kind="package" ;; esac
  [ "$dir" = "$TISS_HOME" ] && kind="core"
  n="$(find "$dir/scripts" -type f -perm -100 2>/dev/null | wc -l | tr -d ' ')"
  jq -cn \
    --arg name "$(basename "$dir")" \
    --arg kind "$kind" \
    --argjson enabled "$enabled" \
    --arg path "$dir" \
    --arg source "$src" \
    --arg track "$track" \
    --arg ref "$ref" \
    --argjson commands "${n:-0}" \
    '{name: $name, kind: $kind, enabled: $enabled, commands: $commands,
      source: (if $source == "" then null else $source end),
      track: (if $track == "" then null else $track end),
      ref: (if $ref == "" then null else $ref end),
      path: $path}'
}

# --- the registered stack (persisted TISS_PATH) --------------------------------
TISS_TREE_MARKER="# tiss:tree-path (managed by 'tiss self tree')"

tissTreeStack() { # registered overlay roots, one per line (core excluded)
  tissTrees | while IFS= read -r t; do
    [ "$t" = "$TISS_HOME" ] || printf '%s\n' "$t"
  done
}

tissTreeStackWrite() { # tissTreeStackWrite <colon-joined> — persist + in-process
  local configFile="$TISS_CONFIG/config.sh" tmp
  mkdir -p "$TISS_CONFIG"
  tmp="$(mktemp)"
  if [ -f "$configFile" ]; then
    grep -v -e "^cfg TISS_PATH " -e "^$TISS_TREE_MARKER\$" "$configFile" >"$tmp" || true
  fi
  if [ -n "$1" ]; then
    printf '%s\ncfg TISS_PATH "%s"\n' "$TISS_TREE_MARKER" "$1" >>"$tmp"
  fi
  mv "$tmp" "$configFile"
  TISS_PATH="$1" # this invocation routes with the new stack immediately
  export TISS_PATH
}

tissTreeByName() { # tissTreeByName <name> -> dir of a registered OR installed tree
  local t
  while IFS= read -r t; do
    if [ "$(basename "$t")" = "$1" ]; then
      printf '%s\n' "$t"
      return 0
    fi
  done < <(tissTreeStack)
  t="$(tissTreesDir)/$1"
  if [ -d "$t/scripts" ]; then
    printf '%s\n' "$t"
    return 0
  fi
  return 1
}

tissTreeEnable() { # tissTreeEnable <dir> — put at the front of the stack
  local dir="$1" trees="" t
  while IFS= read -r t; do
    [ "$t" = "$dir" ] && {
      logDebug "already registered: $dir"
      return 0
    }
    trees="$trees:$t"
  done < <(tissTreeStack)
  tissTreeStackWrite "$dir${trees}"
  logInfo "tree enabled: $(basename "$dir") ($dir)"
}

tissTreeDisable() { # tissTreeDisable <dir> — drop from the stack, keep the clone
  local dir="$1" trees="" t found=0
  while IFS= read -r t; do
    if [ "$t" = "$dir" ]; then
      found=1
      continue
    fi
    trees="$trees${trees:+:}$t"
  done < <(tissTreeStack)
  if [ "$found" = 0 ]; then
    logWarn "not registered: $dir"
    return 0
  fi
  tissTreeStackWrite "$trees"
  logInfo "tree disabled: $(basename "$dir") (clone kept at $dir)"
}
