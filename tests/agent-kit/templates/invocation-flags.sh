#!/usr/bin/env bash
# Regression guard for the invocation-flag-hygiene goal: the seven P0
# `disable-model-invocation: true` skill flags, the `terminal` agent's wiring
# (frontmatter, models.map, test-ladder, setup description, ORCHESTRATION.md,
# emitters, Codex registration), and the research doc's status lines. Tracked,
# self-install-independent -- checks the canonical templates/ source tree
# directly (no `_loop/`, no `.claude/`, no self-install required).
#
# Copy this repo's `skills/agent-kit/` + `tests/agent-kit/templates/` + `docs/` subtree into
# a mktemp dir, mutate a file under test, then run the COPIED script: HERE and
# REPO_ROOT resolve relative to this script's own location, so the copy checks
# the mutated copy, not the live repo. Every assertion is outcome-verifying: it
# inspects file content and FAILs loudly (non-zero exit, explicit FAIL line) if
# a P0 flag, the `terminal` wiring, or the research-doc status lines regress.
# No network, no external services.
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location (works from
# any cwd, any clone path, and inside a mktemp copy of the subtree above).
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
EMITTERS="$REPO_ROOT/skills/agent-kit/emitters"
EMIT_SH="$REPO_ROOT/skills/agent-kit/bin/emit.sh"
SETUP_SKILL_MD="$REPO_ROOT/skills/agent-kit/SKILL.md"
RESEARCH_DOC="$REPO_ROOT/_memory/research/token-efficient-skills.md"
ROOT_README="$REPO_ROOT/skills/agent-kit/README.md"
ROOT_ORCHESTRATION="$REPO_ROOT/docs/agent-kit/README.md"

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

# Prints the text strictly between the first two `---` lines of a file (the
# YAML frontmatter block), or nothing if the file is missing/malformed.
frontmatter() {
  awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f{print}' "$1" 2>/dev/null
}

# Remove `<!-- IF opt_in -->` … `<!-- ENDIF opt_in -->` blocks (whole-line markers).
strip_opt_in_if_blocks() {
  awk '
    /^<!-- IF opt_in -->$/ { skip=1; next }
    /^<!-- ENDIF opt_in -->$/ { skip=0; next }
    !skip { print }
  '
}

# ===========================================================================
# 1. Seven P0 skills carry `disable-model-invocation: true` in frontmatter.
# ===========================================================================
p0_files=(
  "$TEMPLATES/skills/align-docs/SKILL.template.md"
  "$TEMPLATES/skills/ship-pr/SKILL.template.md"
  "$TEMPLATES/skills/goal-criteria/SKILL.template.md"
  "$TEMPLATES/skills/task-criteria/SKILL.template.md"
  "$TEMPLATES/skills/qa-criteria/SKILL.template.md"
  "$TEMPLATES/skills/test-ladder/SKILL.template.md"
  "$TEMPLATES/loop/SKILL.template.md"
)
for f in "${p0_files[@]}"; do
  rel="${f#"$REPO_ROOT"/}"
  fm="$(frontmatter "$f")"
  if [[ -f "$f" ]] && grep -qxF 'disable-model-invocation: true' <<<"$fm"; then
    report PASS "P0 flag present: $rel"
  else
    report FAIL "P0 flag present: $rel" "missing exact frontmatter line 'disable-model-invocation: true'"
  fi
done

# ===========================================================================
# 2. test-ladder keeps `user-invocable: true` alongside the P0 flag.
# ===========================================================================
tl="$TEMPLATES/skills/test-ladder/SKILL.template.md"
tl_fm="$(frontmatter "$tl")"
if grep -qxF 'user-invocable: true' <<<"$tl_fm"; then
  report PASS "test-ladder/SKILL.template.md keeps user-invocable: true"
else
  report FAIL "test-ladder/SKILL.template.md keeps user-invocable: true"
fi

# ===========================================================================
# 3. `feature` and `research` stay auto-invocable outside IF opt_in; flag only
#    inside an opt_in block when present.
# ===========================================================================
for f in "$TEMPLATES/skills/feature/SKILL.template.md" "$TEMPLATES/skills/research/SKILL.template.md"; do
  rel="${f#"$REPO_ROOT"/}"
  fm="$(frontmatter "$f" | strip_opt_in_if_blocks)"
  if [[ -f "$f" ]] && ! grep -q 'disable-model-invocation' <<<"$fm"; then
    report PASS "$rel stays unflagged outside IF opt_in (auto-invocable)"
  else
    report FAIL "$rel stays unflagged outside IF opt_in (auto-invocable)" "disable-model-invocation present in frontmatter after stripping IF opt_in blocks"
  fi
  if [[ -f "$f" ]] && grep -q 'disable-model-invocation: true' "$f"; then
    if awk '
      /^<!-- IF opt_in -->$/ { in_opt=1; next }
      /^<!-- ENDIF opt_in -->$/ { in_opt=0; next }
      /disable-model-invocation: true/ && !in_opt { exit 1 }
      END { exit 0 }
    ' "$f"; then
      report PASS "$rel disable-model-invocation only inside IF opt_in"
    else
      report FAIL "$rel disable-model-invocation only inside IF opt_in" "flag line outside IF opt_in block"
    fi
  fi
done

# ===========================================================================
# 4. feature/SKILL.md path-Reads align-docs + ship-pr (not a legacy "Invoke
#    the `X` skill" phrasing).
# ===========================================================================
feat="$TEMPLATES/skills/feature/SKILL.template.md"
if grep -qF '{{IDE_DIR}}/skills/align-docs/SKILL.md' "$feat" \
   && grep -qF '{{IDE_DIR}}/skills/ship-pr/SKILL.md' "$feat" \
   && ! grep -qF 'Invoke the `align-docs` skill' "$feat" \
   && ! grep -qF 'Invoke the `ship-pr` skill' "$feat"; then
  report PASS "feature/SKILL.template.md path-Reads align-docs + ship-pr (no legacy invoke phrasing)"
else
  report FAIL "feature/SKILL.template.md path-Reads align-docs + ship-pr (no legacy invoke phrasing)"
fi

# ===========================================================================
# 5. feature/SKILL.md spawns `terminal` (case-insensitive) and its Phase 5 /
#    Quality Checks area names the log path + forbids dumping the full suite
#    into the orchestrator session.
# ===========================================================================
if grep -qiF 'spawn `terminal`' "$feat"; then
  report PASS "feature/SKILL.template.md spawns terminal (case-insensitive)"
else
  report FAIL "feature/SKILL.template.md spawns terminal (case-insensitive)"
fi

if grep -qF 'log path' "$feat"; then
  report PASS "feature/SKILL.template.md Phase 5 failure path names the log path"
else
  report FAIL "feature/SKILL.template.md Phase 5 failure path names the log path"
fi

if grep -qF 'never dump the full suite here' "$feat"; then
  report PASS "feature/SKILL.template.md forbids dumping the full suite into the orchestrator session"
else
  report FAIL "feature/SKILL.template.md forbids dumping the full suite into the orchestrator session"
fi

# ===========================================================================
# 6. loop/PROMPT.md starts with /auto-loop.
# ===========================================================================
prompt="$TEMPLATES/loop/PROMPT.md"
if [[ -f "$prompt" ]]; then
  first_line="$(head -n1 "$prompt")"
else
  first_line=""
fi
if [[ "$first_line" == /auto-loop* ]]; then
  report PASS "loop/PROMPT.md starts with /auto-loop"
else
  report FAIL "loop/PROMPT.md starts with /auto-loop" "first line: '$first_line'"
fi

# ===========================================================================
# 7. ORCHESTRATION.md: flag note sits after the domain-skill BOOTSTRAP comment
#    and before the "Domain skills are the project's knowledge base" blockquote,
#    naming all seven flagged skills; plus a subagents-table `terminal` row.
# ===========================================================================
orch="$TEMPLATES/ORCHESTRATION.md"
region="$(sed -n '/BOOTSTRAP\[domain-skill-rows\]: append one row per project domain skill/,/Domain skills are the project.s knowledge base/p' "$orch")"
flagged_names=(goal-criteria task-criteria qa-criteria test-ladder align-docs ship-pr auto-loop)
region_ok=1
if [[ -z "$region" ]]; then
  region_ok=0
else
  for n in "${flagged_names[@]}"; do
    grep -qF "$n" <<<"$region" || region_ok=0
  done
  grep -qF 'disable-model-invocation' <<<"$region" || region_ok=0
fi
if [[ $region_ok -eq 1 ]]; then
  report PASS "ORCHESTRATION.md flag note between BOOTSTRAP comment and Domain-skills blockquote names all seven skills"
else
  report FAIL "ORCHESTRATION.md flag note between BOOTSTRAP comment and Domain-skills blockquote names all seven skills"
fi

if grep -qE '^\| *`terminal`' "$orch"; then
  report PASS "ORCHESTRATION.md subagents table includes a terminal row"
else
  report FAIL "ORCHESTRATION.md subagents table includes a terminal row"
fi

# ===========================================================================
# 8. templates/agents/terminal.md exists, frontmatter has name/model/tools,
#    body forbids edits.
# ===========================================================================
term="$TEMPLATES/agents/terminal.md"
if [[ -s "$term" ]]; then
  term_fm="$(frontmatter "$term")"
  if grep -qxF 'name: terminal' <<<"$term_fm" \
     && grep -qF '{{MODEL_FAST}}' <<<"$term_fm" \
     && grep -qF 'effort: low' <<<"$term_fm" \
     && grep -qF 'tools: Bash, Read' <<<"$term_fm"; then
    report PASS "terminal.md frontmatter: name: terminal, {{MODEL_FAST}}, effort: low, tools: Bash, Read"
  else
    report FAIL "terminal.md frontmatter: name: terminal, {{MODEL_FAST}}, effort: low, tools: Bash, Read"
  fi

  if grep -qiF 'No Edit/Write tools' "$term" \
     && grep -qiF 'PowerShell' "$term" \
     && grep -qiF 'Bash' "$term"; then
    report PASS "terminal.md body: Bash or PowerShell, no Edit/Write tools"
  else
    report FAIL "terminal.md body: Bash or PowerShell, no Edit/Write tools"
  fi
else
  report FAIL "templates/agents/terminal.md exists and is non-empty" "file missing or empty"
  report FAIL "terminal.md body: Bash or PowerShell, no Edit/Write tools" "file missing or empty"
fi

# ===========================================================================
# 9. models.map.md fast-tier Roles cell includes terminal.
# ===========================================================================
mm="$TEMPLATES/models.map.md"
if grep -qiE '\| *`fast`.*`terminal`' "$mm"; then
  report PASS "models.map.md fast-tier Roles cell includes terminal"
else
  report FAIL "models.map.md fast-tier Roles cell includes terminal"
fi

# ===========================================================================
# 10. test-ladder: Who-does-what table has a dedicated `terminal` row and the
#     orchestrator row spawns it; a fenceless terminal reporter is not a closer.
# ===========================================================================
if grep -qE '^\| *`terminal`' "$tl" && grep -qiF 'spawn `terminal`' "$tl"; then
  report PASS "test-ladder Who-does-what table has a terminal row + orchestrator spawn line"
else
  report FAIL "test-ladder Who-does-what table has a terminal row + orchestrator spawn line"
fi

tl_flat="$(tr '\n' ' ' < "$tl")"
if grep -qiF 'fenceless' <<<"$tl_flat" && grep -qiE 'not\**[* ]*a designated closer task' <<<"$tl_flat"; then
  report PASS "test-ladder states a fenceless terminal reporter is not a designated closer task"
else
  report FAIL "test-ladder states a fenceless terminal reporter is not a designated closer task"
fi

# ===========================================================================
# 11. agent-kit/SKILL.md description names terminal, diagnostician, evidence-collector,
#     and enumerates seven subagents (no longer claims only four or five).
# ===========================================================================
setup_fm="$(frontmatter "$SETUP_SKILL_MD")"
desc_line="$(grep '^description:' <<<"$setup_fm")"
if grep -qiF 'terminal' <<<"$desc_line" \
   && grep -qiF 'diagnostician' <<<"$desc_line" \
   && grep -qiF 'evidence-collector' <<<"$desc_line" \
   && grep -qiF 'seven subagents' <<<"$desc_line" \
   && ! grep -qiF 'four subagents' <<<"$desc_line"; then
  report PASS "agent-kit/SKILL.md description names terminal, diagnostician, evidence-collector, and seven subagents (not four)"
else
  report FAIL "agent-kit/SKILL.md description names terminal, diagnostician, evidence-collector, and seven subagents (not four)"
fi

# ===========================================================================
# 12. Emitters cursor.md, copilot.md, claude-code.md each mention
#     disable-model-invocation and terminal.
# ===========================================================================
for f in cursor.md copilot.md claude-code.md; do
  path="$EMITTERS/$f"
  if grep -qF 'disable-model-invocation' "$path" && grep -qiF 'terminal' "$path"; then
    report PASS "emitters/$f mentions disable-model-invocation + terminal"
  else
    report FAIL "emitters/$f mentions disable-model-invocation + terminal"
  fi
done

# ===========================================================================
# 13. emitters/codex.md registers [agents.terminal] + agents/terminal.toml.
# ===========================================================================
codex="$EMIT_SH"
if grep -qF '[agents.terminal]' "$codex" && grep -qF 'agents/terminal.toml' "$codex"; then
  report PASS "emit.sh registers [agents.terminal] + agents/terminal.toml"
else
  report FAIL "emit.sh registers [agents.terminal] + agents/terminal.toml"
fi

# ===========================================================================
# 14. emitters/copilot.md: mentions allowInvocationsFromSubagents, never
#     enables it, drops the stale escape-hatch phrase, and every occurrence's
#     nearby window carries a keep-off phrase.
# ===========================================================================
copilot="$EMITTERS/copilot.md"
if grep -qF 'allowInvocationsFromSubagents' "$copilot" \
   && ! grep -qF 'allowInvocationsFromSubagents: true' "$copilot" \
   && ! grep -qF 'if the flow needs judge-spawned helpers' "$copilot"; then
  report PASS "copilot.md mentions allowInvocationsFromSubagents without enabling it or the stale escape phrase"
else
  report FAIL "copilot.md mentions allowInvocationsFromSubagents without enabling it or the stale escape phrase"
fi

if [[ -f "$copilot" ]]; then
  mapfile -t occ_lines < <(grep -n 'allowInvocationsFromSubagents' "$copilot" | cut -d: -f1)
  total_lines=$(wc -l < "$copilot")
  window_ok=1
  for ln in "${occ_lines[@]}"; do
    start=$((ln - 2)); ((start < 1)) && start=1
    end=$((ln + 2)); ((end > total_lines)) && end=$total_lines
    window="$(sed -n "${start},${end}p" "$copilot")"
    grep -qiE 'do not|stays off|must not|not enable' <<<"$window" || window_ok=0
  done
  if [[ ${#occ_lines[@]} -gt 0 && $window_ok -eq 1 ]]; then
    report PASS "copilot.md: every allowInvocationsFromSubagents window carries a keep-off phrase"
  else
    report FAIL "copilot.md: every allowInvocationsFromSubagents window carries a keep-off phrase"
  fi
else
  report FAIL "copilot.md: every allowInvocationsFromSubagents window carries a keep-off phrase" "file missing"
fi

# ===========================================================================
# 15. Research doc status: invocation-flag-hygiene, "flag in place", "shipped
#     by this goal", "blocks pinning up, not down".
# ===========================================================================
research_phrases=(
  "invocation-flag-hygiene"
  "flag in place"
  "shipped by this goal"
  "blocks pinning up, not down"
)
research_ok=1
if [[ -f "$RESEARCH_DOC" ]]; then
  for p in "${research_phrases[@]}"; do
    grep -qiF "$p" "$RESEARCH_DOC" || research_ok=0
  done
else
  research_ok=0
fi
if [[ $research_ok -eq 1 ]]; then
  report PASS "research doc carries invocation-flag-hygiene status phrases"
else
  report FAIL "research doc carries invocation-flag-hygiene status phrases"
fi

# ===========================================================================
# 16 (harness-evaluator-upgrade): case-insensitive vocabulary guard -- no
# judge-family word survives in the live-vocabulary surfaces named by the
# goal's success criterion 1 sweep. Scope deliberately EXCLUDES
# templates/loop/ drivers, reference/harness-matrix.md, and the test files
# themselves (frozen provenance / flagged fixtures / this guard's own
# pattern) -- none of those paths are in the list below, so the exclusion is
# structural, not a grep flag.
# ===========================================================================
judg_scope=(
  "$TEMPLATES/agents"
  "$TEMPLATES/skills"
  "$TEMPLATES/ORCHESTRATION.md"
  "$TEMPLATES/models.map.md"
  "$EMITTERS"
  "$SETUP_SKILL_MD"
  "$ROOT_README"
  "$ROOT_ORCHESTRATION"
)
judg_missing=()
for p in "${judg_scope[@]}"; do
  [[ -e "$p" ]] || judg_missing+=("$p")
done
if [[ ${#judg_missing[@]} -gt 0 ]]; then
  report FAIL "vocabulary guard: no judge-family word in live-vocabulary surfaces" \
    "scope path(s) missing -- a rename/move degraded the guard: ${judg_missing[*]}"
else
  judg_hits="$(grep -rIni 'judg' "${judg_scope[@]}" 2>/dev/null)"
  if [[ -z "$judg_hits" ]]; then
    report PASS "vocabulary guard: no judge-family word in templates/agents, templates/skills, templates/ORCHESTRATION.md, templates/models.map.md, emitters/, agent-kit/SKILL.md, README.md, ORCHESTRATION.md"
  else
    report FAIL "vocabulary guard: no judge-family word in live-vocabulary surfaces" \
      "$(wc -l <<<"$judg_hits") match(es) found -- first few: $(head -3 <<<"$judg_hits")"
  fi
fi

echo
echo "=== invocation-flags summary ==="
echo "PASS: $pass_count   FAIL: $fail_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
