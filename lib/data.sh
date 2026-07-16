# shellcheck shell=bash
#
# tiss data store — named, pipe-friendly storage.
#
#   ... | saveData <name>     write stdin to the data dir (gzipped by default)
#   readData <name> | ...     stream it back (unwinds whatever save did)
#
# Design (see DESIGN.md "Data store"):
#   - Writes stream to a tmp file next to the target, then rename atomically:
#     readers never see partial data.
#   - Extensions record the write pipeline: name.gz.age = gzipped, then
#     encrypted. readData reads them right-to-left to unwind — files
#     self-describe, no flags needed to read them back.
#   - One file per name: a successful save removes variants written with
#     different options.
#   - Names may contain / for namespacing (aws/params); absolute paths and
#     .. are rejected.
#
tissDataDir() {
  echo "${TISS_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/tiss/data}"
}

_tissDataBase() { # _tissDataBase <name> -> full path base (no extensions)
  local name="${1:-}"
  case "$name" in
    "")
      logError "data name required"
      return 2
      ;;
    /* | *..* | */ | *" "*)
      logError "invalid data name '$name' (must be relative, no '..', no spaces)"
      return 2
      ;;
  esac
  echo "$(tissDataDir)/$name"
}

saveData() { # saveData [--gzip|--no-gzip] [--encrypt|--no-encrypt] <name>
  local gz=1 enc=0 name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --gzip) gz=1 ;;
      --no-gzip) gz=0 ;;
      --encrypt) enc=1 ;;
      --no-encrypt) enc=0 ;;
      -*)
        logError "saveData: unknown option $1"
        return 2
        ;;
      *) name="$1" ;;
    esac
    shift
  done

  local base
  base="$(_tissDataBase "$name")" || return $?

  # Extension chain records the write pipeline, in order.
  local ext=""
  [ "$gz" = 1 ] && ext=".gz"
  [ "$enc" = 1 ] && ext="$ext.age"

  # Encryption needs only the public recipients file — never prompts.
  local recipients=""
  if [ "$enc" = 1 ]; then
    ensureTool age || return 1
    recipients="$(tissRecipients)" || return 1
  fi

  mkdir -p "$(dirname "$base")"

  local tmp rc=0
  tmp="$(mktemp "$base.tmp.XXXXXX")" || return 1
  chmod 600 "$tmp"

  # Stream stdin through the requested pipeline into the tmp file.
  # Compression always happens BEFORE encryption (encrypted bytes don't
  # compress) — same order the extension chain records.
  if [ "$gz" = 1 ] && [ "$enc" = 1 ]; then
    gzip -c | age -R "$recipients" >"$tmp" || rc=$?
  elif [ "$gz" = 1 ]; then
    gzip -c >"$tmp" || rc=$?
  elif [ "$enc" = 1 ]; then
    age -R "$recipients" >"$tmp" || rc=$?
  else
    cat >"$tmp" || rc=$?
  fi
  if [ "$rc" != 0 ]; then
    rm -f "$tmp"
    logError "saveData: write failed for '$name'"
    return "$rc"
  fi

  # Atomic publish, then drop variants written with different options so
  # every name resolves to exactly one file.
  mv -f "$tmp" "$base$ext"
  local f
  for f in "$base" "$base.gz" "$base.age" "$base.gz.age"; do
    [ "$f" != "$base$ext" ] && rm -f "$f"
  done
  logDebug "saveData: wrote $base$ext"
}

tissHumanBytes() { # tissHumanBytes <n> -> 512B, 1.4KB, 13.2MB ...
  awk -v b="${1:-0}" 'BEGIN {
    split("B KB MB GB TB", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d%s" : "%.1f%s"), b, u[i]
  }'
}

