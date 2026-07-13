#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the overlay tree system: resolution, shadowing, config layering,
# overlay libs, tree management.
. "$(dirname "$0")/harness.sh"

export TISS_CONFIG="$TISS_TEST_TMP/config"
mkdir -p "$TISS_CONFIG"

# Build a fake company tree.
tree="$TISS_TEST_TMP/acme"
mkdir -p "$tree/scripts/git" "$tree/etc" "$tree/lib"

cat >"$tree/scripts/hello.sh" <<'EOF'
#!/usr/bin/env bash
# @description Say hello from the acme tree
source "$TISS_LIB/init.sh"
echo "hello from acme (helper says: $(acmeGreeting)) account=$ACME_ACCOUNT"
EOF

cat >"$tree/scripts/lock.sh" <<'EOF'
#!/usr/bin/env bash
# @description Acme-shadowed lock
echo "acme lock wins"
EOF

cat >"$tree/scripts/git/clone.sh" <<'EOF'
#!/usr/bin/env bash
# @description Acme git clone with defaults
echo "acme clone: $*"
EOF

cat >"$tree/etc/config.sh" <<'EOF'
cfg ACME_ACCOUNT 123456789
EOF

cat >"$tree/lib/init.sh" <<'EOF'
acmeGreeting() { echo "hi"; }
EOF

chmod +x "$tree"/scripts/*.sh "$tree"/scripts/git/*.sh
export TISS_PATH="$tree"

# Overlay commands resolve, with config + libs available.
out="$("$TISS_BIN" hello)"
assertMatch "overlay command runs" 'hello from acme' "$out"
assertMatch "overlay lib function available" 'helper says: hi' "$out"
assertMatch "overlay config var set" 'account=123456789' "$out"

# Env beats overlay config (cfg semantics).
assertMatch "env overrides overlay config" 'account=OVERRIDDEN' \
  "$(ACME_ACCOUNT=OVERRIDDEN "$TISS_BIN" hello)"

# Overlay shadows a core command.
assertEq "overlay wins over core" "acme lock wins" "$("$TISS_BIN" lock)"

# Namespaced overlay command; core namespace still reachable.
assertEq "overlay namespace command" "acme clone: repo" "$("$TISS_BIN" git clone repo)"
assertMatch "core commands still resolve" 'usage: tiss encrypt' "$("$TISS_BIN" encrypt --help)"

# Merged help shows overlay commands tagged, shadowed core hidden.
help_out="$("$TISS_BIN")"
assertMatch "help shows overlay command with tag" 'hello.*\[acme\]' "$help_out"
assertEq "shadowed core lock listed once" 1 "$(printf '%s\n' "$help_out" | grep -c '^  lock')"
assertMatch "help still lists core commands" 'encrypt' "$help_out"

# Manifest: tree field, dedupe, overlay wins.
mf="$("$TISS_BIN" --manifest)"
assertMatch "manifest tags overlay tree" '"command":"hello".*"tree":"acme"' "$mf"
assertEq "manifest dedupes shadowed lock" 1 "$(printf '%s\n' "$mf" | grep -c '"command":"lock"')"
assertMatch "manifest lock comes from acme" '"command":"lock".*"tree":"acme"' "$mf"

# Completions union across trees.
comp="$("$TISS_BIN" --complete "")"
assertMatch "completion includes overlay cmd" '(^|\n)hello(\n|$)' "$comp"
assertMatch "completion includes core cmd" '(^|\n)encrypt(\n|$)' "$comp"

# tree management: add/list/remove persist to user config.
unset TISS_PATH
"$TISS_BIN" self tree add "$tree" >/dev/null 2>&1
assertMatch "tree add persists to config" 'cfg TISS_PATH' "$(cat "$TISS_CONFIG/config.sh")"
assertEq "persisted tree resolves commands" "acme lock wins" "$("$TISS_BIN" lock)"
list_out="$("$TISS_BIN" self tree list 2>/dev/null)"
assertMatch "tree list shows overlay" 'acme' "$list_out"
assertMatch "tree list shows shadow count" 'shadowed by a higher tree' "$list_out"
"$TISS_BIN" self tree remove "$tree" >/dev/null 2>&1
assertMatch "tree remove restores core" 'Forget the unlocked' "$("$TISS_BIN" lock --help)"

# Guards.
assertExit "add rejects non-tree dir" 2 "$TISS_BIN" self tree add "$TISS_TEST_TMP"
assertExit "remove rejects unknown" 2 "$TISS_BIN" self tree remove /nope

finish
