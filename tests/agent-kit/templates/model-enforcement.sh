#!/usr/bin/env bash
# Regression guard for the token-efficiency-a-policy goal: locks ## Model
# sections, self-reported model lines, PASS (with notes) / severity minor, ladder
# phases, align_docs default, models.map spawn naming, task tier defaults, loop
# ladder:auto, align-docs small-change fold, and minimum kit VERSION. Tracked,
# self-install-independent — no network, no LLM.
#
# Copy this repo's `tests/` + `skills/` + `.claude/` + `.cursor/` + `_loop/` +
# `README.md` + `ORCHESTRATION.md` subtree into a mktemp dir, mutate a guarded
# string, then run the COPIED script: HERE and REPO_ROOT resolve relative to
# this script's own location, so the copy checks the mutated copy, not the live
# repo.
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location.
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../lib/kit-version.sh
source "$REPO_ROOT/tests/agent-kit/lib/kit-version.sh"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
FEATURE_TPL="$TEMPLATES/skills/feature/SKILL.template.md"
GOAL_TPL="$TEMPLATES/skills/feature/templates/goal.md"
TASK_TPL="$TEMPLATES/skills/feature/templates/task.md"
ORCH_TPL="$TEMPLATES/ORCHESTRATION.md"
MODELS_MAP="$TEMPLATES/models.map.md"
EVALUATOR_TPL="$TEMPLATES/agents/evaluator.md"
TASK_CRITERIA_TPL="$TEMPLATES/skills/task-criteria/SKILL.template.md"
ALIGN_DOCS_TPL="$TEMPLATES/skills/align-docs/SKILL.template.md"
LOOP_SKILL_TPL="$TEMPLATES/loop/SKILL.template.md"
LOOP_PROMPT_TPL="$TEMPLATES/loop/PROMPT.md"
VERSION_FILE="$REPO_ROOT/skills/agent-kit/SKILL.md"

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

file_has() { # file_has <file> <needle>
  [[ -f "$1" ]] && grep -qF "$2" "$1"
}

check_paths_all() { # check_paths_all <needle> <path>...
  local needle="$1" p
  shift
  for p in "$@"; do
    [[ -f "$p" ]] || return 1
    grep -qF "$needle" "$p" || return 1
  done
}

check_instance_paths() { # check_instance_paths <inst_dir> <check_name> <needle> <relpath>...
  local inst_dir="$1" check_name="$2" needle="$3"
  shift 3
  local inst_root="$REPO_ROOT/$inst_dir"
  if [[ ! -d "$inst_root" ]]; then
    skip_report "$check_name ($inst_dir/ absent)"
    return 0
  fi
  local rel f
  for rel in "$@"; do
    f="$inst_root/$rel"
    if [[ ! -f "$f" ]]; then
      report FAIL "$check_name" "missing $inst_dir/$rel"
      return 1
    fi
    if ! grep -qF "$needle" "$f"; then
      report FAIL "$check_name" "$inst_dir/$rel: '$needle' missing"
      return 1
    fi
  done
  return 0
}

# ===========================================================================
# (a) ## Model in canonical + instance feature skills.
# ===========================================================================
check_a_ok=1
check_a_detail=""
for f in \
  "$FEATURE_TPL" \
  "$REPO_ROOT/.claude/skills/feature/SKILL.md" \
  "$REPO_ROOT/.cursor/skills/feature/SKILL.md"; do
  rel="${f#"$REPO_ROOT"/}"
  if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
    inst="${rel%%/*}"
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(a) ## Model in feature skills ($inst/ absent)"
      continue
    fi
  fi
  if [[ ! -f "$f" ]]; then
    check_a_ok=0
    check_a_detail="missing $rel"
    break
  fi
  if ! grep -qF '## Model' "$f"; then
    check_a_ok=0
    check_a_detail="$rel: ## Model missing"
    break
  fi
done
if [[ $check_a_ok -eq 1 ]]; then
  report PASS "(a) ## Model in canonical + instance feature skills"
else
  report FAIL "(a) ## Model in canonical + instance feature skills" "$check_a_detail"
fi

# ===========================================================================
# (b) Model (self-reported) in six canonical + twelve instance agent templates.
# ===========================================================================
check_b_ok=1
check_b_detail=""
for agent in diagnostician evaluator implementer qa-evaluator terminal test-writer; do
  f="$TEMPLATES/agents/${agent}.md"
  if ! file_has "$f" 'Model (self-reported)'; then
    check_b_ok=0
    check_b_detail="${f#"$REPO_ROOT"/}: Model (self-reported) missing"
    break
  fi
