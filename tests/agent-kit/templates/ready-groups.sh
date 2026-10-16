#!/usr/bin/env bash
# Regression guard for orchestration-ready-groups: locks ready-groups reference,
# feature-skill and ORCHESTRATION wiring, goal template parallel flag, harness-matrix
# and emitter caveats, emitted ready-groups instances, and a negative self-test on a
# copied template. Tracked, self-install-independent — no network, no LLM.
#
# Copy ready-groups.md into a mktemp dir, mutate under test, then run check logic
# against the copy — never the live repo (see check 7).
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location.
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
READY_GROUPS_REF="$TEMPLATES/skills/feature/reference/ready-groups.md"
FEATURE_SKILL="$TEMPLATES/skills/feature/SKILL.template.md"
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"
GOAL_TEMPLATE="$TEMPLATES/skills/feature/templates/goal.md"
GOAL_CRITERIA="$TEMPLATES/skills/goal-criteria/SKILL.template.md"
HARNESS_MATRIX="$REPO_ROOT/skills/agent-kit/reference/harness-matrix.md"
EMITTERS_DIR="$REPO_ROOT/skills/agent-kit/emitters"
READY_GROUPS_CURSOR="$REPO_ROOT/.cursor/skills/feature/reference/ready-groups.md"
READY_GROUPS_CLAUDE="$REPO_ROOT/.claude/skills/feature/reference/ready-groups.md"

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

check_canonical_ready_groups() { # check_canonical_ready_groups <file> → 0 if all anchors present
  local f="$1"
  reject_empty_path "$f" || return 1
  [[ -f "$f" ]] || return 1
  grep -qF 'up to **3**' "$f" || return 1
  grep -qF 'pairwise disjoint' "$f" || return 1
  grep -qF 'parallel: false' "$f" || return 1
  grep -qF 'NN in task order' "$f" || return 1
  grep -qF 'evaluator is **read-only**' "$f" || return 1
  grep -qF 'no writer (executor, fix cycle, instance refresh) is **in flight**' "$f" || return 1
  grep -qF '**Evaluator-in-flight rule:**' "$f" || return 1
  grep -qF 'Each member keeps its own fix-cycle accounting' "$f" || return 1
  grep -qF 'only after every in-flight evaluator' "$f" || return 1
  grep -qF 'The next ready group starts only when **every member**' "$f" || return 1
  grep -qF '**Baseline (before the group):**' "$f" || return 1
  grep -qF 'git status --porcelain --untracked-files=all' "$f" || return 1
  grep -qF 'Cross-check each' "$f" || return 1
  grep -qF 'whose paths are matched by fence alone' "$f" || return 1
  grep -qF 'designated closer' "$f" || return 1
  grep -qF 'ledger writes under the goal folder are exempt' "$f" || return 1
  grep -qF 'escalated for any reason' "$f" || return 1
  grep -qF '**concurrency-related**' "$f" || return 1
  grep -qF '**fall back**' "$f" || return 1
  if grep -qF 'harness-matrix' "$f" 2>/dev/null; then
    return 1
  fi
  return 0
}

check_emitted_ready_groups() { # check_emitted_ready_groups <file> → 0 if cap + fallback anchors
  local f="$1"
  reject_empty_path "$f" || return 1
  [[ -f "$f" ]] || return 1
  grep -qF 'up to **3**' "$f" || return 1
  grep -qF '**concurrency-related**' "$f" || return 1
  grep -qF '**fall back**' "$f" || return 1
}

# ===========================================================================
# 1. Canonical ready-groups.md anchors.
# ===========================================================================
if check_canonical_ready_groups "$READY_GROUPS_REF"; then
  report PASS "canonical ready-groups.md: cap, disjoint writes, parallel false, rules, no harness-matrix link"
else
  report FAIL "canonical ready-groups.md: cap, disjoint writes, parallel false, rules, no harness-matrix link" \
    "missing file or anchor in $READY_GROUPS_REF"
fi

# ===========================================================================
# 2. Feature skill Phase 4 wiring.
# ===========================================================================
check2_ok=1
if [[ ! -f "$FEATURE_SKILL" ]]; then
  check2_ok=0
else
  grep -qF 'reference/ready-groups.md' "$FEATURE_SKILL" || check2_ok=0
  grep -qF 'parallel: false' "$FEATURE_SKILL" || check2_ok=0
fi
if [[ $check2_ok -eq 1 ]]; then
  report PASS "feature skill: Phase 4 reference/ready-groups.md and parallel: false"
else
  report FAIL "feature skill: Phase 4 reference/ready-groups.md and parallel: false"
fi

# ===========================================================================
# 3. ORCHESTRATION.md Phase 4 notes, repository group variant, file trees.
# ===========================================================================
check3_ok=1
if [[ ! -f "$ORCH_TEMPLATE" ]]; then
  check3_ok=0
else
  grep -qF 'group (`reference/ready-groups.md`)' "$ORCH_TEMPLATE" || check3_ok=0
  grep -qF 'up to **three** write-disjoint' "$ORCH_TEMPLATE" || check3_ok=0
  grep -qF '**Group variant:**' "$ORCH_TEMPLATE" || check3_ok=0
  grep -qF 'reference/ready-groups.md' "$ORCH_TEMPLATE" || check3_ok=0
  grep -qF 'preflight.md,ready-groups.md,' "$ORCH_TEMPLATE" || check3_ok=0
