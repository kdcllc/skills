#!/usr/bin/env bash
# Offline self-test for the outcome eval set (tests/agent-kit/evals/README.md "## Self-test").
# No network, no claude binary: the runner is driven through lib/stub-cli.sh. Bash 3.2 compatible.
# Cases print `ok <case>` or `FAIL <case>: <reason>`; the last line is `PASS: <p> FAIL: <f> SKIP: <s>`.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
RUN="$HERE/run.sh"
REPORT="$HERE/report.sh"
STUB="$HERE/lib/stub-cli.sh"
TASKS="$HERE/tasks"
README="$HERE/README.md"
KIT_SRC="$REPO_ROOT/skills/agent-kit"

pass=0
fail=0
skip=0

ok() { pass=$((pass + 1)); echo "ok $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1: $2"; }
skipcase() { skip=$((skip + 1)); echo "SKIP $1: $2"; }
# expect_eq <case> <actual> <expected>
expect_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', want '$3'"; fi
}

pycache_count() { find "$REPO_ROOT" -name __pycache__ -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' '; }
PYCACHE_BEFORE="$(pycache_count)"

# --- scratch (one directory, removed on exit) ----------------------------------------------
_base="${TMPDIR:-/tmp}"
case "$_base" in *" "*) _base=/tmp ;; esac
ST="$(mktemp -d "$_base/evalselftest.XXXXXX")" || { echo "FAIL setup: mktemp"; exit 1; }
ST="$(cd "$ST" && pwd -P)"
trap 'rm -rf "$ST"' EXIT
export TMPDIR="$ST"
# shellcheck source=../lib/fixture-root.sh
FIXTURE_TMPDIR="$ST" . "$HERE/../lib/fixture-root.sh"

# --- helpers --------------------------------------------------------------------------------
# jf <results.jsonl> <key> [row]: the JSON text of one field of one row (empty on any error).
jf() {
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(json.dumps(rows[int(sys.argv[3]) - 1].get(sys.argv[2], "<missing>")))
' "$1" "$2" "${3:-1}" 2>/dev/null
}
# row_keys <results.jsonl>: the keys of row 1, in order, space separated.
row_keys() {
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(" ".join(rows[0].keys()))
' "$1" 2>/dev/null
}
nrows() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
probe_val() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

# tree_offenders <dir>: SKILL.md files and agent skill folders under <dir>.
tree_offenders() {
  find "$1" \( -name SKILL.md -o -name .claude -o -name .cursor -o -name .agents -o -name .github \) -print 2>/dev/null
}

# run_eval <stub-mode> <probe-file|""> <run.sh args...>: the runner driven through the stub copy.
run_eval() {
  local mode="$1" probe="$2"
  shift 2
  EVAL_CLI="bash $STUBCP" EVAL_TASKS_DIR="$TT" EVAL_STUB_MODE="$mode" \
    EVAL_STUB_SOLUTION="$TT/01-trivial-fix/solution" EVAL_STUB_PROBE="$probe" bash "$RUN" "$@"
}

# apply_solution <seed-copy-dir> <solution-dir>: overlay then honour .delete.
apply_solution() {
  cp -R "$2/." "$1/"
  rm -f "$1/.delete"
  if [ -f "$2/.delete" ]; then
    while IFS= read -r rel || [ -n "$rel" ]; do
      [ -n "$rel" ] || continue
      rm -rf -- "${1:?}/$rel"
    done < "$2/.delete"
  fi
}

# --- tasks ----------------------------------------------------------------------------------
IDS=""
n_ids=0
for d in "$TASKS"/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"
  IDS="$IDS ${d##*/}"
  n_ids=$((n_ids + 1))
done
cat_ids="$(sed -n 's/^- `\([0-9][0-9]-[a-z0-9-]*\)`:.*/\1/p' "$README" | sort | tr '\n' ' ')"
dir_ids="$(for i in $IDS; do echo "$i"; done | sort | tr '\n' ' ')"
if [ "$n_ids" -eq 10 ] && [ "$cat_ids" = "$dir_ids" ]; then
  ok "tasks/count"
else
  bad "tasks/count" "$n_ids task dirs [$dir_ids], README categories [$cat_ids], want 10 matching"
fi

