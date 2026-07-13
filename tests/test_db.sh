#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the db wrapper set. A fake mysql shim proves the plumbing —
# including the <(readData ...) creds path — without a real database.
# --plain storage keeps the tests non-interactive (no age passphrase).
. "$(dirname "$0")/harness.sh"

if ! command -v mlr >/dev/null 2>&1; then
  echo "$(basename "$0"): skipped (mlr not installed)"
  rm -rf "$TISS_TEST_TMP"
  exit 0
fi

# Fake mysql: proves it received the defaults file + query, emits TSV.
mkdir -p "$TISS_TEST_TMP/bin"
cat >"$TISS_TEST_TMP/bin/mysql" <<'EOF'
#!/usr/bin/env bash
df=""
for a in "$@"; do
  case "$a" in --defaults-extra-file=*) df="${a#*=}" ;; esac
done
echo "shim-host=$(grep '^host=' "$df" | cut -d= -f2)" >&2
printf 'id\tname\n1\twidget\n2\tgadget\n'
EOF
chmod +x "$TISS_TEST_TMP/bin/mysql"
export PATH="$TISS_TEST_TMP/bin:$PATH"

# add --stdin --plain (non-interactive path).
printf '[client]\nhost=db.internal\nport=3306\nuser=t\npassword=secret\n' |
  "$TISS_BIN" db add widgets --plain --stdin 2>/dev/null
assertFileExists "plain connection stored" "$TISS_DATA/db/widgets"
assertMatch "stored as defaults-file ini" '\[client\]' "$(cat "$TISS_DATA/db/widgets")"

# list shows it, flagged as plain.
assertMatch "list shows connection" 'widgets.*PLAIN' "$("$TISS_BIN" db list 2>/dev/null)"

# connect: creds reach mysql through process substitution.
err="$("$TISS_BIN" db connect widgets 2>&1 >/dev/null)"
assertMatch "connect feeds creds via process substitution" 'shim-host=db.internal' "$err"

# query: TSV from mysql becomes jsonl.
out="$("$TISS_BIN" db query widgets "select id, name from things" 2>/dev/null)"
assertEq "query emits jsonl rows" 2 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assertEq "query jsonl is typed" 1 "$(printf '%s\n' "$out" | jq -s '.[0].id')"
assertEq "query jsonl values" "gadget" "$(printf '%s\n' "$out" | jq -rs '.[1].name')"

# query --raw passes TSV through.
raw="$("$TISS_BIN" db query widgets "select 1" --raw 2>/dev/null)"
assertMatch "raw keeps TSV header" "id$(printf '\t')name" "$raw"

# guards + remove.
assertExit "query without sql errors" 2 "$TISS_BIN" db query widgets
assertExit "add without name errors" 2 bash -c "printf x | \"$TISS_BIN\" db add --stdin --plain"
"$TISS_BIN" db remove widgets >/dev/null 2>&1
assertFileMissing "remove deletes connection" "$TISS_DATA/db/widgets"
assertExit "remove unknown errors" 2 "$TISS_BIN" db remove widgets

finish
