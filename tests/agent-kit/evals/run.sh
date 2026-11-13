#!/usr/bin/env bash
# Outcome eval runner: runs one arm (baseline or kit) over the eval tasks and appends one
# JSONL row per run to <out>/results.jsonl. Contract: tests/agent-kit/evals/README.md.
#
#   bash tests/agent-kit/evals/run.sh --arm baseline|kit [options]
#
# Options: --tasks id[,id...]  --runs N (3)  --model ID (claude-sonnet-5-5)  --budget-usd X (5)
#          --timeout S (1800)  --label NAME  --kit-src DIR  --out DIR  --keep
# Environment: EVAL_CLI (default claude), EVAL_TASKS_DIR (default <evals>/tasks).
# Exit: 0 all runs executed and graded, 2 usage error, 3 a run could not be set up.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: run.sh --arm baseline|kit [--tasks id[,id...]] [--runs N] [--model ID] [--budget-usd X]
              [--timeout S] [--label NAME] [--kit-src DIR] [--out DIR] [--keep]
USAGE
  exit 2
}

is_int() {
  case "${1-}" in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

ARM=""
TASKS_ARG=""
RUNS=3
MODEL="claude-sonnet-5-5"
BUDGET=5
TIMEOUT_S=1800
LABEL=""
KIT_SRC="$REPO_ROOT/skills/agent-kit"
OUT=""
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1; shift ;;
    --arm | --tasks | --runs | --model | --budget-usd | --timeout | --label | --kit-src | --out)
      [ $# -ge 2 ] || { echo "run.sh: $1 needs a value" >&2; usage; }
      case "$1" in
        --arm) ARM="$2" ;;
        --tasks) TASKS_ARG="$2" ;;
        --runs) RUNS="$2" ;;
        --model) MODEL="$2" ;;
        --budget-usd) BUDGET="$2" ;;
        --timeout) TIMEOUT_S="$2" ;;
        --label) LABEL="$2" ;;
        --kit-src) KIT_SRC="$2" ;;
        --out) OUT="$2" ;;
      esac
      shift 2
      ;;
    *) echo "run.sh: unknown argument: $1" >&2; usage ;;
  esac
done

case "$ARM" in
  baseline | kit) ;;
  *) echo "run.sh: --arm baseline|kit is required" >&2; usage ;;
esac
is_int "$RUNS" && [ "$RUNS" -ge 1 ] || { echo "run.sh: --runs must be an integer of at least 1" >&2; usage; }
is_int "$TIMEOUT_S" && [ "$TIMEOUT_S" -ge 1 ] || { echo "run.sh: --timeout must be an integer of at least 1" >&2; usage; }
[ -n "$BUDGET" ] || { echo "run.sh: --budget-usd needs a value" >&2; usage; }
[ -n "$MODEL" ] || { echo "run.sh: --model needs a value" >&2; usage; }
[ -n "$LABEL" ] || LABEL="$ARM"

TASKS_DIR="${EVAL_TASKS_DIR:-$HERE/tasks}"
if [ -n "$TASKS_ARG" ]; then
  TASK_IDS=()
  _oldifs="$IFS"
  IFS=','
  for _t in $TASKS_ARG; do TASK_IDS+=("$_t"); done
  IFS="$_oldifs"
else
  TASK_IDS=()
  for _d in "$TASKS_DIR"/*/; do
    [ -d "$_d" ] || continue
    _d="${_d%/}"
    TASK_IDS+=("${_d##*/}")
  done
fi
for _t in ${TASK_IDS[@]+"${TASK_IDS[@]}"}; do
  if [ -z "$_t" ] || [ ! -d "$TASKS_DIR/$_t" ]; then
    echo "run.sh: no task directory for id '$_t' under $TASKS_DIR" >&2
    usage
  fi
done

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
[ -n "$OUT" ] || OUT="$REPO_ROOT/_memory/work/evals/$LABEL-$STAMP"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac

if [ "$ARM" = kit ] && [ -d "$KIT_SRC" ]; then
  KIT_SRC="$(cd "$KIT_SRC" && pwd)"
fi

# --- run-level scratch + git isolation (README step 0) -------------------------------------
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akeval.XXXXXX")" || exit 1
cleanup() {
  if [ "$KEEP" -eq 0 ]; then
    rm -rf "$FIXTURE_TMPDIR"
  fi
}
trap cleanup EXIT
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"
if [ "$KEEP" -eq 1 ]; then
  echo "scratch kept under: $FIXTURE_TMPDIR"
fi

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN=gtimeout
else
  echo "note: no timeout command found; running without a per-run timeout"
fi

# Variables removed before the CLI starts: an explicit denylist (never a keep-list, never a prefix match).
ENV_UNSET=()
for _v in EVAL_TASKS_DIR OLDPWD CLAUDECODE CLAUDE_EFFORT CLAUDE_PID CLAUDE_AGENT_SDK_VERSION \
  CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_EMIT_STARTUP_TIMING CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING \
  CLAUDE_CODE_ENABLE_TASKS CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH \
  CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN \
  CLAUDE_CODE_QUESTION_PREVIEW_FORMAT CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_SESSION_ID \
  CLAUDE_CODE_STARTUP_FAILURE_RESULTS CLAUDE_CODE_SSE_PORT; do
  ENV_UNSET+=(-u "$_v")
