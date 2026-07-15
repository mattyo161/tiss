# shellcheck shell=bash
# tiss tf parallel sweep — ported from tools/tf lib/parallel.sh, tiss paths.
# Sourced by scripts/tf/plan.sh only (not via init.sh); needs lib/tf.sh.
#
# Design (unchanged from the original): each module runs as a background
# worker doing the same silent init -> plan -> export pipeline, reporting
# through a small key=value status file. The monitor keeps N workers running
# (kill -0 polling; bash 3.2 has no `wait -n`), renders a live status region
# on a tty (plain event lines when piped/CI), prints a permanent completion
# block per module with FULL counts (imports/forgets/moves included, zeros
# shown), pauses and re-queues workers that die from expired AWS
# credentials, and ends with a summary table.
#
# Parallel sweeps are plan-only by design — applies stay serialized through
# `tiss tf apply` afterwards.

tfStatusSet() { # tfStatusSet <file> <step> [key=value ...] — atomic snapshot
  local f="$1" step="$2" kv
  shift 2
  {
    echo "step=$step"
    echo "start=${WORKER_START:-$(date +%s)}"
    for kv in "$@"; do echo "$kv"; done
  } >"${f}.tmp" && mv "${f}.tmp" "$f"
}

tfStatusGet() { # tfStatusGet <file> <key>
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1
}

# tfPlanWorker <abs-dir> <name> <status-file> — one module, no console
# output, no prompts (stdin closed). Exit codes: 0 ok (with or without
# changes), 75 credential failure (retryable after a refresh), 1 other.
tfPlanWorker() {
  local dir="$1" name="$2" sf="$3"
  local wlog="${sf%.status}.worker.log" run_ts base rc
  WORKER_START="$(date +%s)"
  exec >>"$wlog" 2>&1 </dev/null
  cd "$dir" || exit 1

  tfStatusSet "$sf" init
  if ! tfInitModule; then
    if tfLooksLikeAuthError "$(cat "$wlog")"; then
      tfStatusSet "$sf" auth-failed "log=$wlog"
      exit 75
    fi
    tfStatusSet "$sf" failed "log=$wlog"
    exit 1
  fi

  mkdir -p "$(tfPlansDir)"
  run_ts="$(date +"%Y%m%dT%H%M%S")"
  base="$(tfPlansDir)/${name}.${run_ts}"

  tfStatusSet "$sf" plan
  terraform plan -input=false -detailed-exitcode -no-color \
    -out "${base}.tfplan" ${TF_ARGS[@]+"${TF_ARGS[@]}"} >"${base}.tfplan.log" 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    if tfLooksLikeAuthError "$(cat "${base}.tfplan.log")"; then
      tfStatusSet "$sf" auth-failed "log=$PWD/${base}.tfplan.log"
      exit 75
    fi
    tfWriteRunMeta "$name" "$run_ts" "$base" 1 'null' "tf plan (sweep)"
    tfStatusSet "$sf" failed "log=$PWD/${base}.tfplan.log"
    exit 1
  fi

  tfStatusSet "$sf" json
  if ! terraform show -json "${base}.tfplan" >"${base}.tfplan.json"; then
    tfStatusSet "$sf" failed "log=$wlog"
    exit 1
  fi
  tfWriteRunMeta "$name" "$run_ts" "$base" "$rc" "$(tfPlanCounts "${base}.tfplan.json")" "tf plan (sweep)"
  [ "${TISS_TF_PLAN_TTL:-1d}" != 0 ] && rmAfter "${TISS_TF_PLAN_TTL:-1d}" "${base}.tfplan" >/dev/null 2>&1
  tfStatusSet "$sf" "done" "meta=$PWD/${base}.run.json" "json=$PWD/${base}.tfplan.json"
  exit 0
}

# ---- rendering ----------------------------------------------------------------

tfStepLabel() {
  case "$1" in
    init) echo "initializing" ;;
    plan) echo "planning" ;;
    json) echo "exporting json" ;;
    queued) echo "starting" ;;
    *) echo "${1:-starting}" ;;
  esac
}

# The live region is DRAWN lines tall; erase before printing anything permanent.
_tfEraseRegion() {
  [ "${DRAWN:-0}" -gt 0 ] && printf '\033[%dA\033[J' "$DRAWN"
  DRAWN=0
}

