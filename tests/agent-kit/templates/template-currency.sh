#!/usr/bin/env bash
# Structural guard for orchestration-template-currency goal: locks seven fixed template
# claims G1–G7 in skills/agent-kit/templates/ORCHESTRATION.md and (SKIP-when-absent)
# instance mirrors .claude/ORCHESTRATION.md and .cursor/ORCHESTRATION.md.
# Tracked, self-install-independent — no network, no LLM, no loop-harness dependency.
#
# Copy this repo's `tests/` + `skills/` subtree into a mktemp dir, mutate a locked
# claim under skills/agent-kit/templates/ORCHESTRATION.md, then run the COPIED script:
# HERE and REPO_ROOT resolve relative to this script's own location, so the copy
# checks the mutated copy, not the live repo.
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location.
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CANONICAL="$REPO_ROOT/skills/agent-kit/templates/ORCHESTRATION.md"
MIRROR_CLAUDE="$REPO_ROOT/.claude/ORCHESTRATION.md"
MIRROR_CURSOR="$REPO_ROOT/.cursor/ORCHESTRATION.md"
DOCS_GUIDE="$REPO_ROOT/docs/agent-kit/guide/feature-workflow.md"

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

extract_section() { # extract_section <file> <start-pattern> <stop-pattern>
  local file="$1" start="$2" stop="$3"
  awk -v start="$start" -v stop="$stop" '
    $0 ~ start { p=1; next }
    p && $0 ~ stop { exit }
    p { print }
  ' "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# G1 — Research Flow handoff at Phase 3 (goal evaluation); stale fragment absent.
# ---------------------------------------------------------------------------
check_g1() {
  local file="$1"
  local rf=""
  rf="$(extract_section "$file" '^## Research Flow' '^## ')"
  [[ -n "$rf" ]] || return 1
  grep -qF 'Phase 3 (goal evaluation)' <<<"$rf" || return 1
  ! grep -qF 'feeds directly into' <<<"$rf"
}

# ---------------------------------------------------------------------------
# G2 — Escalation Format block: **Ladder**: line + criteria-defective verbatim note.
# ---------------------------------------------------------------------------
check_g2() {
  local file="$1"
  local block=""
  block="$(awk '/^### Escalation Format/{p=1;next} p&&/^---$/{exit} p' "$file" 2>/dev/null)"
  [[ -n "$block" ]] || return 1
  grep -qF '**Ladder**:' <<<"$block" || return 1
  grep -qF 'criteria-defective' <<<"$block" || return 1
  grep -qF 'verbatim' <<<"$block"
}

# ---------------------------------------------------------------------------
# G3 — designated closer at both rung-3 sites; stale once-after-audit absent.
# ---------------------------------------------------------------------------
check_g3() {
  local file="$1"
  local closer_count=""
  closer_count="$(grep -cF 'designated closer' "$file" 2>/dev/null || true)"
  [[ "${closer_count:-0}" -ge 2 ]] || return 1
  ! grep -qF '**once**, after the audit is APPROVED' "$file"
}

# ---------------------------------------------------------------------------
# G4 — Autonomous Loop: write-set admission, sentinel, LOOP_SLOTS/LOOP_WORKTREE.
# ---------------------------------------------------------------------------
check_g4() {
  local file="$1"
  local loop=""
  loop="$(extract_section "$file" '^## Autonomous Loop' '^## ')"
  [[ -n "$loop" ]] || return 1
  grep -qF 'write-set admission' <<<"$loop" || return 1
  grep -qF 'single-writer integrator' <<<"$loop" || return 1
  grep -qF 'never re-select' <<<"$loop" || return 1
  grep -qF 'LOOP_SLOTS' <<<"$loop" || return 1
  grep -qF 'LOOP_WORKTREE' <<<"$loop"
}

# ---------------------------------------------------------------------------
# G5 — Exit funnel: precedence, exit 1/5, quarantine markers and reasons.
# ---------------------------------------------------------------------------
check_g5() {
  local file="$1"
  grep -qF '4>3>2>1>0' "$file" || return 1
  grep -qF 'exit 1' "$file" || return 1
  grep -qF 'exit 5' "$file" || return 1
  grep -qF 'QUARANTINE-' "$file" || return 1
  grep -qE 'mismatch\|abnormal\|subset\|killed' "$file"
}

# ---------------------------------------------------------------------------
# G6 — Merge gate per-story rung 3; stale "rung 3 at run end" absent.
# ---------------------------------------------------------------------------
check_g6() {
  local file="$1"
  grep -qF 'rung 3 per story' "$file" || return 1
  ! grep -qF 'rung 3 at run end' "$file"
}

# ---------------------------------------------------------------------------
# G7 — Feature Flow lifecycle mermaid diagram byte-identical to the docs guide.
# ---------------------------------------------------------------------------
extract_first_mermaid() { # extract_first_mermaid <file> <start-pattern>
  # Prints the body of the first ```mermaid fence at or after start-pattern.
  local file="$1" start="$2"
  awk -v start="$start" '
    $0 ~ start { s=1 }
    s && /^```mermaid$/ { m=1; next }
    m && /^```$/ { exit }
    m { print }
  ' "$file" 2>/dev/null
}

check_g7() {
  local file="$1"
  local tmpl_diag="" guide_diag=""
  tmpl_diag="$(extract_first_mermaid "$file" '^## Feature Flow')"
  guide_diag="$(extract_first_mermaid "$DOCS_GUIDE" '^# Feature workflow')"
  [[ -n "$tmpl_diag" && -n "$guide_diag" ]] || return 1
  [[ "$tmpl_diag" == "$guide_diag" ]]
}

check_all_g1_g7() { # check_all_g1_g7 <file> → 0 if all pass
  local file="$1"
  check_g1 "$file" && check_g2 "$file" && check_g3 "$file" \
    && check_g4 "$file" && check_g5 "$file" && check_g6 "$file" \
    && check_g7 "$file"
}

# ===========================================================================
# Canonical template — G1 through G7 (distinct PASS lines per claim).
# ===========================================================================
if [[ ! -f "$CANONICAL" ]]; then
  report FAIL "canonical ORCHESTRATION: research handoff at Phase 3 (goal evaluation)" "file missing"
  report FAIL "canonical ORCHESTRATION: Escalation Format **Ladder** line and criteria-defective verbatim note" "file missing"
  report FAIL "canonical ORCHESTRATION: closer-task rung-3 carve-out at Execution Order and Quality Checks" "file missing"
  report FAIL "canonical ORCHESTRATION: driver-owned dispatch summary (write-set, sentinel, LOOP_SLOTS/LOOP_WORKTREE)" "file missing"
  report FAIL "canonical ORCHESTRATION: exit funnel (4>3>2>1>0, exit 1/5, quarantine markers)" "file missing"
  report FAIL "canonical ORCHESTRATION: merge gate per-story rung 3 (no run end)" "file missing"
  report FAIL "canonical ORCHESTRATION: Feature Flow mermaid identical to docs/agent-kit/guide/feature-workflow.md" "file missing"
else
  if check_g1 "$CANONICAL"; then
    report PASS "canonical ORCHESTRATION: research handoff at Phase 3 (goal evaluation)"
  else
    report FAIL "canonical ORCHESTRATION: research handoff at Phase 3 (goal evaluation)" \
      "G1: missing Phase 3 (goal evaluation) in Research Flow and/or stale 'feeds directly into' present"
  fi

  if check_g2 "$CANONICAL"; then
    report PASS "canonical ORCHESTRATION: Escalation Format **Ladder** line and criteria-defective verbatim note"
  else
    report FAIL "canonical ORCHESTRATION: Escalation Format **Ladder** line and criteria-defective verbatim note" \
      "G2: **Ladder**: line and/or criteria-defective verbatim note missing"
  fi

  if check_g3 "$CANONICAL"; then
    report PASS "canonical ORCHESTRATION: closer-task rung-3 carve-out at Execution Order and Quality Checks"
  else
    report FAIL "canonical ORCHESTRATION: closer-task rung-3 carve-out at Execution Order and Quality Checks" \
      "G3: designated closer absent at one or both sites and/or stale once-after-audit phrasing present"
  fi

  if check_g4 "$CANONICAL"; then
    report PASS "canonical ORCHESTRATION: driver-owned dispatch summary (write-set, sentinel, LOOP_SLOTS/LOOP_WORKTREE)"
  else
    report FAIL "canonical ORCHESTRATION: driver-owned dispatch summary (write-set, sentinel, LOOP_SLOTS/LOOP_WORKTREE)" \
      "G4: write-set admission, single-writer integrator, never re-select, LOOP_SLOTS, or LOOP_WORKTREE missing"
  fi

  if check_g5 "$CANONICAL"; then
    report PASS "canonical ORCHESTRATION: exit funnel (4>3>2>1>0, exit 1/5, quarantine markers)"
  else
    report FAIL "canonical ORCHESTRATION: exit funnel (4>3>2>1>0, exit 1/5, quarantine markers)" \
      "G5: precedence, exit 1/5, QUARANTINE- marker, or quarantine reasons missing"
  fi

  if check_g6 "$CANONICAL"; then
    report PASS "canonical ORCHESTRATION: merge gate per-story rung 3 (no run end)"
  else
    report FAIL "canonical ORCHESTRATION: merge gate per-story rung 3 (no run end)" \
      "G6: per-story rung 3 missing and/or stale 'rung 3 at run end' present"
  fi

  if check_g7 "$CANONICAL"; then
    report PASS "canonical ORCHESTRATION: Feature Flow mermaid identical to docs/agent-kit/guide/feature-workflow.md"
  else
    report FAIL "canonical ORCHESTRATION: Feature Flow mermaid identical to docs/agent-kit/guide/feature-workflow.md" \
      "G7: lifecycle mermaid block missing in template or docs guide, or the two blocks differ — keep them byte-identical"
  fi
fi

# ===========================================================================
# Instance mirrors — SKIP when absent, combined G1–G7 PASS when present.
# ===========================================================================
if [[ -f "$MIRROR_CLAUDE" ]]; then
  if check_all_g1_g7 "$MIRROR_CLAUDE"; then
    report PASS "instance mirror .claude/ORCHESTRATION.md: G1–G7"
  else
    report FAIL "instance mirror .claude/ORCHESTRATION.md: G1–G7" \
      "one or more G1–G7 claims regressed in .claude/ORCHESTRATION.md"
  fi
else
  skip_report "instance mirror .claude/ORCHESTRATION.md absent"
fi

if [[ -f "$MIRROR_CURSOR" ]]; then
  if check_all_g1_g7 "$MIRROR_CURSOR"; then
    report PASS "instance mirror .cursor/ORCHESTRATION.md: G1–G7"
  else
    report FAIL "instance mirror .cursor/ORCHESTRATION.md: G1–G7" \
      "one or more G1–G7 claims regressed in .cursor/ORCHESTRATION.md"
  fi
else
  skip_report "instance mirror .cursor/ORCHESTRATION.md absent"
fi

echo
echo "=== template-currency summary ==="
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
