#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the tf wrapper set, against a fake terraform shim.
. "$(dirname "$0")/harness.sh"

# Fake terraform: writes plan files, applies only real plan paths.
mkdir -p "$TISS_TEST_TMP/bin"
cat >"$TISS_TEST_TMP/bin/terraform" <<'EOF'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
case "$cmd" in
  plan)
    out=""
    while [ $# -gt 0 ]; do
      case "$1" in -out)
        out="$2"
        shift
        ;;
      esac
      shift
    done
    [ -n "$out" ] && echo "fake-plan-content" >"$out"
    echo "Plan: 1 to add, 0 to change, 0 to destroy."
    ;;
  apply)
    [ -f "${1:-}" ] || {
      echo "shim: apply needs a plan file" >&2
      exit 1
    }
    echo "Applied from: $1"
    ;;
  *)
    echo "terraform-shim: $cmd $*"
    ;;
esac
EOF
chmod +x "$TISS_TEST_TMP/bin/terraform"
export PATH="$TISS_TEST_TMP/bin:$PATH"
export TISS_RMAFTER_INTERVAL=60

work="$TISS_TEST_TMP/infra"
mkdir -p "$work"
cd "$work" || exit 1

# apply refuses without a plan.
assertExit "apply without plan refuses" 2 "$TISS_BIN" tf apply
assertMatch "refusal explains the discipline" 'no plan file' \
  "$("$TISS_BIN" tf apply 2>&1 || true)"

# plan writes a timestamped plan file and schedules self-destruction.
out="$("$TISS_BIN" tf plan 2>&1)"
assertMatch "plan narrates via LEARN" 'LEARN.*terraform plan -out' "$out"
plan_count="$(ls .tiss/tf-*.plan 2>/dev/null | wc -l | tr -d ' ')"
assertEq "plan file created" 1 "$plan_count"
sched="$(find "$TISS_STATE/rmAfter" -type l 2>/dev/null | wc -l | tr -d ' ')"
assertEq "plan file scheduled for self-destruct" 1 "$sched"

# apply consumes the newest plan.
sleep 1
"$TISS_BIN" tf plan >/dev/null 2>&1 # a second, newer plan
newest="$(ls -t .tiss/tf-*.plan | head -1)"
out="$("$TISS_BIN" tf apply 2>&1)"
assertMatch "apply used the newest plan" "Applied from: $newest" "$out"
assertFileMissing "applied plan consumed" "$newest"

# apply takes no arguments.
assertExit "apply rejects arguments" 2 "$TISS_BIN" tf apply -auto-approve

# passthrough alias: tiss tf <anything else> runs terraform.
assertMatch "tf passthrough hits terraform" 'terraform-shim: init' \
  "$("$TISS_BIN" tf init 2>/dev/null)"

# cleanup: stop any rmAfter monitor from this test.
mpid="$(cat "$TISS_STATE/rmAfter/.monitor.pid" 2>/dev/null)" && kill "$mpid" 2>/dev/null
finish
