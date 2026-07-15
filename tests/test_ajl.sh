#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal $ in inner shells is intentional
# Tests for the ajl wrapper: intent routing (reads cached, writes narrated,
# streams never cached) and the custom-install path in ensureTool.
. "$(dirname "$0")/harness.sh"

export TISS_CONFIG="$TISS_TEST_TMP/config"

# Custom install: ajl is outside mise/brew, ensureTool must point at the
# uv command. Direct function call with a bare PATH (no ajl anywhere).
rc=0
hint="$(TISS_AUTO_INSTALL=never PATH=/usr/bin:/bin ensureTool ajl 2>&1)" || rc=$?
assertEq "ensureTool ajl fails without install" 127 "$rc"
assertMatch "never-mode hint shows the custom command" 'uv tool install git\+https://github.com/mattyo161/ajl' "$hint"

# Fake ajl: logs every invocation, streams canned jsonl.
mkdir -p "$TISS_TEST_TMP/bin"
export AJL_SHIM_LOG="$TISS_TEST_TMP/ajl.log"
cat >"$TISS_TEST_TMP/bin/ajl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$AJL_SHIM_LOG"
printf '{"Type":"ec2:instance","Id":"i-1","Name":"one","Tags":{"Name":"one"}}\n'
printf '{"Type":"ec2:instance","Id":"i-2","Name":"two","Tags":{"Name":"two"}}\n'
EOF
chmod +x "$TISS_TEST_TMP/bin/ajl"
export PATH="$TISS_TEST_TMP/bin:$PATH"

# Reads stream jsonl and cache.
out="$("$TISS_BIN" ajl ec2 describe-instances 2>/dev/null)"
assertEq "read emits jsonl rows" 2 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assertEq "rows are jq-ready" "i-1" "$(printf '%s\n' "$out" | jq -rs '.[0].Id')"
out2="$("$TISS_BIN" ajl ec2 describe-instances 2>/dev/null)"
assertEq "second read served from cache" 1 "$(wc -l <"$AJL_SHIM_LOG" | tr -d ' ')"
assertEq "cached output identical" "$out" "$out2"
"$TISS_BIN" ajl s3 list-buckets >/dev/null 2>&1
assertEq "different argv is a different cache entry" 2 "$(wc -l <"$AJL_SHIM_LOG" | tr -d ' ')"
"$TISS_BIN" ajl ec2 describe-instances --recache >/dev/null 2>&1
assertEq "--recache scavenged through the handler" 3 "$(wc -l <"$AJL_SHIM_LOG" | tr -d ' ')"

# Streaming reads (--params-json) are never cached.
: >"$AJL_SHIM_LOG"
"$TISS_BIN" ajl s3 list-objects-v2 --params-json - </dev/null >/dev/null 2>&1
"$TISS_BIN" ajl s3 list-objects-v2 --params-json - </dev/null >/dev/null 2>&1
assertEq "params-json streams bypass the cache" 2 "$(wc -l <"$AJL_SHIM_LOG" | tr -d ' ')"

# Writes: never cached, narrated via LEARN.
: >"$AJL_SHIM_LOG"
"$TISS_BIN" ajl ssm put-parameter --name /x --value 1 >/dev/null 2>&1
"$TISS_BIN" ajl ssm put-parameter --name /x --value 1 >/dev/null 2>&1
assertEq "writes never cached" 2 "$(wc -l <"$AJL_SHIM_LOG" | tr -d ' ')"
learn="$("$TISS_BIN" ajl ssm put-parameter --name /x --value 1 2>&1 >/dev/null)"
assertMatch "writes narrated via LEARN" 'LEARN.*ajl ssm put-parameter' "$learn"

# A service with no operation passes through uncached (ajl errors usefully).
: >"$AJL_SHIM_LOG"
"$TISS_BIN" ajl ec2 >/dev/null 2>&1
"$TISS_BIN" ajl ec2 >/dev/null 2>&1
assertEq "bare service never cached" 2 "$(wc -l <"$AJL_SHIM_LOG" | tr -d ' ')"

# Namespace UX: bare landing shows help, handler owns the footer; the
# handler answers --help itself.
ns="$("$TISS_BIN" ajl)"
assertMatch "bare namespace shows help" 'usage: tiss ajl' "$ns"
assertMatch "handler described in help footer" 'Anything else: Any ajl call' "$ns"
assertMatch "handler answers --help" 'usage: tiss ajl <service> <operation>' "$("$TISS_BIN" ajl --help)"

finish
