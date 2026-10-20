#!/usr/bin/env bash
# Regression guard for feature-skill feedback fixes (tasks 01–03): locks goal/task
# criteria, feature references, ORCHESTRATION wiring, frozen W1–W5 wording, and
# emitted presence of goal-revisions.md + corrective-tasks.md. Tracked,
# self-install-independent — no network, no LLM.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
GOAL_CRITERIA="$TEMPLATES/skills/goal-criteria/SKILL.template.md"
TASK_CRITERIA="$TEMPLATES/skills/task-criteria/SKILL.template.md"
EVALUATOR="$TEMPLATES/agents/evaluator.md"
PREFLIGHT_REF="$TEMPLATES/skills/feature/reference/preflight.md"
GOAL_REVISIONS="$TEMPLATES/skills/feature/reference/goal-revisions.md"
CORRECTIVE_TASKS="$TEMPLATES/skills/feature/reference/corrective-tasks.md"
LADDER_REF="$TEMPLATES/skills/feature/reference/continuation-ladder.md"
FEATURE_SKILL="$TEMPLATES/skills/feature/SKILL.template.md"
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akff.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"
# shellcheck source=../lib/emit-cache.sh
. "$HERE/../lib/emit-cache.sh"

pass=0
fail=0
skip=0

if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; else HAVE_JQ=0; fi

_suite_cleanup() {
  rm -rf "$FIXTURE_TMPDIR"
  emit_cache_cleanup
}
trap _suite_cleanup EXIT

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

alloc_root() {
  EMIT_ALLOC_PATH="$(mktemp -d "$FIXTURE_TMPDIR/root.XXXXXX")" || exit 1
  assert_fixture_root "$EMIT_ALLOC_PATH" || exit 1
}

alloc_path() {
  EMIT_ALLOC_PATH="$(mktemp "$FIXTURE_TMPDIR/${1}.XXXXXX")"
}

run_emit_sh() { # root [emit args...]
  assert_fixture_root "$1" || exit 1
  bash "$EMIT_SH" --root "$1" --kit "$KIT" "${@:2}"
}

# grep -cF with empty needle returns 1; treat missing file as 0.
count_fixed() {
  local f="$1" needle="$2" n
  [[ -f "$f" ]] || { echo 0; return; }
  n="$(grep -cF -- "$needle" "$f" 2>/dev/null || true)"
  [[ -n "$n" ]] || n=0
  echo "$n"
}

assert_anchor() { # assert_anchor <file> <needle> <want> → 0 if count == want
  local f="$1" needle="$2" want="$3" got
  got="$(count_fixed "$f" "$needle")"
  [[ "$got" == "$want" ]]
}

read -r -d '' FROZEN_W1 <<'EOF' || true
A criterion is defective when it is vacuous (it cannot fail), blind (it cannot see the change it checks), or mutually unsatisfiable with another criterion of the same task.
EOF
read -r -d '' FROZEN_W2 <<'EOF' || true
`criteria-defect` stops fix cycles at detection on any cycle: with `ladder: auto` run rung 5 arbitration now; with `ladder: escalate` escalate with arbitration offered as option 1.
EOF
read -r -d '' FROZEN_W3 <<'EOF' || true
Early arbitration costs no implementation attempt; criteria-defective, or any arbiter/primary disagreement, escalates to the user, a criterion correction the user approves is a criterion-correction amendment, and a criterion the user upholds resumes the task at its next fix cycle.
EOF
read -r -d '' FROZEN_W4 <<'EOF' || true
 A criterion that requires writing outside the task's `writes` is an ownership gap, not a criteria defect: the orchestrator re-plans ownership as an amendment.
EOF
read -r -d '' FROZEN_W5 <<'EOF' || true
Material amendments re-run pre-flight and the full Phase 3 evaluation with a fresh evaluator and reset the cycle count; additive amendments and criterion corrections run pre-flight checks 1, 2 and 5 on the changed tasks, then a targeted evaluation.
EOF

check_a() {
  local f="$GOAL_CRITERIA" ok=1
  assert_anchor "$f" '_memory/work/goals/<goal>/criteria-evidence.md' 1 || ok=0
  assert_anchor "$f" 'also shows a **true negative** (passes on the correct shape) and a **true positive**' 1 || ok=0
  assert_anchor "$f" 'Criteria within one task are checked pairwise for **mutual satisfiability**' 1 || ok=0
  assert_anchor "$f" 'uses `--untracked-files=all`' 1 || ok=0
  [[ $ok -eq 1 ]]
}

