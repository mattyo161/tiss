#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the tf wrapper set (ported from tools/tf), against shims.
. "$(dirname "$0")/harness.sh"

export TISS_RMAFTER_INTERVAL=60
export TISS_LOG_LEVEL=INFO # assertions read logInfo/logWarn output

# --- canned plan JSON covering every action class ---------------------------------
cat >"$TISS_TEST_TMP/plan.json" <<'JSON'
{"resource_changes":[
 {"address":"aws_instance.web","type":"aws_instance","name":"web","change":{"actions":["create"]}},
 {"address":"aws_s3_bucket.logs","type":"aws_s3_bucket","name":"logs","change":{"actions":["update"]}},
 {"address":"aws_iam_role.old","type":"aws_iam_role","name":"old","change":{"actions":["delete"]}},
 {"address":"aws_ecs_service.api","type":"aws_ecs_service","name":"api","change":{"actions":["delete","create"]}},
 {"address":"aws_db_instance.legacy","type":"aws_db_instance","name":"legacy","change":{"actions":["forget"]}},
 {"address":"aws_vpc.main","type":"aws_vpc","name":"main","change":{"actions":["no-op"],"importing":{"id":"vpc-123"}}},
 {"address":"module.net.aws_subnet.a","module_address":"module.net","type":"aws_subnet","name":"a","previous_address":"aws_subnet.a","change":{"actions":["no-op"]}},
 {"address":"aws_route53_zone.z","type":"aws_route53_zone","name":"z","change":{"actions":["no-op"]}}
]}
JSON

# --- terraform + aws shims ---------------------------------------------------------
mkdir -p "$TISS_TEST_TMP/bin"
export TF_SHIM_JSON="$TISS_TEST_TMP/plan.json"
cat >"$TISS_TEST_TMP/bin/terraform" <<'EOF'
#!/usr/bin/env bash
cmd="${1:-}"; shift || true
case "$cmd" in
  fmt) echo "shim-fmt" ;;
  init)
    if [ -f .fail-init-backend-once ]; then
      rm -f .fail-init-backend-once
      echo "Error: Backend configuration changed"
      exit 1
    fi
    echo "shim-init: $*"
    ;;
  plan)
    out=""
    while [ $# -gt 0 ]; do
      case "$1" in -out) out="$2"; shift ;; esac
      shift
    done
    [ -n "$out" ] && echo "shim-plan" >"$out"
    echo "shim plan output"
    [ -n "${TF_SHIM_NOCHANGES:-}" ] && exit 0
    exit 2
    ;;
  show)
    if [ -n "${TF_SHIM_NOCHANGES:-}" ]; then
      echo '{"resource_changes":[]}'
    else
      cat "$TF_SHIM_JSON"
    fi
    ;;
  apply)
    f=""
    for a in "$@"; do case "$a" in -*) ;; *) f="$a" ;; esac; done
    [ -f "$f" ] || { echo "shim: no plan file"; exit 1; }
    [ -n "${TF_SHIM_APPLY_STALE:-}" ] && { echo "Error: saved plan is stale"; exit 1; }
    echo "shim-applied: $f"
    ;;
  version) echo '{"terraform_version":"1.9.0-shim"}' ;;
  *) echo "terraform-shim: $cmd $*" ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "{\\"Arn\\":\\"arn:aws:iam::1:user/shim\\"}"\n' >"$TISS_TEST_TMP/bin/aws"
chmod +x "$TISS_TEST_TMP/bin/terraform" "$TISS_TEST_TMP/bin/aws"
export PATH="$TISS_TEST_TMP/bin:$PATH"

work="$TISS_TEST_TMP/infra"
mkdir -p "$work"
cd "$work" || exit 1

# --- classifiers (unit) --------------------------------------------------------------
tfLooksLikeAuthError "blah ExpiredToken blah" && _report ok "auth classifier hits" || _report FAIL "auth classifier missed"
tfLooksLikeBackendChange "Backend configuration changed" && _report ok "backend classifier hits" || _report FAIL "backend classifier missed"
tfLooksLikeAuthError "some random error" && _report FAIL "auth classifier false positive" || _report ok "auth classifier clean"

