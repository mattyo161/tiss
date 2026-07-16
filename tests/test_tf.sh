#!/usr/bin/env bash
# shellcheck disable=SC2012,SC2015,SC2016  # intentional test idioms: ls-count, A&&B||C with safe B, literal $ in inner shells
# Tests for the tf wrapper set (ported from tools/tf), against shims.
TREE_ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
. "${TISS_HOME:?run via tiss test}/tests/harness.sh"
export TISS_PATH="$TREE_ROOT" # this tree must be on the pile for routing
. "$TREE_ROOT/lib/init.sh"     # tree helpers, for direct lib assertions

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
    if [ -f .tf-shim-fail-plan ]; then
      echo "shim-boom: plan exploded"
      exit 1
    fi
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

# ============ sweeps, parallel, deep-diff (ported from tools/tf) ============

# A little estate: two root modules and one non-module dir.
estate="$TISS_TEST_TMP/estate"
mkdir -p "$estate/mod-a" "$estate/mod-b" "$estate/not-a-module"
printf 'terraform {\n  backend "s3" {}\n}\n' >"$estate/mod-a/main.tf"
printf 'terraform {\n  backend "s3" {}\n}\n' >"$estate/mod-b/main.tf"
echo "just a readme" >"$estate/not-a-module/notes.txt"
cd "$estate" || exit 1

# --all discovery + serial sweep.
out="$("$TISS_BIN" tf plan --all --no-apply 2>&1)"
assertMatch "--all discovers modules" 'discovered 2 root module' "$out"
assertFileExists "sweep planned mod-a" "$estate/mod-a/.tiss/tfplans/latest.json"
assertFileExists "sweep planned mod-b" "$estate/mod-b/.tiss/tfplans/latest.json"
assertMatch "sweep suggests combined report" 'report --format diff' "$out"

# --skip-fresh reuses recent plans.
out="$("$TISS_BIN" tf plan --all --no-apply --skip-fresh 24 2>&1)"
assertMatch "skip-fresh skips mod-a" 'skipping mod-a' "$out"
assertMatch "skip-fresh skips mod-b" 'skipping mod-b' "$out"

# Parallel sweep: event lines (no tty), completion blocks, summary table.
rm -rf "$estate"/mod-{a,b}/.tiss
out="$("$TISS_BIN" tf plan --all --no-apply -j 2 2>&1)"
assertMatch "parallel announces" 'planning 2 module\(s\), 2 at a time' "$out"
assertMatch "parallel event lines" '> mod-a: started' "$out"
assertMatch "parallel completion block" '✔ mod-a' "$out"
assertMatch "parallel full counts show zeros" 'import 1 · forget 1 · move 1' "$out"
assertMatch "parallel summary table" 'module +result +create' "$out"
assertMatch "parallel rows" 'mod-b +changes' "$out"
assertFileExists "parallel wrote artifacts" "$estate/mod-a/.tiss/tfplans/latest.json"

# Parallel ignores --auto-apply (plan-only by design).
rm -rf "$estate"/mod-{a,b}/.tiss
out="$(TISS_TF_AUTO_APPLY=always "$TISS_BIN" tf plan --all -j 2 2>&1)"
assertMatch "parallel refuses auto-apply" 'plan-only' "$out"
grep -q 'shim-applied' <<<"$out" && _report FAIL "parallel applied!" || _report ok "parallel did not apply"

# Worker failure surfaces as ✖ + failed row, exit nonzero.
mkdir -p "$estate/mod-c" && printf 'terraform {\n  backend "s3" {}\n}\n' >"$estate/mod-c/main.tf"
touch "$estate/mod-c/.tf-shim-fail-plan"
rc=0
out="$("$TISS_BIN" tf plan --all --no-apply -j 2 2>&1)" || rc=$?
assertEq "sweep with failure exits nonzero" 1 "$rc"
assertMatch "failure block" '✖ mod-c' "$out"
assertMatch "failure tail shown" 'shim-boom' "$out"
assertMatch "failed summary row" 'mod-c +failed' "$out"
rm -rf "$estate/mod-c"