done
if [[ $check_b_ok -eq 1 ]]; then
  for inst in .claude .cursor; do
    if [[ ! -d "$REPO_ROOT/$inst/agents" ]]; then
      skip_report "(b) Model (self-reported) in instance agents ($inst/agents absent)"
      continue
    fi
    for agent in diagnostician evaluator implementer qa-evaluator terminal test-writer; do
      f="$REPO_ROOT/$inst/agents/${agent}.md"
      if [[ ! -f "$f" ]] || ! grep -qF 'Model (self-reported)' "$f"; then
        check_b_ok=0
        check_b_detail="${f#"$REPO_ROOT"/}: Model (self-reported) missing"
        break 2
      fi
    done
  done
fi
if [[ $check_b_ok -eq 1 ]]; then
  report PASS "(b) Model (self-reported) in six canonical + twelve instance agent templates"
else
  report FAIL "(b) Model (self-reported) in six canonical + twelve instance agent templates" \
    "$check_b_detail"
fi

# ===========================================================================
# (c) PASS (with notes) in evaluator + task-criteria (canonical + instance).
# ===========================================================================
check_c_ok=1
check_c_detail=""
for f in \
  "$EVALUATOR_TPL" \
  "$TASK_CRITERIA_TPL"; do
  if ! file_has "$f" 'PASS (with notes)'; then
    check_c_ok=0
    check_c_detail="${f#"$REPO_ROOT"/}: PASS (with notes) missing"
    break
  fi
done
if [[ $check_c_ok -eq 1 ]]; then
  for inst in .claude .cursor; do
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(c) PASS (with notes) in evaluator + task-criteria ($inst/ absent)"
      continue
    fi
    for rel in agents/evaluator.md skills/task-criteria/SKILL.md; do
      f="$REPO_ROOT/$inst/$rel"
      if [[ ! -f "$f" ]] || ! grep -qF 'PASS (with notes)' "$f"; then
        check_c_ok=0
        check_c_detail="${f#"$REPO_ROOT"/}: PASS (with notes) missing"
        break 2
      fi
    done
  done
fi
if [[ $check_c_ok -eq 1 ]]; then
  report PASS "(c) PASS (with notes) in evaluator + task-criteria (canonical + instance)"
else
  report FAIL "(c) PASS (with notes) in evaluator + task-criteria (canonical + instance)" \
    "$check_c_detail"
fi

# ===========================================================================
# (d) ## Severity: minor in canonical + instance task-criteria.
# ===========================================================================
check_d_ok=1
check_d_detail=""
if ! file_has "$TASK_CRITERIA_TPL" '## Severity: minor'; then
  check_d_ok=0
  check_d_detail="canonical task-criteria: ## Severity: minor missing"
fi
if [[ $check_d_ok -eq 1 ]]; then
  for inst in .claude .cursor; do
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(d) ## Severity: minor in task-criteria ($inst/ absent)"
      continue
    fi
    f="$REPO_ROOT/$inst/skills/task-criteria/SKILL.md"
    if [[ ! -f "$f" ]] || ! grep -qF '## Severity: minor' "$f"; then
      check_d_ok=0
      check_d_detail="${f#"$REPO_ROOT"/}: ## Severity: minor missing"
      break
    fi
  done
fi
if [[ $check_d_ok -eq 1 ]]; then
  report PASS "(d) ## Severity: minor in canonical + instance task-criteria"
else
  report FAIL "(d) ## Severity: minor in canonical + instance task-criteria" "$check_d_detail"
fi

# ===========================================================================
# (e) ladder: escalate|auto in goal.md; phases.ladder or ladder: in feature + ORCH.
# ===========================================================================
check_e_ok=1
check_e_detail=""
for goal in \
  "$GOAL_TPL" \
  "$REPO_ROOT/.claude/skills/feature/templates/goal.md" \
  "$REPO_ROOT/.cursor/skills/feature/templates/goal.md"; do
  rel="${goal#"$REPO_ROOT"/}"
  if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
    inst="${rel%%/*}"
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(e) ladder phases in goal/feature/ORCH ($inst/ absent)"
      continue
    fi
  fi
  if [[ ! -f "$goal" ]] || ! grep -qF 'ladder: escalate|auto' "$goal"; then
    check_e_ok=0
    check_e_detail="$rel: ladder: escalate|auto missing"
    break
  fi
done
if [[ $check_e_ok -eq 1 ]]; then
  for feat in \
    "$FEATURE_TPL" \
    "$REPO_ROOT/.claude/skills/feature/SKILL.md" \
    "$REPO_ROOT/.cursor/skills/feature/SKILL.md"; do
    rel="${feat#"$REPO_ROOT"/}"
    if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
      inst="${rel%%/*}"
      [[ -d "$REPO_ROOT/$inst" ]] || continue
    fi
    if [[ ! -f "$feat" ]]; then
      check_e_ok=0
      check_e_detail="missing $rel"
      break
    fi
    if ! grep -qE 'phases\.ladder|ladder:' "$feat"; then
      check_e_ok=0
      check_e_detail="$rel: phases.ladder or ladder: missing"
      break
    fi
  done
