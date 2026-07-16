#!/usr/bin/env bash
# Tests for tree packages: +name/-name prefixes, install/enable/disable,
# @version refs, spec parsing, and pile install.
. "$(dirname "$0")/harness.sh"

export TISS_CONFIG="$TISS_TEST_TMP/config"
export TISS_TREES="$TISS_TEST_TMP/trees"

G() { git -c user.email=t@t -c user.name=t "$@"; } # fixture commits need an identity

# Fixture: a bare "distribution repo" whose tree/devops branch is a tree
# shell — v1 tagged tree/devops@v1, branch head at v2.
bare="$TISS_TEST_TMP/dist.git"
fix="$TISS_TEST_TMP/fixture"
git init -q --bare "$bare"
git init -q "$fix"
G -C "$fix" checkout -q --orphan tree/devops
mkdir -p "$fix/scripts"
printf '#!/usr/bin/env bash\n# @description say hello\necho "hello v1"\n' >"$fix/scripts/hello.sh"
chmod +x "$fix/scripts/hello.sh"
G -C "$fix" add -A && G -C "$fix" commit -q -m "devops v1"
G -C "$fix" tag "tree/devops@v1"
printf '#!/usr/bin/env bash\n# @description say hello\necho "hello v2"\n' >"$fix/scripts/hello.sh"
G -C "$fix" add -A && G -C "$fix" commit -q -m "devops v2"
G -C "$fix" push -q "$bare" tree/devops "tree/devops@v1"
export TISS_TREES_REPO="$bare"

# --- +name: install, enable, route — one gesture --------------------------------
assertEq "+name installs and routes in one shot" "hello v2" "$("$TISS_BIN" +devops hello 2>/dev/null)"
assertFileExists "clone landed in TISS_TREES" "$TISS_TREES/devops/scripts/hello.sh"
assertMatch "enable persisted to the managed config line" 'cfg TISS_PATH .*trees/devops' "$(cat "$TISS_CONFIG/config.sh")"
assertEq "subsequent plain invocation routes" "hello v2" "$("$TISS_BIN" hello 2>/dev/null)"
assertMatch "pile list shows the package" 'devops' "$("$TISS_BIN" pile list 2>/dev/null)"

# --- -name: disable keeps the clone ----------------------------------------------
"$TISS_BIN" -devops >/dev/null 2>&1
assertExit "disabled tree no longer routes" 127 env TISS_AUTO_INSTALL=never "$TISS_BIN" hello
assertFileExists "clone kept on disk after disable" "$TISS_TREES/devops/scripts/hello.sh"
assertMatch "disabled package surfaced in list" 'installed, disabled' "$("$TISS_BIN" pile list 2>/dev/null)"

# --- re-enable is pure local (no network) ------------------------------------------
mv "$bare" "$bare.offline"
assertEq "+name re-enables offline" "hello v2" "$("$TISS_BIN" +devops hello 2>/dev/null)"
mv "$bare.offline" "$bare"

# --- flags still work: -h is help, not a tree op -------------------------------------
assertMatch "-h stays help" '^usage: tiss' "$("$TISS_BIN" -h)"

# --- @version fetches the tag; @latest returns to branch head -------------------------
assertEq "@version checks out the tag" "hello v1" "$("$TISS_BIN" +devops@v1 hello 2>/dev/null)"
assertEq "@latest returns to the branch head" "hello v2" "$("$TISS_BIN" +devops@latest hello 2>/dev/null)"
assertExit "unknown version fails" 2 "$TISS_BIN" +devops@nope hello

# --- pile install is the long-form spelling ----------------------------------------
"$TISS_BIN" -devops >/dev/null 2>&1
assertMatch "pile install enables too" 'devops' "$("$TISS_BIN" pile install devops 2>/dev/null)"
assertEq "and routing works after it" "hello v2" "$("$TISS_BIN" hello 2>/dev/null)"

# --- spec resolution (direct lib calls) ---------------------------------------------------
tissTreeResolve "acme/tiss-devops@v3"
assertEq "owner/repo url" "https://github.com/acme/tiss-devops" "$TREE_URL"
assertEq "owner/repo name" "tiss-devops" "$TREE_NAME"
assertEq "owner/repo track is the default branch" "HEAD" "$TREE_TRACK"
assertEq "owner/repo ref is the literal ref" "v3" "$(tissTreeRefCandidates | head -1)"
tissTreeResolve "git@github.com:acme/tools.git"
assertEq "ssh url untouched by @-splitting" "git@github.com:acme/tools.git" "$TREE_URL"
assertEq "ssh url name strips .git" "tools" "$TREE_NAME"
tissTreeResolve "prod@v2" "" "env/prod"
assertEq "branch override respected" "env/prod" "$TREE_TRACK"
assertEq "version tries the tag convention first" "env/prod@v2" "$(tissTreeRefCandidates | head -1)"
assertEq "and falls back to the literal ref" "v2" "$(tissTreeRefCandidates | tail -1)"
tissTreeResolve "devops"
assertEq "installed clone is the mapping (track)" "tree/devops" "$TREE_TRACK"
assertEq "installed clone is the mapping (source)" "$bare" "$TREE_URL"