_tfDrawRegion() {
  [ "$IS_TTY" = true ] || return 0
  local i now lines=1 sf st ws
  now="$(date +%s)"
  printf 'running: %d   done: %d   failed: %d   queued: %d   elapsed %s\n' \
    "${#RUN_PIDS[@]}" "$N_DONE" "$N_FAIL" "${#QUEUE[@]}" "$(tfFmtAge $((now - SWEEP_START)))"
  i=0
  while [ "$i" -lt "${#RUN_PIDS[@]}" ]; do
    sf="${RUN_SFS[$i]}"
    st="$(tfStatusGet "$sf" step)"
    ws="$(tfStatusGet "$sf" start)"
    ws="${ws:-$now}"
    printf '  %-28s %-16s %4ss\n' "${RUN_NAMES[$i]}" "$(tfStepLabel "$st")" "$((now - ws))"
    lines=$((lines + 1))
    i=$((i + 1))
  done
  DRAWN=$lines
}

# tfFullCounts <run.json> — every bucket, zeros included: the buckets the
# normal summary hides (imports, forgets, moves) always show here.
tfFullCounts() {
  jq -r '.summary
         | "create \(.create) · update \(.update) · destroy \(.destroy) · replace \(.replace) · import \(.import) · forget \(.forget) · move \(.move)"' \
    "$1"
}

_tfPrintDoneBlock() { # name dur meta json
  local name="$1" dur="$2" meta="$3" json="$4" summary
  tfHr
  echo "✔ ${name}  ($(tfFmtAge "$dur"))"
  echo "   plan: $(jq -r '.plan_file' "$meta")"
  echo "   $(tfFullCounts "$meta")"
  summary="$(tfSummary "$json")"
  case "$summary" in
    "No changes."*) echo "   no changes" ;;
    *) printf '%s\n' "$summary" | sed '1d; s/^/ /' ;;
  esac
  echo
}

_tfPrintFailBlock() { # name dur log why
  local name="$1" dur="$2" log="$3" why="$4"
  tfHr
  echo "✖ ${name}  ($(tfFmtAge "$dur")) — ${why}"
  if [ -n "$log" ] && [ -f "$log" ]; then
    echo "   log: $log"
    tail -5 "$log" | sed 's/^/   | /'
  fi
  echo
}

_tfSummaryRow() { # name meta dur -> "name|result|c|u|d|r|i|f|m|time"
  jq -r --arg n "$1" --arg t "$(tfFmtAge "$3")" \
    '.summary as $s
     | [$n, (if .exit_code == 2 then "changes" else "clean" end),
        ($s.create|tostring), ($s.update|tostring), ($s.destroy|tostring),
        ($s.replace|tostring), ($s.import|tostring), ($s.forget|tostring),
        ($s.move|tostring), $t]
     | join("|")' "$2"
}

tfParallelSummaryTable() {
  [ "${#SUMMARY_ROWS[@]}" -eq 0 ] && return 0
  echo
  tfBanner "sweep summary"
  {
    echo "module|result|create|update|destroy|replace|import|forget|move|time"
    local r
    for r in "${SUMMARY_ROWS[@]}"; do echo "$r"; done
  } | column -t -s '|'
  echo
}

# ---- monitor ------------------------------------------------------------------

_tfParallelAbort() {
  trap - INT TERM
  [ "${#RUN_PIDS[@]}" -gt 0 ] && kill "${RUN_PIDS[@]}" 2>/dev/null
  _tfEraseRegion
  logError "sweep interrupted — ${N_DONE} done, ${#QUEUE[@]} still queued"
  exit 130
}

# _tfHarvest <name> <status-file> <dir> <rc> — account for one finished worker
_tfHarvest() {
  local name="$1" sf="$2" dir="$3" rc="$4" meta json dur start now
  now="$(date +%s)"
  start="$(tfStatusGet "$sf" start)"
  start="${start:-$now}"
  dur=$((now - start))
  case "$rc" in
    0)
      meta="$(tfStatusGet "$sf" meta)"
      json="$(tfStatusGet "$sf" json)"
      PLANNED_JSONS+=("$json")
      N_DONE=$((N_DONE + 1))
      _tfEraseRegion
      _tfPrintDoneBlock "$name" "$dur" "$meta" "$json"
      SUMMARY_ROWS+=("$(_tfSummaryRow "$name" "$meta" "$dur")")
      ;;
    75)
      case " $RETRIED " in
        *" $name "*) # already re-queued once — give up on it
          N_FAIL=$((N_FAIL + 1))
          _tfEraseRegion
          _tfPrintFailBlock "$name" "$dur" "$(tfStatusGet "$sf" log)" "credentials expired again after refresh"
          SUMMARY_ROWS+=("${name}|auth-failed|-|-|-|-|-|-|-|$(tfFmtAge "$dur")")
          ;;
        *)
          RETRIED="$RETRIED $name"
          AUTHQ_DIRS+=("$dir")
          PAUSED=true
          _tfEraseRegion
          logWarn "${name}: AWS credentials expired — pausing new launches for a refresh"
          ;;
      esac
      ;;
    *)
      N_FAIL=$((N_FAIL + 1))
      _tfEraseRegion
      _tfPrintFailBlock "$name" "$dur" "$(tfStatusGet "$sf" log)" "failed (exit $rc)"
      SUMMARY_ROWS+=("${name}|failed|-|-|-|-|-|-|-|$(tfFmtAge "$dur")")
      ;;
  esac
}

