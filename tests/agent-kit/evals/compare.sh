#!/usr/bin/env bash
# Compare candidate kits against the stock kit through run.sh. Contract: tests/agent-kit/evals/README.md
# ("## Candidates", "## compare.sh").
#
#   bash tests/agent-kit/evals/compare.sh [--plan|--check] [--cand NAME]... [--with-baseline]
#          [--tasks ...] [--runs N] [--model ID] [--budget-usd X] [--timeout S] [--out DIR] [--keep]
#
# Environment: EVAL_CANDIDATES_DIR (default <evals>/candidates), EVAL_CLI and EVAL_TASKS_DIR (passed
# through to run.sh untouched).
# Exit: 0 ok, 1 check failure / run.sh exit 1 / scratch setup failure, 2 usage error, 3 a patch did not
# apply; in a full run otherwise the first non-zero run.sh exit code.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: compare.sh [--plan|--check] [--cand NAME]... [--with-baseline] [--tasks id[,id...]] [--runs N]
                  [--model ID] [--budget-usd X] [--timeout S] [--out DIR] [--keep]
USAGE
  exit 2
}

die_usage() {
  echo "compare.sh: $1" >&2
  usage
}

is_int() {
  case "${1-}" in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

MODE=run
CAND_ARGS=""
WITH_BASELINE=0
TASKS_ARG=""
RUNS_ARG=""
MODEL_ARG=""
BUDGET_ARG=""
TIMEOUT_ARG=""
OUT=""
KEEP=0
RUNS_SET=0
BUDGET_SET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --plan) [ "$MODE" = check ] && die_usage "--plan and --check cannot be combined"; MODE=plan; shift ;;
    --check) [ "$MODE" = plan ] && die_usage "--plan and --check cannot be combined"; MODE=check; shift ;;
    --with-baseline) WITH_BASELINE=1; shift ;;
    --keep) KEEP=1; shift ;;
    --cand | --tasks | --runs | --model | --budget-usd | --timeout | --out)
      [ $# -ge 2 ] || die_usage "$1 needs a value"
      case "$1" in
        --cand) CAND_ARGS="$CAND_ARGS$2"$'\n' ;;
        --tasks) TASKS_ARG="$2" ;;
        --runs) RUNS_ARG="$2"; RUNS_SET=1 ;;
        --model) MODEL_ARG="$2" ;;
        --budget-usd) BUDGET_ARG="$2"; BUDGET_SET=1 ;;
        --timeout) TIMEOUT_ARG="$2" ;;
        --out) OUT="$2" ;;
      esac
      shift 2
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

abs_path() { # path -> absolute path (no symlink resolution)
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$PWD/$1" ;;
  esac
}

CAND_DIR="$(abs_path "${EVAL_CANDIDATES_DIR:-$HERE/candidates}")"
STOCK_KIT="$REPO_ROOT/skills/agent-kit"
ANSWERS="$HERE/answers.json"
BUDGET_LIMIT=11264

# --- candidate discovery: every directory holding patch.diff, sorted -------------------------
ALL_CANDS=""
if [ -d "$CAND_DIR" ]; then
  for _d in "$CAND_DIR"/*/; do
    [ -d "$_d" ] || continue
    _d="${_d%/}"
    [ -f "$_d/patch.diff" ] || continue
    ALL_CANDS="$ALL_CANDS${_d##*/}"$'\n'
  done
fi
ALL_CANDS="$(printf '%s' "$ALL_CANDS" | LC_ALL=C sort)"

while IFS= read -r _n; do
  [ -n "$_n" ] || continue
  case "$_n" in
    kit | baseline) echo "compare.sh: candidate directory name '$_n' is reserved" >&2; usage ;;
  esac
done <<EOF
$ALL_CANDS
EOF

