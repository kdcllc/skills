#!/usr/bin/env bash
# Regression guard for the autonomous-escalation-ladder goal (v0.20.0): locks in the
# Phase 4 continuation-ladder subsection, failure-class taxonomy identity across
# canonical templates, diagnostician template + dual-instance emission, tools-line
# hygiene, hardcoded-model-ID absence, per-emitter diagnostician wiring,
# {{MODEL_FRONTIER_ALT_FAMILY}} documentation, feature-skill guard anchors,
# bypass-class dual presence, evaluator arbitration verdict strings, research-doc
# linkage, and version/subagent-count consistency. Tracked, self-install-independent
# — checks the canonical templates/ source tree, root docs, and emitted instance
# paths directly (no network, no LLM, no `_loop/` required).
#
# Copy this repo's `tests/` + `skills/` + `docs/` + `README.md` + `ORCHESTRATION.md`
# subtree into a mktemp dir, mutate a file under test, then run the COPIED script:
# HERE and REPO_ROOT resolve relative to this script's own location, so the copy
# checks the mutated copy, not the live repo.
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
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"
FEATURE_SKILL="$TEMPLATES/skills/feature/SKILL.template.md"
LADDER_REF="$TEMPLATES/skills/feature/reference/continuation-ladder.md"
LADDER_CLAUDE="$REPO_ROOT/.claude/skills/feature/reference/continuation-ladder.md"
LADDER_CURSOR="$REPO_ROOT/.cursor/skills/feature/reference/continuation-ladder.md"
FEATURE_CLAUDE="$REPO_ROOT/.claude/skills/feature/SKILL.md"
FEATURE_CURSOR="$REPO_ROOT/.cursor/skills/feature/SKILL.md"
EVALUATOR="$TEMPLATES/agents/evaluator.md"
DIAGNOSTICIAN="$TEMPLATES/agents/diagnostician.md"
TASK_CRITERIA="$TEMPLATES/skills/task-criteria/SKILL.template.md"
MODELS_MAP="$TEMPLATES/models.map.md"
SETUP_SKILL="$REPO_ROOT/skills/agent-kit/SKILL.md"
EMITTERS="$REPO_ROOT/skills/agent-kit/emitters"
EMIT_SH="$REPO_ROOT/skills/agent-kit/bin/emit.sh"
VERSION_FILE="$REPO_ROOT/skills/agent-kit/SKILL.md"
ROOT_README="$REPO_ROOT/skills/agent-kit/README.md"
ROOT_ORCHESTRATION="$REPO_ROOT/docs/agent-kit/ORCHESTRATION.md"
RESEARCH_DOC="$REPO_ROOT/docs/agent-kit/research-autonomous-escalation.md"
EMITTED_ORCH="$REPO_ROOT/.claude/ORCHESTRATION.md"
EMITTED_DIAG_CLAUDE="$REPO_ROOT/.claude/agents/diagnostician.md"
EMITTED_DIAG_CURSOR="$REPO_ROOT/.cursor/agents/diagnostician.md"

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

frontmatter() {
  awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f{print}' "$1" 2>/dev/null
}

extract_ladder_section() {
  awk '/^### Continuation ladder/{p=1;next} p&&/^### /{exit} p' "$1" 2>/dev/null
}

normalize_taxonomy_prose() {
  tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/ \./\./g; s/Bypass subset.*//; s/[[:space:]]*$//'
}

extract_taxonomy_from_file() {
  local f="$1"
  local ladder=""
  if [[ "$f" == "$ORCH_TEMPLATE" ]]; then
    ladder="$(extract_ladder_section "$f")"
    awk '
      /Failure-class taxonomy \(closed set\)/ { p=1 }
      p {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /Bypass/) { exit }
          printf "%s ", $i
        }
        printf "\n"
        if ($0 ~ /`infra`\./) { exit }
      }
    ' <<<"$ladder" | normalize_taxonomy_prose
  else
    grep -F 'Failure-class taxonomy (closed set):' "$f" 2>/dev/null | head -1 | normalize_taxonomy_prose
  fi
}

# ===========================================================================
# 1. Continuation ladder section in canonical and emitted ORCHESTRATION.
# ===========================================================================
check1_ok=1
if ! grep -qF '### Continuation ladder (Phase 4 task execution)' "$ORCH_TEMPLATE" 2>/dev/null; then
  check1_ok=0
