#!/usr/bin/env bash
# @description Show, create, or edit your tiss configuration
# @usage tiss config [list|path|edit]
# @example tiss config           # every setting + its effective value
# @example tiss config edit      # open it in $EDITOR (creates from template)
#
# Your config lives at $TISS_CONFIG/config.sh, seeded from the fully
# commented template (etc/config.sh.example) — uncomment a line to make
# it your default. Precedence: environment > this file > overlay trees >
# core. Full reference: docs/configuration.md.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

template="$TISS_HOME/etc/config.sh.example"
target="$TISS_CONFIG/config.sh"

seed() {
  if [ ! -f "$target" ]; then
    mkdir -p "$TISS_CONFIG"
    cp "$template" "$target"
    logInfo "created $target (everything commented = all defaults)"
  fi
}

case "${1:-list}" in
  -h | --help | help)
    tissHelp "$0"
    ;;
  path)
    seed
    echo "$target"
    ;;
  edit)
    seed
    exec "${EDITOR:-vi}" "$target"
    ;;
  list)
    # The template is the settings registry: every `# cfg NAME default`
    # line is a known setting. Show each with its effective value.
    printf '%-26s %-22s %s\n' "SETTING" "EFFECTIVE" "DEFAULT"
    while IFS= read -r line; do
      name="${line#\# cfg }"
      name="${name%% *}"
      default="${line#\# cfg "$name" }"
      value="$(eval "printf '%s' \"\${$name:-}\"")"
      printf '%-26s %-22s %s\n' "$name" "${value:-(default)}" "$default"
    done < <(grep '^# cfg ' "$template")
    echo
    echo "config file: $target$([ -f "$target" ] || echo '  (not created yet — tiss config edit)')"
    ;;
  *)
    logError "unknown subcommand '${1}' (list, path, edit)"
    exit 2
    ;;
esac
