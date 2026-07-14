#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for environment profiles (@name), tool@version, and REPL help.
. "$(dirname "$0")/harness.sh"

export TISS_CONFIG="$TISS_TEST_TMP/config"
mkdir -p "$TISS_CONFIG/env"

# Overlay tree with a team profile + a probe script.
tree="$TISS_TEST_TMP/acme"
mkdir -p "$tree/scripts" "$tree/etc/env"
cat >"$tree/etc/env/dev.sh" <<'ENV'
export ACME_MARKER=from-tree
export ACME_REGION=us-east-1
ENV
cat >"$tree/scripts/envprobe.sh" <<'PROBE'
#!/usr/bin/env bash
# @description Print environment probe
echo "${TISS_ENV:-none}|${ACME_MARKER:-unset}|${ACME_REGION:-unset}"
PROBE
chmod +x "$tree/scripts/envprobe.sh"
export TISS_PATH="$tree"

# @name loads the profile for one invocation.
assertEq "@env loads tree profile" "dev|from-tree|us-east-1" "$("$TISS_BIN" @dev envprobe)"
assertEq "no @env means no profile" "none|unset|unset" "$("$TISS_BIN" envprobe)"

# User profile layers over the tree's (loads last, wins).
echo 'export ACME_MARKER=user-wins' >"$TISS_CONFIG/env/dev.sh"
assertEq "user profile wins over tree" "dev|user-wins|us-east-1" "$("$TISS_BIN" @dev envprobe)"

# Unknown environment: guided error, lists what exists.
err="$("$TISS_BIN" @nope envprobe 2>&1 || true)"
assertExit "unknown env exits 2" 2 "$TISS_BIN" @nope envprobe
assertMatch "unknown env lists available" 'available:.*dev' "$err"
assertMatch "unknown env says how to create" 'self env edit nope' "$err"

# self env list/show.
assertMatch "self env list shows dev" '(^|\n)dev(\n|$)' "$("$TISS_BIN" self env list 2>/dev/null)"
show="$("$TISS_BIN" self env show dev)"
assertMatch "show lists tree file first" "acme/etc/env/dev.sh" "$show"
assertMatch "show lists user file" "config/env/dev.sh" "$show"

# Environments never share cacheExec keys.
k_dev="$(TISS_ENV=dev bash -c 'source "$TISS_LIB/init.sh"; tissCacheKey echo x' 2>/dev/null)"
k_prod="$(TISS_ENV=prod bash -c 'source "$TISS_LIB/init.sh"; tissCacheKey echo x' 2>/dev/null)"
[ "$k_dev" != "$k_prod" ] && _report ok "TISS_ENV separates cache keys" || _report FAIL "dev/prod share a cache key"

# Bare @env drops into the dev shell with the environment loaded.
repl="$(printf 'echo "E=$TISS_ENV M=$ACME_MARKER"\nexit\n' | "$TISS_BIN" @dev 2>/dev/null)"
assertMatch "bare @env enters the env shell" 'E=dev M=user-wins' "$repl"
assertMatch "env shell banner names the env" 'environment: dev' "$repl"

# REPL help: command tree + loaded helpers.
h="$(printf 'help\nexit\n' | "$TISS_BIN" self shell 2>/dev/null)"
assertMatch "repl help shows commands" 'commands:' "$h"
assertMatch "repl help lists helpers" 'helpers loaded in this shell' "$h"
assertMatch "repl help includes cacheExec" 'cacheExec' "$h"

# tool@version routes through mise x (shimmed), gated by the allowlist.
mkdir -p "$TISS_TEST_TMP/bin"
printf '#!/usr/bin/env bash\necho "mise-shim: $*"\n' >"$TISS_TEST_TMP/bin/mise"
chmod +x "$TISS_TEST_TMP/bin/mise"
export PATH="$TISS_TEST_TMP/bin:$PATH"
assertEq "tool@version becomes mise x" "mise-shim: x python@3.13 -- python --version" \
  "$("$TISS_BIN" python@3.13 --version 2>/dev/null)"
assertExit "unlisted tool@version refused" 127 "$TISS_BIN" nothere@1.0 --version

finish
