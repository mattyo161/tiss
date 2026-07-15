# shellcheck shell=bash
#
# tiss terraform helpers — the engine behind tf plan / tf apply / tf report.
# Ported from Matt's battle-tested tools/tf (lib/common.sh), tiss-ified:
# versioned artifacts live under .tiss/tfplans/, prompts honor
# TISS_TF_AUTO_APPLY, and the plan summary uses single-width ICONS so an
# editor column-selection over the address column yields a -target list.
#
#   ✚ create   ✎ update   ✘ delete   ⟳ replace   ⊘ forget   ↧ import   ➜ moved
#
# Artifacts per plan run (base = .tiss/tfplans/<module>.<ts>):
#   <base>.tfplan        the plan itself (self-destructs per TISS_TF_PLAN_TTL)
#   <base>.tfplan.log    full terraform plan output
#   <base>.tfplan.json   terraform show -json (reports read this, never re-plan)
#   <base>.run.json      metadata: argv, profile, exit code, counts, applied_at
#   .tiss/tfplans/latest.json   copy of the newest run.json
#
tfPlansDir() { echo ".tiss/tfplans"; }
tfLatestMeta() { echo "$(tfPlansDir)/latest.json"; }

# ---- failure classifiers (verbatim from the original) -------------------------
tfLooksLikeAuthError() {
  grep -qiE 'ExpiredToken|token .*(is |has )?expired|InvalidClientTokenId|no valid credential|failed to refresh cached|SSO session|credentials.* expired|InvalidGrantException|AuthFailure' <<<"$1"
}
tfLooksLikeBackendChange() {
  grep -qiE 'Backend configuration changed|Backend initialization required|terraform init -reconfigure' <<<"$1"
}

# ---- prompts -------------------------------------------------------------------
tfConfirm() { # tfConfirm <question> -> 0 on yes; honors TISS_TF_AUTO_APPLY
  local q="$1" ans
  case "${TISS_TF_AUTO_APPLY:-ask}" in
    always)
      logInfo "$q — auto-approved (TISS_TF_AUTO_APPLY=always)"
      return 0
      ;;
    never) return 1 ;;
  esac
  { : </dev/tty >/dev/tty; } 2>/dev/null || return 1
  while :; do
    printf '%s [y/N] ' "$q" >/dev/tty
    IFS= read -r ans </dev/tty || return 1
    case "$ans" in
      y | Y | yes | YES | Yes) return 0 ;;
      n | N | no | NO | No | '') return 1 ;;
      *) echo "please answer y or n" >/dev/tty ;;
    esac
  done
}

# ---- AWS credentials -------------------------------------------------------------
# Verify the active credentials actually work; on failure pause so the user
# can refresh them in another terminal, then retry. No-op when aws is absent
# (not every terraform root is AWS).
tfEnsureAwsAuth() {
  command -v aws >/dev/null 2>&1 || return 0
  local out ans
  while :; do
    if out="$(aws sts get-caller-identity --output json 2>&1)"; then
      logInfo "AWS credentials OK: $(jq -r '.Arn' <<<"$out" 2>/dev/null)"
      return 0
    fi
    logError "AWS credential check failed (profile: ${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-default}}):"
    printf '%s\n' "$out" | sed 's/^/    /' >&2
    if ! { : </dev/tty >/dev/tty; } 2>/dev/null; then
      logError "non-interactive session — cannot wait for refreshed credentials"
      return 1
    fi
    printf 'Refresh your AWS credentials in another terminal, then press Enter to retry (q to abort): ' >/dev/tty
    IFS= read -r ans </dev/tty || return 1
    case "$ans" in q | Q) return 1 ;; esac
  done
}

