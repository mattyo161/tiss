#!/usr/bin/env bash
# @description Manage environment profiles (dev/stage/prod...)
# @usage tiss self env [list|show NAME|edit NAME]
# @example tiss self env edit dev      # create/edit your dev profile
# @example tiss @dev ssm get --path /develop
# @example tiss @prod                  # dev shell inside the prod environment
#
# A profile is plain exports (AWS_PROFILE, regions, defaults). Trees ship
# etc/env/<name>.sh for team-wide profiles; yours live in
# $TISS_CONFIG/env/<name>.sh and are sourced LAST, so your exports win.
# Every environment gets its own cacheExec keyspace automatically.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-list}" in
  -h | --help | help)
    tissHelp "$0"
    ;;
  list)
    avail="$(tissListEnvs)"
    if [ -z "$avail" ]; then
      logInfo "no environments yet — create one: $TISS_NAME self env edit dev"
      exit 0
    fi
    echo "$avail"
    [ -n "${TISS_ENV:-}" ] && logInfo "active: $TISS_ENV"
    ;;
  show)
    name="${2:?usage: $TISS_NAME self env show NAME}"
    files="$(tissEnvFiles "$name")"
    if [ -z "$files" ]; then
      logError "no environment '$name'"
      exit 2
    fi
    echo "profile '$name' loads, in order (later wins):"
    printf '%s\n' "$files" | sed 's/^/  /'
    ;;
  edit)
    name="${2:?usage: $TISS_NAME self env edit NAME}"
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
    logError "unknown subcommand '${1}' (list, show NAME, edit NAME)"
    exit 2
    ;;
esac
