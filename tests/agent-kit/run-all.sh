#!/usr/bin/env bash
# Full agent-kit suite: refresh the gitignored dogfood instance, then run the
# structural checks, every template guard, the docs checker, and the loop /
# self-install harness. Prints one line per suite and exits non-zero when any
# suite fails.
#
# Usage (from anywhere):
#   bash tests/agent-kit/run-all.sh [options]
#
# Options:
#   --no-install     Skip scripts/agent-kit/self-install.sh (use the current instance).
#   -j N               Run up to N suites in parallel (default: CPU count capped at 8).
#   --only SUBSTR      Run suites whose path contains SUBSTR (repeatable).
#   --quick            Run a fast subset (see usage(): checks, docs-link-check, template-currency, …).
#
# Environment:
#   AGENT_KIT_TEST_JOBS   Same as -j (command line wins).
#   AGENT_KIT_CASE_JOBS   Parallel case blocks inside suites (default 4; exported to children).
#   AGENT_KIT_EMIT_CACHE  Run-scoped emit cache directory (set automatically under the log dir).
#   AGENT_KIT_DOCKER      1 = run the Docker bash:3.2 check in emit-portability.sh (default: skip).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT" || exit 2

_cpu_jobs() {
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

_resolve_test_jobs() {
  local raw="$1"
  if [ -z "$raw" ]; then
    _cpu_jobs
    return 0
  fi
  echo "$raw"
}

usage() {
  cat >&2 <<EOF
usage: $0 [--no-install] [-j N] [--only SUBSTR]... [--quick]

Options:
  --no-install   Skip scripts/agent-kit/self-install.sh (use the current instance).
  -j N           Run up to N suites in parallel (default: CPU count capped at 8).
  --only SUBSTR  Run suites whose path contains SUBSTR (repeatable).
  --quick        Fast subset: checks.sh, docs-link-check.sh, template-currency.sh,
                 skill-slimming.sh, model-enforcement.sh, forge-adapter.sh,
                 invocation-flags.sh, escalation-ladder.sh.

Environment:
  AGENT_KIT_TEST_JOBS   Same as -j (command line wins).
  AGENT_KIT_CASE_JOBS   Parallel case blocks inside suites (default 4).
  AGENT_KIT_EMIT_CACHE  Run-scoped emit cache dir (run-all sets under the log dir).
  AGENT_KIT_DOCKER      1 = run the Docker bash:3.2 check in emit-portability.sh (default: skip).
EOF
  exit 2
}

install=1
test_jobs_raw=""
quick=0
only_patterns=()

while [ $# -gt 0 ]; do
  case "$1" in
    --no-install)
      install=0
      shift
      ;;
    -j)
      shift
      [ $# -gt 0 ] || usage
      test_jobs_raw="$1"
      shift
      ;;
    --only)
      shift
      [ $# -gt 0 ] || usage
      only_patterns+=("$1")
      shift
      ;;
    --quick)
      quick=1
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

if [ -n "${AGENT_KIT_TEST_JOBS:-}" ] && [ -z "$test_jobs_raw" ]; then
  test_jobs_raw="$AGENT_KIT_TEST_JOBS"
fi
if [ -n "$test_jobs_raw" ]; then
  case "$test_jobs_raw" in
    *[!0-9]* | '')
      echo "usage: $0 [--no-install] [-j N] [--only SUBSTR]... [--quick]" >&2
      echo "agent-kit: invalid -j (positive integer required): ${test_jobs_raw}" >&2
      exit 2
      ;;
  esac
  if [ "$test_jobs_raw" -lt 1 ]; then
    echo "usage: $0 [--no-install] [-j N] [--only SUBSTR]... [--quick]" >&2
    echo "agent-kit: invalid -j (positive integer required): ${test_jobs_raw}" >&2
    exit 2
  fi
fi
TEST_JOBS="$(_resolve_test_jobs "$test_jobs_raw")"

_validate_case_jobs() {
  local raw="${AGENT_KIT_CASE_JOBS:-}"
  if [ -z "$raw" ]; then
    return 0
  fi
  case "$raw" in
    *[!0-9]* | '')
      echo "agent-kit: invalid AGENT_KIT_CASE_JOBS (positive integer required): ${raw}" >&2
      exit 2
      ;;
  esac
  if [ "$raw" -lt 1 ]; then
    echo "agent-kit: invalid AGENT_KIT_CASE_JOBS (positive integer required): ${raw}" >&2
    exit 2
  fi
}
_validate_case_jobs