# ---- self-correcting terraform init ----------------------------------------------
# tfInitModule [extra init args...] — runs in the CURRENT directory.
#   * expired AWS credentials -> pause for refresh, retry
#   * changed backend config  -> rerun once with -reconfigure (terraform's
#     recommendation; for intentional moves run -migrate-state yourself)
tfInitModule() {
  local attempt=0 reconfigured=false out rc
  while :; do
    attempt=$((attempt + 1))
    printf '[LEARN] %s\n' "terraform init -input=false $*" >&2
    out="$(terraform init -input=false "$@" 2>&1)"
    rc=$?
    printf '%s\n' "$out"
    [ "$rc" -eq 0 ] && return 0
    if [ "$attempt" -ge 4 ]; then
      logError "terraform init still failing after ${attempt} attempts"
      return "$rc"
    fi
    if tfLooksLikeAuthError "$out"; then
      logWarn "terraform init failed — AWS credentials look expired"
      tfEnsureAwsAuth || return "$rc"
    elif [ "$reconfigured" = false ] && tfLooksLikeBackendChange "$out"; then
      logWarn "backend configuration changed — rerunning with 'terraform init -reconfigure'"
      logWarn "if you actually moved state to a new backend, abort and run 'terraform init -migrate-state' instead"
      set -- -reconfigure "$@"
      reconfigured=true
    else
      return "$rc"
    fi
  done
}

# ---- plan JSON parsing ---------------------------------------------------------
tfPlanCounts() { # tfPlanCounts <plan.json> -> compact counts object
  jq -c '
    [.resource_changes[]?] as $all
    | { create:  ($all | map(select(.change.actions == ["create"])) | length),
        update:  ($all | map(select(.change.actions == ["update"])) | length),
        destroy: ($all | map(select(.change.actions == ["delete"])) | length),
        replace: ($all | map(select(.change.actions == ["delete","create"]
                              or .change.actions == ["create","delete"])) | length),
        forget:  ($all | map(select(.change.actions == ["forget"])) | length),
        import:  ($all | map(select(.change.importing != null)) | length),
        move:    ($all | map(select(.previous_address != null)) | length) }
    | . + { total: (.create + .update + .destroy + .replace + .forget) }
  ' "$1"
}

tfChangesJsonl() { # tfChangesJsonl <plan.json> -> one object per change
  jq -c '
    def klass:
      if (.change.importing // null) != null then "import"
      elif ((.change.actions | sort) == ["create","delete"]) then "replace"
      elif .change.actions == ["delete"] then "delete"
      elif .change.actions == ["create"] then "create"
      elif .change.actions == ["update"] then "update"
      elif .change.actions == ["forget"] then "forget"
      elif (.previous_address // null) != null then "moved"
      else "noop" end;
    .resource_changes[]?
    | {action: klass, address, type, name,
       module: (.module_address // ""),
       import_id: (.change.importing.id // ""),
       previous_address: (.previous_address // "")}
    | select(.action != "noop")' "$1"
}

tfIcon() { # tfIcon <action> -> single-width glyph
  case "$1" in
    create) printf '✚' ;;
    update) printf '✎' ;;
    delete) printf '✘' ;;
    replace) printf '⟳' ;;
    forget) printf '⊘' ;;
    import) printf '↧' ;;
    moved) printf '➜' ;;
    *) printf '?' ;;
  esac
}

_tfPaint() { # _tfPaint <action> <text> — colorize when stdout is a tty
  local code
  case "$1" in
    create) code=32 ;;
    update) code=33 ;;
    delete) code=31 ;;
    replace) code=35 ;;
    forget) code=36 ;;
    import) code=34 ;;
    *) code=0 ;;
  esac
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    printf '\033[%sm%s\033[0m' "$code" "$2"
  else
    printf '%s' "$2"
  fi
}