fi
if ! rg --no-ignore -qF '### Continuation ladder (Phase 4 task execution)' "$EMITTED_ORCH" 2>/dev/null; then
  check1_ok=0
fi
if [[ $check1_ok -eq 1 ]]; then
  report PASS "Continuation ladder section in canonical and emitted ORCHESTRATION"
else
  report FAIL "Continuation ladder section in canonical and emitted ORCHESTRATION" \
    "heading missing in canonical template and/or .claude/ORCHESTRATION.md"
fi

# ===========================================================================
# 2. Failure-class taxonomy character-identical across three canonical templates.
# ===========================================================================
tax_orch="$(extract_taxonomy_from_file "$ORCH_TEMPLATE")"
tax_eval="$(extract_taxonomy_from_file "$EVALUATOR")"
tax_task="$(extract_taxonomy_from_file "$TASK_CRITERIA")"
if [[ -n "$tax_orch" && -n "$tax_eval" && -n "$tax_task" \
      && "$tax_orch" == "$tax_eval" && "$tax_eval" == "$tax_task" ]]; then
  report PASS "failure-class taxonomy character-identical across three canonical templates"
else
  report FAIL "failure-class taxonomy character-identical across three canonical templates" \
    "orch='${tax_orch:-<empty>}' eval='${tax_eval:-<empty>}' task='${tax_task:-<empty>}'"
fi

# ===========================================================================
# 3. Diagnostician template, frontmatter, frozen report sections, dual copies.
# ===========================================================================
check3_ok=1
diag_fm=""
if [[ ! -f "$DIAGNOSTICIAN" ]]; then
  check3_ok=0
else
  diag_fm="$(frontmatter "$DIAGNOSTICIAN")"
  grep -qxF 'name: diagnostician' <<<"$diag_fm" || check3_ok=0
  grep -qF '### Root-Cause Hypothesis' "$DIAGNOSTICIAN" || check3_ok=0
  grep -qF '### Split Recommendation' "$DIAGNOSTICIAN" || check3_ok=0
  grep -qF '### Signature Declaration' "$DIAGNOSTICIAN" || check3_ok=0
fi
if [[ ! -f "$EMITTED_DIAG_CLAUDE" ]] \
   || ! rg --no-ignore -qF '### Root-Cause Hypothesis' "$EMITTED_DIAG_CLAUDE" 2>/dev/null; then
  check3_ok=0
fi
if [[ ! -f "$EMITTED_DIAG_CURSOR" ]] \
   || ! rg --no-ignore -qF '### Root-Cause Hypothesis' "$EMITTED_DIAG_CURSOR" 2>/dev/null; then
  check3_ok=0
fi
if [[ $check3_ok -eq 1 ]]; then
  report PASS "diagnostician template, frontmatter, frozen report sections, dual emitted copies"
else
  report FAIL "diagnostician template, frontmatter, frozen report sections, dual emitted copies"
fi

# ===========================================================================
# 4. Diagnostician tools: line present and excludes Write/Edit.
# ===========================================================================
tools_line="$(grep '^tools:' <<<"${diag_fm:-$(frontmatter "$DIAGNOSTICIAN")}" || true)"
if [[ -z "$tools_line" ]]; then
  report FAIL "diagnostician tools: line present and excludes Write/Edit" "tools: line absent"
elif grep -qE '(^|, | )Write(,|$| )|(^|, | )Edit(,|$| )' <<<"$tools_line"; then
  report FAIL "diagnostician tools: line present and excludes Write/Edit" \
    "forbidden tool on tools line: $tools_line"
else
  report PASS "diagnostician tools: line present and excludes Write/Edit"
fi

