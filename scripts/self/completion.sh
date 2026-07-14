#!/usr/bin/env bash
# @description Emit shell completion code for bash or zsh
# @usage tiss self completion <bash|zsh>
# @example eval "$(tiss self completion zsh)"    # in ~/.zshrc, after compinit
# @example eval "$(tiss self completion bash)"   # in ~/.bashrc
#
# Completions are generated for whatever name invoked tiss — if you
# symlinked the dispatcher as `x`, run `x tiss completion zsh` and tab
# completion is wired up for `x`. Candidates come live from the scripts
# tree (via --complete), so new scripts complete immediately, no
# regeneration needed.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

shell="${1:-}"
case "$shell" in
  -h | --help | help | "")
    tissHelp "$0"
    exit 0
    ;;
esac

name="$TISS_NAME"
fname="_${name//-/_}_complete"

case "$shell" in
  bash)
    sed "s/__NAME__/$name/g; s/__FNAME__/$fname/g" <<'EOF'
__FNAME__() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local mid=("${COMP_WORDS[@]:1:COMP_CWORD-1}")
  COMPREPLY=($(compgen -W "$(__NAME__ --complete "${mid[@]}" 2>/dev/null)" -- "$cur"))
}
complete -F __FNAME__ __NAME__
EOF
    ;;
  zsh)
    sed "s/__NAME__/$name/g; s/__FNAME__/$fname/g" <<'EOF'
__FNAME__() {
  local -a cands
  local IFS=$'\n'
  cands=($(__NAME__ --complete-zsh "${(@)words[2,CURRENT-1]}" 2>/dev/null))
  if (( ${#cands} )); then
    _describe -t commands '__NAME__ command' cands
  else
    _default
  fi
}
compdef __FNAME__ __NAME__
EOF
    ;;
  *)
    logError "unsupported shell '$shell' (bash or zsh)"
    exit 2
    ;;
esac