# --- graders --------------------------------------------------------------------------------
mkdir -p "$ST/g"
for id in $IDS; do
  t="$TASKS/$id"
  gs="$ST/g/$id.seed"
  gp="$ST/g/$id.sol"
  mkdir -p "$gs" "$gp"
  cp -R "$t/seed/." "$gs/"
  cp -R "$t/seed/." "$gp/"
  apply_solution "$gp" "$t/solution"

  out="$(bash "$t/grade/grade.sh" "$gs" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qx 'GRADE fail'; then
    ok "grader/$id/fails-on-seed"
  else
    bad "grader/$id/fails-on-seed" "rc=$rc, last line '$(printf '%s\n' "$out" | tail -1)'"
  fi
  out="$(bash "$t/grade/grade.sh" "$gp" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx 'GRADE pass'; then
    ok "grader/$id/passes-on-solution"
  else
    bad "grader/$id/passes-on-solution" "rc=$rc, last line '$(printf '%s\n' "$out" | tail -1)'"
  fi
done

# --- runner fixtures ------------------------------------------------------------------------
mkdir -p "$ST/stub" "$ST/tt" "$ST/o"
STUBCP="$ST/stub/stub-cli.sh"
cp "$STUB" "$STUBCP"
TT="$ST/tt"
cp -R "$TASKS/01-trivial-fix" "$TT/01-trivial-fix"
T01=01-trivial-fix

# baseline solve
run_eval solve "$ST/o/bs.probe" --arm baseline --tasks "$T01" --runs 1 --out "$ST/o/bs" > "$ST/o/bs.log" 2>&1
bs_rc=$?
BSR="$ST/o/bs/results.jsonl"
expect_eq "runner/baseline-solve-exit" "$bs_rc" "0"
expect_eq "runner/baseline-solve-pass-true" "$(jf "$BSR" pass)" "true"

# baseline noop
run_eval noop "$ST/o/np.probe" --arm baseline --tasks "$T01" --runs 1 --out "$ST/o/np" > "$ST/o/np.log" 2>&1
NPR="$ST/o/np/results.jsonl"
expect_eq "runner/baseline-noop-pass-false" "$(jf "$NPR" pass)" "false"
expect_eq "runner/baseline-noop-changed-files-0" "$(jf "$NPR" changed_files)" "0"

# baseline solve row values
vals="$(for k in cli_exit timed_out cost_usd num_turns stop_reason arm label run; do jf "$BSR" "$k"; done | tr '\n' ' ')"
expect_eq "row/baseline-solve-values" "$vals" '0 false 0 1 "success" "baseline" "baseline" 1 '
cp_="$(jf "$BSR" checks_passed)"; ct_="$(jf "$BSR" checks_total)"; ch_="$(jf "$BSR" changed_files)"
if [ -n "$ct_" ] && [ "$ct_" != "0" ] && [ "$cp_" = "$ct_" ]; then ok "row/baseline-solve-checks-all-pass"; else bad "row/baseline-solve-checks-all-pass" "checks_passed=$cp_ checks_total=$ct_"; fi
if [ -n "$ch_" ] && [ "$ch_" != '"<missing>"' ] && [ "$ch_" -ge 1 ] 2>/dev/null; then ok "row/baseline-solve-changed-files"; else bad "row/baseline-solve-changed-files" "changed_files=$ch_"; fi
expect_eq "row/baseline-spawns-null" "$(jf "$BSR" spawns)" "null"

# row key order, from the README itself
want_keys="$(sed -n '/^## Result rows/,/^## report.sh/p' "$README" | sed -n 's/^[0-9][0-9]*\. `\([a-z_]*\)`.*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
n_want="$(printf '%s\n' "$want_keys" | wc -w | tr -d ' ')"
if [ "$n_want" -ne 18 ]; then
  bad "row/key-order" "README lists $n_want keys, want 18"
else
  expect_eq "row/key-order" "$(row_keys "$BSR")" "$want_keys"
fi

# probes: baseline
expect_eq "probe/baseline-grade-visible-no" "$(probe_val "$ST/o/bs.probe" grade_visible)" "no"
expect_eq "probe/baseline-prompt-has-feature-no" "$(probe_val "$ST/o/bs.probe" prompt_has_feature)" "no"

