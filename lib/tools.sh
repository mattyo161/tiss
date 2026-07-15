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

tissCustomInstall() { # tissCustomInstall <tool> -> install command for tools
  # outside the mise/brew registries, or fail. Keep each one a single
  # runnable command — it's shown to the user verbatim before running.
  case "$1" in
    ajl) echo "uv tool install git+https://github.com/mattyo161/ajl" ;;
    *) return 1 ;;
  esac
}

tissCommandAlias() { # namespace/short name -> real command for passthrough
  # May be multi-word ("aws s3"). Note: a namespace _self handler is
  # usually better than an alias — it can add logic (see ssm/_self.sh).
  case "$1" in
    tf) echo terraform ;;
    *) echo "$1" ;;
  esac
}

# Passthrough installs are gated by an allowlist: tools declared via
# `# @needs` are implicitly trusted (the declaring script is already
# running with your permissions), but a mistyped passthrough command must
# never become an "install this package? [Y/n]" prompt. Extend with
# TISS_INSTALL_ALLOW (space-separated names) in your config.
TISS_INSTALL_ALLOW_DEFAULT="age ajl aws fzf gh git go jc jq mise mlr node pstree python python3 rg ruby shellcheck terraform tmux tree uv watch"

tissInstallAllowed() { # tissInstallAllowed <tool> -> 0 if passthrough-installable
  local t
  for t in $TISS_INSTALL_ALLOW_DEFAULT ${TISS_INSTALL_ALLOW:-}; do
    [ "$t" = "$1" ] && return 0
  done
  return 1
}

ensureTool() { # ensureTool [--gated] <name> -> 0 if available (installing if needed)
  local gated=0
  if [ "$1" = "--gated" ]; then
    gated=1
    shift
  fi
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 && return 0

  if [ "$gated" = 1 ] && ! tissInstallAllowed "$tool"; then
    logError "'$tool' is not installed, and it's not on the passthrough install allowlist."
    logError "install it yourself, or allow it in your config: cfg TISS_INSTALL_ALLOW \"$tool\""
    return 127
  fi

  local pkg custom=""
  pkg="$(tissRegistryName "$tool")"
  custom="$(tissCustomInstall "$tool")" || custom=""

  case "${TISS_AUTO_INSTALL:-ask}" in
    never)
      logError "'$tool' is not installed (TISS_AUTO_INSTALL=never). Try: ${custom:-mise use -g $pkg@latest}"
      return 127
      ;;
  esac

  if [ -z "$custom" ] && ! command -v mise >/dev/null 2>&1 && ! command -v brew >/dev/null 2>&1; then
    logError "'$tool' is not installed, and neither mise nor brew is available to install it."
    logError "Install mise (https://mise.jdx.dev) to enable auto-install, or install '$tool' manually."
    return 127
  fi

  case "${TISS_AUTO_INSTALL:-ask}" in
    always) ;;
    *)
      # Prompt on the controlling terminal so pipelines are unaffected.
      if { : </dev/tty >/dev/tty; } 2>/dev/null; then
        local reply="" inst="$pkg"
        [ -n "$custom" ] && inst="via \`$custom\`"
        printf "%s: '%s' is not installed. Install %s now? [Y/n] " \
          "${TISS_NAME:-tiss}" "$tool" "$inst" >/dev/tty
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

  if [ -n "$custom" ]; then
    # Tools outside the mise/brew registries carry their own install
    # command (tissCustomInstall) — shown verbatim, run verbatim.
    ensureTool uv || return 127
    logInfo "Installing $tool: $custom"
    # shellcheck disable=SC2086  # the install command is intentionally word-split
    $custom >&2 || {
      logError "could not install $tool ($custom failed)"
      return 127
    }
  # mise first (version-pinned, no sudo); brew fallback for tools outside
  # mise's registry (e.g. miller).
  elif command -v mise >/dev/null 2>&1 && mise use -g "$pkg@latest" >/dev/null 2>&1; then
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
