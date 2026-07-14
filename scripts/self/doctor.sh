#!/usr/bin/env bash
# @description Check your tiss installation and guide you through anything missing
# @usage tiss self doctor
# @example tiss self doctor
#
# The intuitive way in: run this first on a new machine and follow the hints.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

ok=0
warn=0

check() { # check <label> <hint> <command...>
  local label="$1" hint="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    logInfo "ok: $label"
    ok=$((ok + 1))
  else
    logWarn "missing: $label — $hint"
    warn=$((warn + 1))
  fi
}

logInfo "tiss home: $TISS_HOME (invoked as '$TISS_NAME')"

check "bash" "how are you even running this?" command -v bash
check "jq (required)" "run: mise use -g jq@latest" command -v jq
check "mise (enables lazy tool install)" "install: https://mise.jdx.dev" command -v mise
check "age (encryption engine)" "installs on first 'tiss encrypt', or: mise use -g age@latest" command -v age
check "encryption identity" "created on first 'tiss encrypt'" test -s "$TISS_CONFIG/age/identity.age"
check "on PATH as '$TISS_NAME'" "ln -s $TISS_HOME/bin/tiss /usr/local/bin/$TISS_NAME" command -v "$TISS_NAME"

# Non-executable scripts are invisible to routing — the #1 authoring trap.
nonexec=0
while IFS= read -r tree; do
  while IFS= read -r f; do
    if [ ! -x "$f" ]; then
      logWarn "not executable (invisible to routing): $f"
      logWarn "  activate it with: chmod +x $f"
      nonexec=$((nonexec + 1))
    fi
  done < <(find "$tree/scripts" -type f ! -name '.*' 2>/dev/null)
done < <(tissTrees)
if [ "$nonexec" -eq 0 ]; then
  logInfo "ok: all tree scripts are executable"
  ok=$((ok + 1))
else
  warn=$((warn + nonexec))
fi

if [ "$warn" -eq 0 ]; then
  logInfo "All $ok checks passed — you're all set."
else
  logWarn "$ok ok, $warn to fix — hints above."
fi