# kit solve (kept scratch)
run_eval solve "$ST/o/kit.probe" --arm kit --kit-src "$KIT_SRC" --tasks "$T01" --runs 1 --keep --out "$ST/o/kit" > "$ST/o/kit.log" 2>&1
kit_rc=$?
KR="$ST/o/kit/results.jsonl"
expect_eq "runner/kit-solve-exit" "$kit_rc" "0"
expect_eq "runner/kit-solve-pass-true" "$(jf "$KR" pass)" "true"
expect_eq "row/key-order-kit" "$(row_keys "$KR")" "$want_keys"
expect_eq "runner/kit-solve-spawns-0" "$(jf "$KR" spawns)" "0"
expect_eq "probe/kit-grade-visible-no" "$(probe_val "$ST/o/kit.probe" grade_visible)" "no"
expect_eq "probe/kit-prompt-has-feature-yes" "$(probe_val "$ST/o/kit.probe" prompt_has_feature)" "yes"
kch="$(jf "$KR" changed_files)"
if [ -n "$kch" ] && [ "$kch" -ge 1 ] 2>/dev/null; then ok "row/kit-solve-changed-files"; else bad "row/kit-solve-changed-files" "changed_files=$kch"; fi
run_eval noop "" --arm kit --kit-src "$KIT_SRC" --tasks "$T01" --runs 1 --out "$ST/o/kn" > "$ST/o/kn.log" 2>&1
expect_eq "runner/kit-noop-pass-false" "$(jf "$ST/o/kn/results.jsonl" pass)" "false"
expect_eq "row/kit-noop-changed-files-0" "$(jf "$ST/o/kn/results.jsonl" changed_files)" "0"
kept="$(sed -n 's/^scratch kept under: //p' "$ST/o/kit.log" | head -1)"
if [ -n "$kept" ] && [ -n "$(find "$kept" -path '*/.claude/agents/evaluator.md' -print -quit 2>/dev/null)" ]; then
  ok "kit/emit-holds-evaluator-agent"
else
  bad "kit/emit-holds-evaluator-agent" "kept='$kept', no .claude/agents/evaluator.md under it"
fi

# garbage
run_eval garbage "" --arm baseline --tasks "$T01" --runs 1 --out "$ST/o/gb" > "$ST/o/gb.log" 2>&1
gb_rc=$?
GBR="$ST/o/gb/results.jsonl"
expect_eq "runner/garbage-exit-0" "$gb_rc" "0"
expect_eq "runner/garbage-null-fields" "$(for k in cost_usd num_turns stop_reason; do jf "$GBR" "$k"; done | tr '\n' ' ')" "null null null "

# kit-src empty: exit 3, no row
mkdir -p "$ST/emptykit"
run_eval solve "" --arm kit --kit-src "$ST/emptykit" --tasks "$T01" --runs 1 --out "$ST/o/ek" > "$ST/o/ek.log" 2>&1
ek_rc=$?
expect_eq "runner/kit-src-empty-exit-3" "$ek_rc" "3"
expect_eq "runner/kit-src-empty-no-row" "$(nrows "$ST/o/ek/results.jsonl")" "0"

# sleep + timeout
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  run_eval sleep "" --arm baseline --label slow --tasks "$T01" --runs 1 --timeout 1 --out "$ST/o/sl" > "$ST/o/sl.log" 2>&1
  SLR="$ST/o/sl/results.jsonl"
  expect_eq "runner/sleep-timed-out-true" "$(jf "$SLR" timed_out)" "true"
else
  skipcase "runner/sleep-timed-out-true" "no timeout command"
fi

# 143 handling: a fast 143 is not a timeout, a 143 at or past --timeout is (timeout shim on PATH)
mkdir -p "$ST/shim-fast" "$ST/shim-slow"
printf '#!/bin/sh\nexit 143\n' > "$ST/shim-fast/timeout"
printf '#!/bin/sh\nsleep 1\nexit 143\n' > "$ST/shim-slow/timeout"
chmod +x "$ST/shim-fast/timeout" "$ST/shim-slow/timeout"
(PATH="$ST/shim-fast:$PATH"; run_eval noop "" --arm baseline --tasks "$T01" --runs 1 --timeout 30 --out "$ST/o/f143") > "$ST/o/f143.log" 2>&1
expect_eq "runner/exit-143-fast-not-timed-out" "$(jf "$ST/o/f143/results.jsonl" cli_exit)/$(jf "$ST/o/f143/results.jsonl" timed_out)" "143/false"
(PATH="$ST/shim-slow:$PATH"; run_eval noop "" --arm baseline --tasks "$T01" --runs 1 --timeout 1 --out "$ST/o/s143") > "$ST/o/s143.log" 2>&1
expect_eq "runner/exit-143-at-timeout-timed-out" "$(jf "$ST/o/s143/results.jsonl" cli_exit)/$(jf "$ST/o/s143/results.jsonl" timed_out)" "143/true"

