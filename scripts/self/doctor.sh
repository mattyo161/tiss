#!/usr/bin/env bash
# @description Check your tiss installation and guide you through anything missing
# @usage tiss doctor
# @example tiss doctor
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

logInfo "tiss $(cat "$TISS_HOME/version.txt" 2>/dev/null || echo dev) — home: $TISS_HOME (invoked as '$TISS_NAME')"

check "bash" "how are you even running this?" command -v bash
check "jq (required)" "run: mise use -g jq@latest" command -v jq
check "mise (enables lazy tool install)" "any tool-needing tiss command offers to bootstrap it, or: curl https://mise.run | sh" command -v mise
check "age (encryption engine)" "installs on first 'tiss encrypt', or: mise use -g age@latest" command -v age
check "encryption identity" "created on first 'tiss encrypt'" test -s "$TISS_CONFIG/age/identity.age"
rc="$HOME/.bashrc"; case "${SHELL:-}" in */zsh) rc="$HOME/.zshrc" ;; esac
check "rc activation (eval \"\$($TISS_NAME init)\" in ${rc##*/})" \
  "run: echo 'eval \"\$($TISS_NAME init)\"' >> $rc" \
  grep -qF "$TISS_NAME init" "$rc"
check "on PATH as '$TISS_NAME'" "ln -s $TISS_HOME/bin/tiss /usr/local/bin/$TISS_NAME" command -v "$TISS_NAME"

# A tree shipping a reserved lexicon name is dead code at best,
# deception at worst — routing resolves the lexicon from core only.
shadowed=0
while IFS= read -r tree; do
  [ "$tree" = "$TISS_HOME" ] && continue
  for w in $TISS_LEXICON self; do
    for f in "$tree/scripts/$w" "$tree/scripts/$w".*; do
      if [ -e "$f" ]; then
        logWarn "tree '$(basename "$tree")' ships reserved name '$w' — ignored by routing: $f"
        shadowed=$((shadowed + 1))
      fi
    done
  done
done < <(tissTrees)
if [ "$shadowed" -eq 0 ]; then
  logInfo "ok: no tree shadows the reserved lexicon"
  ok=$((ok + 1))
else
  warn=$((warn + shadowed))
fi

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

# Shortcuts need a healthy shim each, and the shim dir on PATH (the
# dispatcher recorded whether it saw the dir before stripping it).
shortcuts=0
shimIssues=0
shims="$(tissShims)"
while IFS=$'\t' read -r name _ _; do
  [ -n "$name" ] || continue
  shortcuts=$((shortcuts + 1))
  if [ "$(readlink "$shims/$name" 2>/dev/null)" != "$TISS_HOME/bin/tiss" ]; then
    logWarn "shortcut '$name' has no working shim — run: $TISS_NAME shortcuts sync"
    shimIssues=$((shimIssues + 1))
  fi
done < <(tissShortcutList)
if [ "$shortcuts" -gt 0 ]; then
  if [ "$shimIssues" -eq 0 ]; then
    logInfo "ok: $shortcuts shortcut shim(s) in sync"
    ok=$((ok + 1))
  else
    warn=$((warn + shimIssues))
  fi
  if [ "${TISS_SHIMS_ON_PATH:-0}" = 1 ]; then
    logInfo "ok: shim dir on PATH ($shims)"
    ok=$((ok + 1))
  else
    logWarn "shim dir not on PATH — add to your rc file:  eval \"\$($TISS_NAME init)\""
    warn=$((warn + 1))
  fi
fi

if [ "$warn" -eq 0 ]; then
  logInfo "All $ok checks passed — you're all set."
else
  logWarn "$ok ok, $warn to fix — hints above."
fi
