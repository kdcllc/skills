#!/usr/bin/env bash
# Regression guard for orchestration-preflight-linepatch: locks pre-flight reference,
# bootstrap id, evaluator/implementer/task-criteria line-patch wording, continuation-ladder
# tag-stripping, feature-skill and ORCHESTRATION wiring, emitted preflight instances,
# and a negative self-test on copied templates. Tracked, self-install-independent — no
# network, no LLM.
#
# Copy this repo's `tests/` + `skills/` subtree into a mktemp dir, mutate a file under
# test, then run check logic against the copy — never the live repo (see check 9).
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location.
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
PREFLIGHT_REF="$TEMPLATES/skills/feature/reference/preflight.md"
BOOTSTRAP_IDS="$REPO_ROOT/skills/agent-kit/reference/bootstrap-ids.md"
EVALUATOR="$TEMPLATES/agents/evaluator.md"
IMPLEMENTER="$TEMPLATES/agents/implementer.md"
TEST_WRITER="$TEMPLATES/agents/test-writer.md"
TASK_CRITERIA="$TEMPLATES/skills/task-criteria/SKILL.template.md"
LADDER_REF="$TEMPLATES/skills/feature/reference/continuation-ladder.md"
FIX_CYCLES_REF="$TEMPLATES/skills/feature/reference/fix-cycles.md"
FEATURE_SKILL="$TEMPLATES/skills/feature/SKILL.template.md"
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"
PREFLIGHT_CURSOR="$REPO_ROOT/.cursor/skills/feature/reference/preflight.md"
PREFLIGHT_CLAUDE="$REPO_ROOT/.claude/skills/feature/reference/preflight.md"

PREFLIGHT_CHECK_NAMES=(
  "Acceptance criteria and paths"
  "Missed callers"
  "Scope drift"
  "Default-value semantics"
  "Stated facts"
)

fail_count=0
pass_count=0
skip_count=0

report() { # report <PASS|FAIL> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  if [[ "$status" == "PASS" ]]; then
    pass_count=$((pass_count + 1))
    echo "PASS: $name"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $name${detail:+ -- $detail}" >&2
  fi
}

skip_report() { # skip_report <name>
  skip_count=$((skip_count + 1))
  echo "SKIP: $1"
}

reject_empty_path() { # reject_empty_path <path> → 1 if empty (no report — callers decide)
  [[ -n "$1" ]]
}

check_canonical_preflight() { # check_canonical_preflight <file> → 0 if all anchors present
  local f="$1"
  reject_empty_path "$f" || return 1
  [[ -f "$f" ]] || return 1
  grep -qF 'before Phase 3 evaluation attempt 1' "$f" || return 1
  grep -qF '**once**' "$f" || return 1
  grep -qF 'Never run it between evaluation attempts' "$f" || return 1
  local name
  for name in "${PREFLIGHT_CHECK_NAMES[@]}"; do
    grep -qF "$name" "$f" || return 1
  done
  grep -qF 'BOOTSTRAP[preflight-extra]' "$f" || return 1
  grep -qF 'Pre-flight: ' "$f" || return 1
}

check_emitted_preflight() { # check_emitted_preflight <file> → 0 if emitted copy is clean
  local f="$1"
  reject_empty_path "$f" || return 1
  [[ -f "$f" ]] || return 1
  local name
  for name in "${PREFLIGHT_CHECK_NAMES[@]}"; do
    grep -qF "$name" "$f" || return 1
  done
  grep -qF 'Pre-flight: ' "$f" || return 1
  if grep -qF 'BOOTSTRAP[' "$f" 2>/dev/null; then
    return 1
  fi
}

check_evaluator_task_criteria_tags() { # check_evaluator_task_criteria_tags <eval> <task> → 0
  local eval="$1" task="$2"
  reject_empty_path "$eval" || return 1
  reject_empty_path "$task" || return 1
  [[ -f "$eval" && -f "$task" ]] || return 1
  grep -qF '[line-patch]' "$eval" || return 1
  grep -qF '[structural]' "$eval" || return 1
  grep -qF '[line-patch]' "$task" || return 1
  grep -qF '[structural]' "$task" || return 1
  grep -qF 'mislabeled' "$task" || return 1
  grep -qF 'line patch) is a **`major`**' "$task" || return 1
}

# ===========================================================================
# 1. Canonical preflight.md anchors.
# ===========================================================================
if check_canonical_preflight "$PREFLIGHT_REF"; then
  report PASS "canonical preflight.md: once-before-attempt-1, five checks, bootstrap, log prefix"
else
  report FAIL "canonical preflight.md: once-before-attempt-1, five checks, bootstrap, log prefix" \
    "missing file or anchor in $PREFLIGHT_REF"
fi

# ===========================================================================
# 2. bootstrap-ids preflight-extra row.
# ===========================================================================
check2_ok=1
if [[ ! -f "$BOOTSTRAP_IDS" ]]; then
  check2_ok=0