# Memory split ON when normalized label sets match (task 08 AC1): exclude SKIP lines
# whose detail contains `not in MEMORY_SUITES` from the union of split logs.
# Comparison (2026-10-12): 92 labels each for memory.log vs filtered union — split ON.
MEMORY_SPLIT=1

if (( install )); then
  if ! bash scripts/agent-kit/self-install.sh >/dev/null; then
    echo "FAIL  self-install (scripts/agent-kit/self-install.sh)"
    exit 1
  fi
  echo "ok    self-install"
fi

# Slowest suites first when scheduling parallel jobs (stable print order is separate).
PRIORITY=(
  tests/agent-kit/templates/memory.sh
  tests/agent-kit/loop-harness/run.sh
  tests/agent-kit/templates/emit-determinism.sh
  tests/agent-kit/templates/emit-portability.sh
  tests/agent-kit/templates/model-currency.sh
  tests/agent-kit/templates/legacy-paths.sh
  tests/agent-kit/templates/memory-wiring.sh
  tests/agent-kit/templates/emit-migrate.sh
  tests/agent-kit/templates/emit-golden.sh
  tests/agent-kit/templates/windows-launcher.sh
  tests/agent-kit/templates/log-spawn.sh
)

QUICK_SUITES=(
  tests/agent-kit/checks.sh
  tests/agent-kit/docs-link-check.sh
  tests/agent-kit/templates/template-currency.sh
  tests/agent-kit/templates/skill-slimming.sh
  tests/agent-kit/templates/model-enforcement.sh
  tests/agent-kit/templates/forge-adapter.sh
  tests/agent-kit/templates/invocation-flags.sh
  tests/agent-kit/templates/escalation-ladder.sh
)

