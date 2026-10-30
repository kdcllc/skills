#!/usr/bin/env bash
# Regression guard for fix-cycle provenance (tasks 01–03): locks evaluator/diagnostician
# provenance contracts, task-criteria and fix-cycles reference wording, continuation-ladder
# drift trigger, feature-skill § Provenance, ORCHESTRATION mirror text, fresh emit copies,
# and in-suite mutation proofs on copied templates. Goal release-backlog, task 06: the
# fix-cycles heading is exactly `## Provenance` and its opening paragraph states both scopes.
# Tracked, self-install-independent — no network, no LLM.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
EVALUATOR="$TEMPLATES/agents/evaluator.md"
DIAGNOSTICIAN="$TEMPLATES/agents/diagnostician.md"
TASK_CRITERIA="$TEMPLATES/skills/task-criteria/SKILL.template.md"
FIX_CYCLES_REF="$TEMPLATES/skills/feature/reference/fix-cycles.md"
LADDER_REF="$TEMPLATES/skills/feature/reference/continuation-ladder.md"
FEATURE_SKILL="$TEMPLATES/skills/feature/SKILL.template.md"
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akfcp.XXXXXX")" || exit 1
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

count_fixed() { # count_fixed <file> <needle> → line count (0 if missing)
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

assert_ge() { # assert_ge <file> <needle> <min> → 0 if count >= min
  local f="$1" needle="$2" min="$3" got
  got="$(count_fixed "$f" "$needle")"
  [[ "${got:-0}" -ge "$min" ]]
}

task_criteria_provenance_section() {
  awk '/^## Provenance tags \(/{p=1;next} p&&/^## /{exit} p' "$1"
}

count_line() { # count_line <file> <exact line> → lines equal to it (0 if missing)
  local f="$1" line="$2" n
  [[ -f "$f" ]] || { echo 0; return; }
  n="$(grep -cxF -- "$line" "$f" 2>/dev/null || true)"
  [[ -n "$n" ]] || n=0
  echo "$n"
}

assert_line() { # assert_line <file> <exact line> <want> → 0 if the count == want
  local got
  got="$(count_line "$1" "$2")"
  [[ "$got" == "$3" ]]
}

fix_cycles_provenance_section() {
  awk '/^## Provenance$/{p=1;next} p&&/^## /{exit} p' "$1"
}

# The section's opening paragraph (its first sentence states the scope of the snapshot and the tags).
fix_cycles_provenance_scope() {
  fix_cycles_provenance_section "$1" | awk 'NF{p=1} p&&!NF{exit} p'
}

fix_cycles_cycle3_section() {
  awk '/^## On cycle-3 exhaustion/{p=1;next} p&&/^## /{exit} p' "$1"
}

orch_phase5_paragraph() {
  awk '/^\*\*Phase 5 — Final audit/{p=1} p&&/^\*\*Phase 6/{exit} p' "$1"
}

evaluator_trigger_paragraph() {
  awk '/^\*\*Trigger\*\* — Ladder rung 5/{p=1} p&&/^$/{exit} p' "$1"
}

emit_file_clean() { # no unresolved {{TOK}} or BOOTSTRAP[
  local f="$1"
  [[ -f "$f" ]] || return 1
  ! grep -qE '\{\{[A-Z_]+\}\}|BOOTSTRAP\[' "$f" 2>/dev/null
}

check_canonical_evaluator() {
  local f="$1" sec ok=1 n
  [[ -f "$f" ]] || return 1
  assert_anchor "$f" '[line-patch|structural] [carried|regression|new]' 1 || ok=0
  assert_anchor "$f" '**Provenance tags** — ' 1 || ok=0
  assert_anchor "$f" 'exactly one trailing tag' 0 || ok=0
  assert_ge "$f" 'directly before the kind tag' 1 || ok=0
  sec="$(evaluator_trigger_paragraph "$f")"
  for needle in 'drift trigger' '≥ 2 `[new]` items'; do
    n="$(printf '%s\n' "$sec" | grep -cF -- "$needle" 2>/dev/null || true)"
    [[ "${n:-0}" -ge 1 ]] || ok=0
  done
  [[ $ok -eq 1 ]]
}

check_canonical_task_criteria() {
  local f="$1" sec ok=1 n
  [[ -f "$f" ]] || return 1
  assert_anchor "$f" '## Provenance tags (' 1 || ok=0
  assert_anchor "$f" 'exactly one trailing tag' 0 || ok=0
  sec="$(task_criteria_provenance_section "$f")"
  for needle in '[carried]' '[regression]' '[new]' 'missed earlier:' 'reverses cycle N:' \
                'failure_class: criteria-defect'; do
    n="$(printf '%s\n' "$sec" | grep -cF -- "$needle" 2>/dev/null || true)"
    [[ "${n:-0}" -ge 1 ]] || ok=0
  done
  for needle in 'justification clause' 'directly before the kind tag' 'through the end of the item'; do
    n="$(printf '%s\n' "$sec" | grep -cF -- "$needle" 2>/dev/null || true)"
    [[ "${n:-0}" -ge 1 ]] || ok=0
  done
  [[ $ok -eq 1 ]]
}

check_canonical_fix_cycles() {
  local f="$1" sec sec3 ok=1 n scope
  [[ -f "$f" ]] || return 1
  assert_line "$f" '## Provenance' 1 || ok=0
  # The heading is exactly `## Provenance`: the tree snapshot applies to every evaluator spawn, so
  # the heading must not name only re-evaluations; the opening paragraph states both scopes.
  assert_anchor "$f" '## Provenance (' 0 || ok=0
  scope="$(fix_cycles_provenance_scope "$f" | tr '\n' ' ')"
  for needle in 'tree snapshot' 'every evaluator spawn' 'provenance tags' 're-evaluations and re-audits'; do
    case "$scope" in *"$needle"*) ;; *) ok=0 ;; esac
  done
  sec="$(fix_cycles_provenance_section "$f")"
  for needle in 'every earlier required-fixes list verbatim' 'consumes no cycle' \
                'late finding: ' 'no extra cycle' 'reverses cycle N:' 'Phase 5' \
                'justification clause' '(those escalate at detection first)'; do
    n="$(printf '%s\n' "$sec" | grep -cF -- "$needle" 2>/dev/null || true)"
    [[ "${n:-0}" -ge 1 ]] || ok=0
  done
  sec3="$(fix_cycles_cycle3_section "$f")"
  printf '%s\n' "$sec3" | grep -qF 'drift' || ok=0
  printf '%s\n' "$sec3" | grep -qF 'rung 5 runs first' || ok=0
  [[ $ok -eq 1 ]]
}