# ===========================================================================
# 5. No hardcoded model IDs in changed canonical templates.
# ===========================================================================
model_id_files=(
  "$DIAGNOSTICIAN"
  "$EVALUATOR"
  "$FEATURE_SKILL"
  "$ORCH_TEMPLATE"
  "$MODELS_MAP"
)
check5_ok=1
check5_detail=""
for f in "${model_id_files[@]}"; do
  rel="${f#"$REPO_ROOT"/}"
  raw_hits="$(rg -n 'claude-|gpt-|gemini-' "$f" 2>/dev/null || true)"
  if [[ -z "$raw_hits" ]]; then
    continue
  fi
  if [[ "$f" == "$MODELS_MAP" ]]; then
    # Documented exception: BOOTSTRAP comments and resolved-ID table cells only.
    filtered_hits=""
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if grep -qF 'BOOTSTRAP[' <<<"$line"; then
        continue
      fi
      # Allow resolved-ID cells in the markdown model table (pipe-delimited rows).
      if grep -qE '^\|[[:space:]]*[^|]*\|(claude-|gpt-|gemini-)' <<<"$line"; then
        continue
      fi
      filtered_hits+="${line}"$'\n'
    done <<<"$raw_hits"
    if [[ -n "${filtered_hits//[$'\n']/}" ]]; then
      check5_ok=0
      check5_detail="${rel}: disallowed model ID hit(s)"
      break
    fi
  else
    check5_ok=0
    check5_detail="${rel}: $(head -1 <<<"$raw_hits")"
    break
  fi
done
if [[ $check5_ok -eq 1 ]]; then
  report PASS "no hardcoded model IDs in changed canonical templates"
else
  report FAIL "no hardcoded model IDs in changed canonical templates" "$check5_detail"
fi

# ===========================================================================
# 6. Four emitters reference diagnostician structurally (one named check).
# ===========================================================================
check6_ok=1
check6_detail=""
if ! rg -qF 'tools: Agent(implementer, test-writer, evaluator, qa-evaluator, terminal, diagnostician)' \
     "$EMITTERS/claude-code.md" 2>/dev/null; then
  check6_ok=0
  check6_detail="claude-code spawn-allowlist missing diagnostician"
fi
if [[ $check6_ok -eq 1 ]] && ! rg -q '\.github/agents/\$\{role\}\.agent\.md' "$EMIT_SH" 2>/dev/null; then
  check6_ok=0
  check6_detail="emit.sh copilot agent path missing"
fi
if [[ $check6_ok -eq 1 ]] \
   && ! rg -qF 'agents: [implementer, test-writer, evaluator, qa-evaluator, terminal, diagnostician]' \
        "$EMIT_SH" 2>/dev/null; then
  check6_ok=0
  check6_detail="emit.sh copilot agents: allowlist missing diagnostician"
fi
if [[ $check6_ok -eq 1 ]] && ! rg -qF '[agents.diagnostician]' "$EMIT_SH" 2>/dev/null; then
  check6_ok=0
  check6_detail="emit.sh [agents.diagnostician] table missing"
fi
cursor_harness="$(awk '/^## Harness specifics/{p=1;next} p&&/^## Verify/{exit} p' "$EMITTERS/cursor.md" 2>/dev/null)"
if [[ $check6_ok -eq 1 ]] && ! grep -q 'diagnostician' <<<"${cursor_harness:-}"; then
  check6_ok=0
  check6_detail="cursor Harness specifics→Verify range missing diagnostician"
fi
if [[ $check6_ok -eq 1 ]]; then
  report PASS "four emitters reference diagnostician structurally"
else
  report FAIL "four emitters reference diagnostician structurally" "$check6_detail"
fi

# ===========================================================================
# 7. {{MODEL_FRONTIER_ALT_FAMILY}} documented in the agent-kit skill and models.map.md.
# ===========================================================================
step4_region="$(awk '/^### Placeholder reference/{p=1;next} p&&/^## /{exit} p' "$SETUP_SKILL" 2>/dev/null)"
check7_ok=1
if ! grep -qF '{{MODEL_FRONTIER_ALT_FAMILY}}' <<<"${step4_region:-}"; then
  check7_ok=0
fi
if ! grep -qF '{{MODEL_FRONTIER_ALT_FAMILY}}' "$MODELS_MAP" 2>/dev/null; then
  check7_ok=0
fi
if [[ $check7_ok -eq 1 ]]; then
  report PASS "{{MODEL_FRONTIER_ALT_FAMILY}} documented in the agent-kit skill and used in models.map.md"
else
  report FAIL "{{MODEL_FRONTIER_ALT_FAMILY}} documented in the agent-kit skill and used in models.map.md"
fi