if [ -n "$CAND_ARGS" ]; then
  SELECTED=""
  while IFS= read -r _n; do
    [ -n "$_n" ] || continue
    case "$_n" in
      */* | . | ..) echo "compare.sh: unknown candidate: $_n" >&2; usage ;;
    esac
    [ -f "$CAND_DIR/$_n/patch.diff" ] || { echo "compare.sh: unknown candidate: $_n" >&2; usage; }
    SELECTED="$SELECTED$_n"$'\n'
  done <<EOF
$CAND_ARGS
EOF
  SELECTED="$(printf '%s' "$SELECTED" | LC_ALL=C sort -u)"
else
  SELECTED="$ALL_CANDS"
fi

CAND_COUNT=0
ARM_LABELS="kit"
while IFS= read -r _n; do
  [ -n "$_n" ] || continue
  CAND_COUNT=$((CAND_COUNT + 1))
  ARM_LABELS="$ARM_LABELS $_n"
done <<EOF
$SELECTED
EOF
[ "$WITH_BASELINE" -eq 1 ] && ARM_LABELS="$ARM_LABELS baseline"
ARM_COUNT=$((CAND_COUNT + 1 + WITH_BASELINE))

# --- --plan: no scratch, no run.sh -----------------------------------------------------------
if [ "$MODE" = plan ]; then
  _runs=3
  _budget=5
  [ "$RUNS_SET" -eq 1 ] && _runs="$RUNS_ARG"
  [ "$BUDGET_SET" -eq 1 ] && _budget="$BUDGET_ARG"
  is_int "$_runs" || die_usage "--runs must be an integer of at least 1"
  _stripped="${_runs#"${_runs%%[!0]*}"}"
  [ "${#_stripped}" -le 9 ] || die_usage "--runs is too large"
  _runs=$((10#$_runs))
  [ "$_runs" -ge 1 ] || die_usage "--runs must be an integer of at least 1"
  case "$_budget" in
    '' | *[!0-9.]* | *.*.* | .) die_usage "--budget-usd must be a positive number" ;;
  esac
  awk -v b="$_budget" 'BEGIN { exit !(b + 0 > 0) }' || die_usage "--budget-usd must be a positive number"
  if [ -n "$TASKS_ARG" ]; then
    _tcount=0
    _oldifs="$IFS"
    IFS=','
    for _t in $TASKS_ARG; do _tcount=$((_tcount + 1)); done
    IFS="$_oldifs"
  else
    _tcount=0
    for _d in "${EVAL_TASKS_DIR:-$HERE/tasks}"/*/; do
      [ -d "$_d" ] && _tcount=$((_tcount + 1))
    done
  fi
  _total="$(awk -v a="$ARM_COUNT" -v t="$_tcount" -v r="$_runs" 'BEGIN { printf "%.0f", a * t * r }')" \
    || die_usage "cannot compute the plan"
  _bound="$(awk -v n="$_total" -v b="$_budget" 'BEGIN { printf "%.2f", n * b }')" \
    || die_usage "cannot compute the plan"
  echo "plan: $ARM_COUNT arms × $_tcount tasks × $_runs runs = $_total runs; upper cost bound \$$_bound"
  echo "arms: $ARM_LABELS"
  exit 0
fi

# --- run-level scratch + git isolation (README step 0) ---------------------------------------
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akcmp.XXXXXX")" || exit 1
cleanup() {
  if [ "$KEEP" -eq 0 ]; then
    rm -rf "$FIXTURE_TMPDIR"
  fi
}
trap cleanup EXIT
# shellcheck source=../lib/fixture-root.sh
. "$REPO_ROOT/tests/agent-kit/lib/fixture-root.sh"
if [ "$KEEP" -eq 1 ]; then
  echo "scratch kept under: $FIXTURE_TMPDIR"
fi

# --- step 1: copy the stock kit per candidate and apply the patch ----------------------------
while IFS= read -r _n; do
  [ -n "$_n" ] || continue
  mkdir -p "$FIXTURE_TMPDIR/kits/$_n" || exit 1
  cp -R "$STOCK_KIT/." "$FIXTURE_TMPDIR/kits/$_n/" || exit 1
  if ! (cd "$FIXTURE_TMPDIR/kits/$_n" && git apply -p1 "$CAND_DIR/$_n/patch.diff") >/dev/null 2>&1; then
    echo "compare.sh: patch of candidate '$_n' does not apply to $STOCK_KIT" >&2
    exit 3
  fi
done <<EOF
$SELECTED
EOF

# emit_into DIR KIT: scratch git repo + emit; returns emit's exit code (1 on setup failure).
emit_into() {
  local dir="$1" kit="$2"
  mkdir -p "$dir" || return 1
  git init -q "$dir" >/dev/null 2>&1 || return 1
  assert_fixture_repo "$dir" || return 1
  bash "$kit/bin/emit.sh" --root "$dir" --kit "$kit" --answers "$ANSWERS" > "$dir.emit.log" 2>&1
}

# marker_of README: the single backticked line under "## Marker"; prints it, returns 1 when malformed.
marker_of() {
  local readme="$1" lines n line
  [ -f "$readme" ] || return 1
  lines="$(awk '
    /^## / { if (s) exit; line = $0; sub(/[ \t\r]+$/, "", line); if (line == "## Marker") s = 1; next }
    s && $0 !~ /^[ \t\r]*$/ { sub(/\r$/, "", $0); print }
  ' "$readme")"
  [ -n "$lines" ] || return 1
  n="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || return 1
  line="$lines"
  case "$line" in
    '`'*'`') ;;
    *) return 1 ;;
  esac
  line="${line#\`}"
  line="${line%\`}"
  [ -n "$line" ] || return 1
  printf '%s\n' "$line"
}