# usage errors
run_eval noop "" --tasks "$T01" --runs 1 --out "$ST/o/u1" > "$ST/o/u1.log" 2>&1
expect_eq "usage/no-arm-exit-2" "$?" "2"
run_eval noop "" --arm both --tasks "$T01" --runs 1 --out "$ST/o/u2" > "$ST/o/u2.log" 2>&1
expect_eq "usage/bad-arm-exit-2" "$?" "2"
run_eval noop "" --arm baseline --tasks no-such-task --runs 1 --out "$ST/o/u3" > "$ST/o/u3.log" 2>&1
expect_eq "usage/unknown-task-exit-2" "$?" "2"
run_eval noop "" --arm baseline --tasks "$T01" --runs 0 --out "$ST/o/u4" > "$ST/o/u4.log" 2>&1
expect_eq "usage/runs-0-exit-2" "$?" "2"
run_eval noop "" --arm baseline --timeout 0 --out "$ST/o/u5" > "$ST/o/u5.log" 2>&1
expect_eq "usage/timeout-0-exit-2" "$?" "2"

# environment: the Claude session variables never reach the CLI
precheck="$(cd "$ST" && CLAUDECODE=1 EVAL_STUB_MODE=noop EVAL_STUB_PROBE="$ST/o/pre.probe" bash "$STUBCP" -p x >/dev/null 2>&1; probe_val "$ST/o/pre.probe" claude_env)"
expect_eq "probe/precondition-stub-sees-claudecode" "$precheck" "yes"
(export CLAUDECODE=1; run_eval noop "$ST/o/ce.probe" --arm baseline --tasks "$T01" --runs 1 --out "$ST/o/ce") > "$ST/o/ce.log" 2>&1
expect_eq "probe/claudecode-removed" "$(probe_val "$ST/o/ce.probe" claude_env)" "no"
(unset CLAUDECODE; export CLAUDE_CODE_SESSION_ID=x; run_eval noop "$ST/o/ci.probe" --arm baseline --tasks "$T01" --runs 1 --out "$ST/o/ci") > "$ST/o/ci.log" 2>&1
expect_eq "probe/session-id-removed" "$(probe_val "$ST/o/ci.probe" claude_env)" "no"

# stdin of the CLI is /dev/null
cat > "$ST/stub/dump-stdin.sh" <<'DUMP'
#!/bin/bash
readlink "/proc/$$/fd/0" > "$DUMP_FILE" 2>/dev/null
exit 0
DUMP
if [ -e /proc/self/fd/0 ]; then
  printf 'piped\n' | EVAL_CLI="bash $ST/stub/dump-stdin.sh" DUMP_FILE="$ST/o/stdin.txt" EVAL_TASKS_DIR="$TT" \
    bash "$RUN" --arm baseline --tasks "$T01" --runs 1 --out "$ST/o/in" > "$ST/o/in.log" 2>&1
  expect_eq "runner/cli-stdin-is-dev-null" "$(cat "$ST/o/stdin.txt" 2>/dev/null)" "/dev/null"
else
  skipcase "runner/cli-stdin-is-dev-null" "no /proc"
fi

# caller-repository isolation under an exported GIT_DIR
caller="$ST/caller"
mkdir -p "$caller"
git init -q "$caller" >/dev/null 2>&1
printf 'caller\n' > "$caller/f.txt"
git -C "$caller" add -A >/dev/null 2>&1
git -C "$caller" commit -q -m caller-base >/dev/null 2>&1
head_before="$(git -C "$caller" rev-parse HEAD 2>/dev/null)"
index_before="$(cksum < "$caller/.git/index")"
(export GIT_DIR="$caller/.git"; run_eval solve "" --arm baseline --tasks "$T01" --runs 1 --out "$ST/o/gd") > "$ST/o/gd.log" 2>&1
gd_rc=$?
head_after="$(git -C "$caller" rev-parse HEAD 2>/dev/null)"
index_after="$(cksum < "$caller/.git/index" 2>/dev/null)"
if [ -z "$head_before" ]; then
  bad "isolation/git-dir-caller-untouched" "could not build the caller repository"