# ===========================================================================
# 8. Continuation-ladder guard anchors in reference file (canonical + instances);
#    feature skill(s) assert the pointer to reference/continuation-ladder.md.
# ===========================================================================
check8_ok=1
check8_detail=""
for ladder in "$LADDER_REF" "$LADDER_CLAUDE" "$LADDER_CURSOR"; do
  rel="${ladder#"$REPO_ROOT"/}"
  if [[ ! -f "$ladder" ]]; then
    check8_ok=0
    check8_detail="missing $rel"
    break
  fi
  grep -qF '3 additional implementation attempts' "$ladder" || { check8_ok=0; check8_detail="$rel: 3-additional-attempts anchor missing"; break; }
  grep -qF 'repeated failure signature' "$ladder" || { check8_ok=0; check8_detail="$rel: repeated-failure-signature anchor missing"; break; }
  if ! grep -q 'remaining budget' "$ladder" \
     && ! grep -q 'exceeds the remaining budget' "$ladder" \
     && ! grep -q 'failing-subtask count against the remaining budget' "$ladder"; then
    check8_ok=0
    check8_detail="$rel: split-vs-budget anchor missing"
    break
  fi
done
if [[ $check8_ok -eq 1 ]]; then
  for feat in "$FEATURE_SKILL" "$FEATURE_CLAUDE" "$FEATURE_CURSOR"; do
    rel="${feat#"$REPO_ROOT"/}"
    if [[ ! -f "$feat" ]]; then
      check8_ok=0
      check8_detail="missing $rel"
      break
    fi
    grep -qF 'reference/continuation-ladder.md' "$feat" || {
      check8_ok=0
      check8_detail="$rel: continuation-ladder pointer missing"
      break
    }
  done
fi
if [[ $check8_ok -eq 1 ]]; then
  report PASS "continuation-ladder guard anchors in reference file (canonical + instances) and pointer in feature skill(s)"
else
  report FAIL "continuation-ladder guard anchors in reference file (canonical + instances) and pointer in feature skill(s)" \
    "$check8_detail"
fi

# ===========================================================================
# 9. Bypass classes in canonical feature skill and ORCHESTRATION ladder section.
# ===========================================================================
feat_bypass_region="$(awk '/Bypass at detection/{p=1} p&&/On cycle-3 exhaustion/{exit} p' "$FEATURE_SKILL" 2>/dev/null)"
orch_ladder="$(extract_ladder_section "$ORCH_TEMPLATE")"
check9_ok=1
for term in destructive security infra; do
  if ! grep -qF "$term" <<<"${feat_bypass_region:-}"; then
    check9_ok=0
    break
  fi
  if ! grep -qF "$term" <<<"${orch_ladder:-}"; then
    check9_ok=0
    break
  fi
done
if [[ $check9_ok -eq 1 ]]; then
  report PASS "bypass classes in canonical feature skill and ORCHESTRATION ladder section"
else
  report FAIL "bypass classes in canonical feature skill and ORCHESTRATION ladder section"
fi

# ===========================================================================
# 10. Arbitration verdict strings in evaluator template.
# ===========================================================================
if grep -qF 'criteria-sound' "$EVALUATOR" 2>/dev/null \
   && grep -qF 'criteria-defective' "$EVALUATOR" 2>/dev/null; then
  report PASS "arbitration verdict strings criteria-sound and criteria-defective in evaluator template"
else
  report FAIL "arbitration verdict strings criteria-sound and criteria-defective in evaluator template"
fi

# ===========================================================================
# 11. Research doc exists, linked from README and root ORCHESTRATION, ladder pointer.
# ===========================================================================
check11_ok=1
if [[ ! -f "$RESEARCH_DOC" ]]; then
  check11_ok=0
fi
if ! grep -qF 'research-autonomous-escalation.md' "$ROOT_README" 2>/dev/null; then
  check11_ok=0
fi
if ! grep -qF 'research-autonomous-escalation.md' "$ROOT_ORCHESTRATION" 2>/dev/null; then
  check11_ok=0
fi
if ! grep -qi 'continuation ladder' "$ROOT_ORCHESTRATION" 2>/dev/null; then
  check11_ok=0
fi
if [[ $check11_ok -eq 1 ]]; then
  report PASS "research doc exists, linked from README and root ORCHESTRATION, ladder pointer"
else
  report FAIL "research doc exists, linked from README and root ORCHESTRATION, ladder pointer"
fi

