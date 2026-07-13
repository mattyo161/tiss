# shellcheck shell=bash
#
# tiss encryption identity — the machinery behind `tiss encrypt` / `tiss decrypt`.
#
# Design (see DESIGN.md "Encryption"):
#   - Engine is `age` (https://age-encryption.org): modern, streaming, single
#     binary, lazy-installable — we wrap it rather than reinvent it.
#   - tiss generates its own age identity at first use, protected by a
#     passphrase you choose. The identity never leaves this machine.
#   - Encrypting needs only the PUBLIC key (recipients.txt) — no prompt, ever.
#   - Decrypting unlocks the identity ONCE per session (passphrase prompt),
#     then caches the unlocked identity in a 0700 per-user tmp dir. This is
#     the agent-like UX: ssh-agent itself cannot decrypt (it only signs), so
#     tiss provides its own session unlock instead.
#
tissAgeDir() {
  echo "$TISS_CONFIG/age"
}

tissRecipients() { # path to public recipients file, guiding setup if missing
  tissEnsureIdentity || return 1
  echo "$(tissAgeDir)/recipients.txt"
}

tissEnsureIdentity() { # create the tiss identity interactively if absent
  local dir
  dir="$(tissAgeDir)"
  if [ -s "$dir/identity.age" ] && [ -s "$dir/recipients.txt" ]; then
    return 0
  fi

  ensureTool age || return 1

  logInfo "No tiss encryption identity found — let's create one (once per machine)."
  logInfo "tiss encrypts with 'age' using a key that never leaves this machine."
  logInfo "Choose a passphrase now; decrypting will ask for it once per session."

  if ! [ -r /dev/tty ]; then
    logError "First-time setup needs an interactive terminal. Run '${TISS_NAME:-tiss} encrypt' once from a shell."
    return 1
  fi

  mkdir -p "$dir"
  chmod 700 "$dir"

  local key pub
  key="$(age-keygen 2>/dev/null)"
  pub="$(printf '%s\n' "$key" | age-keygen -y -)"

  # age -p prompts for the passphrase on /dev/tty; -a keeps the file ASCII.
  if ! printf '%s\n' "$key" | age -p -a >"$dir/identity.age"; then
    rm -f "$dir/identity.age"
    unset key
    logError "Identity creation aborted."
    return 1
  fi
  unset key

  printf '%s\n' "$pub" >"$dir/recipients.txt"
  chmod 600 "$dir/identity.age" "$dir/recipients.txt"
  logInfo "Identity created in $dir"
  logInfo "Public key (safe to share): $pub"
}

tissSessionDir() { # per-user 0700 session dir for unlocked material
  local dir
  dir="${TMPDIR:-/tmp}/tiss-$(id -u)"
  mkdir -p "$dir"
  chmod 700 "$dir"
  echo "$dir"
}

tissUnlockedIdentity() { # path to unlocked identity, prompting once per session
  tissEnsureIdentity || return 1
  ensureTool age || return 1

  local idfile
  idfile="$(tissSessionDir)/identity.txt"

  if [ ! -s "$idfile" ]; then
    logInfo "Unlocking tiss identity for this session (passphrase prompt)..."
    if ! (
      umask 077
      age -d "$(tissAgeDir)/identity.age" >"$idfile"
    ); then
      rm -f "$idfile"
      logError "Could not unlock identity."
      return 1
    fi
  fi
  echo "$idfile"
}

tissLockSession() { # forget the unlocked identity (used by `tiss lock`)
  rm -f "$(tissSessionDir)/identity.txt"
}