# tfParallelSweep <jobs> — consumes QUEUE[] (absolute module dirs), appends
# to PLANNED_JSONS[] and SUMMARY_ROWS[]. Returns nonzero if any failed.
tfParallelSweep() {
  local jobs="$1" statusdir dir name sf pid rc i
  local keep_pids keep_names keep_sfs keep_dirs
  statusdir="$(mktemp -d "${TMPDIR:-/tmp}/tfplan-sweep.XXXXXX")"
  SWEEP_START="$(date +%s)"
  RUN_PIDS=()
  RUN_NAMES=()
  RUN_SFS=()
  RUN_DIRS=()
  AUTHQ_DIRS=()
  SUMMARY_ROWS=()
  RETRIED=""
  N_DONE=0
  N_FAIL=0
  DRAWN=0
  PAUSED=false
  if [ -t 1 ]; then IS_TTY=true; else IS_TTY=false; fi
  trap '_tfParallelAbort' INT TERM

  while [ "${#QUEUE[@]}" -gt 0 ] || [ "${#RUN_PIDS[@]}" -gt 0 ]; do
    # fill free slots (unless paused for a credential refresh)
    while [ "$PAUSED" = false ] && [ "${#RUN_PIDS[@]}" -lt "$jobs" ] && [ "${#QUEUE[@]}" -gt 0 ]; do
      dir="${QUEUE[0]}"
      QUEUE=("${QUEUE[@]:1}")
      name="$(basename "$dir")"
      sf="${statusdir}/${name}.status"
      tfStatusSet "$sf" queued
      tfPlanWorker "$dir" "$name" "$sf" &
      RUN_PIDS+=($!)
      RUN_NAMES+=("$name")
      RUN_SFS+=("$sf")
      RUN_DIRS+=("$dir")
      [ "$IS_TTY" = true ] || echo "> ${name}: started"
    done

    # harvest finished workers
    keep_pids=()
    keep_names=()
    keep_sfs=()
    keep_dirs=()
    i=0
    while [ "$i" -lt "${#RUN_PIDS[@]}" ]; do
      pid="${RUN_PIDS[$i]}"
      if kill -0 "$pid" 2>/dev/null; then
        keep_pids+=("$pid")
        keep_names+=("${RUN_NAMES[$i]}")
        keep_sfs+=("${RUN_SFS[$i]}")
        keep_dirs+=("${RUN_DIRS[$i]}")
      else
        wait "$pid"
        rc=$?
        _tfHarvest "${RUN_NAMES[$i]}" "${RUN_SFS[$i]}" "${RUN_DIRS[$i]}" "$rc"
      fi
      i=$((i + 1))
    done
    RUN_PIDS=(${keep_pids[@]+"${keep_pids[@]}"})
    RUN_NAMES=(${keep_names[@]+"${keep_names[@]}"})
    RUN_SFS=(${keep_sfs[@]+"${keep_sfs[@]}"})
    RUN_DIRS=(${keep_dirs[@]+"${keep_dirs[@]}"})

    # paused: let in-flight workers drain, then prompt once and re-queue
    if [ "$PAUSED" = true ] && [ "${#RUN_PIDS[@]}" -eq 0 ]; then
      _tfEraseRegion
      if { : </dev/tty >/dev/tty; } 2>/dev/null && tfEnsureAwsAuth; then
        for dir in ${AUTHQ_DIRS[@]+"${AUTHQ_DIRS[@]}"}; do QUEUE+=("$dir"); done
        logInfo "re-queued ${#AUTHQ_DIRS[@]} module(s) after credential refresh"
      else
        for dir in ${AUTHQ_DIRS[@]+"${AUTHQ_DIRS[@]}"}; do
          name="$(basename "$dir")"
          N_FAIL=$((N_FAIL + 1))
          SUMMARY_ROWS+=("${name}|auth-failed|-|-|-|-|-|-|-|-")
          logError "${name}: AWS credentials expired and no tty to wait for a refresh"
        done
      fi
      AUTHQ_DIRS=()
      PAUSED=false
      continue
    fi

    [ "${#QUEUE[@]}" -eq 0 ] && [ "${#RUN_PIDS[@]}" -eq 0 ] && break
    _tfEraseRegion
    _tfDrawRegion
    sleep 0.5
  done

  _tfEraseRegion
  trap - INT TERM
  rm -rf "$statusdir"
  [ "$N_FAIL" -eq 0 ]
}
