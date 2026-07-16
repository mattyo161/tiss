#!/usr/bin/env bash
# Tests for the reserved lexicon: top-level meta commands, core-only
# resolution (no tree can shadow the contract), the -- escape, and the
# lexicon-first help layout.
. "$(dirname "$0")/harness.sh"

# --- reserved words route to core, top-level -------------------------------------
assertMatch "tiss doctor works top-level" 'invoked as' "$(TISS_LOG_LEVEL=INFO "$TISS_BIN" doctor 2>&1 || true)"
assertEq "tiss config path works top-level" "$TISS_CONFIG/config.sh" "$("$TISS_BIN" config path 2>/dev/null)"
assertMatch "tiss version prints the version" '^tiss .* \(' "$("$TISS_BIN" version)"
assertMatch "tiss init emits rc code" 'mise activate' "$("$TISS_BIN" init 2>/dev/null)"
assertMatch "legacy self spelling still works (hidden)" 'invoked as' "$(TISS_LOG_LEVEL=INFO "$TISS_BIN" self doctor 2>&1 || true)"

# --- no tree can shadow the lexicon ------------------------------------------------
tree="$TISS_TEST_TMP/evil"
mkdir -p "$tree/scripts/self"
printf '#!/usr/bin/env bash\necho HIJACKED\n' >"$tree/scripts/doctor.sh"
printf '#!/usr/bin/env bash\necho HIJACKED\n' >"$tree/scripts/pull.sh"
printf '#!/usr/bin/env bash\necho HIJACKED\n' >"$tree/scripts/self/doctor.sh"
chmod +x "$tree/scripts/doctor.sh" "$tree/scripts/pull.sh" "$tree/scripts/self/doctor.sh"
out="$(TISS_PATH="$tree" TISS_LOG_LEVEL=INFO "$TISS_BIN" doctor 2>&1 || true)"
assertMatch "reserved word resolves from core despite shadow" 'invoked as' "$out"
case "$out" in
  *HIJACKED*) _report FAIL "tree hijacked a reserved word" ;;
  *) _report ok "tree cannot hijack a reserved word" ;;
esac
assertMatch "doctor flags the shadow attempt" "ships reserved name" \
  "$(TISS_PATH="$tree" TISS_LOG_LEVEL=WARN "$TISS_BIN" doctor 2>&1 || true)"

# --- -- escapes to the real tool -----------------------------------------------------
assertEq "-- runs the real binary" "hi" "$("$TISS_BIN" -- echo hi 2>/dev/null)"
assertMatch "-- env reaches /usr/bin/env" 'PATH=' "$("$TISS_BIN" -- env 2>/dev/null)"

# --- help: lexicon first, divider, self hidden ----------------------------------------
h="$("$TISS_BIN")"
assertMatch "help leads with the lexicon" 'tiss lexicon \(reserved' "$h"
assertMatch "help has the commands divider" '== Commands =' "$h"
assertMatch "lexicon lists doctor" 'doctor.*installation' "$h"
case "$h" in
  *"self doctor"*) _report FAIL "help still lists self-prefixed commands" ;;
  *) _report ok "self hidden from top-level help" ;;
esac
assertEq "lexicon section precedes commands" "1" "$(printf '%s\n' "$h" | awk '/tiss lexicon/{l=NR} /== Commands/{c=NR} END{print (l<c)?1:0}')"

# --- completions and manifest carry the lexicon ------------------------------------------
comp="$("$TISS_BIN" --complete)"
assertMatch "completion offers doctor" '(^|\n)doctor($|\n)' "$comp"
case "$comp" in
  *self*) _report FAIL "completion offers self" ;;
  *) _report ok "completion hides self" ;;
esac
mf="$("$TISS_BIN" --manifest 2>/dev/null)"
assertMatch "manifest carries reserved entries" '"command":"doctor","type":"reserved"' "$mf"
case "$mf" in
  *'"command":"self'*) _report FAIL "manifest still has self-prefixed commands" ;;
  *) _report ok "manifest maps self away" ;;
esac

# --- shortcuts can't take reserved names ---------------------------------------------------
export TISS_SHIMS="$TISS_TEST_TMP/shims"
assertExit "shortcut named 'doctor' refused" 2 "$TISS_BIN" shortcuts add doctor tf plan
assertExit "shortcut named 'pile' refused" 2 "$TISS_BIN" shortcuts add pile tf plan

finish
