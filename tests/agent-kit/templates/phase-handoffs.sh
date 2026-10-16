#!/usr/bin/env bash
# Guard: align-docs working-tree change set and research path-Read handoff in canonical
# templates. Tracked, self-install-independent — checks skills/agent-kit/templates/
# directly. Copy this repo's skills/agent-kit/ + tests/agent-kit/ subtree into mktemp,
# mutate a template under test, then run the COPIED script: HERE and REPO_ROOT resolve
# relative to this script's location, so the copy checks the mutated copy, not the live
# repo. No network, no external services.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
ALIGN_DOCS="$TEMPLATES/skills/align-docs/SKILL.template.md"
RESEARCH="$TEMPLATES/skills/research/SKILL.template.md"

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

# --- check helpers (optional path override for mutation copies) ---

check_a_align_working_tree_cmds() {
  local f="${1:-$ALIGN_DOCS}"
  [[ -f "$f" ]] || return 1
  grep -qF -- 'git merge-base <base> HEAD' "$f" || return 1
  grep -qF -- 'git diff --stat "$BASE_SHA"' "$f" || return 1
  grep -qF -- 'git diff --name-only --no-renames "$BASE_SHA"' "$f" || return 1
  grep -qF -- 'git ls-files --others --exclude-standard' "$f" || return 1
  return 0
}

check_b_align_no_three_dot_range() {
  local f="${1:-$ALIGN_DOCS}"
  [[ -f "$f" ]] || return 1
  ! grep -qF -- '<base>...HEAD' "$f"
}

check_c_align_phase6_tree_diff() {
  local f="${1:-$ALIGN_DOCS}"
  [[ -f "$f" ]] || return 1
  grep -qF -- 'git write-tree' "$f" || return 1
  grep -qF -- 'git diff --name-status --no-renames "$PHASE6_TREE"' "$f" || return 1
  grep -qF -- 'never under `_memory/`' "$f" || return 1
  return 0
}

check_d_align_no_only_docs_phrase() {
  local f="${1:-$ALIGN_DOCS}"
  [[ -f "$f" ]] || return 1
  ! grep -qF -- 'shows **only** documentation files changed' "$f"
}

check_e_align_not_owned_phrase() {
  local f="${1:-$ALIGN_DOCS}"
  [[ -f "$f" ]] || return 1
  grep -qF -- 'not owned by this goal' "$f"
}

check_f_research_feature_path_read() {
  local f="${1:-$RESEARCH}"
  [[ -f "$f" ]] || return 1
  grep -qF -- '{{IDE_DIR}}/skills/feature/SKILL.md' "$f"
}

check_g_research_phase3_eval() {
  local f="${1:-$RESEARCH}"
  [[ -f "$f" ]] || return 1
  grep -qF -- 'Phase 3 (goal evaluation)' "$f"
}

check_h_research_no_legacy_handoff() {
  local f="${1:-$RESEARCH}"
  [[ -f "$f" ]] || return 1
  ! grep -qF -- 'Hand off: the goal enters' "$f"
}

run_canonical_checks() {
  if check_a_align_working_tree_cmds; then
    report PASS "(a) align-docs: working-tree git commands present"
  else
    report FAIL "(a) align-docs: working-tree git commands present"
  fi

  if check_b_align_no_three_dot_range; then
    report PASS "(b) align-docs: no <base>...HEAD three-dot range"
  else
    report FAIL "(b) align-docs: no <base>...HEAD three-dot range"
  fi

  if check_c_align_phase6_tree_diff; then
    report PASS "(c) align-docs: Phase 6 write-tree + name-status diff + never under _memory/"
  else
    report FAIL "(c) align-docs: Phase 6 write-tree + name-status diff + never under _memory/"
  fi

  if check_d_align_no_only_docs_phrase; then
    report PASS "(d) align-docs: no shows **only** documentation files changed"
  else
    report FAIL "(d) align-docs: no shows **only** documentation files changed"
  fi

  if check_e_align_not_owned_phrase; then
    report PASS "(e) align-docs: not owned by this goal"
  else
    report FAIL "(e) align-docs: not owned by this goal"
  fi

  if check_f_research_feature_path_read; then
    report PASS "(f) research: path-Read {{IDE_DIR}}/skills/feature/SKILL.md"
  else
    report FAIL "(f) research: path-Read {{IDE_DIR}}/skills/feature/SKILL.md"
  fi

  if check_g_research_phase3_eval; then
    report PASS "(g) research: Phase 3 (goal evaluation)"
  else
    report FAIL "(g) research: Phase 3 (goal evaluation)"
  fi

  if check_h_research_no_legacy_handoff; then
    report PASS "(h) research: no Hand off: the goal enters"
  else
    report FAIL "(h) research: no Hand off: the goal enters"
  fi
}

