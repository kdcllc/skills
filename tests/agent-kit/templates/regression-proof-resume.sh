#!/usr/bin/env bash
# Pins tasks 01–05 resume/progress/regression-proof template changes (canonical + emit).
# Self-install-independent — no network, no LLM, scratch emit roots only.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"

TEMPLATES="$KIT/templates"
TEST_LADDER="$TEMPLATES/skills/test-ladder/SKILL.template.md"
TEST_WRITER="$TEMPLATES/agents/test-writer.md"
IMPLEMENTER="$TEMPLATES/agents/implementer.md"
EVALUATOR="$TEMPLATES/agents/evaluator.md"
TASK_CRITERIA="$TEMPLATES/skills/task-criteria/SKILL.template.md"
FEATURE_SKILL="$TEMPLATES/skills/feature/SKILL.template.md"
PROGRESS_TMPL="$TEMPLATES/skills/feature/templates/progress.md"
RESUME_REF="$TEMPLATES/skills/feature/reference/resume.md"
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"
MEMORY_README="$TEMPLATES/memory/README.md"
BOOTSTRAP_IDS="$KIT/reference/bootstrap-ids.md"

FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

FEATURE_PROGRESS_LINE='Rewrite `_memory/work/goals/[goal]/progress.md` from `templates/progress.md` after each phase, verdict and user decision; resume goals per `reference/resume.md`.'

FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akrpr.XXXXXX")" || exit 1
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

count_fixed() {
  local f="$1" needle="$2" n
  [[ -f "$f" ]] || { echo 0; return; }
  n="$(grep -cF -- "$needle" "$f" 2>/dev/null || true)"
  [[ -n "$n" ]] || n=0
  echo "$n"
}

assert_anchor() {
  local f="$1" needle="$2" want="$3" got
  got="$(count_fixed "$f" "$needle")"
  [[ "$got" == "$want" ]]
}

regression_proof_section() {
  awk '/^## Regression proof$/{f=1;next} /^## /{f=0} f' "$TEST_LADDER"
}

task_criteria_sec4() {
  awk '/^## 4\. Test Evidence$/{f=1;next} /^## /{f=0} f' "$TASK_CRITERIA"
}

evaluator_what_to_eval() {
  awk '/^## What to evaluate$/{f=1;next} /^## /{f=0} f' "$EVALUATOR"
}

orch_workflow_note() {
  awk '/^### Workflow State Tracking$/{f=1;next} f&&/^```/{exit} f' "$ORCH_TEMPLATE"
}

section_phrases_ok() { # section_text phrase...
  local sec="$1" p
  shift
  for p in "$@"; do
    [[ "$sec" == *"$p"* ]] || return 1
  done
  return 0
}

report_order_ok() { # file after before
  local f="$1" after="$2" before="$3"
  awk -v a="$after" -v b="$before" '
    $0 ~ ("^" a "$") { va=NR }
    $0 ~ ("^" b "$") { vb=NR }
    END { exit !(va>0 && vb>0 && va<vb) }
  ' "$f"
}

answers_kg_mode() { # outfile research loop kg_mode
  local out="$1" research="$2" loop="$3" mode="$4" rj lj
  [[ "$research" == 1 ]] && rj=true || rj=false
  [[ "$loop" == 1 ]] && lj=true || lj=false
  jq --argjson r "$rj" --argjson l "$lj" '
    .flags.research = $r |
    .flags.loop = $l
  ' "$FIXTURE" > "${out}.tmp"
  case "$mode" in
    absent) jq 'del(.flags.kit_guard)' "${out}.tmp" > "$out" ;;
    false)  jq '.flags.kit_guard = false' "${out}.tmp" > "$out" ;;
    true)   jq '.flags.kit_guard = true' "${out}.tmp" > "$out" ;;
    *) return 1 ;;
  esac
  rm -f "${out}.tmp"
}

check_a_test_ladder() {
  local ok=1 sec
  awk '/^## Rung 1 — New tests$/{a=NR} /^## Regression proof$/{b=NR;n++} /^## Rung 2 — Impacted tests$/{c=NR} END{exit !(n==1 && a<b && b<c)}' "$TEST_LADDER" || ok=0
  sec="$(regression_proof_section)"
  section_phrases_ok "$sec" \
    'guarding test' 'bug fix' 'behavior change' 'scratch copy' 'without `.git`' 'cmp' \
    'injected edit' 'FAIL line' 'PASS' 'method' 'file:line' \
    'vacuous' 'unbound' 'syntax error' 'echo rc=$?' \
    'never delete a definition' 'equivalent mutation' 'exactly at the boundary' \
    'precondition' 'time zone' 'layer where the regression' 'never committed' \
    || ok=0
  [[ $ok -eq 1 ]]
}