# --- step 2: --check -------------------------------------------------------------------------
if [ "$MODE" = check ]; then
  if ! emit_into "$FIXTURE_TMPDIR/emit/stock" "$STOCK_KIT"; then
    echo "check stock: FAIL stock kit did not emit (see $FIXTURE_TMPDIR/emit/stock.emit.log; kept only with --keep)"
    exit 1
  fi
  CHECK_RC=0
  while IFS= read -r _n; do
    [ -n "$_n" ] || continue
    _kit="$FIXTURE_TMPDIR/kits/$_n"
    _reasons=""
    if ! emit_into "$FIXTURE_TMPDIR/emit/$_n" "$_kit"; then
      _reasons="patched kit did not emit (see $FIXTURE_TMPDIR/emit/$_n.emit.log; kept only with --keep)"
    else
      if _marker="$(marker_of "$CAND_DIR/$_n/README.md")"; then
        grep -rqF -- "$_marker" "$FIXTURE_TMPDIR/emit/$_n/.claude" 2>/dev/null \
          || _reasons="marker not found in the patched emit"
        if grep -rqF -- "$_marker" "$FIXTURE_TMPDIR/emit/stock/.claude" 2>/dev/null; then
          _reasons="${_reasons:+$_reasons; }marker also present in the stock emit"
        fi
      else
        _reasons="README.md has no single backticked line under ## Marker"
      fi
    fi
    _size="$(wc -c < "$_kit/templates/skills/feature/SKILL.template.md" 2>/dev/null | tr -d ' ')"
    if [ -z "$_size" ]; then
      _reasons="${_reasons:+$_reasons; }templates/skills/feature/SKILL.template.md is missing"
    elif [ "$_size" -gt "$BUDGET_LIMIT" ]; then
      _reasons="${_reasons:+$_reasons; }SKILL.template.md is $_size bytes, over $BUDGET_LIMIT"
    fi
    if [ -n "$_reasons" ]; then
      echo "check $_n: FAIL $_reasons"
      CHECK_RC=1
    else
      echo "check $_n: ok"
    fi
  done <<EOF
$SELECTED
EOF
  exit "$CHECK_RC"
fi

# --- step 4: full run ------------------------------------------------------------------------
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
[ -n "$OUT" ] || OUT="$REPO_ROOT/_memory/work/evals/compare-$STAMP"
OUT="$(abs_path "$OUT")"

PASS_ARGS=()
[ -n "$TASKS_ARG" ] && PASS_ARGS+=(--tasks "$TASKS_ARG")
[ -n "$RUNS_ARG" ] && PASS_ARGS+=(--runs "$RUNS_ARG")
[ -n "$MODEL_ARG" ] && PASS_ARGS+=(--model "$MODEL_ARG")
[ -n "$BUDGET_ARG" ] && PASS_ARGS+=(--budget-usd "$BUDGET_ARG")
[ -n "$TIMEOUT_ARG" ] && PASS_ARGS+=(--timeout "$TIMEOUT_ARG")
[ "$KEEP" -eq 1 ] && PASS_ARGS+=(--keep)

FIRST_RC=0
REPORT_DIRS=()
STOCK_HAS_ROWS=0
ANY_ROWS=0

# run_arm LABEL ARM [KIT_SRC]
run_arm() {
  local label="$1" arm="$2" kit="${3-}" rc
  if [ -n "$kit" ]; then
    bash "$HERE/run.sh" --arm "$arm" --kit-src "$kit" --label "$label" --out "$OUT/$label" \
      ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
  else
    bash "$HERE/run.sh" --arm "$arm" --label "$label" --out "$OUT/$label" \
      ${PASS_ARGS[@]+"${PASS_ARGS[@]}"}
  fi
  rc=$?
  [ "$rc" -ne 0 ] && [ "$FIRST_RC" -eq 0 ] && FIRST_RC=$rc
  if [ -s "$OUT/$label/results.jsonl" ]; then
    REPORT_DIRS+=("$OUT/$label")
    ANY_ROWS=1
    [ "$label" = kit ] && STOCK_HAS_ROWS=1
  else
    echo "compare.sh: arm '$label' wrote no results (run.sh exit $rc); left out of the report" >&2
  fi
  return 0
}

run_arm kit kit
while IFS= read -r _n; do
  [ -n "$_n" ] || continue
  run_arm "$_n" kit "$FIXTURE_TMPDIR/kits/$_n"
done <<EOF
$SELECTED
EOF
[ "$WITH_BASELINE" -eq 1 ] && run_arm baseline baseline

if [ "$ANY_ROWS" -eq 0 ]; then
  echo "compare.sh: no results to report" >&2
  [ "$FIRST_RC" -ne 0 ] || FIRST_RC=1
  exit "$FIRST_RC"
fi
if [ "$STOCK_HAS_ROWS" -eq 0 ]; then
  echo "compare.sh: the stock kit arm wrote no results; the comparisons below are not against the stock kit" >&2
fi

bash "$HERE/report.sh" "${REPORT_DIRS[@]}"
_rep_rc=$?
[ "$FIRST_RC" -ne 0 ] || FIRST_RC=$_rep_rc
exit "$FIRST_RC"