elif ! grep -qF 'preflight-extra' "$BOOTSTRAP_IDS" 2>/dev/null; then
  check2_ok=0
elif ! grep -F 'preflight-extra' "$BOOTSTRAP_IDS" 2>/dev/null | grep -qF '| a text |'; then
  check2_ok=0
fi
if [[ $check2_ok -eq 1 ]]; then
  report PASS "bootstrap-ids.md: preflight-extra row with class a text"
else
  report FAIL "bootstrap-ids.md: preflight-extra row with class a text"
fi

# ===========================================================================
# 3. Evaluator verdict format and task-criteria tags + mislabel rule.
# ===========================================================================
if check_evaluator_task_criteria_tags "$EVALUATOR" "$TASK_CRITERIA"; then
  report PASS "evaluator verdict tags [line-patch]/[structural] and task-criteria mislabel-is-major"
else
  report FAIL "evaluator verdict tags [line-patch]/[structural] and task-criteria mislabel-is-major"
fi

# ===========================================================================
# 4. Implementer + test-writer templates: Apply-verbatim mode and NOT APPLIED.
# ===========================================================================
check4_ok=1
for agent_tpl in "$IMPLEMENTER" "$TEST_WRITER"; do
  if [[ ! -f "$agent_tpl" ]]; then
    check4_ok=0
    break
  fi
  grep -qF 'Apply-verbatim mode' "$agent_tpl" || check4_ok=0
  grep -qF 'NOT APPLIED' "$agent_tpl" || check4_ok=0
done
if [[ $check4_ok -eq 1 ]]; then
  report PASS "implementer + test-writer templates: Apply-verbatim mode and NOT APPLIED"
else
  report FAIL "implementer + test-writer templates: Apply-verbatim mode and NOT APPLIED"
fi

# ===========================================================================
# 5. Continuation ladder: tags stripped before signature comparison.
# ===========================================================================
check5_ok=1
if [[ ! -f "$LADDER_REF" ]]; then
  check5_ok=0
else
  grep -qF 'tags stripped' "$LADDER_REF" || check5_ok=0
  grep -qF 'stripping trailing `[line-patch]` / `[structural]` tags' "$LADDER_REF" || check5_ok=0
fi
if [[ $check5_ok -eq 1 ]]; then
  report PASS "continuation ladder: tags stripped before signature comparison"
else
  report FAIL "continuation ladder: tags stripped before signature comparison"
fi

# ===========================================================================
# 6. Feature skill: preflight reference and line-patch-only resume rule.
# ===========================================================================
check6_ok=1
if [[ ! -f "$FEATURE_SKILL" ]]; then
  check6_ok=0
elif ! grep -qF 'reference/preflight.md' "$FEATURE_SKILL"; then
  check6_ok=0
fi
if [[ $check6_ok -eq 1 ]] && [[ ! -f "$FIX_CYCLES_REF" ]]; then
  check6_ok=0
elif [[ $check6_ok -eq 1 ]]; then
  grep -qF 'Line-patch-only' "$FIX_CYCLES_REF" || check6_ok=0
  grep -qF 'no rotation' "$FIX_CYCLES_REF" || check6_ok=0
  grep -qF 'counts toward 3' "$FIX_CYCLES_REF" || check6_ok=0
  grep -qF 'apply-verbatim any cycle' "$FIX_CYCLES_REF" || check6_ok=0
fi
if [[ $check6_ok -eq 1 ]]; then
  report PASS "feature skill: reference/preflight.md; fix-cycles reference: line-patch-only resume rule"
else
  report FAIL "feature skill: reference/preflight.md; fix-cycles reference: line-patch-only resume rule"
fi

# ===========================================================================
# 7. ORCHESTRATION.md pre-flight and line-patch rule.
# ===========================================================================
check7_ok=1
if [[ ! -f "$ORCH_TEMPLATE" ]]; then
  check7_ok=0
else
  grep -qF 'reference/preflight.md' "$ORCH_TEMPLATE" || check7_ok=0
  grep -qF 'line-patch-only' "$ORCH_TEMPLATE" || check7_ok=0
fi
if [[ $check7_ok -eq 1 ]]; then
  report PASS "ORCHESTRATION.md: pre-flight reference and line-patch rule"
else
  report FAIL "ORCHESTRATION.md: pre-flight reference and line-patch rule"
fi

