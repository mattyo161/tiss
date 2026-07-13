#!/usr/bin/env bash
# Tests for bin/tiss — routing, help, manifest, completion, passthrough.
. "$(dirname "$0")/harness.sh"

# Top-level help lists commands and follows argv[0].
help_out="$("$TISS_BIN")"
assertMatch "help shows usage" '^usage: tiss' "$help_out"
assertMatch "help lists encrypt" 'encrypt' "$help_out"
assertMatch "help lists namespaced command" 'tiss doctor' "$help_out"

# argv[0] awareness via symlink.
ln -s "$TISS_BIN" "$TISS_TEST_TMP/x"
x_help="$("$TISS_TEST_TMP/x")"
assertMatch "symlinked name in usage" '^usage: x' "$x_help"

# Namespace landing.
ns="$("$TISS_BIN" tiss)"
assertMatch "namespace help" '^usage: tiss tiss' "$ns"
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

# Completion.
top="$("$TISS_BIN" --complete "")"
assertMatch "completion lists encrypt" '(^|\n)encrypt(\n|$)' "$top"
assertMatch "completion lists tiss namespace" '(^|\n)tiss(\n|$)' "$top"
sub="$("$TISS_BIN" --complete tiss)"
assertMatch "completion descends namespaces" 'doctor' "$sub"
assertEq "no completion inside script args" "" "$("$TISS_BIN" --complete encrypt --in)"
zsh_mode="$("$TISS_BIN" --complete-zsh tiss)"
assertMatch "zsh completions carry descriptions" 'doctor:Check' "$zsh_mode"

# Script --help renders from annotations.
h="$("$TISS_BIN" encrypt --help)"
assertMatch "script help usage line" 'usage: tiss encrypt' "$h"
assertMatch "script help examples" 'examples:' "$h"

finish