fi
if [[ $check_e_ok -eq 1 ]]; then
  for orch in \
    "$ORCH_TPL" \
    "$REPO_ROOT/.claude/ORCHESTRATION.md" \
    "$REPO_ROOT/.cursor/ORCHESTRATION.md"; do
    rel="${orch#"$REPO_ROOT"/}"
    if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
      inst="${rel%%/*}"
      if [[ ! -d "$REPO_ROOT/$inst" ]]; then
        skip_report "(e) ladder in ORCHESTRATION ($inst/ absent)"
        continue
      fi
    fi
    if [[ ! -f "$orch" ]]; then
      check_e_ok=0
      check_e_detail="missing $rel"
      break
    fi
    if ! grep -qE 'phases\.ladder|ladder:' "$orch"; then
      check_e_ok=0
      check_e_detail="$rel: phases.ladder or ladder: missing"
      break
    fi
  done
fi
if [[ $check_e_ok -eq 1 ]]; then
  report PASS "(e) ladder: escalate|auto in goal.md; phases.ladder or ladder: in feature + ORCH"
else
  report FAIL "(e) ladder: escalate|auto in goal.md; phases.ladder or ladder: in feature + ORCH" \
    "$check_e_detail"
fi

# ===========================================================================
# (f) (default false) on align_docs line in canonical + instance goal.md.
# ===========================================================================
check_f_ok=1
check_f_detail=""
for goal in \
  "$GOAL_TPL" \
  "$REPO_ROOT/.claude/skills/feature/templates/goal.md" \
  "$REPO_ROOT/.cursor/skills/feature/templates/goal.md"; do
  rel="${goal#"$REPO_ROOT"/}"
  if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
    inst="${rel%%/*}"
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(f) align_docs (default false) in goal.md ($inst/ absent)"
      continue
    fi
  fi
  if [[ ! -f "$goal" ]] || ! grep -qF '(default false)' "$goal"; then
    check_f_ok=0
    check_f_detail="$rel: (default false) missing on align_docs line"
    break
  fi
done
if [[ $check_f_ok -eq 1 ]]; then
  report PASS "(f) (default false) on align_docs line in canonical + instance goal.md"
else
  report FAIL "(f) (default false) on align_docs line in canonical + instance goal.md" \
    "$check_f_detail"
fi

# ===========================================================================
# (g) code-tier work absent; Every spawn names its model present in models maps.
# ===========================================================================
check_g_ok=1
check_g_detail=""
for map in \
  "$MODELS_MAP" \
  "$REPO_ROOT/.claude/skills/agent-kit-models.map.md" \
  "$REPO_ROOT/.cursor/skills/agent-kit-models.map.md"; do
  rel="${map#"$REPO_ROOT"/}"
  if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
    inst="${rel%%/*}"
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(g) models.map spawn naming ($inst/ absent)"
      continue
    fi
  fi
  if [[ ! -f "$map" ]]; then
    check_g_ok=0
    check_g_detail="missing $rel"
    break
  fi
  if grep -qF 'code-tier work' "$map"; then
    check_g_ok=0
    check_g_detail="$rel: code-tier work must be absent"
    break
  fi
  if ! grep -qF 'Every spawn names its model' "$map"; then
    check_g_ok=0
    check_g_detail="$rel: Every spawn names its model missing"
    break
  fi
done
if [[ $check_g_ok -eq 1 ]]; then
  report PASS "(g) code-tier work absent; Every spawn names its model in models maps"
else
  report FAIL "(g) code-tier work absent; Every spawn names its model in models maps" \
    "$check_g_detail"
fi

# ===========================================================================
# (h) Default: light in canonical + instance task.md templates.
# ===========================================================================
check_h_ok=1
check_h_detail=""
for task in \
  "$TASK_TPL" \
  "$REPO_ROOT/.claude/skills/feature/templates/task.md" \
  "$REPO_ROOT/.cursor/skills/feature/templates/task.md"; do
  rel="${task#"$REPO_ROOT"/}"
  if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
    inst="${rel%%/*}"
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(h) Default: light in task.md ($inst/ absent)"
      continue
    fi
  fi
  if [[ ! -f "$task" ]] || ! grep -qF 'Default: light' "$task"; then
    check_h_ok=0
    check_h_detail="$rel: Default: light missing"
    break
  fi
done
if [[ $check_h_ok -eq 1 ]]; then
  report PASS "(h) Default: light in canonical + instance task.md templates"
else
  report FAIL "(h) Default: light in canonical + instance task.md templates" "$check_h_detail"
fi