check_canonical_continuation_ladder() {
  local f="$1" ok=1
  [[ -f "$f" ]] || return 1
  assert_ge "$f" 'drift trigger' 1 || ok=0
  assert_ge "$f" '≥ 2 `[new]` items' 1 || ok=0
  assert_ge "$f" 'provenance tags' 2 || ok=0
  assert_ge "$f" 'justification clause' 2 || ok=0
  [[ $ok -eq 1 ]]
}

check_canonical_diagnostician() {
  local f="$1" ok=1
  [[ -f "$f" ]] || return 1
  assert_ge "$f" 'provenance tags' 1 || ok=0
  assert_ge "$f" 'reverses cycle N:' 1 || ok=0
  assert_ge "$f" 'justification clause' 1 || ok=0
  [[ $ok -eq 1 ]]
}

check_canonical_feature_skill() {
  local f="$1" ok=1
  [[ -f "$f" ]] || return 1
  assert_anchor "$f" '§ Provenance' 1 || ok=0
  assert_anchor "$f" 'Phase 4/5 list applied fixes and carry earlier required-fix lists' 1 || ok=0
  assert_anchor "$f" 'list only applied fixes' 0 || ok=0
  [[ $ok -eq 1 ]]
}

check_canonical_orchestration() {
  local f="$1" sec ok=1
  [[ -f "$f" ]] || return 1
  assert_ge "$f" 'late finding:' 1 || ok=0
  assert_ge "$f" 'reverses cycle N:' 1 || ok=0
  assert_ge "$f" 'drift trigger' 1 || ok=0
  assert_ge "$f" '≥ 2 `[new]` items' 1 || ok=0
  assert_ge "$f" 'plus every earlier required-fixes list' 1 || ok=0
  assert_ge "$f" 'provenance tags' 2 || ok=0
  assert_ge "$f" 'justification clause' 2 || ok=0
  if grep -E 'delta prompt listing only[[:space:]]*$' "$f" >/dev/null 2>&1; then
    ok=0
  fi
  sec="$(orch_phase5_paragraph "$f")"
  printf '%s\n' "$sec" | grep -qF 'provenance' || ok=0
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

check_emitted_provenance() {
  local root="$1" ok=1 f path
  [[ -d "$root" ]] || return 1
  for path in .claude/agents/evaluator.md .cursor/agents/evaluator.md; do
    f="$root/$path"
    [[ -f "$f" ]] || return 1
    assert_anchor "$f" '**Provenance tags** — ' 1 || ok=0
    emit_file_clean "$f" || return 1
  done
  for path in \
    .claude/skills/task-criteria/SKILL.md \
    .cursor/skills/task-criteria/SKILL.md; do
    f="$root/$path"
    [[ -f "$f" ]] || return 1
    assert_anchor "$f" '## Provenance tags (' 1 || ok=0
    emit_file_clean "$f" || return 1
  done
  for path in \
    .claude/skills/feature/reference/fix-cycles.md \
    .cursor/skills/feature/reference/fix-cycles.md; do
    f="$root/$path"
    [[ -f "$f" ]] || return 1
    assert_line "$f" '## Provenance' 1 || ok=0
    emit_file_clean "$f" || return 1
  done
  for path in \
    .claude/skills/feature/reference/continuation-ladder.md \
    .cursor/skills/feature/reference/continuation-ladder.md; do
    f="$root/$path"
    [[ -f "$f" ]] || return 1
    assert_ge "$f" 'drift trigger' 1 || ok=0
    emit_file_clean "$f" || return 1
  done
  [[ $ok -eq 1 ]]
}

_mutate_copy() { # _mutate_copy <kind> <file>
  local kind="$1" f="$2"
  case "$kind" in
    evaluator)
      sed '/\*\*Provenance tags\*\* —/d' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    task-criteria)
      sed '/^## Provenance tags (/d' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    fix-cycles)
      sed '/consumes no cycle/d' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    fix-cycles-heading)
      # the old heading, which names only re-evaluations
      sed 's/^## Provenance$/## Provenance (re-evaluations and re-audits)/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    fix-cycles-scope)
      # the opening sentence stops naming every evaluator spawn
      sed 's/applies to every evaluator spawn in Phases 4 and 5/applies to re-evaluation spawns/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    continuation-ladder)
      sed '/drift trigger/d' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    diagnostician)
      sed '/reverses cycle N:/d' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    feature-skill)
      sed 's/§ Provenance/§ Removed/' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    orchestration)
      sed '/late finding:/d' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    evaluator-trigger)
      sed '/drift trigger/d' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      ;;
    *)
      return 1
      ;;
  esac
}