check_b_writers() {
  local ok=1
  assert_anchor "$TEST_WRITER" '- **Prove guarding tests bite.**' 1 || ok=0
  assert_anchor "$IMPLEMENTER" '- **Prove guarding tests bite.**' 1 || ok=0
  grep -c '^### Regression proofs$' "$TEST_WRITER" | grep -qx 1 || ok=0
  grep -c '^### Regression proofs$' "$IMPLEMENTER" | grep -qx 1 || ok=0
  report_order_ok "$TEST_WRITER" '### Verification' '### Regression proofs' || ok=0
  report_order_ok "$TEST_WRITER" '### Regression proofs' '### Gaps' || ok=0
  report_order_ok "$IMPLEMENTER" '### Verification' '### Regression proofs' || ok=0
  report_order_ok "$IMPLEMENTER" '### Regression proofs' '### Notes for the evaluator' || ok=0
  [[ $ok -eq 1 ]]
}

check_c_gates() {
  local ok=1 s
  s="$(task_criteria_sec4)"
  section_phrases_ok "$s" \
    'guarding test' 'Regression proof' 'NEEDS FIXES' 'F3' 'scratch copy' 'terminal' 'eval_depth: light' \
    || ok=0
  s="$(evaluator_what_to_eval)"
  section_phrases_ok "$s" 'Regression proof' 'scratch copy' 'terminal' 'Contradicted' || ok=0
  [[ $ok -eq 1 ]]
}

check_d_single_home() {
  ! grep -lE 'equivalent mutation|time zone' "$TEST_WRITER" "$IMPLEMENTER" "$EVALUATOR" "$TASK_CRITERIA" >/dev/null 2>&1
}

check_e_feature_and_compaction() {
  local ok=1 n
  n="$(awk '/<!-- IF /{d++} /<!-- ENDIF /{d--} d==0 && /_memory\/work\/goals\/\[goal\]\/progress\.md/ && /templates\/progress\.md/ && /reference\/resume\.md/{n++} END{print n+0}' "$FEATURE_SKILL")"
  [[ "$n" == 1 ]] || ok=0
  assert_anchor "$FEATURE_SKILL" 'Update ORCHESTRATION.md Orchestration Progress' 0 || ok=0
  [[ "$(awk '/^## Phase 2/{f=1} /^## Phase 3/{f=0} f' "$FEATURE_SKILL" | grep -c '^\*\*Unfinished goals:\*\* offer per `reference/resume.md`')" == 1 ]] || ok=0
  [[ "$(awk '/^## Phase 4/{f=1} /^## Phase 5/{f=0} f' "$FEATURE_SKILL" | grep -c '^3\. .*per acceptance-criterion command and one regression proof, attach output')" == 1 ]] || ok=0
  assert_anchor "$ORCH_TEMPLATE" "resume per the feature skill's \`reference/resume.md\`, from \`progress.md\`" 1 || ok=0
  assert_anchor "$ORCH_TEMPLATE" 'past ~60% of its context window' 1 || ok=0
  assert_anchor "$ORCH_TEMPLATE" 'resume from `goal.md` and the orchestration log' 0 || ok=0
  [[ $ok -eq 1 ]]
}

check_f_progress_template() {
  local ok=1
  head -1 "$PROGRESS_TMPL" | grep -qxF '# Progress: [goal]' || ok=0
  [[ "$(grep -c '^updated: \|^status: active | waiting-on-user | blocked | done$' "$PROGRESS_TMPL")" == 2 ]] || ok=0
  sed -n '4p' "$PROGRESS_TMPL" | grep -q '^phase: ' || ok=0
  diff -q <(grep -n '^## ' "$PROGRESS_TMPL" | cut -d: -f2-) <(printf '%s\n' \
    '## Next step' '## Git' '## Tasks' '## In flight' '## Waiting on user' \
    '## Deviations and exclusions' '## Orchestration Progress: [Goal Name]') >/dev/null || ok=0
  assert_anchor "$PROGRESS_TMPL" '| Task | Group | Cycle | Verdicts | Final | Last spawn |' 1 || ok=0
  diff -q \
    <(awk '/^## Orchestration Progress: \[Goal Name\]$/{f=1;next} f&&/^```/{exit} f' "$ORCH_TEMPLATE" | grep -E '^(### Phase|- \[ \])') \
    <(awk '/^## Orchestration Progress: \[Goal Name\]$/{f=1;next} f' "$PROGRESS_TMPL" | grep -E '^(### Phase|- \[ \])') \
    >/dev/null || ok=0
  [[ "$(grep -v '^[[:space:]]*$' "$PROGRESS_TMPL" | tail -n 1)" == 'See ORCHESTRATION.md § Forge adapter (Phase 7 delivery).' ]] || ok=0
  [[ $ok -eq 1 ]]
}

