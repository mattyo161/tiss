# shellcheck shell=bash
#
# tiss config layering & overlay trees.
#
#   cfg VAR default...   set VAR only if currently unset/empty. Because every
#                        config file assigns through cfg, whoever is sourced
#                        FIRST wins — and the environment (already set before
#                        any sourcing) always beats everything.
#
#   tissTrees            print tree roots one per line, most-specific first,
#                        the core (TISS_HOME) always last. A tree is any
#                        directory containing scripts/; optional etc/config.sh
#                        and lib/init.sh make it a full-power overlay.
#
# Precedence (highest to lowest):
#   environment > ~/.config/tiss/config.sh > overlay configs (specific first)
#   > core etc/config.sh
#
cfg() { # cfg VAR value... -> set VAR unless it already has a value
  local var="$1"
  shift
  case "$var" in
    *[!A-Za-z0-9_]* | [0-9]*)
      logError "cfg: invalid variable name '$var'"
      return 2
      ;;
  esac
  [ -n "$(eval "printf '%s' \"\${$var:-}\"")" ] && return 0
  eval "$var=\"\$*\""
}

tissTrees() { # tree roots, one per line, most-specific first, core last
  local IFS=':' t
  for t in ${TISS_PATH:-}; do
    [ -n "$t" ] || continue
    t="${t%/}"
    [ -d "$t/scripts" ] && printf '%s\n' "$t"
  done
  printf '%s\n' "$TISS_HOME"
}

tissLoadConfigs() { # source user config, overlay libs + configs, core config
  # 1. User config first: with cfg semantics, first-sourced wins.
  # shellcheck disable=SC1091
  [ -f "$TISS_CONFIG/config.sh" ] && . "$TISS_CONFIG/config.sh"

  # 2. Tree configs, most-specific first (cfg makes that the precedence).
  local tree
  while IFS= read -r tree; do
    # shellcheck disable=SC1091
    [ -f "$tree/etc/config.sh" ] && . "$tree/etc/config.sh"
  done < <(tissTrees)

  # 3. Tree helper libs, REVERSED (least-specific first) so that a more
  #    specific tree's function definitions override a company's, which
  #    override nothing of core's unless intentionally redefined.
  local trees_reversed=""
  while IFS= read -r tree; do
    [ "$tree" = "$TISS_HOME" ] && continue # core libs already loaded
    trees_reversed="$tree
$trees_reversed"
  done < <(tissTrees)
  while IFS= read -r tree; do
    [ -n "$tree" ] || continue
    # shellcheck disable=SC1091
    [ -f "$tree/lib/init.sh" ] && . "$tree/lib/init.sh"
  done <<EOF
$trees_reversed
EOF
  return 0
}