mutation_proof() { # mutation_proof <kind> <src> <check_fn>
  local kind="$1" src="$2" check_fn="$3"
  local d copy
  d="$(mktemp -d "${TMPDIR:-/tmp}/fcpmut.XXXXXX")" || return 1
  copy="$d/$(basename "$src")"
  cp "$src" "$copy" || { rm -rf "$d"; return 1; }
  _mutate_copy "$kind" "$copy" || { rm -rf "$d"; return 1; }
  if "$check_fn" "$copy"; then
    rm -rf "$d"
    return 1
  fi
  rm -rf "$d"
  return 0
}

run_canonical() {
  local name="$1" path="$2" fn="$3"
  if "$fn" "$path"; then
    report PASS "canonical $name"
  else
    report FAIL "canonical $name" "$path"
  fi
}

run_mutation() {
  local name="$1" kind="$2" path="$3" fn="$4"
  if mutation_proof "$kind" "$path" "$fn"; then
    report PASS "mutation-proof $name"
  else
    report FAIL "mutation-proof $name" "check still passed on mutated copy"
  fi
}

PAR_REPORT_FAIL="report"
emit_cache_init

run_canonical 'evaluator.md' "$EVALUATOR" check_canonical_evaluator
run_canonical 'task-criteria/SKILL.template.md' "$TASK_CRITERIA" check_canonical_task_criteria
run_canonical 'reference/fix-cycles.md' "$FIX_CYCLES_REF" check_canonical_fix_cycles
run_canonical 'reference/continuation-ladder.md' "$LADDER_REF" check_canonical_continuation_ladder
run_canonical 'diagnostician.md' "$DIAGNOSTICIAN" check_canonical_diagnostician
run_canonical 'feature/SKILL.template.md' "$FEATURE_SKILL" check_canonical_feature_skill
run_canonical 'ORCHESTRATION.md' "$ORCH_TEMPLATE" check_canonical_orchestration

run_mutation 'evaluator.md' evaluator "$EVALUATOR" check_canonical_evaluator
run_mutation 'evaluator.md (trigger)' evaluator-trigger "$EVALUATOR" check_canonical_evaluator
run_mutation 'task-criteria/SKILL.template.md' task-criteria "$TASK_CRITERIA" check_canonical_task_criteria
run_mutation 'reference/fix-cycles.md' fix-cycles "$FIX_CYCLES_REF" check_canonical_fix_cycles
run_mutation 'reference/fix-cycles.md (heading names only re-evaluations)' fix-cycles-heading "$FIX_CYCLES_REF" check_canonical_fix_cycles
run_mutation 'reference/fix-cycles.md (opening sentence scope)' fix-cycles-scope "$FIX_CYCLES_REF" check_canonical_fix_cycles
run_mutation 'reference/continuation-ladder.md' continuation-ladder "$LADDER_REF" check_canonical_continuation_ladder
run_mutation 'diagnostician.md' diagnostician "$DIAGNOSTICIAN" check_canonical_diagnostician
run_mutation 'feature/SKILL.template.md' feature-skill "$FEATURE_SKILL" check_canonical_feature_skill
run_mutation 'ORCHESTRATION.md' orchestration "$ORCH_TEMPLATE" check_canonical_orchestration

if [[ "$HAVE_JQ" -ne 1 ]]; then
  report SKIP 'emitted claude+cursor provenance anchors' 'jq not on PATH'
else
  alloc_path ansfile
  answers_for_emit "$EMIT_ALLOC_PATH"
  ans="$EMIT_ALLOC_PATH"
  alloc_root
  root="$EMIT_ALLOC_PATH"
  if emit_cache_copy "$root" "$ans" && check_emitted_provenance "$root"; then
    report PASS 'emitted claude+cursor provenance anchors'
  else
    report FAIL 'emitted claude+cursor provenance anchors'
  fi
fi

emit_cache_verify

echo
echo "=== fix-cycle-provenance summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
