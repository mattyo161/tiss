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

tissMiseBootstrap() { # official installer -> ~/.local/bin, activated in-process
  # Preflight what the installer itself needs, and point at the exact
  # package-manager command when something is missing (truly bare boxes:
  # minimal containers lack even tar).
  local missing="" t
  for t in curl tar gzip; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
  done
  if [ -n "$missing" ]; then
    logError "bootstrapping mise needs:$missing"
    if command -v dnf >/dev/null 2>&1; then
      logError "  install first:  sudo dnf install -y$missing"
    elif command -v yum >/dev/null 2>&1; then
      logError "  install first:  sudo yum install -y$missing"
    elif command -v apt-get >/dev/null 2>&1; then
      logError "  install first:  sudo apt-get install -y$missing"
    fi
    return 127
  fi
  logInfo "Bootstrapping mise (curl https://mise.run | sh)..."
  curl -fsSL https://mise.run | sh >&2 || {
    logError "mise bootstrap failed — see https://mise.jdx.dev for alternatives"
    return 127
  }
  # The installer lands in ~/.local/bin: make it visible to THIS process
  # (and its children) so the command you originally typed still works.
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
  command -v mise >/dev/null 2>&1 || {
    logError "bootstrap ran but mise is not at ~/.local/bin/mise — check the installer output above"
    return 127
  }
  logInfo "mise is ready in this shell."
  tissOfferRcActivation
}

# tissOfferRcActivation — the last mile of a fresh box: get the one
# activation line (eval "$(tiss init)") into the user's rc so every NEW
# shell has mise/brew/shortcuts live. Idempotent (marker line), rc is
# bkup'd first, consent follows TISS_AUTO_INSTALL (ask/always/never).
tissOfferRcActivation() {
  local rc marker="# tiss activation" line
  case "${SHELL:-}" in
    */zsh) rc="$HOME/.zshrc" ;;
    *) rc="$HOME/.bashrc" ;;
  esac
  # shellcheck disable=SC2016  # the rc line is meant literal
  line='eval "$('"${TISS_NAME:-tiss}"' init)"'
  if grep -qF "$marker" "$rc" 2>/dev/null || grep -qF "$line" "$rc" 2>/dev/null; then
    return 0 # already wired
  fi
  case "${TISS_AUTO_INSTALL:-ask}" in
    never)
      logInfo "new shells need this in $rc:  $line"
      return 0
      ;;
    always) ;;
    *)
      if { : </dev/tty >/dev/tty; } 2>/dev/null; then
        local reply=""
        printf "%s: add activation to %s so every new shell has it? [Y/n] "           "${TISS_NAME:-tiss}" "$rc" >/dev/tty
        IFS= read -r reply </dev/tty || reply=""
        case "$reply" in
          n* | N*)
            logInfo "skipped — add it yourself:  echo '$line' >> $rc"
            return 0
            ;;
        esac
      else
        logInfo "new shells need this in $rc:  $line"
        return 0
      fi
      ;;
  esac
  [ -f "$rc" ] && bkup "$rc" >/dev/null
  {
    echo ""
    echo "$marker — mise/brew/shortcuts on PATH (remove any old activation lines they now duplicate)"
    echo "$line"
  } >>"$rc"
  logInfo "activation added to $rc (backed up first) — new shells are fully wired"
}

tissBrewActivate() { # 0 if brew is usable; finds it even if shellenv never ran
  command -v brew >/dev/null 2>&1 && return 0
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    if [ -x "$b" ]; then
      eval "$("$b" shellenv)"
      logInfo "brew found at $b but not on your shell's PATH — the rc line 'eval \"\$(${TISS_NAME:-tiss} init)\"' fixes that"
      return 0
    fi
  done
  return 1
}

# shellcheck disable=SC2016  # the hints are copy-paste lines, $ stays literal
tissBrewHint() { # exact steps: the installer + the platform's activation line
  logError "get Homebrew with:"
  logError '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  case "$(uname -s)" in
    Darwin) logError '  eval "$(/opt/homebrew/bin/brew shellenv)"    # then add to your rc file' ;;
    *) logError '  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"    # then add to your rc file' ;;
  esac
}

