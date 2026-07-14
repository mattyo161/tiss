#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for bin/tiss — routing, help, manifest, completion, passthrough.
. "$(dirname "$0")/harness.sh"

# Top-level help lists commands and follows argv[0].
help_out="$("$TISS_BIN")"
assertMatch "help shows usage" '^usage: tiss' "$help_out"
assertMatch "help lists encrypt" 'encrypt' "$help_out"
assertMatch "help lists namespaced command" 'self doctor' "$help_out"

# argv[0] awareness via symlink.
ln -s "$TISS_BIN" "$TISS_TEST_TMP/x"
x_help="$("$TISS_TEST_TMP/x")"
assertMatch "symlinked name in usage" '^usage: x' "$x_help"

# Namespace landing.
ns="$("$TISS_BIN" self)"
assertMatch "namespace help" '^usage: tiss self' "$ns"
assertMatch "namespace lists doctor" 'doctor' "$ns"

# Manifest is valid jsonl with expected fields.
mf="$("$TISS_BIN" --manifest)"
count="$(printf '%s\n' "$mf" | wc -l | tr -d ' ')"
[ "$count" -ge 10 ] && _report ok "manifest has $count commands" || _report FAIL "manifest only $count lines"
assertEq "manifest is valid json per line" "$count" "$(printf '%s\n' "$mf" | jq -c . | wc -l | tr -d ' ')"
assertMatch "manifest has needs array" '"needs":\["age"\]' "$(printf '%s\n' "$mf" | grep '"command":"encrypt"')"

# Passthrough behaves like the native tool.
assertEq "passthrough echo" "hello" "$("$TISS_BIN" echo hello)"
assertExit "passthrough exit status" 1 "$TISS_BIN" false
assertExit "missing tool without mise install" 127 env TISS_AUTO_INSTALL=never "$TISS_BIN" definitely-not-a-real-tool-xyz

# Namespace + help flag = namespace help, never an install prompt
# (regression: `tiss self --help` once offered to install 'self').
assertMatch "namespace --help shows help" 'usage: tiss self' "$("$TISS_BIN" self --help)"
assertMatch "namespace -h shows help" 'usage: tiss self' "$("$TISS_BIN" self -h)"
assertMatch "namespace trailing help word" 'usage: tiss git' "$("$TISS_BIN" git help)"
assertExit "namespace + other flags still pass through" 1 "$TISS_BIN" false --version

# Passthrough installs are gated by the allowlist; @needs never is.
gated="$(TISS_AUTO_INSTALL=always "$TISS_BIN" not-a-listed-tool-xyz 2>&1 || true)"
assertMatch "unlisted tool refused even with always" 'allowlist' "$gated"
assertExit "unlisted tool exits 127" 127 env TISS_AUTO_INSTALL=always "$TISS_BIN" not-a-listed-tool-xyz
allowed="$(TISS_INSTALL_ALLOW=not-a-listed-tool-xyz TISS_AUTO_INSTALL=never "$TISS_BIN" not-a-listed-tool-xyz 2>&1 || true)"
assertMatch "TISS_INSTALL_ALLOW extends the gate" 'TISS_AUTO_INSTALL=never' "$allowed"

# Completion.
top="$("$TISS_BIN" --complete "")"
assertMatch "completion lists encrypt" '(^|\n)encrypt(\n|$)' "$top"
assertMatch "completion lists self namespace" '(^|\n)self(\n|$)' "$top"
sub="$("$TISS_BIN" --complete self)"
assertMatch "completion descends namespaces" 'doctor' "$sub"
assertEq "no completion inside script args" "" "$("$TISS_BIN" --complete encrypt --in)"
zsh_mode="$("$TISS_BIN" --complete-zsh self)"
assertMatch "zsh completions carry descriptions" 'doctor:Check' "$zsh_mode"

# Script --help renders from annotations.
h="$("$TISS_BIN" encrypt --help)"
assertMatch "script help usage line" 'usage: tiss encrypt' "$h"
assertMatch "script help examples" 'examples:' "$h"

finish