elif [ "$gd_rc" -ne 0 ] || [ "$(jf "$ST/o/gd/results.jsonl" pass)" != "true" ]; then
  bad "isolation/git-dir-caller-untouched" "run under GIT_DIR: rc=$gd_rc pass=$(jf "$ST/o/gd/results.jsonl" pass)"
elif [ "$head_before" != "$head_after" ] || [ "$index_before" != "$index_after" ]; then
  bad "isolation/git-dir-caller-untouched" "caller HEAD $head_before -> $head_after, index $index_before -> $index_after"
else
  ok "isolation/git-dir-caller-untouched"
fi

# --- report.sh ------------------------------------------------------------------------------
if [ -d "$ST/o/sl" ]; then
  rep="$(bash "$REPORT" "$ST/o/bs" "$ST/o/kit" "$ST/o/sl" 2>&1)"; rep_rc=$?
else
  rep="$(bash "$REPORT" "$ST/o/bs" "$ST/o/kit" 2>&1)"; rep_rc=$?
fi
expect_eq "report/exit-0" "$rep_rc" "0"
if printf '%s\n' "$rep" | grep -q 'baseline pass' && printf '%s\n' "$rep" | grep -q 'kit pass'; then ok "report/table-both-labels"; else bad "report/table-both-labels" "no 'baseline pass' and 'kit pass' columns"; fi
if printf '%s\n' "$rep" | grep -q '^| Total |'; then ok "report/totals-row"; else bad "report/totals-row" "no '| Total |' row"; fi
if printf '%s\n' "$rep" | grep -qx 'vs baseline: kit wins 0, losses 0, ties 1'; then ok "report/win-loss-tie-kit"; else bad "report/win-loss-tie-kit" "no 'vs baseline: kit wins 0, losses 0, ties 1' line"; fi
if [ -d "$ST/o/sl" ]; then
  if printf '%s\n' "$rep" | grep -qx 'vs baseline: slow wins 0, losses 1, ties 0'; then ok "report/win-loss-tie-slow"; else bad "report/win-loss-tie-slow" "no 'vs baseline: slow wins 0, losses 1, ties 0' line"; fi
  if printf '%s\n' "$rep" | grep -qx 'note: 1 run(s) of slow stopped by budget or timeout'; then ok "report/budget-timeout-note"; else bad "report/budget-timeout-note" "no budget/timeout note line for slow"; fi
else
  skipcase "report/win-loss-tie-slow" "no timeout command"
  skipcase "report/budget-timeout-note" "no timeout command"
fi
if printf '%s\n' "$rep" | grep -qx 'warning: 1 kit run(s) with spawns 0 (the kit may not have run)'; then ok "report/spawns-0-warning"; else bad "report/spawns-0-warning" "no spawns-0 warning line"; fi
if printf '%s\n' "$rep" | grep -q '^caveat: at 10 tasks × 3 runs, differences below roughly 25 percentage points are within noise'; then ok "report/caveat"; else bad "report/caveat" "no caveat line"; fi
mkdir -p "$ST/emptyreport"
bash "$REPORT" "$ST/emptyreport" > "$ST/o/er.log" 2>&1
expect_eq "report/empty-dir-exit-2" "$?" "2"

# --- tree -----------------------------------------------------------------------------------
off="$(tree_offenders "$HERE")"
if [ -z "$off" ]; then ok "tree/no-skill-md-or-agent-folders"; else bad "tree/no-skill-md-or-agent-folders" "$(printf '%s\n' "$off" | head -3 | tr '\n' ' ')"; fi
mkdir -p "$ST/plant/sub/.claude"
: > "$ST/plant/sub/SKILL.md"
if [ "$(tree_offenders "$ST/plant" | wc -l | tr -d ' ')" = "2" ]; then ok "tree/detector-finds-planted-offenders"; else bad "tree/detector-finds-planted-offenders" "detector missed a planted SKILL.md or .claude"; fi
pyc_after="$(pycache_count)"
if [ -z "$(find "$HERE" -name __pycache__ -print -quit)" ] && [ "$pyc_after" = "$PYCACHE_BEFORE" ]; then
  ok "tree/no-pycache-left"
else
  bad "tree/no-pycache-left" "repo __pycache__ dirs $PYCACHE_BEFORE -> $pyc_after, or one under $HERE"
fi

echo "PASS: $pass FAIL: $fail SKIP: $skip"
[ "$fail" -eq 0 ]
