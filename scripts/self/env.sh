#!/usr/bin/env bash
# @description Show the resolved tiss environment; manage profiles (dev/prod...)
# @usage tiss env [--exports|--json|--yaml|--toml] | [list|show NAME|edit NAME]
# @example tiss env                    # every effective TISS_* var, resolved, as props
# @example tiss env --json | jq -r .TISS_DATA
# @example tiss env --yaml
# @example tiss @prod env              # see exactly what the prod profile changes
# @example tiss env edit dev           # create/edit your dev profile
#
# Bare `tiss env` prints the POST-RESOLUTION truth — environment beats
# config beats pile beats defaults — which `env | grep '^TISS'` can
# never show (it only sees what your shell exported). One KEY=value per
# line (props), sorted; --exports emits eval-able export lines, --json/
# --yaml/--toml pipe through the matching props2* converter.
#
# Profiles: plain exports (AWS_PROFILE, regions, defaults). Trees ship
# etc/env/<name>.sh for team-wide profiles; yours live in
# $TISS_CONFIG/env/<name>.sh and are sourced LAST, so your exports win.
# Every environment gets its own cacheExec keyspace automatically.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

dumpProps() { # every effective TISS_* setting, resolved, sorted props
  local line name default value
  {
    # Settings from the template registry: current value, else the
    # documented default (wrappers apply those via cfg at runtime).
    while IFS= read -r line; do
      name="${line#\# cfg }"
      name="${name%% *}"
      default="${line#\# cfg "$name"}"
      default="${default# }"
      case "$name" in
        TISS_SHIMS) value="$(tissShims)" ;;
        TISS_TREES) value="$(tissTreesDir)" ;;
        TISS_TREES_REPO) value="$(tissTreesRepo 2>/dev/null || true)" ;;
        *) value="$(eval "printf '%s' \"\${$name:-}\"")" ;;
      esac
      if [ -z "$value" ] && [ -n "$default" ]; then
        eval "value=$default" # template defaults may quote or use \$HOME
      fi
      printf '%s=%s\n' "$name" "$value"
    done < <(grep '^# cfg ' "$TISS_HOME/etc/config.sh.example")
    for name in TISS_HOME TISS_NAME TISS_CONFIG TISS_SCRIPTS TISS_LIB; do
      printf '%s=%s\n' "$name" "$(eval "printf '%s' \"\${$name:-}\"")"
    done
  } | sort -u
}

case "${1:-}" in
  "")
    dumpProps
    ;;
  --exports)
    dumpProps | while IFS= read -r line; do
      printf 'export %s=%q\n' "${line%%=*}" "${line#*=}"
    done
    ;;
  --json)
    ensureTool jq || exit 127
    dumpProps | "$TISS_SCRIPTS/props2json.sh"
    ;;
  --yaml)
    ensureTool jq || exit 127
    ensureTool yq || exit 127
    dumpProps | "$TISS_SCRIPTS/props2yaml.sh"
    ;;
  --toml)
    ensureTool jq || exit 127
    ensureTool yq || exit 127
    dumpProps | "$TISS_SCRIPTS/props2toml.sh"
    ;;
  -h | --help | help)
    tissHelp "$0"
    ;;
  list)
    avail="$(tissListEnvs)"
    if [ -z "$avail" ]; then
      logInfo "no environments yet — create one: $TISS_NAME env edit dev"
      exit 0
    fi
    echo "$avail"
    [ -n "${TISS_ENV:-}" ] && logInfo "active: $TISS_ENV"
    ;;
  show)
    name="${2:?usage: $TISS_NAME env show NAME}"
    files="$(tissEnvFiles "$name")"
    if [ -z "$files" ]; then
      logError "no environment '$name'"
      exit 2
    fi
    echo "profile '$name' loads, in order (later wins):"
    printf '%s\n' "$files" | sed 's/^/  /'
    ;;
  edit)
    name="${2:?usage: $TISS_NAME env edit NAME}"
    target="$TISS_CONFIG/env/$name.sh"
    if [ ! -f "$target" ]; then
      mkdir -p "$TISS_CONFIG/env"
      cat >"$target" <<TPL
# tiss environment profile '$name' — plain exports, loaded by:
#   tiss @$name <command>     one command in this environment
#   tiss @$name               dev shell inside it
# Tree-provided profiles (etc/env/$name.sh) load first; this file wins.

# export AWS_PROFILE=$name
# export AWS_REGION=us-east-1
# export KUBECONFIG=\$HOME/.kube/$name.yaml
TPL
      logInfo "created $target"
    fi
    exec "${EDITOR:-vi}" "$target"
    ;;
  *)
    logError "unknown subcommand '${1}' (bare = resolved env; --exports, --json, --yaml, --toml, list, show NAME, edit NAME)"
    exit 2
    ;;
esac
