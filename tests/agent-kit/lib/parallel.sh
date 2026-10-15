# shellcheck shell=bash
# Parallel block runner for agent-kit template suites (Bash 3.2).
# Source silently; suites set PAR_COUNTERS, PAR_LISTS, PAR_REPORT_FAIL before par_init.

PAR_DIR=""
PAR_JOBS=1
PAR_NEXT_ID=0
PAR_BLOCK_IDS=()
PAR_BLOCK_PIDS=()

_par_cpu_jobs() {
  local n=1
  if command -v nproc >/dev/null 2>&1; then
    n="$(nproc 2>/dev/null || echo 1)"
  elif command -v sysctl >/dev/null 2>&1; then
    n="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
  fi
  case "$n" in
    '' | *[!0-9]*) n=1 ;;
  esac
  if [ "$n" -gt 8 ]; then
    n=8
  fi
  if [ "$n" -lt 1 ]; then
    n=1
  fi
  echo "$n"
}

_par_validate_jobs() {
  local raw="$1"
  local label="$2"
  local outvar="${3:-}"
  local n
  if [ -z "$raw" ]; then
    n="$(_par_cpu_jobs)"
  else
    case "$raw" in
      *[!0-9]* | '')
        echo "agent-kit: invalid ${label} (positive integer required): ${raw}" >&2
        return 2
        ;;
    esac
    if [ "$raw" -lt 1 ]; then
      echo "agent-kit: invalid ${label} (positive integer required): ${raw}" >&2
      return 2
    fi
    n="$raw"
    if [ "$n" -gt 8 ]; then
      n=8
    fi
  fi
  if [ -n "$outvar" ]; then
    printf -v "$outvar" '%s' "$n"
  else
    echo "$n"
  fi
  return 0
}

par_init() {
  if [ -n "${PAR_DIR:-}" ] && [ -d "${PAR_DIR:-}" ]; then
    rm -rf "$PAR_DIR"
    PAR_DIR=""
  fi
  _par_validate_jobs "${AGENT_KIT_CASE_JOBS:-}" "AGENT_KIT_CASE_JOBS" PAR_JOBS || exit $?
  PAR_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t par)"
  PAR_NEXT_ID=0
  PAR_BLOCK_IDS=()
  PAR_BLOCK_PIDS=()
}

_par_running_count() {
  local running=0
  local i=0
  local pids
  if [ "${#PAR_BLOCK_PIDS[@]}" -gt 0 ]; then
    pids=("${PAR_BLOCK_PIDS[@]}")
  else
    pids=()
  fi
  while [ "$i" -lt "${#pids[@]}" ]; do
    if kill -0 "${pids[$i]}" 2>/dev/null; then
      running=$((running + 1))
    fi
    i=$((i + 1))
  done
  echo "$running"
}

_par_wait_for_slot() {
  while :; do
    local running
    running="$(_par_running_count)"
    if [ "$running" -lt "$PAR_JOBS" ]; then
      return 0
    fi
    sleep 0.05
  done
}

_par_counter_names() {
  echo "${PAR_COUNTERS:-}"
}

_par_list_names() {
  echo "${PAR_LISTS:-}"
}

