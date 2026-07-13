#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the git wrapper set, against throwaway repos with a bare remote.
. "$(dirname "$0")/harness.sh"

if ! command -v git >/dev/null 2>&1; then
  echo "$(basename "$0"): skipped (git not installed)"
  rm -rf "$TISS_TEST_TMP"
  exit 0
fi

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

remote="$TISS_TEST_TMP/remote.git"
repo="$TISS_TEST_TMP/repo"
git init --bare -q -b main "$remote"
git init -q -b main "$repo"
cd "$repo" || exit 1
git remote add origin "$remote"
echo one >f.txt
git add -A && git commit -qm "c1"
git push -qu origin main 2>/dev/null

# --- wip / unwip ---------------------------------------------------------------
echo dirty >>f.txt
"$TISS_BIN" git wip trying stuff >/dev/null 2>&1
assertMatch "wip commits with WIP subject" '^WIP .*trying stuff' "$(git log -1 --format=%s)"
assertEq "wip leaves tree clean" "" "$(git status --porcelain)"

"$TISS_BIN" git unwip >/dev/null 2>&1
assertEq "unwip restores working tree" " M f.txt" "$(git status --porcelain)"
assertEq "unwip removed the commit" "c1" "$(git log -1 --format=%s)"

assertExit "unwip refuses non-WIP commit" 2 "$TISS_BIN" git unwip
git checkout -q f.txt

# --- undo ----------------------------------------------------------------------
echo two >g.txt
git add -A && git commit -qm "local only"
"$TISS_BIN" git undo >/dev/null 2>&1
assertEq "undo soft-resets" "c1" "$(git log -1 --format=%s)"
assertEq "undo keeps changes staged" "A  g.txt" "$(git status --porcelain)"
git commit -qm "local only again"
git push -q origin main 2>/dev/null
assertExit "undo refuses published commit without --yes" 2 "$TISS_BIN" git undo
"$TISS_BIN" git undo --yes >/dev/null 2>&1
assertEq "undo --yes overrides" "c1" "$(git log -1 --format=%s)"
git reset -q --hard origin/main

# --- sync ----------------------------------------------------------------------
# Create upstream progress from a second clone.
other="$TISS_TEST_TMP/other"
git clone -q "$remote" "$other" 2>/dev/null
(cd "$other" && echo three >h.txt && git add -A && git commit -qm "upstream change" && git push -q 2>/dev/null)
# Local dirty file + behind upstream.
echo local-dirt >>f.txt
out="$("$TISS_BIN" git sync 2>&1)"
assertMatch "sync narrates via LEARN" 'LEARN.*git fetch --all --prune' "$out"
assertEq "sync rebased onto upstream" "upstream change" "$(git log -1 --format=%s)"
assertMatch "sync restored dirty work" 'local-dirt' "$(cat f.txt)"
assertEq "sync popped the stash" 0 "$(git stash list | wc -l | tr -d ' ')"

# --- cleanup -------------------------------------------------------------------
git checkout -qb feature/done
git push -qu origin feature/done 2>/dev/null
git checkout -q main
git push -q origin --delete feature/done 2>/dev/null
out="$("$TISS_BIN" git cleanup 2>&1)"
assertMatch "cleanup dry-run lists gone branch" 'feature/done' "$out"
git rev-parse -q --verify feature/done >/dev/null && _report ok "dry-run did not delete" || _report FAIL "dry-run deleted the branch"
"$TISS_BIN" git cleanup --yes >/dev/null 2>&1
git rev-parse -q --verify feature/done >/dev/null && _report FAIL "cleanup --yes left branch" || _report ok "cleanup --yes deleted gone branch"

# Outside a repo.
cd "$TISS_TEST_TMP" || exit 1
assertExit "sync outside repo exits 2" 2 "$TISS_BIN" git sync

finish