done

EVAL_CLI_STR="${EVAL_CLI:-claude}"
CLI_ARR=()
for _w in $EVAL_CLI_STR; do CLI_ARR+=("$_w"); done
[ "${#CLI_ARR[@]}" -gt 0 ] || { echo "run.sh: EVAL_CLI is empty" >&2; exit 2; }

BASELINE_PARA='You are working without a user. Do not ask questions; make reasonable decisions and finish the work. Do not push or open pull requests.'
KIT_PREAMBLE='No user is available. The lines below under Decisions are the user'"'"'s confirmed Phase 1 answers: record them in the goal and continue without waiting for confirmation. Set the goal'"'"'s `phases:` block to `align_docs: false`, `pull_request: false`, `ladder: auto`, `qa: skip`. At every decision gate or escalation, take the recommended option and log it. Never push or open a pull request. Stop after Phase 5 is APPROVED and the quality checks have run.'

# section FILE HEADING: lines under "## HEADING" up to the next "## ", blank edges trimmed.
section() {
  awk -v h="$2" '
    /^## / { if (s) exit; line = $0; sub(/[ \t\r]+$/, "", line); if (line == h) s = 1; next }
    s {
      if ($0 ~ /^[ \t\r]*$/) { if (started) pend = pend $0 "\n"; next }
      printf "%s", pend; pend = ""; started = 1; print
    }' "$1"
}

setup_fail() {
  echo "run.sh: setup failed for task $1 run $2/$RUNS: $3" >&2
  exit 3
}