par_block() {
  local func="$1"
  shift
  _par_wait_for_slot

  local id="$PAR_NEXT_ID"
  PAR_NEXT_ID=$((PAR_NEXT_ID + 1))
  PAR_BLOCK_IDS+=("$id")

  local bdir="$PAR_DIR/block-${id}"
  mkdir -p "$bdir" || return 1
  printf '%s\n' "$func" >"$bdir/func"
  printf '%s\n' "$@" >"$bdir/args"

  _PAR_BLOCK_SAVED_OPTS="$-"
  (
    local c l start end delta
    for c in $(_par_counter_names); do
      eval "start=\${${c}:-0}"
      printf '%s\n' "$start" >"$bdir/counter-${c}.start"
    done
    for l in $(_par_list_names); do
      eval "start=\${${l}:-}"
      printf '%s' "$start" >"$bdir/list-${l}.start"
    done

    case "$_PAR_BLOCK_SAVED_OPTS" in
      *u*) set -u ;;
      *) set +u ;;
    esac
    local rc=0
    if "$func" "$@" >"$bdir/stdout" 2>"$bdir/stderr"; then
      rc=0
    else
      rc=$?
    fi

    set +u
    for c in $(_par_counter_names); do
      eval "end=\${${c}:-0}"
      start="$(cat "$bdir/counter-${c}.start" 2>/dev/null || echo 0)"
      delta=$((end - start))
      printf '%s\n' "$delta" >"$bdir/counter-${c}.delta"
    done
    for l in $(_par_list_names); do
      eval "end=\${${l}:-}"
      start="$(cat "$bdir/list-${l}.start" 2>/dev/null || echo)"
      if [ "${#end}" -lt "${#start}" ]; then
        delta=""
      else
        delta="${end#"$start"}"
      fi
      printf '%s' "$delta" >"$bdir/list-${l}.delta"
    done
    printf 'done\n' >"$bdir/marker"
    printf '%s\n' "$rc" >"$bdir/rc"
    exit 0
  ) &
  local pid=$!
  PAR_BLOCK_PIDS+=("$pid")
  printf '%s\n' "$pid" >"$bdir/pid"
}

par_finish() {
  local ids
  if [ "${#PAR_BLOCK_IDS[@]}" -gt 0 ]; then
    ids=("${PAR_BLOCK_IDS[@]}")
  else
    ids=()
  fi
  local i=0
  while [ "$i" -lt "${#ids[@]}" ]; do
    local id="${ids[$i]}"
    local bdir="$PAR_DIR/block-${id}"
    local pid func rc waited=0
    pid="$(cat "$bdir/pid" 2>/dev/null || echo)"
    func="$(cat "$bdir/func" 2>/dev/null || echo block)"
    if [ -n "$pid" ]; then
      while kill -0 "$pid" 2>/dev/null; do
        sleep 0.05
      done
      if wait "$pid" 2>/dev/null; then
        waited=0
      else
        waited=$?
      fi
    fi
    if [ -f "$bdir/stdout" ]; then
      cat "$bdir/stdout"
    fi
    if [ -f "$bdir/stderr" ]; then
      cat "$bdir/stderr" >&2
    fi
    if [ -f "$bdir/marker" ]; then
      local c l delta cur
      for c in $(_par_counter_names); do
        if [ -f "$bdir/counter-${c}.delta" ]; then
          delta="$(cat "$bdir/counter-${c}.delta")"
          eval "${c}=\$(( \${${c}:-0} + delta ))"
        fi
      done
      for l in $(_par_list_names); do
        if [ -f "$bdir/list-${l}.delta" ]; then
          delta="$(cat "$bdir/list-${l}.delta")"
          if [ -n "$delta" ]; then
            eval "cur=\${${l}:-}"
            if [ -n "$cur" ]; then
              case "$delta" in
                \ *) eval "${l}=\${cur}\${delta}" ;;
                *) eval "${l}=\"\${cur} \${delta}\"" ;;
              esac
            else
              eval "${l}=\${delta}"
            fi
          fi
        fi
      done
    else
      rc="$waited"
      if [ -f "$bdir/rc" ]; then
        rc="$(cat "$bdir/rc")"
      fi
      if [ -n "${PAR_REPORT_FAIL:-}" ]; then
        ${PAR_REPORT_FAIL} "par: block ${func} did not complete (rc=${rc})"
      fi
    fi
    i=$((i + 1))
  done
}

par_cleanup() {
  if [ -n "${PAR_DIR:-}" ] && [ -d "${PAR_DIR:-}" ]; then
    rm -rf "$PAR_DIR"
  fi
  PAR_DIR=""
}