check_g_resume_reference() {
  local ok=1 p n
  diff -q <(grep -n '^## ' "$RESUME_REF" | cut -d: -f2-) <(printf '%s\n' \
    '## When progress.md is written' '## Unfinished goals (Phase 2)' '## Resume procedure' \
    '## Missing checkpoint' '## Scope') >/dev/null || ok=0
  n="$(awk '/^3\. \*\*Repository check\.\*\*/{f=1;next} /^4\. /{f=0} f' "$RESUME_REF" | grep -c '^   - ' || true)"
  [[ -n "$n" && "$n" -ge 8 ]] || ok=0
  n="$(awk '/^3\. \*\*Repository check\.\*\*/{f=1;next} /^4\. /{f=0} f' "$RESUME_REF" | grep -c 'HEAD at this write' || true)"
  [[ -n "$n" && "$n" -ge 1 ]] || ok=0
  n="$(grep -c 'phase:' "$RESUME_REF" || true)"
  [[ -n "$n" && "$n" -ge 3 ]] || ok=0
  for p in 'git fetch' 'merged' 'squash' 'ancestor' 'Never edit or delete ledger' 'stops the resume' \
    'RESUMED:' 'silent-success' 'never resume automatically' 'driver-dispatched' 'auto-loop' \
    'before Phase 4' 'is-ancestor' 'not recorded until Phase 4'; do
    grep -qiF -- "$p" "$RESUME_REF" || ok=0
  done
  [[ $ok -eq 1 ]]
}

check_h_orchestration() {
  local ok=1 note
  note="$(orch_workflow_note)"
  section_phrases_ok "$note" 'progress.md' 'templates/progress.md' 'reference/resume.md' \
    'and replaces the Phase 4 table below with its `## Tasks` table' || ok=0
  [[ "$note" != *'<!-- IF kit_guard -->'* ]] || ok=0
  [[ "$(grep -cF 'On Codex-only installs, which ship no kit skills tree, write `progress.md` with the fields this section lists, and resume from `progress.md`, `goal.md` and the orchestration log after checking the branch and HEAD against `progress.md`.' <<<"$note")" == 1 ]] || ok=0
  assert_anchor "$ORCH_TEMPLATE" 'memory-capture.md,resume.md,goal-revisions.md,corrective-tasks.md,fix-cycles.md}' 4 || ok=0
  assert_anchor "$ORCH_TEMPLATE" 'templates/{goal.md,task.md,progress.md}' 4 || ok=0
  assert_anchor "$ORCH_TEMPLATE" '_memory/work/goals/<goal>/progress.md  #' 4 || ok=0
  grep -F '| **Context fatigue** |' "$ORCH_TEMPLATE" | grep -qF 'progress.md' || ok=0
  [[ $ok -eq 1 ]]
}

check_i_memory_readme() {
  sed -n '19p' "$MEMORY_README" | grep -qF 'NN-task.md, progress.md, orchestration-log.md'
}

check_j_bootstrap_ids() {
  local ok=1 stale id loc f n
  while read -r id loc; do
    [[ -z "$id" ]] && continue
    f="$TEMPLATES/${loc%:*}"
    n="${loc##*:}"
    sed -n "${n}p" "$f" | grep -qF "BOOTSTRAP[$id]" || { stale=1; break; }
  done < <(awk -F'|' '/^\| [a-z0-9-]+ \| [^|`]*:[0-9]+/ {
    id=$2; loc=$3; gsub(/^ +| +$/,"",id); gsub(/^ +/,"",loc); split(loc,a," "); print id" "a[1]
  }' "$BOOTSTRAP_IDS")
  [[ "${stale:-0}" -eq 0 ]] || ok=0
  grep '^| kit_guard |' "$BOOTSTRAP_IDS" | grep -qE 'Workflow State Tracking note|progress location' && ok=0
  grep '^| kit_guard |' "$BOOTSTRAP_IDS" | grep -qF 'Repository safety item 4' || ok=0
  grep '^| kit_guard |' "$BOOTSTRAP_IDS" | grep -qF 'Phase 5 kit-file gate' || ok=0
  grep '^| kit_guard |' "$BOOTSTRAP_IDS" | grep -qF 'File Locations trees' || ok=0
  [[ $ok -eq 1 ]]
}

