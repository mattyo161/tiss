#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the ssm wrapper (the cookbook example) + routing UX fixes:
# near-miss detection, help-as-positional, multi-word aliases.
. "$(dirname "$0")/harness.sh"

# Fake aws: logs every invocation, returns canned SSM JSON.
mkdir -p "$TISS_TEST_TMP/bin"
export AWS_SHIM_LOG="$TISS_TEST_TMP/aws.log"
cat >"$TISS_TEST_TMP/bin/aws" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$AWS_SHIM_LOG"
case "$*" in
  *get-parameters-by-path*)
    printf '{"Parameters":[{"Name":"/develop/a","Value":"1"},{"Name":"/develop/b","Value":"2"}]}\n' ;;
  *get-parameters\ *)
    printf '{"Parameters":[{"Name":"/x","Value":"8"},{"Name":"/y","Value":"9"}]}\n' ;;
  *get-parameter\ *)
    printf '{"Parameter":{"Name":"/solo","Value":"42"}}\n' ;;
  *)
    echo "aws-shim: $*" ;;
esac
EOF
chmod +x "$TISS_TEST_TMP/bin/aws"
export PATH="$TISS_TEST_TMP/bin:$PATH"

ssm() { "$TISS_BIN" ssm get --no-encrypt "$@"; } # no age identity in tests

# --path: jsonl rows, decryption on by default.
out="$(ssm --path /develop 2>/dev/null)"
assertEq "path mode emits jsonl rows" 2 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assertEq "rows are jq-ready" "/develop/a" "$(printf '%s\n' "$out" | jq -rs '.[0].Name')"
assertMatch "decryption on by default" 'with-decryption' "$(cat "$AWS_SHIM_LOG")"

# caching: same call again does NOT hit aws.
calls_before="$(wc -l <"$AWS_SHIM_LOG" | tr -d ' ')"
ssm --path /develop >/dev/null 2>&1
assertEq "second call served from cache" "$calls_before" "$(wc -l <"$AWS_SHIM_LOG" | tr -d ' ')"

# --refresh forces a real call.
ssm --path /develop --refresh >/dev/null 2>&1
assertEq "--refresh hits aws again" $((calls_before + 1)) "$(wc -l <"$AWS_SHIM_LOG" | tr -d ' ')"

# --name unwraps the single-parameter shape.
assertEq "name mode unwraps .Parameter" 42 "$(ssm --name /solo 2>/dev/null | jq -r .Value)"

# --names splits commas; flags in any order.
out="$(ssm --duration 1d --names /x,/y 2>/dev/null)"
assertEq "names mode emits both" 2 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assertMatch "comma list split into args" 'get-parameters --names /x /y' "$(cat "$AWS_SHIM_LOG")"

# --no-decryption + passthrough of unknown args.
: >"$AWS_SHIM_LOG"
ssm --path /p --no-decryption --no-cache --max-results 5 >/dev/null 2>&1
assertMatch "unknown args pass through to aws" 'max-results 5' "$(cat "$AWS_SHIM_LOG")"
grep -q 'with-decryption' "$AWS_SHIM_LOG" && _report FAIL "--no-decryption ignored" || _report ok "--no-decryption respected"

# mode is required.
assertExit "missing mode errors" 2 "$TISS_BIN" ssm get --no-encrypt

# help as a positional, both forms.
assertMatch "trailing help works" 'usage: tiss ssm get' "$("$TISS_BIN" ssm get help)"
assertMatch "tiss help <cmd> works" 'usage: tiss ssm get' "$("$TISS_BIN" help ssm get)"
assertMatch "tiss help <namespace> works" 'usage: tiss git' "$("$TISS_BIN" help git)"
assertExit "tiss help unknown errors" 2 "$TISS_BIN" help no-such-thing

# namespace handler (_self): reads cached, writes narrated, never cached.
export TISS_SSM_CACHE_ENCRYPT=0 # no age identity in tests
: >"$AWS_SHIM_LOG"
o1="$("$TISS_BIN" ssm describe-parameters 2>/dev/null)"
o2="$("$TISS_BIN" ssm describe-parameters 2>/dev/null)"
assertEq "_self caches read verbs" 1 "$(wc -l <"$AWS_SHIM_LOG" | tr -d ' ')"
assertEq "_self cached output identical" "$o1" "$o2"
"$TISS_BIN" ssm put-parameter --name /x --value 1 >/dev/null 2>&1
"$TISS_BIN" ssm put-parameter --name /x --value 1 >/dev/null 2>&1
assertEq "_self never caches writes" 3 "$(wc -l <"$AWS_SHIM_LOG" | tr -d ' ')"
learn="$("$TISS_BIN" ssm put-parameter --name /x --value 1 2>&1 >/dev/null)"
assertMatch "_self narrates writes via LEARN" 'LEARN.*aws ssm put-parameter' "$learn"
assertMatch "get.sh still beats the handler" 'usage: tiss ssm get' "$("$TISS_BIN" ssm get help)"
ns_help="$("$TISS_BIN" ssm)"
assertMatch "bare namespace still shows help" 'usage: tiss ssm' "$ns_help"
assertMatch "handler described in help footer" 'Anything else: Any aws ssm subcommand' "$ns_help"
comp="$("$TISS_BIN" --complete ssm)"
assertEq "completion hides _self" "get" "$comp"

# near-miss: a would-match file that isn't executable fails loudly...
tree="$TISS_TEST_TMP/overlay"
mkdir -p "$tree/scripts"
echo '#!/usr/bin/env bash' >"$tree/scripts/mything.sh" # NOT chmod +x
assertExit "non-executable near-miss exits 126" 126 env TISS_PATH="$tree" "$TISS_BIN" mything
assertMatch "near-miss says how to fix" 'chmod \+x' \
  "$(TISS_PATH="$tree" "$TISS_BIN" mything 2>&1 || true)"
# ...and only warns when a real binary also exists.
echo '#!/usr/bin/env bash' >"$tree/scripts/aws.sh" # NOT executable; aws shim exists
warn="$(TISS_LOG_LEVEL=WARN TISS_PATH="$tree" "$TISS_BIN" aws sts get-caller-identity 2>&1 >/dev/null || true)"
assertMatch "near-miss with real binary warns but proceeds" 'not executable' "$warn"

finish
