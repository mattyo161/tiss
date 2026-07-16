#!/usr/bin/env bash
# @description Terraform plan: fmt + self-correcting init, icon summary, sweeps, offer to apply
# @usage tiss tf plan [-y|--auto-apply] [--no-apply] [--all] [--skip-fresh N] [-j N|auto] [dir ...] [-- tf args] [tf args...]
# @example tiss tf plan
# @example tiss tf plan -target=aws_instance.web -var-file=prod.tfvars
# @example tiss tf plan --all --no-apply --skip-fresh 24
# @example tiss tf plan --all -j auto
# @needs terraform jq
#
# The full ritual, ported from years of production use:
#   1. terraform fmt (narrated, non-fatal)
#   2. self-correcting init: expired AWS creds pause for a refresh;
#      backend-config changes rerun with -reconfigure automatically
#   3. plan with -detailed-exitcode into versioned artifacts under
#      .tiss/tfplans/ (.tfplan + .log + .json + run.json), auth-error retry
#   4. the icon summary: one line per change — column-select the addresses
#      and you have a -target list
#   5. offers to apply (y/N) — or -y/--auto-apply/TISS_TF_AUTO_APPLY=always;
#      --no-apply / =never stays hands-off
#
# Sweeps: --all discovers every root module under the cwd (a *.tf declaring
# a backend); dir arguments target specific modules; --skip-fresh N reuses
# plans newer than N hours. -j/--parallel N (or 'auto' = half the cores,
# max 8) plans concurrently: live per-worker status on a tty, a completion
# block per module with FULL counts, credential-expiry pause/re-queue, and
# a final summary table. Parallel sweeps are plan-only — apply afterwards.
#
# Flags terraform owns (-target, -destroy, -var-file, ...) pass through
# untouched; after a literal `--` EVERYTHING passes through.
#
set -o pipefail
source "$TISS_LIB/init.sh"
source "$(cd -P "$(dirname "$0")/../../lib" && pwd)/tf-parallel.sh"

cfg TISS_TF_AUTO_APPLY ask
cfg TISS_TF_PLAN_TTL 1d

apply_mode="$TISS_TF_AUTO_APPLY"
ALL=false
SKIP_FRESH_HOURS=0
JOBS=1
DIRS=()
TF_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help | help)
      tissHelp "$0"
      exit 0
      ;;
    -y | --auto-apply | --yes) apply_mode=always ;;
    --no-apply) apply_mode=never ;;
    --all) ALL=true ;;
    --skip-fresh)
      SKIP_FRESH_HOURS="${2:-}"
      shift
      case "$SKIP_FRESH_HOURS" in '' | *[!0-9]*)
        logError "--skip-fresh needs a number of hours"
        exit 2
        ;;
      esac
      ;;
    -j | --parallel)
      JOBS="${2:-}"
      shift
      case "$JOBS" in
        auto) JOBS="$(tfAutoJobs)" ;;
        '' | *[!0-9]*)
          logError "--parallel needs a number of workers or 'auto'"
          exit 2
          ;;
        0)
          logError "--parallel must be >= 1"
          exit 2
          ;;
      esac
      ;;
    --)
      shift
      TF_ARGS+=("$@")
      break
      ;;
    -*) TF_ARGS+=("$1") ;; # terraform's flags: -target, -destroy, -var-file...
    *) DIRS+=("$1") ;;
  esac
  shift
done

if git rev-parse --git-dir >/dev/null 2>&1; then
  if [ ! -f .gitignore ] || ! grep -q '^\.tiss/$' .gitignore 2>/dev/null; then
    logWarn "add '.tiss/' to .gitignore — plan artifacts can contain sensitive values"
  fi
fi

