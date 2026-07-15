#!/usr/bin/env bash
# @description Emit rc integration (mise/brew activation, shortcut shims, `self cd`)
# @usage eval "$(tiss self init)"
# @example eval "$(tiss self init)"   # in ~/.zshrc or ~/.bashrc
#
# One rc line, everything wired. Emits:
#   1. ~/.local/bin on PATH (where mise bootstraps and install.sh links)
#   2. brew activation when brew exists but the shell never ran shellenv
#   3. mise activation (skipped if something already activated it)
#   4. a guarded PATH line putting the shortcut shim dir first, so the
#      names from `tiss self shortcuts` win everywhere (the dispatcher
#      strips the dir back out of child PATHs — shims never leak down)
#   5. a wrapper function named after however you invoke tiss (symlink
#      as `x` and it wraps `x`), intercepting `self cd` to pushd in YOUR
#      shell; everything else forwards to the real binary. popd returns.
#
set -euo pipefail
source "$TISS_LIB/init.sh"

case "${1:-}" in
  -h | --help | help)
    tissHelp "$0"
    exit 0
    ;;
esac

# Tool managers first: mise (and brew) must be live before anything
# else wants tools. All guarded — every line is a no-op when already set
# up, so the emission is safe to eval in any shell on any machine.
cat <<'BOOT'
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
if ! command -v brew >/dev/null 2>&1; then
  for _tiss_brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$_tiss_brew" ]; then
      eval "$("$_tiss_brew" shellenv)"
      break
    fi
  done
  unset _tiss_brew
fi
if command -v mise >/dev/null 2>&1 && [ -z "${MISE_SHELL:-}" ]; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(mise activate zsh)"
  else
    eval "$(mise activate bash)"
  fi
fi
BOOT

shims="$(tissShims)"
# shellcheck disable=SC2016  # $PATH must reach the user's rc unexpanded
printf 'case ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' "$shims" "$shims"

sed "s/__NAME__/$TISS_NAME/g" <<'WRAP'
__NAME__() {
  if [ "${1:-}" = "self" ] && [ "${2:-}" = "cd" ]; then
    pushd "$(command __NAME__ self cd 2>/dev/null)" || return
  else
    command __NAME__ "$@"
  fi
}
WRAP