tfSummary() { # tfSummary <plan.json> — counts line + one icon line per change
  local counts
  counts="$(tfPlanCounts "$1")"
  if [ "$(jq -r '.total + .import + .move' <<<"$counts")" = 0 ]; then
    echo "No changes."
    return 0
  fi
  jq -r '"Plan: \(.create) to create, \(.update) to update, \(.destroy) to destroy, \(.replace) to replace"
    + (if .import > 0 then ", \(.import) to import" else "" end)
    + (if .forget > 0 then ", \(.forget) to forget (removed from state only)" else "" end)
    + (if .move > 0 then "  (+\(.move) moved)" else "" end)' <<<"$counts"
  # NB: fields are joined with the unit separator (\x1f), NOT tabs — tab is
  # IFS whitespace, so consecutive tabs collapse and empty fields vanish.
  local us action address import_id prev line
  us="$(printf '\037')"
  while IFS="$us" read -r action address import_id prev; do
    line="  $(tfIcon "$action") $address"
    [ "$action" = import ] && [ -n "$import_id" ] && line="$line  (id: $import_id)"
    [ "$action" = moved ] && [ -n "$prev" ] && line="$line  (was $prev)"
    _tfPaint "$action" "$line"
    printf '\n'
  done < <(tfChangesJsonl "$1" | jq -r '[.action, .address, .import_id, .previous_address] | join("\u001f")' |
    sort -t"$us" -k1,1 -k2,2)
  echo "  legend: ✚ create  ✎ update  ✘ delete  ⟳ replace  ⊘ forget  ↧ import  ➜ moved"
}

tfFmtAge() { # tfFmtAge <seconds> -> "2d 3h" / "3h 24m" / "12m" / "42s"
  local s="$1"
  if [ "$s" -ge 86400 ]; then
    echo "$((s / 86400))d $(((s % 86400) / 3600))h"
  elif [ "$s" -ge 3600 ]; then
    echo "$((s / 3600))h $(((s % 3600) / 60))m"
  elif [ "$s" -ge 60 ]; then
    echo "$((s / 60))m"
  else
    echo "${s}s"
  fi
}

# ---- run metadata ---------------------------------------------------------------
tfWriteRunMeta() { # tfWriteRunMeta <name> <ts> <base> <exit_code> <counts_json> <argv>
  local name="$1" ts="$2" base="$3" rc="$4" counts="$5" argv="$6"
  jq -n \
    --arg name "$name" --arg dir "$PWD" --arg ts "$ts" \
    --arg created_at "$(date +"%Y-%m-%dT%H:%M:%S%z")" \
    --argjson created_epoch "$(date +%s)" \
    --arg argv "$argv" \
    --arg profile "${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}" \
    --arg tf_version "$(terraform version -json 2>/dev/null | jq -r '.terraform_version // ""')" \
    --arg plan "${base}.tfplan" --arg log "${base}.tfplan.log" --arg json "${base}.tfplan.json" \
    --argjson exit_code "$rc" --argjson summary "$counts" \
    '{ name: $name, dir: $dir, timestamp: $ts, created_at: $created_at,
       created_epoch: $created_epoch, argv: $argv, aws_profile: $profile,
       terraform_version: $tf_version,
       plan_file: $plan, log_file: $log, json_file: $json,
       exit_code: $exit_code, has_changes: ($exit_code == 2), summary: $summary }' \
    >"${base}.run.json"
  cp "${base}.run.json" "$(tfLatestMeta)"
}