# --- resolve: "where does this fetch from?" as jsonl -----------------------------------------
r="$("$TISS_BIN" pile resolve devops 2>/dev/null)"
assertEq "resolve shows the source" "$bare" "$(printf '%s' "$r" | jq -r .source)"
assertEq "resolve shows the track" "tree/devops" "$(printf '%s' "$r" | jq -r .track)"
assertEq "resolve knows it's installed" "true" "$(printf '%s' "$r" | jq -r .installed)"
r="$("$TISS_BIN" pile resolve newpkg@v9 2>/dev/null)"
assertEq "uninstalled name resolves by convention" "tree/newpkg@v9" "$(printf '%s' "$r" | jq -r .ref)"
assertEq "uninstalled name has no path" "null" "$(printf '%s' "$r" | jq -r .path)"

# --- custom mapping: --repo/--branch, non-tree/ branch names ---------------------------------
bare2="$TISS_TEST_TMP/acme.git"
fix2="$TISS_TEST_TMP/fixture2"
git init -q --bare "$bare2"
git init -q "$fix2"
G -C "$fix2" checkout -q --orphan env/prod
mkdir -p "$fix2/scripts"
printf '#!/usr/bin/env bash\n# @description prod greeting\necho "prod v0.8.5"\n' >"$fix2/scripts/prodhello.sh"
chmod +x "$fix2/scripts/prodhello.sh"
G -C "$fix2" add -A && G -C "$fix2" commit -q -m "prod v0.8.5"
G -C "$fix2" tag 'env/prod@v0.8.5'
printf '#!/usr/bin/env bash\n# @description prod greeting\necho "prod v0.9.0"\n' >"$fix2/scripts/prodhello.sh"
G -C "$fix2" add -A && G -C "$fix2" commit -q -m "prod v0.9.0"
G -C "$fix2" push -q "$bare2" env/prod 'env/prod@v0.8.5'

"$TISS_BIN" pile add prod --repo "$bare2" --branch env/prod >/dev/null 2>&1
assertEq "custom-mapped tree routes" "prod v0.9.0" "$("$TISS_BIN" prodhello 2>/dev/null)"
r="$("$TISS_BIN" pile resolve prod 2>/dev/null)"
assertEq "mapping stored in the clone (source)" "$bare2" "$(printf '%s' "$r" | jq -r .source)"
assertEq "mapping stored in the clone (track)" "env/prod" "$(printf '%s' "$r" | jq -r .track)"
assertEq "@ver uses the mapped track's tag convention" "prod v0.8.5" "$("$TISS_BIN" +prod@v0.8.5 prodhello 2>/dev/null)"
assertEq "@latest returns to the mapped branch head" "prod v0.9.0" "$("$TISS_BIN" +prod@latest prodhello 2>/dev/null)"

# --- list --json ------------------------------------------------------------------------------
"$TISS_BIN" -devops >/dev/null 2>&1 # one disabled package for the listing
lj="$("$TISS_BIN" pile list --json 2>/dev/null)"
assertEq "list --json is valid jsonl" "$(printf '%s\n' "$lj" | wc -l | tr -d ' ')" "$(printf '%s\n' "$lj" | jq -c . | wc -l | tr -d ' ')"
assertEq "core row present" "core" "$(printf '%s\n' "$lj" | jq -rs '.[] | select(.kind == "core") | .kind')"
assertEq "package rows carry their source" "$bare2" "$(printf '%s\n' "$lj" | jq -rs '.[] | select(.name == "prod") | .source')"
assertEq "disabled packages included, marked" "false" "$(printf '%s\n' "$lj" | jq -rs '.[] | select(.name == "devops") | .enabled')"
assertEq "enabled packages marked" "true" "$(printf '%s\n' "$lj" | jq -rs '.[] | select(.name == "prod") | .enabled')"

# --- pile new: the scaffolder --------------------------------------------------
(cd "$TISS_TEST_TMP" && "$TISS_BIN" pile new mypack >/dev/null 2>&1)
assertFileExists "scaffold creates the example leaf" "$TISS_TEST_TMP/mypack/scripts/hello.sh"
assertFileExists "scaffold seeds tree config" "$TISS_TEST_TMP/mypack/etc/config.sh"
assertEq "scaffold branch follows the convention" "tree/mypack" \
  "$(git -C "$TISS_TEST_TMP/mypack" branch --show-current)"
assertExit "reserved names refused by new" 2 "$TISS_BIN" pile new doctor
assertExit "existing dir refused by new" 2 \
  bash -c "cd '$TISS_TEST_TMP' && '$TISS_BIN' pile new mypack"

bare3="$TISS_TEST_TMP/pubdist.git"
git init -q --bare "$bare3"
(cd "$TISS_TEST_TMP" && "$TISS_BIN" pile new pubpack --push --repo "$bare3" >/dev/null 2>&1)
assertMatch "scaffold published as a tree branch" 'refs/heads/tree/pubpack' "$(git ls-remote "$bare3" 2>/dev/null)"
assertEq "published scaffold installs and routes" "hello from the pubpack tree" \
  "$(TISS_TREES_REPO="$bare3" "$TISS_BIN" +pubpack hello 2>/dev/null)"

finish