check_b() {
  local f="$GOAL_CRITERIA" ok=1
  assert_anchor "$f" '`_memory/work/goals/<goal>/reference-sweep.md` exists, lists the exact search commands (exact-word and derived-identifier searches)' 1 || ok=0
  assert_anchor "$f" 'A corrective task named `NN<letter>-<name>.md`' 1 || ok=0
  assert_anchor "$f" 'After any renumbering the evaluator checks `xref-audit.md` exists' 1 || ok=0
  [[ $ok -eq 1 ]]
}

check_c() {
  local ok=1
  assert_anchor "$TASK_CRITERIA" 'route to arbitration (ladder rung 5)' 1 || ok=0
  assert_anchor "$EVALUATOR" 'review those passages adversarially first' 1 || ok=0
  assert_anchor "$EVALUATOR" 'Phase 3 attempt 3 is a fresh, full goal' 1 || ok=0
  assert_anchor "$TASK_CRITERIA" "$FROZEN_W2" 1 || ok=0
  assert_anchor "$TASK_CRITERIA" 'git status --porcelain --untracked-files=all' 1 || ok=0
  [[ $ok -eq 1 ]]
}

check_d() {
  local f="$PREFLIGHT_REF" ok=1
  assert_anchor "$f" '### 1. Acceptance criteria and paths' 1 || ok=0
  assert_anchor "$f" '### 2. Missed callers' 1 || ok=0
  assert_anchor "$f" '### 3. Scope drift' 1 || ok=0
  assert_anchor "$f" '### 4. Default-value semantics' 1 || ok=0
  assert_anchor "$f" '### 5. Stated facts' 1 || ok=0
  assert_anchor "$f" 'nullability' 1 || ok=0
  [[ $ok -eq 1 ]]
}

check_e() {
  local ok=1
  assert_anchor "$GOAL_REVISIONS" '- **material** — changes Success Criteria or a Phase 1 decision, renumbers tasks, or' 1 || ok=0
  assert_anchor "$GOAL_REVISIONS" '- **additive** — adds tasks without renumbering (including corrective tasks and the' 1 || ok=0
  assert_anchor "$GOAL_REVISIONS" 'Fresh `evaluator` spawn pinned to `{{MODEL_FRONTIER_ALT_FAMILY}}`' 1 || ok=0
  assert_anchor "$GOAL_REVISIONS" 'Write results to `_memory/work/goals/<goal>/xref-audit.md`' 1 || ok=0
  assert_anchor "$GOAL_REVISIONS" "rg -o '\b[0-9]{2}[a-z]?-[a-z][a-z0-9-]*'" 1 || ok=0
  assert_anchor "$CORRECTIVE_TASKS" 'Create `NN<letter>-<name>.md`' 1 || ok=0
  assert_anchor "$CORRECTIVE_TASKS" 'Set `depends_on` to the task whose files it fixes.' 1 || ok=0
  assert_anchor "$CORRECTIVE_TASKS" 'then re-check write-set disjointness against every remaining task' 1 || ok=0
  [[ $ok -eq 1 ]]
}

check_f() {
  assert_anchor "$LADDER_REF" '## Early `criteria-defect` routing (detection)' 1
}

check_g() {
  local ok=1 sz
  assert_anchor "$FEATURE_SKILL" 'reference/corrective-tasks.md' 1 || ok=0
  assert_anchor "$FEATURE_SKILL" '`reference/goal-revisions.md` governs re-checks and post-PASS amendments' 1 || ok=0
  assert_anchor "$FEATURE_SKILL" 'route at detection per `reference/continuation-ladder.md`' 1 || ok=0
  assert_anchor "$FEATURE_SKILL" "[the task's \`writes\` block copied verbatim" 1 || ok=0
  sz="$(wc -c < "$FEATURE_SKILL" | tr -d ' ')"
  [[ "$sz" -le 11264 ]] || ok=0
  [[ $ok -eq 1 ]]
}

orch_repo_safety_item2() {
  awk '/^2\. \*\*Post-spawn repository check\.\*\*/{p=1;next} p&&/^3\. /{exit} p' "$ORCH_TEMPLATE"
}