# ---- apply from metadata ---------------------------------------------------------
# tfApplyRun <run.json> [show_summary=true] [force=false]
# Applies the EXACT saved plan — never re-plans. Warns when the plan was
# already applied; detects stale plans; records applied_at back into the
# metadata (and latest.json when it points at the same plan).
tfApplyRun() {
  local meta="$1" show_summary="${2:-true}" force="${3:-false}"
  local name plan json rc ts log created tmp latest
  name="$(jq -r '.name' "$meta")"
  plan="$(jq -r '.plan_file' "$meta")"
  json="$(jq -r '.json_file' "$meta")"

  case "$(jq -r '.exit_code' "$meta")" in
    0)
      logInfo "latest plan for ${name} has no changes — nothing to apply"
      return 0
      ;;
    1)
      logError "the recorded plan run for ${name} failed — nothing to apply (see $(jq -r '.log_file' "$meta"))"
      return 1
      ;;
  esac
  if [ ! -f "$plan" ]; then
    logError "plan file not found: ${plan} — re-run '${TISS_NAME:-tiss} tf plan' (plans self-destruct after ${TISS_TF_PLAN_TTL:-1d})"
    return 1
  fi
  if [ "$(jq -r '.applied_at // empty' "$meta")" != "" ]; then
    logWarn "this plan was already applied at $(jq -r '.applied_at' "$meta") (exit $(jq -r '.apply_exit' "$meta")) — terraform will reject it if state moved on"
  fi

  if [ "$show_summary" = true ]; then
    created="$(jq -r '.created_epoch // 0' "$meta")"
    logInfo "plan:    ${plan}"
    logInfo "created: $(jq -r '.created_at' "$meta") ($(tfFmtAge $(($(date +%s) - created))) ago)"
    echo
    tfSummary "$json"
    echo
  fi

  if [ "$force" != true ]; then
    tfConfirm "Apply this plan to ${name}?" || {
      logInfo "not applying ${name} — later: ${TISS_NAME:-tiss} tf apply --yes"
      return 0
    }
  fi

  tfEnsureAwsAuth || return 1

  ts="$(date +"%Y%m%dT%H%M%S")"
  log="${plan%.tfplan}.apply.${ts}.log"
  printf '[LEARN] %s\n' "terraform apply -input=false $plan" >&2
  terraform apply -input=false "$plan" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}

  tmp="$(jq --arg at "$(date +"%Y-%m-%dT%H:%M:%S%z")" --arg log "$log" --argjson rc "$rc" \
    '. + { applied_at: $at, apply_exit: $rc, apply_log: $log }' "$meta")"
  printf '%s\n' "$tmp" >"$meta"
  latest="$(tfLatestMeta)"
  if [ -f "$latest" ] && [ "$(jq -r '.plan_file' "$latest")" = "$plan" ]; then
    printf '%s\n' "$tmp" >"$latest"
  fi

  if [ "$rc" -ne 0 ]; then
    if grep -qi 'saved plan is stale' "$log"; then
      logError "the saved plan is stale (state changed since it was created) — re-run '${TISS_NAME:-tiss} tf plan'"
    fi
    logError "terraform apply failed for ${name} (log: ${log})"
    return 1
  fi
  logInfo "apply complete for ${name} (log: ${log})"
}

# ---- module discovery & sweep support ---------------------------------------------
# tfAutoJobs — half the cores, clamped to [1,8]: AWS API throttling, not CPU,
# is the practical ceiling for concurrent plans.
tfAutoJobs() {
  local c
  c="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
  c=$((c / 2))
  [ "$c" -lt 1 ] && c=1
  [ "$c" -gt 8 ] && c=8
  echo "$c"
}

# tfDiscoverRootModules — every directory under the cwd containing a *.tf
# that declares a backend (TISS_TF_MODULE_GREP tunes the marker; the
# original rule was 'backend "s3"').
tfDiscoverRootModules() {
  local marker="${TISS_TF_MODULE_GREP:-backend \"}"
  {
    if command -v rg >/dev/null 2>&1; then
      rg -l "$marker" -g '*.tf' . 2>/dev/null
    else
      grep -rl --include='*.tf' "$marker" . 2>/dev/null
    fi
  } | while IFS= read -r f; do dirname "$f"; done | sort -u
}

# tfFreshPlanJson <abs-dir> — succeeds when the latest plan is newer than
# SKIP_FRESH_HOURS, echoing its json path so callers can reuse it in
# reports. SKIP_FRESH_HOURS=0/unset disables freshness skipping.
tfFreshPlanJson() {
  local dir="$1" latest="$1/.tiss/tfplans/latest.json" prev_epoch age j
  [ "${SKIP_FRESH_HOURS:-0}" -gt 0 ] || return 1
  [ -f "$latest" ] || return 1
  prev_epoch="$(jq -r '.created_epoch // 0' "$latest")"
  age=$(($(date +%s) - prev_epoch))
  [ "$age" -lt $((SKIP_FRESH_HOURS * 3600)) ] || return 1
  j="$(jq -r '.json_file // empty' "$latest")"
  if [ -n "$j" ]; then
    case "$j" in
      /*) [ -f "$j" ] && echo "$j" ;;
      *) [ -f "$dir/$j" ] && echo "$dir/$j" ;;
    esac
  fi
  return 0
}

tfHr() { printf '%*s\n' 50 '' | tr ' ' '*'; }
tfBanner() {
  tfHr
  echo "*** $*"
  tfHr
}