run_one() { # task n
  local task="$1" n="$2"
  local tdir="$TASKS_DIR/$task" rdir scratch gdir base prompt started t0 t1 cli_rc timed_out
  local checks_pass checks_total grade_rc pass_s changed spawns kit_s cost_s

  [ -f "$tdir/task.md" ] || setup_fail "$task" "$n" "missing task.md"
  [ -d "$tdir/seed" ] || setup_fail "$task" "$n" "missing seed/"
  local p_text d_text
  p_text="$(section "$tdir/task.md" "## Prompt")"
  d_text="$(section "$tdir/task.md" "## Decisions")"
  [ -n "$p_text" ] || setup_fail "$task" "$n" "empty ## Prompt in task.md"
  if [ "$ARM" = kit ]; then
    prompt="/feature $p_text"$'\n\n'"$KIT_PREAMBLE"$'\n\n'"Decisions:"$'\n'"$d_text"
  else
    prompt="$p_text"$'\n\n'"$BASELINE_PARA"
  fi

  rdir="$OUT/$task/$n"
  mkdir -p "$rdir" || setup_fail "$task" "$n" "cannot create $rdir"
  scratch="$(mktemp -d "$FIXTURE_TMPDIR/run.XXXXXX")" || setup_fail "$task" "$n" "mktemp failed"
  cp -R "$tdir/seed/." "$scratch/" || setup_fail "$task" "$n" "seed copy failed"
  git init -q "$scratch" >/dev/null 2>&1 || setup_fail "$task" "$n" "git init failed"
  assert_fixture_repo "$scratch" || setup_fail "$task" "$n" "scratch is not an isolated repository"
  git -C "$scratch" add -A && git -C "$scratch" commit -q --allow-empty -m "eval base" \
    || setup_fail "$task" "$n" "base commit failed"

  if [ "$ARM" = kit ]; then
    if ! bash "$KIT_SRC/bin/emit.sh" --root "$scratch" --kit "$KIT_SRC" \
      --answers "$HERE/answers.json" > "$rdir/emit.log" 2>&1; then
      setup_fail "$task" "$n" "kit emit failed (see $rdir/emit.log)"
    fi
    git -C "$scratch" add -A && git -C "$scratch" commit -q --allow-empty -m "eval kit emit" \
      || setup_fail "$task" "$n" "kit commit failed"
  fi
  base="$(git -C "$scratch" rev-parse HEAD)" || setup_fail "$task" "$n" "cannot resolve base commit"

  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  t0="$(date +%s)"
  (
    cd "$scratch" || exit 99
    if [ -n "$TIMEOUT_BIN" ]; then
      exec env "${ENV_UNSET[@]}" "$TIMEOUT_BIN" "$TIMEOUT_S" "${CLI_ARR[@]}" -p "$prompt" --output-format json \
        --model "$MODEL" --max-budget-usd "$BUDGET" --permission-mode acceptEdits \
        --allowedTools "Read Edit Write Glob Grep Bash Agent Skill TodoWrite" \
        --setting-sources project --strict-mcp-config --no-session-persistence
    else
      exec env "${ENV_UNSET[@]}" "${CLI_ARR[@]}" -p "$prompt" --output-format json \
        --model "$MODEL" --max-budget-usd "$BUDGET" --permission-mode acceptEdits \
        --allowedTools "Read Edit Write Glob Grep Bash Agent Skill TodoWrite" \
        --setting-sources project --strict-mcp-config --no-session-persistence
    fi
  ) < /dev/null > "$rdir/cli.json" 2> "$rdir/cli.stderr"
  cli_rc=$?
  t1="$(date +%s)"
  timed_out=false
  if [ -n "$TIMEOUT_BIN" ]; then
    if [ "$cli_rc" -eq 124 ]; then
      timed_out=true
    elif { [ "$cli_rc" -eq 137 ] || [ "$cli_rc" -eq 143 ]; } && [ "$((t1 - t0))" -ge "$TIMEOUT_S" ]; then
      timed_out=true
    fi
  fi

  # grade: the hidden grader is copied only now, into its own temp dir
  gdir="$(mktemp -d "$FIXTURE_TMPDIR/grade.XXXXXX")" || setup_fail "$task" "$n" "mktemp failed"
  if [ -d "$tdir/grade" ]; then cp -R "$tdir/grade/." "$gdir/"; fi
  bash "$gdir/grade.sh" "$scratch" > "$rdir/grade.txt" 2>&1
  grade_rc=$?
  pass_s=false
  [ "$grade_rc" -eq 0 ] && pass_s=true
  checks_pass="$(grep -c '^CHECK pass ' "$rdir/grade.txt")"
  checks_total="$(grep -c '^CHECK ' "$rdir/grade.txt")"

  # changes.txt
  find "$scratch" -name .git -prune -o \( -type d \( -name __pycache__ -o -name .pytest_cache \
    -o -name .mypy_cache -o -name .ruff_cache \) -prune -exec rm -rf {} + \) \
    -o \( -type f -name '*.pyc' -exec rm -f {} + \) 2>/dev/null
  git -C "$scratch" add -A >/dev/null 2>&1
  {
    git -C "$scratch" diff --cached --stat "$base"
    echo "--- paths ---"
    git -C "$scratch" diff --cached --name-only "$base"
  } > "$rdir/changes.txt" 2>&1
  changed="$(awk 'f && NF { c++ } /^--- paths ---$/ { f = 1 } END { print c + 0 }' "$rdir/changes.txt")"

  spawns=null
  kit_s=null
  if [ "$ARM" = kit ]; then
    spawns="$(cat "$scratch"/_memory/work/goals/*/orchestration-log.md 2>/dev/null | grep -c '^### .* — SPAWN ')"
    kit_s="$KIT_SRC"
  fi

  cost_s="$(PYTHONDONTWRITEBYTECODE=1 python3 -B -c '
import json, sys
a = sys.argv[1:]
(task, arm, label, run, model, pass_s, cp, ct, cli_rc, timed_out, dur, cli_json,
 changed, spawns, kit_src, started, results) = a
cost = turns = stop = None
try:
    with open(cli_json, encoding="utf-8") as fh:
        obj = json.load(fh)
    if isinstance(obj, dict):
        c = obj.get("total_cost_usd")
        if isinstance(c, (int, float)) and not isinstance(c, bool):
            cost = c
        t = obj.get("num_turns")
        if isinstance(t, (int, float)) and not isinstance(t, bool):
            turns = t
        s = obj.get("subtype")
        if isinstance(s, str):
            stop = s
except (OSError, ValueError):
    pass
row = {
    "task": task, "arm": arm, "label": label, "run": int(run), "model": model,
    "pass": pass_s == "true", "checks_passed": int(cp), "checks_total": int(ct),
    "cli_exit": int(cli_rc), "timed_out": timed_out == "true", "duration_s": int(dur),
    "cost_usd": cost, "num_turns": turns, "stop_reason": stop,
    "changed_files": int(changed),
    "spawns": None if spawns == "null" else int(spawns),
    "kit_src": None if kit_src == "null" else kit_src,
    "started_at": started,
}
with open(results, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row) + "\n")
print("n/a" if cost is None else "%.2f" % cost)
' "$task" "$ARM" "$LABEL" "$n" "$MODEL" "$pass_s" "$checks_pass" "$checks_total" "$cli_rc" \
    "$timed_out" "$((t1 - t0))" "$rdir/cli.json" "$changed" "$spawns" "$kit_s" "$started" \
    "$OUT/results.jsonl")" || setup_fail "$task" "$n" "could not write the result row"

  if [ "$pass_s" = true ]; then pass_s=pass; else pass_s=fail; fi
  printf '%s %s run %s/%s: %s (%s/%s) %ss $%s\n' "$task" "$ARM" "$n" "$RUNS" "$pass_s" \
    "$checks_pass" "$checks_total" "$((t1 - t0))" "$cost_s"

  if [ "$KEEP" -eq 0 ]; then
    rm -rf "$scratch" "$gdir"
  fi
}

mkdir -p "$OUT" || { echo "run.sh: cannot create $OUT" >&2; exit 2; }

for task in ${TASK_IDS[@]+"${TASK_IDS[@]}"}; do
  n=1
  while [ "$n" -le "$RUNS" ]; do
    run_one "$task" "$n"
    n=$((n + 1))
  done
done

echo "results: $OUT/results.jsonl"
exit 0