lsData() { # lsData [prefix] [--json] [--cache|--cache-only] -> table on a tty, else jsonl
  # cacheExec entries (cache/<sha>) dominate real data, so they are
  # summarized by default: --cache includes them, --cache-only isolates
  # them, and a cache/ prefix implies inclusion. --json forces jsonl
  # even on a tty; piped output is always jsonl.
  local prefix="" json=0 cache_mode=skip a dir
  for a in "$@"; do
    case "$a" in
      --json) json=1 ;;
      --cache) cache_mode=include ;;
      --cache-only) cache_mode=only ;;
      -*)
        logError "lsData: unknown flag '$a' (prefix, --json, --cache, --cache-only)"
        return 2
        ;;
      *) prefix="$a" ;;
    esac
  done
  case "$prefix" in cache*) cache_mode=include ;; esac
  dir="$(tissDataDir)"
  [ -d "$dir" ] || return 0
  ensureTool jq || return 127

  local table=0 now
  [ -t 1 ] && [ "$json" = 0 ] && table=1
  now="$(date +%s)"
  [ "$table" = 1 ] && printf '%-42s %9s %8s %s\n' "NAME" "SIZE" "AGE" "FLAGS"

  local f rel name gz enc bytes mtime flags cache_n=0 cache_b=0
  while IFS= read -r f; do
    rel="${f#"$dir"/}"
    case "$rel" in *.tmp.*) continue ;; esac # in-flight saveData tmp files
    # Unwind the extension chain to recover the logical name (see saveData).
    name="$rel"
    enc=false
    gz=false
    case "$name" in *.age)
      enc=true
      name="${name%.age}"
      ;;
    esac
    case "$name" in *.gz)
      gz=true
      name="${name%.gz}"
      ;;
    esac
    if [ -n "$prefix" ]; then
      case "$name" in "$prefix"*) ;; *) continue ;; esac
    fi
    bytes="$(wc -c <"$f" | tr -d ' ')"
    case "$name" in
      cache/*)
        if [ "$cache_mode" = "skip" ]; then
          cache_n=$((cache_n + 1))
          cache_b=$((cache_b + bytes))
          continue
        fi
        ;;
      *)
        [ "$cache_mode" = "only" ] && continue
        ;;
    esac
    mtime="$(tissFileMtime "$f")"
    if [ "$table" = 1 ]; then
      flags=""
      [ "$gz" = true ] && flags="gz"
      [ "$enc" = true ] && flags="$flags${flags:+,}age"
      printf '%-42s %9s %8s %s\n' "$name" "$(tissHumanBytes "$bytes")" "$(s2dur $((now - mtime)))" "$flags"
    else
      jq -cn \
        --arg name "$name" \
        --argjson gzip "$gz" \
        --argjson encrypted "$enc" \
        --argjson bytes "$bytes" \
        --arg modified "$(ts2js "$mtime")" \
        --arg file "$rel" \
        '{name: $name, gzip: $gzip, encrypted: $encrypted,
          bytes: $bytes, modified: $modified, file: $file}'
    fi
  done < <(find "$dir" -type f | sort)

  # The cache summary rides stderr: tty users see it under the table,
  # pipelines never have their jsonl polluted.
  if [ "$cache_mode" = "skip" ] && [ "$cache_n" -gt 0 ]; then
    logInfo "+ $cache_n cacheExec entr$([ "$cache_n" = 1 ] && echo y || echo ies) ($(tissHumanBytes "$cache_b")) — --cache includes, --cache-only isolates"
  fi
}

readData() { # readData <name> -> stream contents to stdout
  local name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -*)
        logError "readData: unknown option $1"
        return 2
        ;;
      *) name="$1" ;;
    esac
    shift
  done

  local base
  base="$(_tissDataBase "$name")" || return $?

  # Find the stored variant (exactly one after a clean save; newest wins
  # if a crashed save ever left more than one).
  local f file=""
  for f in "$base" "$base.gz" "$base.age" "$base.gz.age"; do
    [ -f "$f" ] || continue
    if [ -z "$file" ] || [ "$f" -nt "$file" ]; then
      file="$f"
    fi
  done
  if [ -z "$file" ]; then
    logError "readData: no data named '$name' in $(tissDataDir)"
    return 1
  fi

  # Unwind the extension chain right-to-left: decrypt, then decompress.
  local identity=""
  case "$file" in
    *.age)
      ensureTool age || return 1
      identity="$(tissUnlockedIdentity)" || return 1
      ;;
  esac

  case "$file" in
    *.gz.age) age -d -i "$identity" "$file" | gzip -dc ;;
    *.age) age -d -i "$identity" "$file" ;;
    *.gz) gzip -dc "$file" ;;
    *) cat "$file" ;;
  esac
}