# ---- resolve target modules ---------------------------------------------------
MODULE_DIRS=()
if [ "$ALL" = true ]; then
  while IFS= read -r d; do
    [ -n "$d" ] && MODULE_DIRS+=("$d")
  done < <(tfDiscoverRootModules)
  if [ ${#MODULE_DIRS[@]} -eq 0 ]; then
    logError "no root modules found under $(pwd) (looking for *.tf with '${TISS_TF_MODULE_GREP:-backend \"}')"
    exit 1
  fi
  logInfo "discovered ${#MODULE_DIRS[@]} root module(s)"
elif [ ${#DIRS[@]} -gt 0 ]; then
  MODULE_DIRS=("${DIRS[@]}")
else
  MODULE_DIRS=(".")
fi

# planModule <dir> — the serial path: full narration, then the apply offer.
planModule() {
  local dir="$1" d_abs name run_ts base rc attempt counts prev_json
  d_abs="$(cd "$dir" 2>/dev/null && pwd)" || {
    logError "no such directory: $dir"
    return 1
  }
  name="$(basename "$d_abs")"
  tfBanner "tf plan — ${name}"

  if prev_json="$(tfFreshPlanJson "$d_abs")"; then
    logInfo "skipping ${name}: latest plan is fresher than ${SKIP_FRESH_HOURS}h"
    [ -n "$prev_json" ] && PLANNED_JSONS+=("$prev_json")
    return 0
  fi

  (
    cd "$d_abs" || exit 1
    learnExec terraform fmt || logWarn "terraform fmt reported issues (continuing)"
    tfInitModule || exit 1

    mkdir -p "$(tfPlansDir)"
    run_ts="$(ts)"
    base="$(tfPlansDir)/${name}.${run_ts}"

    attempt=0
    while :; do
      attempt=$((attempt + 1))
      printf '[LEARN] %s\n' "$(tissSanitizeCmd terraform plan -input=false -detailed-exitcode -out "${base}.tfplan" ${TF_ARGS[@]+"${TF_ARGS[@]}"})" >&2
      terraform plan -input=false -detailed-exitcode -no-color \
        -out "${base}.tfplan" ${TF_ARGS[@]+"${TF_ARGS[@]}"} 2>&1 | tee "${base}.tfplan.log"
      rc=${PIPESTATUS[0]}
      if [ "$rc" -eq 1 ] && [ "$attempt" -lt 3 ] && tfLooksLikeAuthError "$(cat "${base}.tfplan.log")"; then
        logWarn "terraform plan failed — AWS credentials look expired"
        tfEnsureAwsAuth || break
        continue
      fi
      break
    done

    if [ "$rc" -eq 1 ]; then
      tfWriteRunMeta "$name" "$run_ts" "$base" 1 'null' "tf plan ${TF_ARGS[*]+"${TF_ARGS[*]}"}"
      logError "terraform plan failed in ${name} (log: ${base}.tfplan.log)"
      exit 1
    fi

    terraform show -json "${base}.tfplan" >"${base}.tfplan.json" || {
      logError "terraform show -json failed in ${name}"
      exit 1
    }
    counts="$(tfPlanCounts "${base}.tfplan.json")"
    tfWriteRunMeta "$name" "$run_ts" "$base" "$rc" "$counts" "tf plan ${TF_ARGS[*]+"${TF_ARGS[*]}"}"
    [ "$TISS_TF_PLAN_TTL" != 0 ] && rmAfter "$TISS_TF_PLAN_TTL" "${base}.tfplan"

    echo
    tfSummary "${base}.tfplan.json"
    echo
    logInfo "artifacts: ${base}.{tfplan,tfplan.log,tfplan.json,run.json}"
    echo "$PWD/${base}.tfplan.json" >>"$PLANNED_LIST"

    if [ "$rc" -eq 2 ]; then
      case "$apply_mode" in
        never) logInfo "not applying (--no-apply) — later: $TISS_NAME tf apply ${dir}" ;;
        always) tfApplyRun "$(tfLatestMeta)" false true ;;
        *)
          if tfConfirm "Apply these changes to ${name} now?"; then
            tfApplyRun "$(tfLatestMeta)" false true
          else
            logInfo "not applying ${name} — review, then: $TISS_NAME tf apply ${dir}"
          fi
          ;;
      esac
    fi
  ) || return 1
}

tfEnsureAwsAuth || exit 1

PLANNED_JSONS=()
PLANNED_LIST="$(mktemp)"
overall_rc=0

if [ "$JOBS" -gt 1 ] && [ ${#MODULE_DIRS[@]} -gt 1 ]; then
  # ---- parallel sweep: plan-only, live status, per-module completion blocks
  if [ "$apply_mode" = always ]; then
    logWarn "parallel mode is plan-only — ignoring --auto-apply (apply afterwards with '$TISS_NAME tf apply')"
  fi
  QUEUE=()
  for d in "${MODULE_DIRS[@]}"; do
    d_abs="$(cd "$d" 2>/dev/null && pwd)" || {
      logError "no such directory: $d"
      overall_rc=1
      continue
    }
    if prev_json="$(tfFreshPlanJson "$d_abs")"; then
      logInfo "skipping $(basename "$d_abs"): latest plan is fresher than ${SKIP_FRESH_HOURS}h"
      [ -n "$prev_json" ] && PLANNED_JSONS+=("$prev_json")
      continue
    fi
    QUEUE+=("$d_abs")
  done
  if [ ${#QUEUE[@]} -gt 0 ]; then
    logInfo "planning ${#QUEUE[@]} module(s), ${JOBS} at a time (plan-only; apply with '$TISS_NAME tf apply')"
    tfParallelSweep "$JOBS" || overall_rc=1
    tfParallelSummaryTable
  fi
else
  for d in "${MODULE_DIRS[@]}"; do
    planModule "$d" || overall_rc=1
  done
  while IFS= read -r j; do
    [ -n "$j" ] && PLANNED_JSONS+=("$j")
  done <"$PLANNED_LIST"
fi
rm -f "$PLANNED_LIST"

# Sweeping several modules: point at the combined drift report.
if [ ${#PLANNED_JSONS[@]} -gt 1 ]; then
  logInfo "combined drift report: $TISS_NAME tf report --format diff${PLANNED_JSONS[*]+ }${PLANNED_JSONS[*]-}"
fi
exit "$overall_rc"