fi
if [[ $check3_ok -eq 1 ]]; then
  report PASS "ORCHESTRATION.md: Phase 4 ready groups, repository group variant, file-tree entry"
else
  report FAIL "ORCHESTRATION.md: Phase 4 ready groups, repository group variant, file-tree entry"
fi

# ===========================================================================
# 4. goal.md parallel flag and goal-criteria validation.
# ===========================================================================
check4_ok=1
if [[ ! -f "$GOAL_TEMPLATE" ]]; then
  check4_ok=0
else
  grep -qF 'phases:' "$GOAL_TEMPLATE" || check4_ok=0
  grep -qF 'parallel:' "$GOAL_TEMPLATE" || check4_ok=0
fi
if [[ ! -f "$GOAL_CRITERIA" ]]; then
  check4_ok=0
else
  grep -qF 'Phase 4 concurrency (`parallel:`)' "$GOAL_CRITERIA" || check4_ok=0
  grep -qF 'when present it must be `true` or `false`' "$GOAL_CRITERIA" || check4_ok=0
fi
if [[ $check4_ok -eq 1 ]]; then
  report PASS "goal template parallel: and goal-criteria parallel validation"
else
  report FAIL "goal template parallel: and goal-criteria parallel validation"
fi

# ===========================================================================
# 5. harness-matrix row and emitter ready-group caveats.
# ===========================================================================
check5_ok=1
if [[ ! -f "$HARNESS_MATRIX" ]]; then
  check5_ok=0
elif ! grep -qF 'Concurrent subagent spawns (ready groups)' "$HARNESS_MATRIX" 2>/dev/null; then
  check5_ok=0
fi
for emitter in claude-code cursor copilot codex; do
  emitter_file="$EMITTERS_DIR/$emitter.md"
  if [[ ! -f "$emitter_file" ]]; then
    check5_ok=0
    break
  fi
  grep -qFi 'ready group' "$emitter_file" || check5_ok=0
  grep -qF 'parallel: false' "$emitter_file" || check5_ok=0
done
if [[ $check5_ok -eq 1 ]]; then
  report PASS "harness-matrix concurrent spawns row and four emitters: ready groups + parallel: false"
else
  report FAIL "harness-matrix concurrent spawns row and four emitters: ready groups + parallel: false"
fi

# ===========================================================================
# 6. Emitted ready-groups instances (SKIP when absent).
# ===========================================================================
for inst_pair in \
  ".cursor:$READY_GROUPS_CURSOR" \
  ".claude:$READY_GROUPS_CLAUDE"; do
  inst_label="${inst_pair%%:*}"
  inst_path="${inst_pair#*:}"
  if [[ ! -f "$inst_path" ]]; then
    skip_report "emitted $inst_label/skills/feature/reference/ready-groups.md absent"
    continue
  fi
  if check_emitted_ready_groups "$inst_path"; then
    report PASS "emitted $inst_label/skills/feature/reference/ready-groups.md: cap and fallback phrases"
  else
    report FAIL "emitted $inst_label/skills/feature/reference/ready-groups.md: cap and fallback phrases" \
      "regression in $inst_path"
  fi
done

# ===========================================================================
# 7. Negative self-test: mutated copy must fail check-1 logic.
# ===========================================================================
neg_ok=0
neg_root="$(mktemp -d "${TMPDIR:-/tmp}/readygroupsneg.XXXXXX")" || neg_root=""
if [[ -z "$neg_root" || ! -d "$neg_root" ]]; then
  report FAIL "negative self-test: check-1 fails when cap phrase removed from copy" \
    "mktemp -d failed"
else
  mkdir -p "$neg_root/skills/agent-kit/templates/skills/feature/reference" || true
  if cp "$READY_GROUPS_REF" "$neg_root/skills/agent-kit/templates/skills/feature/reference/ready-groups.md"; then
    sed '/up to \*\*3\*\*/d' \
      "$neg_root/skills/agent-kit/templates/skills/feature/reference/ready-groups.md" > \
      "$neg_root/skills/agent-kit/templates/skills/feature/reference/ready-groups.md.tmp" \
      && mv "$neg_root/skills/agent-kit/templates/skills/feature/reference/ready-groups.md.tmp" \
         "$neg_root/skills/agent-kit/templates/skills/feature/reference/ready-groups.md"
    neg_ref="$neg_root/skills/agent-kit/templates/skills/feature/reference/ready-groups.md"
    if check_canonical_ready_groups "$neg_ref"; then
      neg_ok=0
    else
      neg_ok=1
    fi
  fi
  rm -rf "$neg_root"
fi
if [[ $neg_ok -eq 1 ]]; then
  report PASS "negative self-test: check-1 fails when cap phrase removed from copied ready-groups.md"
else
  report FAIL "negative self-test: check-1 fails when cap phrase removed from copied ready-groups.md"
fi

if check_canonical_ready_groups ""; then
  report FAIL "check-1 rejects empty path arguments"
else
  report PASS "check-1 rejects empty path arguments"
fi

echo
echo "=== ready-groups summary ==="
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
