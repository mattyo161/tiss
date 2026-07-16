# shellcheck shell=bash
#
# tiss execution wrappers — teach what ran, remember what it returned.
#
#   learnExec <cmd...>          run a command, showing (sanitized) what ran:
#                               "[LEARN] aws s3 ls s3://bucket" on stderr,
#                               plus an append to the history log. Multi-step
#                               scripts become teachable: the user follows
#                               along and sees every real command.
#
#   cacheExec [opts] <cmd...>   run a command through a content-addressed
#                               cache: SHA-256 of argv + significant env vars
#                               keys a saveData entry. Fresh hits return
#                               instantly — ideal in front of slow, rarely
#                               changing APIs (aws ssm describe-parameters).
#

# --- sanitizer ----------------------------------------------------------------
# Heuristic redaction for rendering commands: secret-looking flags, key=value
# pairs, and AWS-style access keys become REDACTED. This affects only what is
# DISPLAYED/logged — the real argv always runs untouched.
tissSanitizeCmd() {
  local out="" a redact_next=0
  for a in "$@"; do
    if [ "$redact_next" = 1 ]; then
      out="$out REDACTED"
      redact_next=0
      continue
    fi
    case "$a" in
      --password | --passwd | --secret | --token | --api-key | --apikey | --access-key | --secret-key | --private-key)
        out="$out $a"
        redact_next=1
        ;;
      --password=* | --passwd=* | --secret=* | --token=* | --api-key=* | --apikey=* | --access-key=* | --secret-key=* | --private-key=*)
        out="$out ${a%%=*}=REDACTED"
        ;;
      *[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]*=* | *[Ss][Ee][Cc][Rr][Ee][Tt]*=* | *[Tt][Oo][Kk][Ee][Nn]*=* | *_KEY=* | *_key=*)
        out="$out ${a%%=*}=REDACTED"
        ;;
      AKIA[A-Z0-9]*)
        out="$out REDACTED"
        ;;
      *)
        out="$out $a"
        ;;
    esac
  done
  printf '%s\n' "${out# }"
}