emit_skill_roots_for_answers() { # answers.json → newline-separated inst dirs (.claude, …)
  local ans="$1" h
  while read -r h; do
    case "$h" in
      claude-code) printf '%s\n' .claude ;;
      cursor)      printf '%s\n' .cursor ;;
      copilot)     printf '%s\n' .github ;;
      codex)       ;;
    esac
  done < <(jq -r '.harnesses[]' "$ans")
}

assert_emit_resume_bundle() { # emit_root inst_label
  local emit_root="$1" inst="$2" base
  base="$emit_root/$inst/skills"
  [[ -f "$base/feature/reference/resume.md" ]] || return 1
  [[ -f "$base/feature/templates/progress.md" ]] || return 1
  grep -qF '## Regression proof' "$base/test-ladder/SKILL.md" || return 1
  grep -qF "$FEATURE_PROGRESS_LINE" "$base/feature/SKILL.md" || return 1
  return 0
}

check_k_emitted_install() {
  local ans_on ans_off root_on root_off inst had_skills=0
  alloc_path ans-on
  answers_kg_mode "$EMIT_ALLOC_PATH" 1 1 true || return 1
  ans_on="$EMIT_ALLOC_PATH"
  alloc_path ans-off
  answers_kg_mode "$EMIT_ALLOC_PATH" 1 1 absent || return 1
  ans_off="$EMIT_ALLOC_PATH"
  alloc_root; root_on="$EMIT_ALLOC_PATH"
  emit_cache_copy "$root_on" "$ans_on" || return 1
  alloc_root; root_off="$EMIT_ALLOC_PATH"
  emit_cache_copy "$root_off" "$ans_off" || return 1

  while IFS= read -r inst; do
    [[ -z "$inst" ]] && continue
    had_skills=1
    assert_emit_resume_bundle "$root_on" "$inst" || return 1
    assert_emit_resume_bundle "$root_off" "$inst" || return 1
  done < <(emit_skill_roots_for_answers "$ans_on")

  [[ "$had_skills" -eq 1 ]] || return 2
  return 0
}

run_letter() {
  local letter="$1" fn="$2" title="$3"
  if [[ "$letter" == k && "$HAVE_JQ" -ne 1 ]]; then
    report SKIP "($letter) $title" "jq not on PATH"
    return
  fi
  if [[ "$letter" == k ]]; then
    local rc=0
    "$fn" || rc=$?
    if [[ "$rc" -eq 2 ]]; then
      report SKIP "($letter) $title" "Codex harness emits no skills tree"
      return
    fi
    if [[ "$rc" -eq 0 ]]; then
      report PASS "($letter) $title"
    else
      report FAIL "($letter) $title"
    fi
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

run_letter a check_a_test_ladder 'test-ladder: Regression proof section and quality rules'
run_letter b check_b_writers 'test-writer + implementer: prove bite bullet and report subsection'
run_letter c check_c_gates 'task-criteria §4 + evaluator: proof gates'
run_letter d check_d_single_home 'single home: no equivalent mutation or time zone in four files'
run_letter e check_e_feature_and_compaction 'feature skill progress/resume wiring + ORCHESTRATION compaction'
run_letter f check_f_progress_template 'progress.md template parity with ORCHESTRATION checklist'
run_letter g check_g_resume_reference 'resume.md sections and safety phrases'
run_letter h check_h_orchestration 'ORCHESTRATION: unconditional note, trees, File Locations, context fatigue'
run_letter i check_i_memory_readme 'memory README goal folder lists progress.md'
run_letter j check_j_bootstrap_ids 'bootstrap-ids pins and kit_guard row'
run_letter k check_k_emitted_install 'emit: resume/progress/test-ladder/feature progress (kg on/off)'

emit_cache_verify

echo
echo "=== regression-proof-resume summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