# ===========================================================================
# phases.ladder gate in feature skills and continuation-ladder reference.
# ===========================================================================
check_ladder_ok=1
check_ladder_detail=""
for feat in \
  "$FEATURE_SKILL" \
  "$FEATURE_CLAUDE" \
  "$FEATURE_CURSOR"; do
  rel="${feat#"$REPO_ROOT"/}"
  if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
    inst="${rel%%/*}"
    if [[ ! -d "$REPO_ROOT/$inst" ]]; then
      continue
    fi
  fi
  if [[ ! -f "$feat" ]] || ! grep -qF 'phases.ladder' "$feat"; then
    check_ladder_ok=0
    check_ladder_detail="$rel: phases.ladder missing"
    break
  fi
done
if [[ $check_ladder_ok -eq 1 ]]; then
  for ladder in "$LADDER_REF" "$LADDER_CLAUDE" "$LADDER_CURSOR"; do
    rel="${ladder#"$REPO_ROOT"/}"
    if [[ "$rel" == .claude/* || "$rel" == .cursor/* ]]; then
      inst="${rel%%/*}"
      if [[ ! -d "$REPO_ROOT/$inst" ]]; then
        continue
      fi
    fi
    if [[ ! -f "$ladder" ]] || ! grep -qF 'phases.ladder' "$ladder"; then
      check_ladder_ok=0
      check_ladder_detail="$rel: phases.ladder missing"
      break
    fi
  done
fi
if [[ $check_ladder_ok -eq 1 ]]; then
  report PASS "phases.ladder gate in feature skills and continuation-ladder reference"
else
  report FAIL "phases.ladder gate in feature skills and continuation-ladder reference" \
    "$check_ladder_detail"
fi

# ===========================================================================
# 12. Dynamic VERSION, README version prose, instance/manifest pins, no five-subagent phrasing.
# ===========================================================================
check12_ok=1
check12_detail=""
KIT_VERSION="$(kit_version "$VERSION_FILE" 2>/dev/null || true)"
MANIFEST="$REPO_ROOT/orchestration-kit.manifest.json"
CLAUDE_VERSION="$REPO_ROOT/.claude/skills/agent-kit/SKILL.md"
CURSOR_VERSION="$REPO_ROOT/.cursor/skills/agent-kit/SKILL.md"
if [[ ! -f "$VERSION_FILE" ]] || [[ ! "$KIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  check12_ok=0
  check12_detail="skills/agent-kit/SKILL.md metadata.version missing or not semver"
fi
if [[ $check12_ok -eq 1 ]] && ! grep -qF -- "Kit version: **$KIT_VERSION**" "$ROOT_README" 2>/dev/null; then
  check12_ok=0
  check12_detail="README Kit version line missing or wrong"
fi
if [[ $check12_ok -eq 1 ]]; then
  for ivf in "$CLAUDE_VERSION" "$CURSOR_VERSION"; do
    rel="${ivf#"$REPO_ROOT"/}"
    if [[ ! -f "$ivf" ]]; then
      skip_report "check 12: $rel absent"
      continue
    fi
    if [[ "$(kit_version "$ivf")" != "$KIT_VERSION" ]]; then
      check12_ok=0
      check12_detail="$rel != $KIT_VERSION"
      break
    fi
  done
fi
if [[ $check12_ok -eq 1 ]]; then
  if [[ ! -f "$MANIFEST" ]]; then
    skip_report "check 12: orchestration-kit.manifest.json absent"
  else
    manifest_ver="$(grep -m1 '"kitVersion"' "$MANIFEST" 2>/dev/null | \
      sed -E 's/.*"kitVersion"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
    if [[ "$manifest_ver" != "$KIT_VERSION" ]]; then
      check12_ok=0
      check12_detail="manifest kitVersion '$manifest_ver' != $KIT_VERSION"
    fi
  fi
fi
if [[ $check12_ok -eq 1 ]] && rg -q 'five subagents' "$ROOT_README" "$SETUP_SKILL" 2>/dev/null; then
  check12_ok=0
  check12_detail="five-subagent phrasing still present"
fi
if [[ $check12_ok -eq 1 ]] && ! grep -qF 'six subagents' "$SETUP_SKILL" 2>/dev/null; then
  check12_ok=0
  check12_detail="six subagents missing from setup SKILL"
fi
if [[ $check12_ok -eq 1 ]]; then
  report PASS "VERSION $KIT_VERSION, README Kit version prose, instance/manifest pins, no five-subagent phrasing"
else
  report FAIL "VERSION $KIT_VERSION, README Kit version prose, instance/manifest pins, no five-subagent phrasing" \
    "$check12_detail"
fi

echo
echo "=== escalation-ladder summary ==="
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