# --- did-you-mean -----------------------------------------------------------------
tissSuggestCandidates() { # every first word tiss answers to at the root
  {
    local w tree entry name
    for w in $TISS_LEXICON; do
      printf '%s\n' "$w"
    done
    while IFS= read -r tree; do
      for entry in "$tree/scripts"/*; do
        [ -e "$entry" ] || continue
        name="$(basename "$entry")"
        case "$name" in _* | self) continue ;; esac
        if [ -d "$entry" ]; then
          printf '%s\n' "$name"
        elif [ -x "$entry" ]; then
          printf '%s\n' "${name%.*}"
        fi
      done
    done < <(tissTrees)
  } | sort -u
}

tissSuggest() { # tissSuggest <word> -> closest command word(s), or fail
  # Damerau-Levenshtein over the candidate list, git-style threshold:
  # one edit for short words, two for longer. Ties all print.
  local word="$1" max=1
  [ "${#word}" -ge 5 ] && max=2
  tissSuggestCandidates | awk -v w="$word" -v max="$max" '
    function dist(a, b,   i, j, la, lb, ca, cb, cost, m, d) {
      la = length(a); lb = length(b)
      for (i = 0; i <= la; i++) d[i, 0] = i
      for (j = 0; j <= lb; j++) d[0, j] = j
      for (i = 1; i <= la; i++)
        for (j = 1; j <= lb; j++) {
          ca = substr(a, i, 1); cb = substr(b, j, 1)
          cost = (ca == cb) ? 0 : 1
          m = d[i-1, j] + 1
          if (d[i, j-1] + 1 < m) m = d[i, j-1] + 1
          if (d[i-1, j-1] + cost < m) m = d[i-1, j-1] + cost
          if (i > 1 && j > 1 && ca == substr(b, j-1, 1) && substr(a, i-1, 1) == cb && d[i-2, j-2] + 1 < m)
            m = d[i-2, j-2] + 1
          d[i, j] = m
        }
      return d[la, lb]
    }
    {
      dd = dist(w, $0)
      if (best == "" || dd < bestd) { bestd = dd; best = $0 }
      else if (dd == bestd) best = best "\n" $0
    }
    END { if (best != "" && bestd <= max) print best }
  ' | grep . # fail (rc 1) when nothing cleared the threshold
}

tissCustomInstall() { # tissCustomInstall <tool> -> install command for tools
  # outside the mise/brew registries, or fail. Keep each one a single
  # runnable command — it's shown to the user verbatim before running.
  case "$1" in
    gddy) echo "curl -fsSL https://github.com/godaddy/cli/releases/latest/download/install.sh | bash" ;;
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
TISS_INSTALL_ALLOW_DEFAULT="age aws fzf gddy gh git go jc jq mise mlr node pstree python python3 rg ruby shellcheck terraform tmux tree uv watch yq"

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
      local hint="mise use -g $pkg@latest"
      [ "$tool" = "mise" ] && hint="curl https://mise.run | sh"
      [ -n "$custom" ] && hint="$custom"
      logError "'$tool' is not installed (TISS_AUTO_INSTALL=never). Try: $hint"
      return 127
      ;;
    always) ;;
    *)
      # Prompt on the controlling terminal so pipelines are unaffected.
      if { : </dev/tty >/dev/tty; } 2>/dev/null; then
        local reply="" inst="$pkg"
        [ "$tool" = "mise" ] && inst="via \`curl https://mise.run | sh\`"
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

  if [ "$tool" = "mise" ]; then
    # mise is the install engine itself: bootstrap it with the official
    # installer rather than pointing at a URL and stranding the user.
    tissMiseBootstrap
    return $?
  fi

  if [ -n "$custom" ]; then
    # Tools outside the mise/brew registries carry their own install
    # command (tissCustomInstall) — shown verbatim, run verbatim.
    logInfo "Installing $tool: $custom"
    bash -c "$custom" >&2 || {
      logError "could not install $tool ($custom failed)"
      return 127
    }
  # mise first (version-pinned, no sudo, bootstraps itself); brew fallback
  # for tools outside mise's registry (e.g. miller).
  elif ensureTool mise && mise use -g "$pkg@latest" >/dev/null 2>&1; then
    logInfo "Installed $pkg via mise."
  elif tissBrewActivate; then
    logInfo "Installing $pkg via brew..."
    brew install "$pkg" >&2 || {
      logError "could not install $pkg (mise registry miss, brew failed)"
      return 127
    }
  else
    if command -v mise >/dev/null 2>&1; then
      logError "'$pkg' is outside mise's registry, and brew is not installed."
    else
      logError "mise could not be set up, and brew is not installed."
    fi
    tissBrewHint
    return 127
  fi

  if ! command -v "$tool" >/dev/null 2>&1; then
    # Installed but invisible: the shell hasn't activated mise. Make the
    # CURRENT invocation work through mise's shims; future shells get the
    # real activation from the rc line (tiss init).
    local mise_shims="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
    if [ -d "$mise_shims" ]; then
      case ":$PATH:" in
        *":$mise_shims:"*) ;;
        *) export PATH="$mise_shims:$PATH" ;;
      esac
    fi
  fi
  if ! command -v "$tool" >/dev/null 2>&1; then
    logError "Installed $pkg, but '$tool' is still not on PATH — activate mise in your shell:  eval \"\$(${TISS_NAME:-tiss} init)\""
    return 127
  fi
  logInfo "$tool is ready."
}