# ===========================================================================
# 8. Emitted preflight instances (SKIP when absent).
# ===========================================================================
for inst_pair in \
  ".cursor:$PREFLIGHT_CURSOR" \
  ".claude:$PREFLIGHT_CLAUDE"; do
  inst_label="${inst_pair%%:*}"
  inst_path="${inst_pair#*:}"
  if [[ ! -f "$inst_path" ]]; then
    skip_report "emitted $inst_label/skills/feature/reference/preflight.md absent"
    continue
  fi
  if check_emitted_preflight "$inst_path"; then
    report PASS "emitted $inst_label/skills/feature/reference/preflight.md: five checks, log prefix, no BOOTSTRAP"
  else
    report FAIL "emitted $inst_label/skills/feature/reference/preflight.md: five checks, log prefix, no BOOTSTRAP" \
      "regression in $inst_path"
  fi
done

# ===========================================================================
# 9. Negative self-test: mutated copy must fail check-3 logic.
# ===========================================================================
neg_ok=0
neg_root="$(mktemp -d "${TMPDIR:-/tmp}/linepatchneg.XXXXXX")" || neg_root=""
if [[ -z "$neg_root" || ! -d "$neg_root" ]]; then
  report FAIL "negative self-test: check-3 fails when [line-patch] removed from copy" \
    "mktemp -d failed"
else
  mkdir -p "$neg_root/skills/agent-kit/templates/agents" \
           "$neg_root/skills/agent-kit/templates/skills/task-criteria" || true
  if cp "$EVALUATOR" "$neg_root/skills/agent-kit/templates/agents/evaluator.md" \
     && cp "$TASK_CRITERIA" "$neg_root/skills/agent-kit/templates/skills/task-criteria/SKILL.template.md"; then
    sed 's/\[line-patch\]//g' \
      "$neg_root/skills/agent-kit/templates/agents/evaluator.md" > \
      "$neg_root/skills/agent-kit/templates/agents/evaluator.md.tmp" \
      && mv "$neg_root/skills/agent-kit/templates/agents/evaluator.md.tmp" \
         "$neg_root/skills/agent-kit/templates/agents/evaluator.md"
    neg_eval="$neg_root/skills/agent-kit/templates/agents/evaluator.md"
    neg_task="$neg_root/skills/agent-kit/templates/skills/task-criteria/SKILL.template.md"
    if check_evaluator_task_criteria_tags "$neg_eval" "$neg_task"; then
      neg_ok=0
    else
      neg_ok=1
    fi
  fi
  rm -rf "$neg_root"
fi
if [[ $neg_ok -eq 1 ]]; then
  report PASS "negative self-test: check-3 fails when [line-patch] removed from copied evaluator"
else
  report FAIL "negative self-test: check-3 fails when [line-patch] removed from copied evaluator"
fi

if check_evaluator_task_criteria_tags "" "$TASK_CRITERIA"; then
  report FAIL "check-3 rejects empty path arguments"
else
  report PASS "check-3 rejects empty path arguments"
fi

# ===========================================================================
# Optional Phase 3 anchors (cheap extra guards).
# ===========================================================================
check_opt_ok=1
if [[ ! -f "$LADDER_REF" ]] \
   || ! grep -qF 'required-fix item (unanimous-failure heuristic' "$LADDER_REF" \
   || ! grep -qF 'tags stripped' "$LADDER_REF"; then
  check_opt_ok=0
fi
if [[ $check_opt_ok -eq 1 ]] && [[ -f "$ORCH_TEMPLATE" ]] \
   && grep -qF '**Signature identity:**' "$ORCH_TEMPLATE" \
   && grep -qF 'stripping trailing `[line-patch]` / `[structural]` tags from each item' "$ORCH_TEMPLATE"; then
  report PASS "optional: rung-5 same-item tag-stripping in ladder and ORCHESTRATION signature identity"
else
  report FAIL "optional: rung-5 same-item tag-stripping in ladder and ORCHESTRATION signature identity"
fi

check_opt2_ok=1
if [[ -f "$ORCH_TEMPLATE" ]] \
   && grep -qF '### Mandatory Re-Evaluate Invariants' "$ORCH_TEMPLATE" \
   && grep -qF 'except line-patch-only cycles, which do not rotate' "$ORCH_TEMPLATE"; then
  report PASS "optional: ORCHESTRATION Mandatory Re-Evaluate line-patch no-rotation exception"
else
  report FAIL "optional: ORCHESTRATION Mandatory Re-Evaluate line-patch no-rotation exception"
fi

check_opt3_ok=1
if [[ -f "$IMPLEMENTER" ]] \
   && grep -qF 'bottom-up' "$IMPLEMENTER" \
   && grep -qF '±10 lines' "$IMPLEMENTER"; then
  report PASS "optional: implementer bottom-up and ±10-line patch rules"
else
  report FAIL "optional: implementer bottom-up and ±10-line patch rules"
fi

if [[ -f "$EVALUATOR" ]] \
   && grep -qF 'as the evaluator read it' "$EVALUATOR"; then
  report PASS "optional: evaluator line numbers as the evaluator read it"
else
  report FAIL "optional: evaluator line numbers as the evaluator read it"
fi

echo
echo "=== line-patch-preflight summary ==="
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