# --- learnExec ----------------------------------------------------------------
learnExec() { # learnExec <command> [args...] — run it, teaching what ran
  if [ $# -eq 0 ]; then
    logError "usage: learnExec <command> [args...]"
    return 2
  fi
  local line color="" reset="" hist
  line="$(tissSanitizeCmd "$@")"
  if [ -t 2 ]; then
    color=$'\033[35m'
    reset=$'\033[0m'
  fi
  printf '%s[LEARN]%s %s\n' "$color" "$reset" "$line" >&2

  # History log: what actually got run (sanitized), when.
  hist="$(tissStateDir)/history.log"
  mkdir -p "$(dirname "$hist")"
  printf '%s %s\n' "$(ts)" "$line" >>"$hist"

  "$@"
}

# --- cacheExec ----------------------------------------------------------------
# Env vars that change a command's output must change its cache key. The
# defaults cover the usual cloud context; extend with TISS_CACHE_ENV
# (space-separated names). Only vars that are actually set participate.
TISS_CACHE_ENV_DEFAULT="TISS_ENV AWS_PROFILE AWS_DEFAULT_PROFILE AWS_REGION AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID GOOGLE_CLOUD_PROJECT CLOUDSDK_ACTIVE_CONFIG_NAME KUBECONFIG"

tissSha256() { # stdin -> hex digest (shasum on macOS, sha256sum on linux)
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    sha256sum | cut -d' ' -f1
  fi
}

tissCacheKey() { # tissCacheKey <command...> -> cache/<sha>, cacheExec's exact keying
  local sig="$*" v
  for v in $TISS_CACHE_ENV_DEFAULT ${TISS_CACHE_ENV:-}; do
    [ -n "${!v:-}" ] && sig="$sig $v=${!v}"
  done
  printf 'cache/%s' "$(printf '%s' "$sig" | tissSha256)"
}

tissFileMtime() { # epoch mtime, GNU or BSD stat
  # GNU first: BSD stat errors cleanly on -c, but GNU stat treats -f as
  # FILESYSTEM status and happily prints garbage (the mount point) for %m.
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

cacheExec() { # cacheExec [--duration D] [--refresh|--recache|--no-cache] [--encrypt] [--no-gzip] [--] <command...>
  # Two kinds of flags:
  #   prefix-only (author decisions): --duration D, --encrypt, --gzip/--no-gzip
  #   scavenged from ANYWHERE (user toggles): --no-cache, --recache, --refresh
  # Scavenging lets wrappers pass "$@" through and inherit uniform cache
  # control for free (`tiss ssm describe-parameters --recache`). A literal
  # `--` stops scavenging for tools with their own such flags
  # (`cacheExec -- docker build --no-cache .`).
  #
  #   --refresh   rerun; replace the entry only on SUCCESS (old one is safe)
  #   --recache   invalidate FIRST, then run — entry is gone even on failure
  #   --no-cache  bypass entirely: no read, no write. Exports TISS_NO_CACHE=1
  #               so nested cacheExec calls bypass too (cascading is the
  #               intent: "completely fresh, end-to-end").
  local dur="1h" gz_opt="" enc_opt="" refresh=0 recache=0 no_cache=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --duration)
        dur="${2:?--duration needs a value (e.g. 1h, 1w1d, 30)}"
        shift
        ;;
      --refresh) refresh=1 ;;
      --recache) recache=1 ;;
      --no-cache) no_cache=1 ;;
      --encrypt) enc_opt="--encrypt" ;;
      --gzip) gz_opt="--gzip" ;;
      --no-gzip) gz_opt="--no-gzip" ;;
      *) break ;;
    esac
    shift
  done

  # Scavenge the boolean trio from the rest of the argv (until `--`).
  local cmd=() verbatim=0 a
  for a in "$@"; do
    if [ "$verbatim" = 1 ]; then
      cmd+=("$a")
      continue
    fi
    case "$a" in
      --) verbatim=1 ;; # marker consumed; everything after is the command's
      --no-cache) no_cache=1 ;;
      --recache) recache=1 ;;
      --refresh) refresh=1 ;;
      *) cmd+=("$a") ;;
    esac
  done
  set -- ${cmd[@]+"${cmd[@]}"}

  if [ $# -eq 0 ]; then
    logError "usage: cacheExec [--duration D] [--refresh|--recache|--no-cache] [--encrypt] [--] <command...>"
    return 2
  fi

  # Bypass mode: no read, no write — and cascade the intent to children
  # via prefix-env ONLY (mutating/exporting in the caller's shell would
  # silently disable caching for the rest of the calling script).
  if [ "$no_cache" = 1 ] || [ "${TISS_NO_CACHE:-0}" = 1 ]; then
    logDebug "cacheExec: bypassed (--no-cache)"
    TISS_NO_CACHE=1 "$@"
    return $?
  fi

  local dur_s
  dur_s="$(dur2s "$dur")" || return 2

  # Cache key: the exact command line plus every significant env var that
  # is set — AWS_PROFILE=prod and AWS_PROFILE=dev cache separately.
  local key
  key="$(tissCacheKey "$@")"

  # --recache: invalidate up front — the old entry must not survive,
  # even if the command below fails (contrast with --refresh).
  if [ "$recache" = 1 ]; then
    local rc_base rc_f
    rc_base="$(tissDataDir)/$key"
    for rc_f in "$rc_base" "$rc_base.gz" "$rc_base.age" "$rc_base.gz.age"; do
      rm -f "$rc_f"
    done
    logDebug "cacheExec: invalidated ($key)"
  fi

  # Fresh hit?
  if [ "$refresh" = 0 ] && [ "$recache" = 0 ]; then
    local base f file="" now mtime
    base="$(tissDataDir)/$key"
    for f in "$base" "$base.gz" "$base.age" "$base.gz.age"; do
      [ -f "$f" ] && file="$f"
    done
    if [ -n "$file" ]; then
      now="$(date +%s)"
      mtime="$(tissFileMtime "$file")"
      if [ $((now - mtime)) -le "$dur_s" ]; then
        logDebug "cacheExec: hit ($key)"
        # Cached data should never masquerade as fresh: say so on stderr
        # ([LEARN]-style, pipes stay clean). TISS_CACHE_NOTICE=0 silences.
        cfg TISS_CACHE_NOTICE 1
        if [ "$TISS_CACHE_NOTICE" = 1 ]; then
          local nc="" nr=""
          if [ -t 2 ]; then
            nc=$'\033[36m'
            nr=$'\033[0m'
          fi
          printf '%s[CACHE]%s %s (age %s, expires in %s — --refresh reruns)\n' \
            "$nc" "$nr" "$(tissSanitizeCmd "$@")" \
            "$(s2dur $((now - mtime)))" "$(s2dur $((dur_s - now + mtime)))" >&2
        fi
        readData "$key"
        return $?
      fi
    fi
  fi

  # Miss (or stale, or --refresh): run for real. A failing command is never
  # cached — its exit status propagates and the old entry (if any) survives.
  local tmp rc=0
  tmp="$(mktemp)" || return 1
  "$@" >"$tmp" || rc=$?
  if [ "$rc" != 0 ]; then
    rm -f "$tmp"
    logError "cacheExec: command failed (exit $rc) — not cached"
    return "$rc"
  fi
  # shellcheck disable=SC2086  # word-splitting of the option strings is intended
  saveData $gz_opt $enc_opt "$key" <"$tmp"
  cat "$tmp"
  rm -f "$tmp"
}