# ===========================================================================
# (i) ladder: auto in loop skill, auto-loop instances, loop PROMPT, _loop PROMPT.
# ===========================================================================
check_i_ok=1
check_i_detail=""
for f in "$LOOP_SKILL_TPL" "$LOOP_PROMPT_TPL" "$REPO_ROOT/_loop/PROMPT.md"; do
  if [[ ! -f "$f" ]] || ! grep -qF 'ladder: auto' "$f"; then
    check_i_ok=0
    check_i_detail="${f#"$REPO_ROOT"/}: ladder: auto missing"
    break
  fi
done
if [[ $check_i_ok -eq 1 ]]; then
  for inst in .claude .cursor; do
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(i) ladder: auto in auto-loop ($inst/ absent)"
      continue
    fi
    f="$REPO_ROOT/$inst/skills/auto-loop/SKILL.md"
    if [[ ! -f "$f" ]] || ! grep -qF 'ladder: auto' "$f"; then
      check_i_ok=0
      check_i_detail="${f#"$REPO_ROOT"/}: ladder: auto missing"
      break
    fi
  done
fi
if [[ $check_i_ok -eq 1 ]]; then
  report PASS "(i) ladder: auto in loop skill, auto-loop instances, loop + _loop PROMPT"
else
  report FAIL "(i) ladder: auto in loop skill, auto-loop instances, loop + _loop PROMPT" \
    "$check_i_detail"
fi

# ===========================================================================
# (j) Small-change fold in canonical + instance align-docs skills.
# ===========================================================================
check_j_ok=1
check_j_detail=""
if ! file_has "$ALIGN_DOCS_TPL" 'Small-change fold'; then
  check_j_ok=0
  check_j_detail="canonical align-docs: Small-change fold missing"
fi
if [[ $check_j_ok -eq 1 ]]; then
  for inst in .claude .cursor; do
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      skip_report "(j) Small-change fold in align-docs ($inst/ absent)"
      continue
    fi
    f="$REPO_ROOT/$inst/skills/align-docs/SKILL.md"
    if [[ ! -f "$f" ]] || ! grep -qF 'Small-change fold' "$f"; then
      check_j_ok=0
      check_j_detail="${f#"$REPO_ROOT"/}: Small-change fold missing"
      break
    fi
  done
fi
if [[ $check_j_ok -eq 1 ]]; then
  report PASS "(j) Small-change fold in canonical + instance align-docs skills"
else
  report FAIL "(j) Small-change fold in canonical + instance align-docs skills" "$check_j_detail"
fi

# ===========================================================================
# (k) skills/agent-kit/SKILL.md metadata.version is valid semver ≥ 1.0.0.
# ===========================================================================
if [[ ! -f "$VERSION_FILE" ]]; then
  report FAIL "(k) skills/agent-kit/SKILL.md metadata.version is valid semver ≥ 1.0.0" "VERSION file missing"
else
  kit_ver="$(kit_version "$VERSION_FILE")"
  if [[ "$kit_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
     && printf '%s\n' "1.0.0" "$kit_ver" | sort -C -V; then
    report PASS "(k) skills/agent-kit/SKILL.md metadata.version is valid semver ≥ 1.0.0 ($kit_ver)"
  else
    report FAIL "(k) skills/agent-kit/SKILL.md metadata.version is valid semver ≥ 1.0.0" "contents: '${kit_ver:-<empty>}'"
  fi
fi

# ===========================================================================
# (l) ### Footprint in six canonical + twelve instance agent files.
# ===========================================================================
check_l_ok=1
check_l_detail=""
for agent in diagnostician evaluator implementer qa-evaluator terminal test-writer; do
  f="$TEMPLATES/agents/${agent}.md"
  if ! file_has "$f" '### Footprint'; then
    check_l_ok=0
    check_l_detail="${f#"$REPO_ROOT"/}: ### Footprint missing"
    break
  fi
done
if [[ $check_l_ok -eq 1 ]]; then
  for inst in .claude .cursor; do
    if [[ ! -d "$REPO_ROOT/$inst/agents" ]]; then
      skip_report "(l) ### Footprint in instance agents ($inst/agents absent)"
      continue
    fi
    for agent in diagnostician evaluator implementer qa-evaluator terminal test-writer; do
      f="$REPO_ROOT/$inst/agents/${agent}.md"
      if [[ ! -f "$f" ]] || ! grep -qF '### Footprint' "$f"; then
        check_l_ok=0
        check_l_detail="${f#"$REPO_ROOT"/}: ### Footprint missing"
        break 2
      fi
    done
  done
fi
if [[ $check_l_ok -eq 1 ]]; then
  report PASS "(l) ### Footprint in six canonical + twelve instance agent files"
else
  report FAIL "(l) ### Footprint in six canonical + twelve instance agent files" \
    "$check_l_detail"
fi

echo
echo "=== model-enforcement summary ==="
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