check_h() {
  local ok=1 sec tree_count bad
  assert_anchor "$ORCH_TEMPLATE" 'unfenced paths the spawn must not touch' 1 || ok=0
  assert_anchor "$ORCH_TEMPLATE" 'main session=<harness-reported %|unknown>' 1 || ok=0
  assert_anchor "$ORCH_TEMPLATE" 'past ~60% of its context window' 1 || ok=0
  tree_count="$(grep -cF 'goal-revisions.md,corrective-tasks.md' "$ORCH_TEMPLATE" 2>/dev/null || true)"
  [[ "$tree_count" == 4 ]] || ok=0
  sec="$(orch_repo_safety_item2)"
  while IFS= read -r bad; do
    [[ -z "$bad" ]] && continue
    if [[ "$bad" == *'git status --porcelain'* ]] \
       && [[ "$bad" != *'--untracked-files=all'* ]]; then
      ok=0
    fi
  done <<< "$(grep -F 'git status --porcelain' <<<"$sec" || true)"
  [[ $ok -eq 1 ]]
}

check_j() {
  local ok=1 f
  for f in "$TASK_CRITERIA" "$EVALUATOR"; do
    assert_anchor "$f" "$FROZEN_W1" 1 || ok=0
  done
  for f in "$TASK_CRITERIA" "$LADDER_REF" "$ORCH_TEMPLATE"; do
    assert_anchor "$f" "$FROZEN_W2" 1 || ok=0
  done
  for f in "$LADDER_REF" "$EVALUATOR"; do
    assert_anchor "$f" "$FROZEN_W3" 1 || ok=0
  done
  for f in "$TASK_CRITERIA" "$GOAL_CRITERIA"; do
    assert_anchor "$f" "$FROZEN_W4" 1 || ok=0
  done
  for f in "$GOAL_REVISIONS" "$GOAL_CRITERIA"; do
    assert_anchor "$f" "$FROZEN_W5" 1 || ok=0
  done
  [[ $ok -eq 1 ]]
}

answers_for_emit() { # outfile
  jq '
    .harnesses = ["claude-code", "cursor"] |
    .primary = "claude-code" |
    .flags.research = false |
    .flags.loop = false
  ' "$FIXTURE" > "$1"
}

check_i() {
  local root ans path
  alloc_path ansfile
  answers_for_emit "$EMIT_ALLOC_PATH"
  ans="$EMIT_ALLOC_PATH"
  alloc_root
  root="$EMIT_ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  for path in \
    .claude/skills/feature/reference/goal-revisions.md \
    .claude/skills/feature/reference/corrective-tasks.md \
    .cursor/skills/feature/reference/goal-revisions.md \
    .cursor/skills/feature/reference/corrective-tasks.md; do
    [[ -f "$root/$path" ]] || return 1
    if grep -qE '\{\{[A-Z_]+\}\}|BOOTSTRAP:' "$root/$path" 2>/dev/null; then
      return 1
    fi
  done
  return 0
}

run_letter() {
  local letter="$1" fn="$2" title="$3"
  if [[ "$letter" == i && "$HAVE_JQ" -ne 1 ]]; then
    report SKIP "($letter) $title" "jq not on PATH"
    return
  fi
  if "$fn"; then
    report PASS "($letter) $title"
  else
    report FAIL "($letter) $title"
  fi
}

PAR_REPORT_FAIL="report"
emit_cache_init

run_letter a check_a 'goal-criteria: criteria-evidence, TN/TP, mutual satisfiability, untracked-files=all'
run_letter b check_b 'goal-criteria: reference-sweep, corrective-task clause, xref-audit'
run_letter c check_c 'task-criteria + evaluator: criteria-defect at detection, adversarial re-check, attempt 3'
run_letter d check_d 'preflight.md: check 5 Stated facts + nullability'
run_letter e check_e 'goal-revisions + corrective-tasks reference anchors'
run_letter f check_f 'continuation-ladder: criteria-defect at-detection section'
run_letter g check_g 'feature SKILL: new reference pointers, criteria-defect, write fence, size ≤11264'
run_letter h check_h 'ORCHESTRATION: repo safety item 2, hash baseline, session note, 60%, tree ×4'
run_letter j check_j 'frozen wording W1–W5 byte-identical in listed files'
run_letter i check_i 'emit: goal-revisions + corrective-tasks under .claude and .cursor feature/reference'

emit_cache_verify

echo
echo "=== feature-feedback summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
