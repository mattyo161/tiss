#!/usr/bin/env bash
# @description Drop into an interactive tiss shell: helpers loaded, cwd = tiss home
# @usage tiss self shell
# @example tiss self shell
# @example printf 'dur2s 1w1d\nexit\n' | tiss self shell   # scriptable too
#
# A REPL for tiss development: every helper (logInfo, saveData, cacheExec,
# dur2s, bkup, ...) is a first-class command at the prompt, overlay libs
# and config are loaded, you start in $TISS_HOME, and the prompt says so.
# Its own history file, so your experiments don't pollute shell history.
# exit / ctrl-d drops you back exactly where you were.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

mkdir -p "$TISS_STATE"

# The rc is a self-destructing temp file — dogfooding rmAfter: bash reads
# it at startup, and it quietly vanishes a minute later.
rcfile="$(mktemp)"
cat >"$rcfile" <<RC
# tiss dev shell rc (self-destructs via rmAfter)
source "$TISS_LIB/init.sh"
cd "$TISS_HOME"
export PATH="$TISS_HOME/bin:\$PATH"
export HISTFILE="$TISS_STATE/shell_history"
PS1='\[\033[36m\]$TISS_NAME\[\033[0m\]> '
echo "$TISS_NAME dev shell — helpers loaded: logInfo, saveData/readData/lsData, cacheExec, learnExec, dur2s, bkup, rmAfter, ..."
echo "cwd: $TISS_HOME    (exit or ctrl-d to leave)"
RC
rmAfter 1m "$rcfile"

exec bash --rcfile "$rcfile" -i