mutation_expect_script_fail() {
  local name="$1" script="$2" rc
  PHASE_HANDOFFS_SKIP_COPY_PROOFS=1 bash "$script" >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    report FAIL "$name" "copied script still exited 0 on mutant tree"
    return 1
  fi
  report PASS "$name: copied script exits non-zero on mutant tree (rc=$rc)"
  return 0
}

copy_subtree_for_script() {
  local root="$1"
  mkdir -p "$root/skills" "$root/tests/agent-kit"
  cp -a "$REPO_ROOT/skills/agent-kit" "$root/skills/"
  cp -a "$REPO_ROOT/tests/agent-kit/templates" "$root/tests/agent-kit/"
  cp -a "$REPO_ROOT/tests/agent-kit/lib" "$root/tests/agent-kit/"
}

run_canonical_checks

# --- mutation proofs: mktemp copy of skills/ + tests/, run the copied guard ---
if [[ "${PHASE_HANDOFFS_SKIP_COPY_PROOFS:-}" == 1 ]]; then
  echo
  echo "=== phase-handoffs summary ==="
  echo "PASS: $pass_count   FAIL: $fail_count"
  if ((fail_count)); then
    echo "RESULT: $fail_count assertion(s) FAILED"
    exit 1
  fi
  echo "RESULT: all assertions passed"
  exit 0
fi

FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/phase-handoffs.XXXXXX")" || exit 1
trap 'rm -rf "${FIXTURE_TMPDIR:-}"' EXIT
# shellcheck source=../lib/fixture-root.sh
REPO_ROOT="$REPO_ROOT" FIXTURE_TMPDIR="$FIXTURE_TMPDIR" source "$HERE/../lib/fixture-root.sh"

require_fixture_root() {
  if ! assert_fixture_root "$1"; then
    report FAIL "fixture-root" "refused mutation path (fail closed): $1"
    return 1
  fi
}

mut_root="$FIXTURE_TMPDIR/align-three-dot"
mkdir -p "$mut_root"
require_fixture_root "$mut_root" || exit 1
copy_subtree_for_script "$mut_root"
align_mut="$mut_root/skills/agent-kit/templates/skills/align-docs/SKILL.template.md"
sed -i 's/git merge-base <base> HEAD/<base>...HEAD/' "$align_mut"
copied="$mut_root/tests/agent-kit/templates/phase-handoffs.sh"
mutation_expect_script_fail "align-docs three-dot range restored" "$copied"

mut_root="$FIXTURE_TMPDIR/research-no-path-read"
mkdir -p "$mut_root"
require_fixture_root "$mut_root" || exit 1
copy_subtree_for_script "$mut_root"
research_mut="$mut_root/skills/agent-kit/templates/skills/research/SKILL.template.md"
sed -i '/{{IDE_DIR}}\/skills\/feature\/SKILL.md/d' "$research_mut"
copied="$mut_root/tests/agent-kit/templates/phase-handoffs.sh"
mutation_expect_script_fail "research feature path-Read removed" "$copied"

rm -rf "$FIXTURE_TMPDIR"
FIXTURE_TMPDIR=""
trap - EXIT

echo
echo "=== phase-handoffs summary ==="
echo "PASS: $pass_count   FAIL: $fail_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
