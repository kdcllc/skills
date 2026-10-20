#!/usr/bin/env bash
# Regression guard for the feature-skill-slimming goal: locks template
# skill discovery rename (SKILL.template.md only under templates/), acceptance
# criteria in task templates, contract.md absence, goal.md phases gating, token
# proxy log fields, and canonical feature skill byte budget. Tracked,
# self-install-independent — no network, no LLM.
#
# Copy this repo's `tests/` + `skills/` + `.claude/` + `.cursor/` subtree into a
# mktemp dir, mutate a guarded invariant, then run the COPIED script: HERE and
# REPO_ROOT resolve relative to this script's own location.
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location.
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
FEATURE_TPL="$TEMPLATES/skills/feature/SKILL.template.md"
FIX_CYCLES_REF="$TEMPLATES/skills/feature/reference/fix-cycles.md"
TASK_TPL="$TEMPLATES/skills/feature/templates/task.md"
GOAL_TPL="$TEMPLATES/skills/feature/templates/goal.md"
ORCH_TPL="$TEMPLATES/ORCHESTRATION.md"
CONTRACT_CANON="$TEMPLATES/skills/feature/templates/contract.md"

FROZEN_P1=$'   Before any fix cycle, bypass escalation, `criteria-defect` route, or cycle-3 action, **Read `reference/fix-cycles.md`** and follow it (line-patch resume, bypass tags, ladder, rotation).'
FROZEN_P2=$'- Max 3 evaluation cycles per phase/task; Phase 4 fix cycles and cycle-3 exhaustion follow `reference/fix-cycles.md`. Other phases escalate.'
FROZEN_P3=$'Implementer resume and rotation per fix cycle: `reference/fix-cycles.md`.'
FROZEN_P4=$'Read this before acting on **NEEDS FIXES**, **REJECT**, a verdict tagged `destructive`/`security`/`infra`, `failure_class: criteria-defect`, or Phase 4 cycle-3 exhaustion.'

fail_count=0
pass_count=0

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

file_has_all() { # file_has_all <file> <needle>...
  local f="$1" needle
  shift
  [[ -f "$f" ]] || return 1
  for needle in "$@"; do
    grep -qF "$needle" "$f" || return 1
  done
}

# ===========================================================================
# (a) Zero SKILL.md under skills/agent-kit/templates/.
# ===========================================================================
if find "$TEMPLATES" -name 'SKILL.md' -print -quit 2>/dev/null | grep -q .; then
  offenders="$(find "$TEMPLATES" -name 'SKILL.md' 2>/dev/null | head -5)"
  report FAIL "zero SKILL.md under skills/agent-kit/templates/" \
    "found: $(tr '\n' ' ' <<<"$offenders")"
else
  report PASS "zero SKILL.md under skills/agent-kit/templates/"
fi

# ===========================================================================
# (b) ## Acceptance Criteria in canonical + instance task.md templates.
# ===========================================================================
check_b_ok=1
check_b_detail=""
for task in \
  "$TASK_TPL" \
  "$REPO_ROOT/.claude/skills/feature/templates/task.md" \
  "$REPO_ROOT/.cursor/skills/feature/templates/task.md"; do
  rel="${task#"$REPO_ROOT"/}"
  if [[ ! -f "$task" ]]; then
    check_b_ok=0
    check_b_detail="missing $rel"
    break
  fi
  if ! grep -qF '## Acceptance Criteria' "$task"; then
    check_b_ok=0
    check_b_detail="$rel: ## Acceptance Criteria missing"
    break
  fi
done
if [[ $check_b_ok -eq 1 ]]; then
  report PASS "## Acceptance Criteria in canonical + instance task.md templates"
else
  report FAIL "## Acceptance Criteria in canonical + instance task.md templates" \
    "$check_b_detail"
fi

# ===========================================================================
# (c) contract.md absent in canonical + instance feature template dirs.
# ===========================================================================
check_c_ok=1
check_c_detail=""
for contract in \
  "$CONTRACT_CANON" \
  "$REPO_ROOT/.claude/skills/feature/templates/contract.md" \
  "$REPO_ROOT/.cursor/skills/feature/templates/contract.md"; do
  if [[ -f "$contract" ]]; then
    check_c_ok=0
    check_c_detail="still present: ${contract#"$REPO_ROOT"/}"
    break
  fi
done
if [[ $check_c_ok -eq 1 ]]; then
  report PASS "contract.md absent in canonical + instance feature template dirs"
else
  report FAIL "contract.md absent in canonical + instance feature template dirs" \
    "$check_c_detail"
fi

# ===========================================================================
# (d) phases: gating in canonical + instance feature skill and goal.md template.
# ===========================================================================
check_d_ok=1
check_d_detail=""
for goal in \
  "$GOAL_TPL" \
  "$REPO_ROOT/.claude/skills/feature/templates/goal.md" \
  "$REPO_ROOT/.cursor/skills/feature/templates/goal.md"; do
  rel="${goal#"$REPO_ROOT"/}"
  if [[ ! -f "$goal" ]]; then
    check_d_ok=0
    check_d_detail="missing $rel"
    break
  fi
  if ! grep -qF 'phases:' "$goal"; then
    check_d_ok=0
    check_d_detail="$rel: phases: block missing"
    break
  fi