# --- plan: artifacts, icons, counts, no-tty prompt path ------------------------------
out="$("$TISS_BIN" tf plan 2>&1)"
assertMatch "fmt narrated" 'LEARN.*terraform fmt' "$out"
assertMatch "init narrated" 'LEARN.*terraform init -input=false' "$out"
assertMatch "aws auth checked" 'AWS credentials OK' "$out"
assertMatch "counts line" 'Plan: 1 to create, 1 to update, 1 to destroy, 1 to replace, 1 to import, 1 to forget \(removed from state only\)  \(\+1 moved\)' "$out"
assertMatch "create icon" '✚ aws_instance.web' "$out"
assertMatch "update icon" '✎ aws_s3_bucket.logs' "$out"
assertMatch "delete icon" '✘ aws_iam_role.old' "$out"
assertMatch "replace icon" '⟳ aws_ecs_service.api' "$out"
assertMatch "forget icon" '⊘ aws_db_instance.legacy' "$out"
assertMatch "import icon with id" '↧ aws_vpc.main  \(id: vpc-123\)' "$out"
assertMatch "moved icon with was" '➜ module.net.aws_subnet.a  \(was aws_subnet.a\)' "$out"
assertMatch "no-tty ask leaves plan for later" 'tf apply' "$out"
assertEq "artifact set complete" 4 "$(ls .tiss/tfplans/infra.* | wc -l | tr -d ' ')"
assertFileExists "latest.json written" ".tiss/tfplans/latest.json"
assertEq "meta has changes" true "$(jq .has_changes .tiss/tfplans/latest.json)"
assertEq "meta counts" 1 "$(jq .summary.replace .tiss/tfplans/latest.json)"

# --- apply: same summary, prompt behavior, records applied_at ------------------------
out="$("$TISS_BIN" tf apply 2>&1)"
assertMatch "apply shows the icon summary" '✚ aws_instance.web' "$out"
assertMatch "apply shows plan age" 'created:.*ago' "$out"
assertMatch "no-tty ask does not apply" 'not applying' "$out"
out="$("$TISS_BIN" tf apply --yes 2>&1)"
assertMatch "apply --yes applies the saved plan" 'shim-applied' "$out"
assertMatch "apply narrated" 'LEARN.*terraform apply -input=false' "$out"
assertEq "applied_at recorded" 0 "$(jq '.applied_at | length == 0' .tiss/tfplans/latest.json | grep -c true || true)"
out="$("$TISS_BIN" tf apply --yes 2>&1)"
assertMatch "re-apply warns already applied" 'already applied' "$out"

# --- stale + missing plan file --------------------------------------------------------
TF_SHIM_APPLY_STALE=1 "$TISS_BIN" tf plan --no-apply >/dev/null 2>&1
out="$(TF_SHIM_APPLY_STALE=1 "$TISS_BIN" tf apply --yes 2>&1 || true)"
assertMatch "stale plan detected" 'saved plan is stale' "$out"
rm -f .tiss/tfplans/*.tfplan
out="$("$TISS_BIN" tf apply --yes 2>&1 || true)"
assertMatch "missing plan file guided" 're-run' "$out"

# --- auto-apply + no-changes ----------------------------------------------------------
out="$(TISS_TF_AUTO_APPLY=always "$TISS_BIN" tf plan 2>&1)"
assertMatch "TISS_TF_AUTO_APPLY=always applies" 'shim-applied' "$out"
out="$(TF_SHIM_NOCHANGES=1 "$TISS_BIN" tf plan 2>&1)"
assertMatch "no changes reported" 'No changes' "$out"
assertEq "no-changes meta exit 0" 0 "$(jq .exit_code .tiss/tfplans/latest.json)"

# --- backend self-correction -----------------------------------------------------------
touch .fail-init-backend-once
out="$("$TISS_BIN" tf plan --no-apply 2>&1)"
assertMatch "backend change auto-reconfigures" 'reconfigure' "$out"
assertMatch "plan proceeds after reconfigure" 'Plan: 1 to create' "$out"

# --- report formats ---------------------------------------------------------------------
"$TISS_BIN" tf plan --no-apply >/dev/null 2>&1
assertMatch "report list (default)" '✚ aws_instance.web' "$("$TISS_BIN" tf report 2>/dev/null)"
targets="$("$TISS_BIN" tf report --format target 2>/dev/null)"
assertEq "target lines quoted" "-target='aws_instance.web'" "$(printf '%s\n' "$targets" | head -1)"
assertEq "target count" 7 "$(printf '%s\n' "$targets" | wc -l | tr -d ' ')"
assertEq "jsonl parses" 7 "$("$TISS_BIN" tf report --format jsonl 2>/dev/null | jq -s length)"
if command -v mlr >/dev/null 2>&1; then
  assertMatch "md is a pipe table" '\| action \| address \|' "$("$TISS_BIN" tf report --format md 2>/dev/null)"
  assertMatch "csv has header" '^action,' "$("$TISS_BIN" tf report --format csv 2>/dev/null | head -1)"
fi
tree_out="$("$TISS_BIN" tf report --format tree 2>/dev/null)"
assertMatch "tree nests modules" 'module' "$tree_out"
assertMatch "tree icons at leaves" '✚ web' "$tree_out"
assertExit "unknown format errors" 2 "$TISS_BIN" tf report --format bogus

# cleanup any rmAfter monitor
mpid="$(cat "$TISS_STATE/rmAfter/.monitor.pid" 2>/dev/null)" && kill "$mpid" 2>/dev/null
finish
