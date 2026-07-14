#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for dns flush, the self dev commands (pull/checkout/cd/shell),
# and the tmux suite (against an isolated tmux socket).
. "$(dirname "$0")/harness.sh"

# --- dns flush -------------------------------------------------------------------
out="$("$TISS_BIN" dns flush --dry-run 2>/dev/null || true)"
case "$(uname -s)" in
  Darwin)
    assertMatch "dns flush knows macOS step 1" 'dscacheutil -flushcache' "$out"
    assertMatch "dns flush knows macOS step 2" 'killall -HUP mDNSResponder' "$out"
    ;;
  Linux)
    if [ -n "$out" ]; then
      assertMatch "dns flush picks a linux resolver" 'flush-caches|nscd -i hosts' "$out"
    else
      echo "  skip: no known resolver on this linux" >&2
    fi
    ;;
esac
assertExit "dns flush rejects unknown args" 2 "$TISS_BIN" dns flush --bogus

# --- self pull / checkout (against a fake TISS_HOME git checkout) ------------------
if command -v git >/dev/null 2>&1; then
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  origin="$TISS_TEST_TMP/origin.git"
  fake="$TISS_TEST_TMP/fakehome"
  git init --bare -q -b main "$origin"
  git init -q -b main "$fake"
  (cd "$fake" && echo v1 >f && git add -A && git commit -qm c1 && git remote add origin "$origin" && git push -qu origin main 2>/dev/null)
  # advance origin from elsewhere + add a feature branch
  other="$TISS_TEST_TMP/other"
  git clone -q "$origin" "$other" 2>/dev/null
  (cd "$other" && echo v2 >f && git add -A && git commit -qm c2 && git push -q 2>/dev/null &&
    git checkout -qb feature/share && echo v3 >f && git add -A && git commit -qm c3 && git push -qu origin feature/share 2>/dev/null)

  selfrun() { # selfrun <script> [args...] — run a self script against the fake home
    local s="$1"
    shift
    TISS_HOME="$fake" TISS_NAME=tiss bash "$TISS_TEST_ROOT/scripts/self/$s" "$@"
  }

  selfrun pull.sh >/dev/null 2>&1
  assertEq "self pull fast-forwards to origin" \
    "$(git -C "$other" rev-parse main)" "$(git -C "$fake" rev-parse HEAD)"

  list="$(selfrun checkout.sh 2>&1)"
  assertMatch "self checkout (bare) lists branches" 'feature/share' "$list"
  selfrun checkout.sh feature/share >/dev/null 2>&1
  assertEq "self checkout switches branch" "feature/share" "$(git -C "$fake" branch --show-current)"

  assertEq "self cd prints TISS_HOME" "$fake" "$(selfrun cd.sh 2>/dev/null)"
else
  echo "  skip: git missing" >&2
fi

# --- self shell integration ---------------------------------------------------------
emit="$("$TISS_BIN" self shell)"
assertMatch "shell wrapper defines the function" '^tiss\(\)' "$emit"
assertMatch "shell wrapper pushd's on self cd" 'pushd .*command tiss self cd' "$emit"
assertMatch "shell wrapper forwards everything else" 'command tiss "\$@"' "$emit"
# and it's argv[0]-aware
ln -sf "$TISS_BIN" "$TISS_TEST_TMP/nri"
assertMatch "shell wrapper follows the alias" '^nri\(\)' "$("$TISS_TEST_TMP/nri" self shell)"

# --- tmux suite (isolated socket via a shim) -----------------------------------------
if command -v tmux >/dev/null 2>&1; then
  real_tmux="$(command -v tmux)"
  mkdir -p "$TISS_TEST_TMP/bin"
  printf '#!/usr/bin/env bash\nexec %q -L tiss-test-%s "$@"\n' "$real_tmux" "$$" >"$TISS_TEST_TMP/bin/tmux"
  chmod +x "$TISS_TEST_TMP/bin/tmux"
  export PATH="$TISS_TEST_TMP/bin:$PATH"

  assertEq "tmux ls empty when no server" "" "$("$TISS_BIN" tmux ls 2>/dev/null)"
  "$TISS_BIN" tmux new testsess >/dev/null 2>&1 # no tty -> stays detached
  row="$("$TISS_BIN" tmux ls 2>/dev/null)"
  assertEq "tmux new creates a session" "testsess" "$(printf '%s' "$row" | jq -r .name)"
  assertEq "tmux ls reports attach state" false "$(printf '%s' "$row" | jq .attached)"
  assertMatch "tmux new narrates via LEARN" 'LEARN.*tmux new-session -d -s' \
    "$("$TISS_BIN" tmux new another 2>&1 >/dev/null || true)"
  assertMatch "tmux passthrough still native" 'attach-session' \
    "$("$TISS_BIN" tmux list-commands 2>/dev/null | head -1 || true)"
  "$TISS_BIN" tmux kill testsess >/dev/null 2>&1
  "$TISS_BIN" tmux kill another >/dev/null 2>&1
  assertEq "tmux kill removes sessions" "" "$("$TISS_BIN" tmux ls 2>/dev/null)"
  # tmux go: exits 2 without a tty (CI), or 0 on tty-EOF (local) — never hangs.
  rc=0
  "$TISS_BIN" tmux go </dev/null >/dev/null 2>&1 || rc=$?
  case "$rc" in 0 | 2) _report ok "tmux go exits cleanly without interaction" ;; *) _report FAIL "tmux go rc=$rc" ;; esac
  tmux kill-server 2>/dev/null || true
else
  echo "  skip: tmux missing" >&2
fi

finish
