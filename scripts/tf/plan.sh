#!/usr/bin/env bash
# @description Terraform plan: fmt + self-correcting init, icon summary, offer to apply
# @usage tiss tf plan [-y|--auto-apply] [--no-apply] [terraform plan args...]
# @example tiss tf plan
# @example tiss tf plan -target=aws_instance.web -var-file=prod.tfvars
# @example tiss tf plan -destroy
# @needs terraform jq
#
# The full ritual, ported from years of production use:
#   1. terraform fmt (narrated, non-fatal)
#   2. self-correcting init: expired AWS creds pause for a refresh;
#      backend-config changes rerun with -reconfigure automatically
#   3. plan with -detailed-exitcode into versioned artifacts under
#      .tiss/tfplans/ (.tfplan + .log + .json + run.json), auth-error retry
#   4. the icon summary: one line per change, column-select the addresses
#      and you have a -target list (✚ create ✎ update ✘ delete ⟳ replace
#      ⊘ forget ↧ import ➜ moved)
#   5. offers to apply (y/N) — or applies automatically with -y/--auto-apply
#      or TISS_TF_AUTO_APPLY=always; --no-apply / =never stays hands-off
# Everything unrecognized passes straight to terraform plan, so -target,
# -destroy, -var-file all work. Plans self-destruct per TISS_TF_PLAN_TTL.
#
set -uo pipefail
source "$TISS_LIB/init.sh"

cfg TISS_TF_AUTO_APPLY ask
cfg TISS_TF_PLAN_TTL 1d

apply_mode="$TISS_TF_AUTO_APPLY"
tf_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    -y | --auto-apply | --yes) apply_mode=always ;;
    --no-apply) apply_mode=never ;;
    *) tf_args+=("$1") ;; # terraform's args: -target, -destroy, -var-file...
  esac
  shift
done

if git rev-parse --git-dir >/dev/null 2>&1; then
  if [ ! -f .gitignore ] || ! grep -q '^\.tiss/$' .gitignore 2>/dev/null; then
    logWarn "add '.tiss/' to .gitignore — plan artifacts can contain sensitive values"
  fi
fi

learnExec terraform fmt || logWarn "terraform fmt reported issues (continuing)"
tfEnsureAwsAuth || exit 1
tfInitModule || exit 1

mkdir -p "$(tfPlansDir)"
name="$(basename "$PWD")"
run_ts="$(ts)"
base="$(tfPlansDir)/${name}.${run_ts}"

# -detailed-exitcode: 0 = no changes, 1 = error, 2 = changes present.
attempt=0
while :; do
  attempt=$((attempt + 1))
  printf '[LEARN] %s\n' "$(tissSanitizeCmd terraform plan -input=false -detailed-exitcode -out "${base}.tfplan" ${tf_args[@]+"${tf_args[@]}"})" >&2
  terraform plan -input=false -detailed-exitcode -no-color \
    -out "${base}.tfplan" ${tf_args[@]+"${tf_args[@]}"} 2>&1 | tee "${base}.tfplan.log"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -eq 1 ] && [ "$attempt" -lt 3 ] && tfLooksLikeAuthError "$(cat "${base}.tfplan.log")"; then
    logWarn "terraform plan failed — AWS credentials look expired"
    tfEnsureAwsAuth || break
    continue
  fi
  break
done

if [ "$rc" -eq 1 ]; then
  tfWriteRunMeta "$name" "$run_ts" "$base" 1 'null' "tf plan $*"
  logError "terraform plan failed in ${name} (log: ${base}.tfplan.log)"
  exit 1
fi

terraform show -json "${base}.tfplan" >"${base}.tfplan.json" || {
  logError "terraform show -json failed in ${name}"
  exit 1
}
counts="$(tfPlanCounts "${base}.tfplan.json")"
tfWriteRunMeta "$name" "$run_ts" "$base" "$rc" "$counts" "tf plan ${tf_args[*]+"${tf_args[*]}"}"

# Plans go stale; the binary self-destructs (json/log/meta stay for reports).
[ "$TISS_TF_PLAN_TTL" != 0 ] && rmAfter "$TISS_TF_PLAN_TTL" "${base}.tfplan"

echo
tfSummary "${base}.tfplan.json"
echo
logInfo "artifacts: ${base}.{tfplan,tfplan.log,tfplan.json,run.json}"

if [ "$rc" -eq 2 ]; then
  case "$apply_mode" in
    never) logInfo "not applying (--no-apply) — later: $TISS_NAME tf apply" ;;
    always) tfApplyRun "$(tfLatestMeta)" false true ;;
    *)
      if tfConfirm "Apply these changes to ${name} now?"; then
        tfApplyRun "$(tfLatestMeta)" false true
      else
        logInfo "not applying — review, then: $TISS_NAME tf apply"
      fi
      ;;
  esac
fi
