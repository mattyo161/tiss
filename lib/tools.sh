# shellcheck shell=bash
#
# tiss tool management — lazy install of wrapped tools.
#
#   ensureTool <name>   succeed if <name> is on PATH, otherwise install it
#                       via mise (asking first, by default) and re-check.
#
# Behavior is controlled by TISS_AUTO_INSTALL:
#   ask     (default) prompt before installing
#   always  install without asking
#   never   fail with instructions instead of installing
#
tissRegistryName() { # command name -> package name (mise registry / brew)
  case "$1" in
    rg) echo ripgrep ;;
    mlr) echo miller ;;
    *) echo "$1" ;;
  esac
}

ensureTool() { # ensureTool <name> -> 0 if available (installing if needed)
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 && return 0

  local pkg
  pkg="$(tissRegistryName "$tool")"

  if ! command -v mise >/dev/null 2>&1 && ! command -v brew >/dev/null 2>&1; then
    logError "'$tool' is not installed, and neither mise nor brew is available to install it."
    logError "Install mise (https://mise.jdx.dev) to enable auto-install, or install '$tool' manually."
    return 127
  fi

  case "${TISS_AUTO_INSTALL:-ask}" in
    never)
      logError "'$tool' is not installed (TISS_AUTO_INSTALL=never). Try: mise use -g $pkg@latest"
      return 127
      ;;
    always) ;;
    *)
      # Prompt on the controlling terminal so pipelines are unaffected.
      if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        local reply=""
        printf "%s: '%s' is not installed. Install %s now? [Y/n] " \
          "${TISS_NAME:-tiss}" "$tool" "$pkg" >/dev/tty
        IFS= read -r reply </dev/tty || reply=""
        case "$reply" in
          n* | N*) return 127 ;;
        esac
      else
        logError "'$tool' is not installed and no terminal to ask (set TISS_AUTO_INSTALL=always to skip prompts)."
        return 127
      fi
      ;;
  esac

  # mise first (version-pinned, no sudo); brew fallback for tools outside
  # mise's registry (e.g. miller).
  if command -v mise >/dev/null 2>&1 && mise use -g "$pkg@latest" >/dev/null 2>&1; then
    logInfo "Installed $pkg via mise."
  elif command -v brew >/dev/null 2>&1; then
    logInfo "Installing $pkg via brew..."
    brew install "$pkg" >&2 || {
      logError "could not install $pkg (mise registry miss, brew failed)"
      return 127
    }
  else
    logError "could not install $pkg via mise, and brew is not available"
    return 127
  fi

  if ! command -v "$tool" >/dev/null 2>&1; then
    logError "Installed $pkg, but '$tool' is still not on PATH — is mise activated in your shell?"
    return 127
  fi
  logInfo "$tool is ready."
}
