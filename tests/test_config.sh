#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for configuration: the template, tiss self config, and the
# self-enforcing rule that every TISS_* var in code is documented.
. "$(dirname "$0")/harness.sh"

export TISS_CONFIG="$TISS_TEST_TMP/config"
template="$TISS_TEST_ROOT/etc/config.sh.example"

# The template is pure documentation: sourcing it changes nothing.
before="$(env | grep -c '^TISS_' || true)"
# shellcheck disable=SC1090
(. "$template")
assertEq "template sets nothing (all commented)" "$before" "$(env | grep -c '^TISS_' || true)"
assertExit "template sources cleanly" 0 bash -c ". '$template'"

# self config seeds the file from the template on first use.
p="$("$TISS_BIN" self config path 2>/dev/null)"
assertEq "config path under TISS_CONFIG" "$TISS_CONFIG/config.sh" "$p"
assertFileExists "config seeded from template" "$TISS_CONFIG/config.sh"
assertMatch "seeded file is the commented template" '# cfg TISS_AUTO_INSTALL ask' "$(cat "$TISS_CONFIG/config.sh")"

# list shows every template setting with effective values; env overrides show.
list="$("$TISS_BIN" self config list 2>/dev/null)"
assertMatch "list shows settings" 'TISS_RMAFTER_INTERVAL' "$list"
assertMatch "unset shows (default)" 'TISS_CACHE_ENV *\(default\)' "$list"
dbg="$(TISS_LOG_LEVEL=DEBUG "$TISS_BIN" self config list 2>/dev/null)"
assertMatch "env override visible in list" 'TISS_LOG_LEVEL *DEBUG' "$dbg"

# An uncommented setting takes effect... and env still beats it.
echo 'cfg TISS_SSM_CACHE_DURATION 5m' >>"$TISS_CONFIG/config.sh"
assertMatch "config file value effective" 'TISS_SSM_CACHE_DURATION *5m' \
  "$("$TISS_BIN" self config list 2>/dev/null)"
assertMatch "env beats config file" 'TISS_SSM_CACHE_DURATION *2h' \
  "$(TISS_SSM_CACHE_DURATION=2h "$TISS_BIN" self config list 2>/dev/null)"

# Config can now relocate TISS_DATA (the chicken-and-egg fix). The
# harness exports TISS_DATA (env beats config, by design), so unset it
# for this one invocation.
echo "cfg TISS_DATA $TISS_TEST_TMP/relocated" >>"$TISS_CONFIG/config.sh"
echo hi | env -u TISS_DATA "$TISS_BIN" saveData reloc-test 2>/dev/null
assertFileExists "TISS_DATA honored from config" "$TISS_TEST_TMP/relocated/reloc-test.gz"
sed -i.bak '$d' "$TISS_CONFIG/config.sh" && rm -f "$TISS_CONFIG/config.sh.bak"

# --- the enforcement rule ------------------------------------------------------
# Every TISS_* variable referenced in shipped code must be documented in
# the template (or be a known env-only/derived/internal name). Adding a
# new setting without documenting it fails this test — on purpose.
documented="$(grep '^# cfg ' "$template" | awk '{print $3}' | sort -u)"
env_only="TISS_HOME TISS_NAME TISS_CONFIG TISS_SCRIPTS TISS_LIB TISS_BIN_DIR TISS_CACHE_ENV_DEFAULT TISS_INSTALL_ALLOW_DEFAULT TISS_SHIMS_ON_PATH TISS_PILE_MARKER TISS_LEXICON"
referenced="$(grep -ohrE 'TISS_[A-Z_]+' "$TISS_TEST_ROOT/bin" "$TISS_TEST_ROOT/lib" "$TISS_TEST_ROOT/scripts" | sort -u)"
missing=""
for var in $referenced; do
  case " $env_only " in *" $var "*) continue ;; esac
  printf '%s\n' "$documented" | grep -qx "$var" || missing="$missing $var"
done
if [ -z "$missing" ]; then
  _report ok "every TISS_* var in code is documented in the template"
else
  _report FAIL "undocumented settings (add to etc/config.sh.example):$missing"
fi

# And the docs reference covers everything in the template.
docs="$TISS_TEST_ROOT/docs/configuration.md"
undoc=""
for var in $documented; do
  grep -q "$var" "$docs" || undoc="$undoc $var"
done
if [ -z "$undoc" ]; then
  _report ok "docs/configuration.md covers every template setting"
else
  _report FAIL "settings missing from docs/configuration.md:$undoc"
fi

finish