_build_default_suites() {
  local out=()
  out+=(
    tests/agent-kit/checks.sh
    tests/agent-kit/docs-link-check.sh
    tests/agent-kit/lib/selftest.sh
  )
  local t
  for t in tests/agent-kit/templates/*.sh; do
    [ -f "$t" ] || continue
    out+=("$t")
  done
  out+=(tests/agent-kit/loop-harness/run.sh)
  printf '%s\n' "${out[@]}"
}

_suites_contains() {
  local needle="$1"
  shift
  local s
  for s in "$@"; do
    if [ "$s" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

_expand_memory_jobs() {
  local suites=("$@")
  local out=()
  local s
  for s in "${suites[@]}"; do
    if [ "$MEMORY_SPLIT" -eq 1 ] && [ "$s" = "tests/agent-kit/templates/memory.sh" ]; then
      out+=(
        "tests/agent-kit/templates/memory.sh|MEMORY_SUITES=bash|tests/agent-kit/templates/memory.sh[bash]"
        "tests/agent-kit/templates/memory.sh|MEMORY_SUITES=pwsh|tests/agent-kit/templates/memory.sh[pwsh]"
        "tests/agent-kit/templates/memory.sh|MEMORY_SUITES=parity|tests/agent-kit/templates/memory.sh[parity]"
      )
    else
      out+=("$s||$s")
    fi
  done
  printf '%s\n' "${out[@]}"
}

_filter_suites() {
  local suites=("$@")
  if [ "$quick" -eq 1 ]; then
    suites=()
    local q
    for q in "${QUICK_SUITES[@]}"; do
      suites+=("$q")
    done
  fi
  if [ "${#only_patterns[@]}" -gt 0 ]; then
    local filtered=() s pat
    for s in "${suites[@]}"; do
      for pat in "${only_patterns[@]}"; do
        case "$s" in
          *"$pat"*)
            filtered+=("$s")
            break
            ;;
        esac
      done
    done
    if [ "${#filtered[@]}" -gt 0 ]; then
      suites=("${filtered[@]}")
    else
      suites=()
    fi
    if [ "${#suites[@]}" -eq 0 ]; then
      echo "agent-kit: --only matched no suites" >&2
      usage
    fi
  fi
  printf '%s\n' "${suites[@]}"
}

_schedule_key() {
  local path="$1"
  local i=0
  while [ "$i" -lt "${#PRIORITY[@]}" ]; do
    if [ "${PRIORITY[$i]}" = "$path" ]; then
      printf '%03d' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "${#SELECTED[@]}" ]; do
    if [ "${SELECTED[$i]}" = "$path" ]; then
      printf '%03d' "$((100 + i))"
      return 0
    fi
    i=$((i + 1))
  done
  printf '199'
}

DEFAULT_LINES="$(mktemp 2>/dev/null || mktemp -t ra)"
_build_default_suites >"$DEFAULT_LINES"
DEFAULT=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  DEFAULT+=("$line")
done <"$DEFAULT_LINES"
rm -f "$DEFAULT_LINES"

if [ "${#DEFAULT[@]}" -gt 0 ]; then
  SELECTED=("${DEFAULT[@]}")
else
  SELECTED=()
fi
if [ "$quick" -eq 1 ] || [ "${#only_patterns[@]}" -gt 0 ]; then
  SEL_LINES="$(mktemp 2>/dev/null || mktemp -t ra2)"
  _filter_suites "${SELECTED[@]}" >"$SEL_LINES"
  SELECTED=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    SELECTED+=("$line")
  done <"$SEL_LINES"
  rm -f "$SEL_LINES"
fi

JOB_LINES="$(mktemp 2>/dev/null || mktemp -t ra3)"
_expand_memory_jobs "${SELECTED[@]}" >"$JOB_LINES"
JOBS=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  JOBS+=("$line")
done <"$JOB_LINES"
rm -f "$JOB_LINES"

# Stable print order follows SELECTED (default suite list order).
DISPLAY_ORDER=()
for s in "${SELECTED[@]}"; do
  if [ "$MEMORY_SPLIT" -eq 1 ] && [ "$s" = "tests/agent-kit/templates/memory.sh" ]; then
    DISPLAY_ORDER+=(
      "tests/agent-kit/templates/memory.sh[bash]"
      "tests/agent-kit/templates/memory.sh[pwsh]"
      "tests/agent-kit/templates/memory.sh[parity]"
    )
  else
    DISPLAY_ORDER+=("$s")
  fi
done

log_dir="$(mktemp -d 2>/dev/null || mktemp -d -t agent-kit-logs)"
export AGENT_KIT_CASE_JOBS="${AGENT_KIT_CASE_JOBS:-4}"
export AGENT_KIT_EMIT_CACHE="$log_dir/emit-cache"
mkdir -p "$AGENT_KIT_EMIT_CACHE"

wall_start=$SECONDS

_run_one_job() {
  local script="$1"
  local env_kv="$2"
  local log="$3"
  local rcf="$4"
  local secf="$5"
  local start=$SECONDS
  if [ -n "$env_kv" ]; then
    env "${env_kv%%=*}=${env_kv#*=}" bash "$script" >"$log" 2>&1
  else
    bash "$script" >"$log" 2>&1
  fi
  local rc=$?
  local elapsed=$((SECONDS - start))
  printf '%s\n' "$rc" >"$rcf"
  printf '%s\n' "$elapsed" >"$secf"
}

# Schedule: sort job specs by priority key (slowest first).
SCHED_LINES="$(mktemp 2>/dev/null || mktemp -t ra4)"
idx=0
while [ "$idx" -lt "${#JOBS[@]}" ]; do
  line="${JOBS[$idx]}"
  script="${line%%|*}"
  rest="${line#*|}"
  env_kv="${rest%%|*}"
  display="${rest#*|}"
  key="$(_schedule_key "$script")"
  if [ -z "$env_kv" ]; then
    env_kv="-"
  fi
  printf '%s\t%s\t%s\t%s\t%d\n' "$key" "$script" "$env_kv" "$display" "$idx"
  idx=$((idx + 1))
done | LC_ALL=C sort >"$SCHED_LINES"

RUN_PIDS=()
RUN_META=()

while IFS=$'\t' read -r _key script env_kv display job_idx; do
  while :; do
    running=0
    i=0
    if [ "${#RUN_PIDS[@]}" -gt 0 ]; then
      pids=("${RUN_PIDS[@]}")
    else
      pids=()
    fi
    while [ "$i" -lt "${#pids[@]}" ]; do
      if kill -0 "${pids[$i]}" 2>/dev/null; then
        running=$((running + 1))
      fi
      i=$((i + 1))
    done
    if [ "$running" -lt "$TEST_JOBS" ]; then
      break
    fi
    sleep 0.05
  done

  if [ "$env_kv" = "-" ]; then
    env_kv=""
  fi
  safe="$(echo "$display" | tr '/[]' '___')"
  log="$log_dir/${safe}.log"
  rcf="$log_dir/${safe}.rc"
  secf="$log_dir/${safe}.sec"
  (
    _run_one_job "$script" "$env_kv" "$log" "$rcf" "$secf"
  ) &
  pid=$!
  RUN_PIDS+=("$pid")
  RUN_META+=("$display|$log|$rcf|$secf|$pid")
done <"$SCHED_LINES"
rm -f "$SCHED_LINES"

i=0
if [ "${#RUN_PIDS[@]}" -gt 0 ]; then
  pids=("${RUN_PIDS[@]}")
else
  pids=()
fi
while [ "$i" -lt "${#pids[@]}" ]; do
  if kill -0 "${pids[$i]}" 2>/dev/null; then
    wait "${pids[$i]}" 2>/dev/null || true
  fi
  i=$((i + 1))
done

failed=0
result_lines=0
slow_list=""
slow_sec_list=""

for display in "${DISPLAY_ORDER[@]}"; do
  meta=""
  j=0
  if [ "${#RUN_META[@]}" -gt 0 ]; then
    metas=("${RUN_META[@]}")
  else
    metas=()
  fi
  while [ "$j" -lt "${#metas[@]}" ]; do
    if [ "${metas[$j]#"$display"|}" != "${metas[$j]}" ]; then
      meta="${metas[$j]}"
      break
    fi
    j=$((j + 1))
  done
  safe="$(echo "$display" | tr '/[]' '___')"
  default_log="$log_dir/${safe}.log"
  if [ -z "$meta" ]; then
    failed=$((failed + 1))
    result_lines=$((result_lines + 1))
    printf 'FAIL  %s (?s) -- log: %s\n' "$display" "$default_log"
    grep -E '^(FAIL|error)' "$default_log" 2>/dev/null | head -n 10 | sed 's/^/        /'
    continue
  fi
  log="${meta#*|}"
  log="${log%%|*}"
  rest="${meta#*|}"
  rest="${rest#*|}"
  rcf="${rest%%|*}"
  rest="${rest#*|}"
  secf="${rest%%|*}"
  sec="$(cat "$secf" 2>/dev/null || echo 0)"
  rc="$(cat "$rcf" 2>/dev/null || echo)"
  if [ -z "$rc" ]; then
    rc=127
    sec=0
  fi
  result_lines=$((result_lines + 1))
  if [ -z "$slow_list" ]; then
    slow_list="${sec} ${display}"
  else
    slow_list="${slow_list}"$'\n'"${sec} ${display}"
  fi
  if [ "$rc" = "0" ]; then
    printf 'ok    %s (%ss)\n' "$display" "$sec"
  else
    failed=$((failed + 1))
    printf 'FAIL  %s (%ss) -- log: %s\n' "$display" "$sec" "$log"
    grep -E '^(FAIL|error)' "$log" 2>/dev/null | head -n 10 | sed 's/^/        /'
  fi
done

wall=$((SECONDS - wall_start))
echo "agent-kit: $((result_lines - failed))/${result_lines} suite(s) ok; wall ${wall}s"

slow_top="$(printf '%s\n' "$slow_list" | LC_ALL=C sort -nr | head -n 5)"
echo "agent-kit: slowest suites:"
printf '%s\n' "$slow_top" | while IFS= read -r slow_line; do
  [ -z "$slow_line" ] && continue
  sec="${slow_line%% *}"
  name="${slow_line#* }"
  echo "        ${name} (${sec}s)"
done

if (( failed > 0 )); then
  echo "agent-kit: ${failed} suite(s) failed; logs in ${log_dir}"
  exit 1
fi
rm -rf "$log_dir"
echo "agent-kit: ${result_lines} suite(s) passed"
exit 0
