#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the polyglot example scripts — each skips if its runtime is
# absent, so the suite stays green on minimal machines.
. "$(dirname "$0")/harness.sh"

# --- serve.py (python) ----------------------------------------------------------
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  www="$TISS_TEST_TMP/www"
  mkdir -p "$www"
  echo "hello from tiss serve" >"$www/index.html"
  port=$((20000 + RANDOM % 20000))
  "$TISS_BIN" serve --port "$port" --dir "$www" 2>/dev/null &
  serve_pid=$!
  sleep 1
  body="$(curl -s "http://127.0.0.1:$port/index.html" || true)"
  kill "$serve_pid" 2>/dev/null
  wait "$serve_pid" 2>/dev/null || true
  assertEq "serve.py serves the directory" "hello from tiss serve" "$body"
else
  echo "  skip: serve.py (python3/curl missing)" >&2
fi

# --- mkpass.rb (ruby) -------------------------------------------------------------
if command -v ruby >/dev/null 2>&1; then
  p1="$("$TISS_BIN" mkpass)"
  assertEq "mkpass default length" 24 "${#p1}"
  assertMatch "mkpass default is alnum" '^[A-Za-z0-9]+$' "$p1"
  assertEq "mkpass --len respected" 40 "$(v=$("$TISS_BIN" mkpass --len 40); echo ${#v})"
  assertEq "mkpass --count emits lines" 5 "$("$TISS_BIN" mkpass --count 5 | wc -l | tr -d ' ')"
  p2="$("$TISS_BIN" mkpass)"
  [ "$p1" != "$p2" ] && _report ok "mkpass is random" || _report FAIL "mkpass repeated itself"
  assertMatch "mkpass --hex" '^[0-9a-f]{16}$' "$("$TISS_BIN" mkpass --hex --len 16)"
else
  echo "  skip: mkpass.rb (ruby missing)" >&2
fi

# --- urlparse.js (node) -----------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  u="$("$TISS_BIN" urlparse "https://matt@api.example.com:8443/v1/items?limit=5&page=2#top")"
  assertEq "urlparse hostname" "api.example.com" "$(printf '%s' "$u" | jq -r .hostname)"
  assertEq "urlparse port is numeric" 8443 "$(printf '%s' "$u" | jq .port)"
  assertEq "urlparse unpacks query" 5 "$(printf '%s' "$u" | jq -r .query.limit)"
  assertEq "urlparse hash" "top" "$(printf '%s' "$u" | jq -r .hash)"
  assertEq "urlparse stdin mode" 2 "$(printf 'https://a.com/\nhttps://b.com/\n' | "$TISS_BIN" urlparse | wc -l | tr -d ' ')"
  assertExit "urlparse rejects garbage" 1 "$TISS_BIN" urlparse "not a url"
else
  echo "  skip: urlparse.js (node missing)" >&2
fi

# --- jwt.ts (typescript via node type stripping, node >= 23.6) ---------------------
node_major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
if [ -n "$node_major" ] && [ "$node_major" -ge 24 ]; then
  b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=\n'; }
  token="$(b64url '{"alg":"none"}').$(b64url '{"sub":"matt","exp":1783828800}')."
  out="$("$TISS_BIN" jwt "$token")"
  assertEq "jwt.ts decodes payload" "matt" "$(printf '%s' "$out" | jq -r .payload.sub)"
  assertEq "jwt.ts decodes header" "none" "$(printf '%s' "$out" | jq -r .header.alg)"
  assertEq "jwt.ts notes missing signature" false "$(printf '%s' "$out" | jq .signature_present)"
  assertExit "jwt.ts rejects non-jwt" 1 "$TISS_BIN" jwt "garbage"
else
  echo "  skip: jwt.ts (node >= 24 not available)" >&2
fi

# --- checkport.go (go run polyglot trick) ------------------------------------------
if command -v go >/dev/null 2>&1; then
  out="$("$TISS_BIN" checkport 127.0.0.1 1 --timeout 1 2>/dev/null || true)"
  assertEq "checkport reports closed port" false "$(printf '%s' "$out" | jq .open)"
  assertEq "checkport jsonl shape" 1 "$(printf '%s' "$out" | jq .port)"
  assertExit "checkport exit reflects closed" 1 "$TISS_BIN" checkport 127.0.0.1 1 --timeout 1
else
  echo "  skip: checkport.go (go missing)" >&2
fi

# All examples self-describe through their comment style (# or //).
assertMatch "js annotations parse" 'Break URLs' "$("$TISS_BIN" help urlparse)"
assertMatch "go annotations parse" 'TCP port' "$("$TISS_BIN" help checkport)"
assertMatch "manifest includes ts leaf" '"command":"jwt"' "$("$TISS_BIN" --manifest)"

finish