# apply --all applies each module's saved plan.
out="$("$TISS_BIN" tf apply --all --yes 2>&1)"
assertEq "apply --all applies both" 2 "$(grep -c 'shim-applied' <<<"$out")"

# Dir arguments (serial multi-module).
rm -rf "$estate"/mod-{a,b}/.tiss
out="$("$TISS_BIN" tf plan mod-a mod-b --no-apply 2>&1)"
assertEq "dir args plan both" 2 "$(grep -c 'tf plan — mod-' <<<"$out")"

# `--` passthrough reaches terraform.
out="$("$TISS_BIN" tf plan mod-a --no-apply -- -var-file=x.tfvars 2>&1)"
assertMatch "post -- args reach terraform" 'LEARN.*-var-file=x.tfvars' "$out"

# ---- deep-diff report -----------------------------------------------------------
cat >"$TISS_TEST_TMP/diffplan.json" <<'JSON'
{"resource_changes":[
 {"address":"module.svc.aws_ecs_service.api","module_address":"module.svc","type":"aws_ecs_service","name":"api",
  "change":{"actions":["update"],
    "before":{"desired_count":2,"container_definitions":"[{\"name\":\"app\",\"cpu\":256}]","tags":{"env":"prod"}},
    "after":{"desired_count":4,"container_definitions":"[{\"name\":\"app\",\"cpu\":512}]","tags":{"env":"prod"}},
    "after_unknown":{}}},
 {"address":"aws_instance.web","type":"aws_instance","name":"web",
  "change":{"actions":["delete","create"],"replace_paths":[["ami"]],
    "before":{"ami":"ami-old","instance_type":"t3.micro","arn":"arn:aws:ec2:old"},
    "after":{"ami":"ami-new","instance_type":"t3.micro"},
    "after_unknown":{"arn":true}}},
 {"address":"aws_s3_bucket.gone","type":"aws_s3_bucket","name":"gone","change":{"actions":["forget"],"before":{},"after":null}},
 {"address":"aws_vpc.adopted","type":"aws_vpc","name":"adopted","change":{"actions":["no-op"],"importing":{"id":"vpc-9"},"before":{},"after":{}}},
 {"address":"aws_subnet.b","type":"aws_subnet","name":"b","previous_address":"aws_subnet.a","change":{"actions":["no-op"],"before":{},"after":{}}}
]}
JSON
diffout="$("$TISS_BIN" tf report --format diff "$TISS_TEST_TMP/diffplan.json" 2>/dev/null)"
assertMatch "diff title from stem" '## diffplan' "$diffout"
assertMatch "diff counts line" '_2 change\(s\), 1 import\(s\), 1 removed, 1 move\(s\)_' "$diffout"
assertMatch "diff module details" '<summary>📦 <code>module.svc</code></summary>' "$diffout"
assertMatch "diff update badge" '🟡 update' "$diffout"
assertMatch "diff replace badge" '♻️ replace' "$diffout"
assertMatch "diff fence old line" '^- desired_count += 2' "$diffout"
assertMatch "diff fence new line" '^\+ desired_count += 4' "$diffout"
assertMatch "diff decodes embedded json" 'container_definitions.app.' "$diffout"
assertMatch "diff forces replacement flag" 'ami.*# forces replacement' "$diffout"
assertMatch "diff known-after-apply" '\(known after apply\)' "$diffout"
assertMatch "diff import section" '📥 1 imported' "$diffout"
assertMatch "diff removed section" '🗑️ 1 removed from state' "$diffout"
assertMatch "diff moved section" '↪️ 1 moved' "$diffout"

# cleanup any rmAfter monitor from sweep workers
mpid="$(cat "$TISS_STATE/rmAfter/.monitor.pid" 2>/dev/null)" && kill "$mpid" 2>/dev/null
finish