done
if [[ $check_d_ok -eq 1 ]]; then
  for feat in \
    "$FEATURE_TPL" \
    "$REPO_ROOT/.claude/skills/feature/SKILL.md" \
    "$REPO_ROOT/.cursor/skills/feature/SKILL.md"; do
    rel="${feat#"$REPO_ROOT"/}"
    if [[ ! -f "$feat" ]]; then
      check_d_ok=0
      check_d_detail="missing $rel"
      break
    fi
    if ! grep -qF 'align_docs:' "$feat" || ! grep -qF 'phases:' "$feat"; then
      check_d_ok=0
      check_d_detail="$rel: goal.md phases gating prose missing"
      break
    fi
  done
fi
if [[ $check_d_ok -eq 1 ]]; then
  report PASS "phases: gating in canonical + instance feature skill and goal.md template"
else
  report FAIL "phases: gating in canonical + instance feature skill and goal.md template" \
    "$check_d_detail"
fi

# ===========================================================================
# (e) context_chars / est_tokens in feature skills and ORCHESTRATION files.
# ===========================================================================
check_e_ok=1
check_e_detail=""
for f in \
  "$FEATURE_TPL" \
  "$REPO_ROOT/.claude/skills/feature/SKILL.md" \
  "$REPO_ROOT/.cursor/skills/feature/SKILL.md" \
  "$ORCH_TPL" \
  "$REPO_ROOT/.claude/ORCHESTRATION.md" \
  "$REPO_ROOT/.cursor/ORCHESTRATION.md"; do
  rel="${f#"$REPO_ROOT"/}"
  if [[ ! -f "$f" ]]; then
    check_e_ok=0
    check_e_detail="missing $rel"
    break
  fi
  if ! file_has_all "$f" 'context_chars' 'est_tokens'; then
    check_e_ok=0
    check_e_detail="$rel: context_chars and/or est_tokens missing"
    break
  fi
done
if [[ $check_e_ok -eq 1 ]]; then
  report PASS "context_chars and est_tokens in feature skills and ORCHESTRATION files"
else
  report FAIL "context_chars and est_tokens in feature skills and ORCHESTRATION files" \
    "$check_e_detail"
fi

# ===========================================================================
# (f) Canonical feature SKILL.template.md body budget (<= 11264 bytes).
# Release B memory recall/archive steps.
# ===========================================================================
if [[ ! -f "$FEATURE_TPL" ]]; then
  report FAIL "canonical feature SKILL.template.md <= 11264 bytes" "file missing"
else
  feat_bytes="$(wc -c < "$FEATURE_TPL" | tr -d ' ')"
  if [[ "${feat_bytes:-0}" -le 11264 ]]; then
    report PASS "canonical feature SKILL.template.md <= 11264 bytes (${feat_bytes} bytes)"
  else
    report FAIL "canonical feature SKILL.template.md <= 11264 bytes" \
      "actual ${feat_bytes} bytes"
  fi
fi

# ===========================================================================
# (g) Fix-cycles move: frozen P1–P4, moved anchors, ORCHESTRATION tree ×4.
# ===========================================================================
check_g_ok=1
check_g_detail=""
if [[ ! -f "$FEATURE_TPL" ]]; then
  check_g_ok=0
  check_g_detail="missing feature template"
elif ! grep -qxF -- "$FROZEN_P1" "$FEATURE_TPL"; then
  check_g_ok=0
  check_g_detail="P1 whole line missing in feature template"
elif ! grep -qxF -- "$FROZEN_P2" "$FEATURE_TPL"; then
  check_g_ok=0
  check_g_detail="P2 whole line missing in feature template"
elif ! grep -qF "$FROZEN_P3" "$FEATURE_TPL"; then
  check_g_ok=0
  check_g_detail="P3 substring missing in feature template"
fi
if [[ $check_g_ok -eq 1 ]]; then
  if [[ ! -f "$FIX_CYCLES_REF" ]]; then
    check_g_ok=0
    check_g_detail="missing fix-cycles reference"
  else
    p4_line="$(sed -n '3p' "$FIX_CYCLES_REF" 2>/dev/null || true)"
    if [[ "$p4_line" != "$FROZEN_P4" ]]; then
      check_g_ok=0
      check_g_detail="fix-cycles line 3 is not P4"
    elif ! file_has_all "$FIX_CYCLES_REF" \
          'Fix-cycle model rotation' \
          'On cycle-3 exhaustion' \
          'Bypass at detection' \
          'Implementer MAY be resumed for fix cycle 1' \
          'Max 3 evaluation cycles per phase/task'; then
      check_g_ok=0
      check_g_detail="fix-cycles moved anchor missing"
    fi
  fi
fi
if [[ $check_g_ok -eq 1 ]]; then
  tree_n="$(grep -cF 'corrective-tasks.md,fix-cycles.md}' "$ORCH_TPL" 2>/dev/null || true)"
  if [[ "${tree_n:-0}" != 4 ]]; then
    check_g_ok=0
    check_g_detail="ORCHESTRATION fix-cycles tree count ${tree_n:-0} != 4"
  fi
fi
if [[ $check_g_ok -eq 1 ]]; then
  report PASS "fix-cycles move: P1–P4 frozen lines, moved anchors, ORCHESTRATION tree ×4"
else
  report FAIL "fix-cycles move: P1–P4 frozen lines, moved anchors, ORCHESTRATION tree ×4" \
    "$check_g_detail"
fi

echo
echo "=== skill-slimming summary ==="
echo "PASS: $pass_count   FAIL: $fail_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
