#!/usr/bin/env bash
# Regression guard for the cursor-self-contained-install goal: locks in the Cursor
# emitter's unconditional self-contained emit set, the `.claude`-free pointer-rule
# fence, the templates tree's `.claude/`-reference absence, the ORCHESTRATION
# template's model-map referencing, the setup skill's per-emitter `{{IDE_DIR}}`
# semantics and multiline-safe absence of the pre-fix Cursor-reuse pairing, the
# harness matrix's v0.19.0 policy note and non-contradictory Cursor model-pin /
# effort-pin cells, the model map's live-verification guidance, and the root docs'
# v0.19.0 version prose. Tracked, self-install-independent -- checks the canonical
# templates/ source tree and root docs directly (no `.claude/`, no `.cursor/`, no
# `_loop/`, no install manifest, no self-install required).
#
# Copy this repo's `tests/` + `skills/` + `README.md` + `ORCHESTRATION.md` subtree
# into a mktemp dir, mutate a file under test, then run the COPIED script: HERE and
# REPO_ROOT resolve relative to this script's own location, so the copy checks the
# mutated copy, not the live repo. Every assertion is outcome-verifying: it inspects
# real file content and FAILs loudly (non-zero exit, explicit FAIL line) if a
# canonical guarantee regresses. No network, no external services.
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location (works from
# any cwd, any clone path, and inside a mktemp copy of the subtree above).
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CURSOR_MD="$REPO_ROOT/skills/setup/emitters/cursor.md"
ORCH_TEMPLATE="$REPO_ROOT/skills/setup/templates/ORCHESTRATION.md"
TEMPLATES_DIR="$REPO_ROOT/skills/setup/templates"
SETUP_SKILL_MD="$REPO_ROOT/skills/setup/SKILL.md"
HARNESS_MATRIX="$REPO_ROOT/skills/setup/reference/harness-matrix.md"
MODELS_MAP="$REPO_ROOT/skills/setup/templates/models.map.md"
VERSION_FILE="$REPO_ROOT/skills/setup/VERSION"
ROOT_README="$REPO_ROOT/README.md"
ROOT_ORCHESTRATION="$REPO_ROOT/ORCHESTRATION.md"

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

# ===========================================================================
# 2. skills/setup/emitters/cursor.md -- unconditional emit set (7 sub-checks).
# ===========================================================================

# 2a. Neither "only if" nor "did not run" appears anywhere in the file.
if [[ -f "$CURSOR_MD" ]] && ! grep -qE 'only if|did not run' "$CURSOR_MD"; then
  report PASS "cursor.md: emit table is unconditional (no 'only if' / 'did not run')"
else
  report FAIL "cursor.md: emit table is unconditional (no 'only if' / 'did not run')" \
    "'only if' or 'did not run' still present, or file missing"
fi

# 2b. No "skip if" clause on the ORCHESTRATION row.
if [[ -f "$CURSOR_MD" ]] && ! grep -q 'skip if' "$CURSOR_MD"; then
  report PASS "cursor.md: no 'skip if' clause on the ORCHESTRATION row"
else
  report FAIL "cursor.md: no 'skip if' clause on the ORCHESTRATION row" \
    "'skip if' still present, or file missing"
fi

# 2c. A self-containment statement exists (exact shipped literal, article included).
if grep -qF 'as a **self-contained** tree' "$CURSOR_MD" 2>/dev/null; then
  report PASS "cursor.md: self-containment statement present ('as a **self-contained** tree')"
else
  report FAIL "cursor.md: self-containment statement present ('as a **self-contained** tree')"
fi

# 2d. The templates/models.map.md -> .cursor/skills/setup-models.map.md EMIT-TABLE row
#     exists, anchored to the row's own structure (line begins with the source cell
#     `| \`templates/models.map.md\` |` AND that same line contains the destination
#     text `.cursor/skills/setup-models.map.md`) -- a whole-file substring grep for
#     just the destination text is NOT decidable here: the Verify section further
#     down also says "`.cursor/skills/setup-models.map.md` exists." (~line 75) and
#     "`setup-models.map.md`'s **Cursor column**" (~line 77), so deleting only the
#     EMIT-TABLE row would leave a whole-file grep green.
if [[ -f "$CURSOR_MD" ]] \
  && grep -qE '^\| `templates/models\.map\.md` \|.*\.cursor/skills/setup-models\.map\.md' "$CURSOR_MD" 2>/dev/null; then
  report PASS "cursor.md: templates/models.map.md -> .cursor/skills/setup-models.map.md EMIT-TABLE row exists"
else
  report FAIL "cursor.md: templates/models.map.md -> .cursor/skills/setup-models.map.md EMIT-TABLE row exists" \
    "row anchored on '| \`templates/models.map.md\` |' + destination text not found (or file missing)"
fi

# 2e. The pointer-rule fenced block (```markdown ... ```) contains zero `.claude`
#     substrings when EXTRACTED and grepped in isolation -- not merely absent from
#     the whole file (a whole-file check would pass even if the fence itself still
#     said `.claude`, as long as some other line balanced it out).
if [[ -f "$CURSOR_MD" ]]; then
  fence_content="$(awk '/^```markdown$/,/^```$/' "$CURSOR_MD")"
  if [[ -n "$fence_content" ]]; then
    fence_claude_count="$(grep -c '\.claude' <<<"$fence_content" || true)"
    if [[ "${fence_claude_count:-0}" -eq 0 ]]; then
      report PASS "cursor.md: pointer-rule fenced block contains zero .claude substrings"
    else
      report FAIL "cursor.md: pointer-rule fenced block contains zero .claude substrings" \
        "found $fence_claude_count occurrence(s) inside the extracted fence"
    fi
  else
    report FAIL "cursor.md: pointer-rule fenced block contains zero .claude substrings" \
      "no \`\`\`markdown ... \`\`\` fence found -- extraction returned empty"
  fi
else
  report FAIL "cursor.md: pointer-rule fenced block contains zero .claude substrings" "file missing"
fi

# 2f. An {{IDE_DIR}} -> .cursor resolution statement exists.
if grep -qE '\{\{IDE_DIR\}\}.*\.cursor|resolves .\{\{IDE_DIR\}\}' "$CURSOR_MD" 2>/dev/null; then
  report PASS "cursor.md: {{IDE_DIR}} -> .cursor resolution statement present"
else
  report FAIL "cursor.md: {{IDE_DIR}} -> .cursor resolution statement present"
fi

# 2g. The literals loop.ps1 and breaker.ps1 are each still present.
if [[ -f "$CURSOR_MD" ]] \
  && [[ "$(grep -c 'loop\.ps1' "$CURSOR_MD")" -ge 1 ]] \
  && [[ "$(grep -c 'breaker\.ps1' "$CURSOR_MD")" -ge 1 ]]; then
  report PASS "cursor.md: literals loop.ps1 and breaker.ps1 both still present"
else
  report FAIL "cursor.md: literals loop.ps1 and breaker.ps1 both still present"
fi

# ===========================================================================
# 3. skills/setup/templates/ORCHESTRATION.md -- model-map referencing.
# ===========================================================================
if [[ -f "$ORCH_TEMPLATE" ]]; then
  model_token_count="$(grep -c '{{MODEL_' "$ORCH_TEMPLATE" || true)"
  setup_map_count="$(grep -c 'setup-models.map.md' "$ORCH_TEMPLATE" || true)"
  if [[ "${model_token_count:-0}" -eq 2 && "${setup_map_count:-0}" -ge 1 ]]; then
    report PASS "templates/ORCHESTRATION.md: two {{MODEL_ tokens, >=1 setup-models.map.md reference"
  else
    report FAIL "templates/ORCHESTRATION.md: two {{MODEL_ tokens, >=1 setup-models.map.md reference" \
      "{{MODEL_ count=${model_token_count:-0}, setup-models.map.md count=${setup_map_count:-0}"
  fi
else
  report FAIL "templates/ORCHESTRATION.md: two {{MODEL_ tokens, >=1 setup-models.map.md reference" "file missing"
fi

# ===========================================================================
# 4. skills/setup/templates/ tree -- .claude/ reference absence.
#    Today's tree has zero occurrences anywhere under templates/ (the allowlist is
#    empty), so this is a plain zero-occurrence absence assertion, not an allowlist
#    walk -- per the task's own reality-anchoring instruction. Any future `.claude/`
#    reintroduction anywhere in the tree FAILs this check.
# ===========================================================================
if [[ -d "$TEMPLATES_DIR" ]]; then
  templates_claude_total="$(grep -rc '\.claude' "$TEMPLATES_DIR" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
  if [[ "${templates_claude_total:-0}" -eq 0 ]]; then
    report PASS "templates/ tree: zero .claude occurrences anywhere under skills/setup/templates/"
  else
    report FAIL "templates/ tree: zero .claude occurrences anywhere under skills/setup/templates/" \
      "found $templates_claude_total occurrence(s)"
  fi
else
  report FAIL "templates/ tree: zero .claude occurrences anywhere under skills/setup/templates/" "directory missing"
fi

# ===========================================================================
# 5. skills/setup/SKILL.md -- reuse-pairing absence and {{IDE_DIR}}/Step-4 semantics.
# ===========================================================================

# 5a. The pre-fix wrapped sentence fragment "-- Cursor and\nVS Code reuse parts of
#     the emitted `.claude/` tree." spans two physical lines in the pre-fix file, so
#     a naive single-line `grep -c "Cursor and VS Code reuse"` is a documented
#     TAUTOLOGY: it returns 0 on BOTH the pre-fix and post-fix file, because the
#     phrase never appears on one physical line either way -- it is NOT the check
#     this script relies on (see the mutation spot-check report for a live
#     side-by-side demonstration). The actual assertion below is multiline-aware: it
#     flattens the file with `tr '\n' ' '` first (mirroring this repo's own
#     tests/templates/invocation-flags.sh convention for multiline prose checks), so
#     a wrapped occurrence is still caught regardless of exactly where the line break
#     falls.
if [[ -f "$SETUP_SKILL_MD" ]]; then
  skill_flat="$(tr '\n' ' ' <"$SETUP_SKILL_MD")"
  if ! grep -qE 'Cursor and[[:space:]]+VS Code reuse' <<<"$skill_flat"; then
    report PASS "SKILL.md: pre-fix Cursor-reuse pairing absent (multiline-aware check)"
  else
    report FAIL "SKILL.md: pre-fix Cursor-reuse pairing absent (multiline-aware check)" \
      "'Cursor and ... VS Code reuse' pairing still present"
  fi
else
  report FAIL "SKILL.md: pre-fix Cursor-reuse pairing absent (multiline-aware check)" "file missing"
fi

# 5b. The {{IDE_DIR}} placeholder-reference row mentions per-emitter resolution.
if grep -qE '\{\{IDE_DIR\}\}.*resolved per emitter' "$SETUP_SKILL_MD" 2>/dev/null; then
  report PASS "SKILL.md: {{IDE_DIR}} row mentions 'resolved per emitter'"
else
  report FAIL "SKILL.md: {{IDE_DIR}} row mentions 'resolved per emitter'"
fi

# 5c. Step 4 carries the re-resolution rule.
if grep -qE 're-resolved \*\*per emitter\*\*' "$SETUP_SKILL_MD" 2>/dev/null; then
  report PASS "SKILL.md: Step 4 carries the 're-resolved **per emitter**' rule"
else
  report FAIL "SKILL.md: Step 4 carries the 're-resolved **per emitter**' rule"
fi

# 5d. The compose note's "Claude Code first" ordering survives.
if grep -qF 'run Claude Code first when it is among the targets' "$SETUP_SKILL_MD" 2>/dev/null; then
  report PASS "SKILL.md: compose note keeps 'run Claude Code first when it is among the targets'"
else
  report FAIL "SKILL.md: compose note keeps 'run Claude Code first when it is among the targets'"
fi

# 5e. _loop/PROMPT.md is named in the Loop-extras paragraph.
if grep -qF '_loop/PROMPT.md' "$SETUP_SKILL_MD" 2>/dev/null; then
  report PASS "SKILL.md: _loop/PROMPT.md named in the Loop-extras paragraph"
else
  report FAIL "SKILL.md: _loop/PROMPT.md named in the Loop-extras paragraph"
fi

# ===========================================================================
# 6. skills/setup/reference/harness-matrix.md -- v0.19.0 policy, non-contradictory
#    Cursor cells. The Cursor column is located via the capability table's own
#    header row (matching the field whose trimmed text is exactly "Cursor"), never
#    via a hardcoded field index or a whole-line grep -- a whole-line date grep
#    could pass on a date sitting in a different harness's cell.
# ===========================================================================

# 6a. v0.19.0 self-containment policy note exists.
if grep -qF 'Kit policy (as of v0.19.0)' "$HARNESS_MATRIX" 2>/dev/null; then
  report PASS "harness-matrix.md: v0.19.0 self-containment policy note present"
else
  report FAIL "harness-matrix.md: v0.19.0 self-containment policy note present"
fi

# 6b. Both the Cursor model-pin cell and the Cursor effort-pin cell carry a
#     verification mark + date, isolated by the header row's column index.
cursor_col=""
matrix_header_line=""
if [[ -f "$HARNESS_MATRIX" ]]; then
  matrix_header_line="$(grep -n '^| Capability | Claude Code | Cursor | Copilot (VS Code) | OpenAI Codex |$' "$HARNESS_MATRIX" | head -1 | cut -d: -f1)"
  if [[ -n "$matrix_header_line" ]]; then
    cursor_col="$(sed -n "${matrix_header_line}p" "$HARNESS_MATRIX" | awk -F'|' '{
      for (i = 1; i <= NF; i++) {
        f = $i
        gsub(/^[ \t]+/, "", f)
        gsub(/[ \t]+$/, "", f)
        if (f == "Cursor") { print i; exit }
      }
    }')"
  fi
fi

model_pin_cell=""
if [[ -n "$cursor_col" ]]; then
  model_pin_line="$(grep -n 'Per-agent model pin' "$HARNESS_MATRIX" | head -1 | cut -d: -f1)"
  if [[ -n "${model_pin_line:-}" ]]; then
    model_pin_cell="$(sed -n "${model_pin_line}p" "$HARNESS_MATRIX" | awk -F'|' -v idx="$cursor_col" '{print $idx}')"
  fi
fi
if [[ -n "$model_pin_cell" ]] && grep -qF '✅' <<<"$model_pin_cell" && grep -qF '2026-08-21' <<<"$model_pin_cell"; then
  report PASS "harness-matrix.md: Per-agent-model-pin Cursor cell (header col $cursor_col) carries a mark + 2026-08-21"
else
  report FAIL "harness-matrix.md: Per-agent-model-pin Cursor cell (header col $cursor_col) carries a mark + 2026-08-21" \
    "header_line=${matrix_header_line:-<missing>} cursor_col=${cursor_col:-<missing>} cell='${model_pin_cell:-}'"
fi

effort_pin_cell=""
if [[ -n "$cursor_col" ]]; then
  effort_pin_line="$(grep -n '^| Effort pin' "$HARNESS_MATRIX" | head -1 | cut -d: -f1)"
  if [[ -n "${effort_pin_line:-}" ]]; then
    effort_pin_cell="$(sed -n "${effort_pin_line}p" "$HARNESS_MATRIX" | awk -F'|' -v idx="$cursor_col" '{print $idx}')"
  fi
fi
if [[ -n "$effort_pin_cell" ]] && grep -qF '✅' <<<"$effort_pin_cell" && grep -qF '2026-08-21' <<<"$effort_pin_cell"; then
  report PASS "harness-matrix.md: Effort-pin Cursor cell (header col $cursor_col) carries a mark + 2026-08-21"
else
  report FAIL "harness-matrix.md: Effort-pin Cursor cell (header col $cursor_col) carries a mark + 2026-08-21" \
    "header_line=${matrix_header_line:-<missing>} cursor_col=${cursor_col:-<missing>} cell='${effort_pin_cell:-}'"
fi

# Non-contradiction is structural: the effort-pin cell's own prose must reference
# the model-pin row above rather than restate a (possibly diverging) scheme.
if [[ -n "$effort_pin_cell" ]] && grep -qF 'same scheme as the model-pin row above' <<<"$effort_pin_cell"; then
  report PASS "harness-matrix.md: effort-pin Cursor cell references 'same scheme as the model-pin row above' (non-contradiction)"
else
  report FAIL "harness-matrix.md: effort-pin Cursor cell references 'same scheme as the model-pin row above' (non-contradiction)" \
    "cell='${effort_pin_cell:-}'"
fi

# ===========================================================================
# 7. README.md, root ORCHESTRATION.md, skills/setup/VERSION.
# ===========================================================================

# 7a. A self-contained Cursor description exists in README.md.
if grep -q 'self-contained' "$ROOT_README" 2>/dev/null; then
  report PASS "README.md: self-contained Cursor description present"
else
  report FAIL "README.md: self-contained Cursor description present"
fi

# 7b. No claim remains that Cursor reuses .claude/ for kit files.
if [[ -f "$ROOT_README" ]]; then
  reuse_claude_count="$(grep -c 'reuse of \.claude' "$ROOT_README" || true)"
  if [[ "${reuse_claude_count:-0}" -eq 0 ]]; then
    report PASS "README.md: no remaining claim that Cursor reuses .claude/ for kit files"
  else
    report FAIL "README.md: no remaining claim that Cursor reuses .claude/ for kit files" \
      "found $reuse_claude_count occurrence(s) of 'reuse of .claude'"
  fi
else
  report FAIL "README.md: no remaining claim that Cursor reuses .claude/ for kit files" "file missing"
fi

# 7c. Root ORCHESTRATION.md mentions v0.19.0.
if grep -q 'v0.19.0' "$ROOT_ORCHESTRATION" 2>/dev/null; then
  report PASS "ORCHESTRATION.md: mentions v0.19.0"
else
  report FAIL "ORCHESTRATION.md: mentions v0.19.0"
fi

# 7d. skills/setup/VERSION equals exactly 0.23.0 (whole-file compare).
if [[ -f "$VERSION_FILE" ]] && [[ "$(cat "$VERSION_FILE")" == "0.23.0" ]]; then
  report PASS "skills/setup/VERSION equals exactly 0.23.0"
else
  version_contents="$(cat "$VERSION_FILE" 2>/dev/null)"
  report FAIL "skills/setup/VERSION equals exactly 0.23.0" \
    "contents: '${version_contents:-<missing>}'"
fi

# ===========================================================================
# 8. skills/setup/templates/models.map.md -- live-verification guidance + tokens.
# ===========================================================================

# 8a. Live-model-list verification guidance is present.
if grep -qF "harness's live model list" "$MODELS_MAP" 2>/dev/null; then
  report PASS "models.map.md: live-model-list verification guidance present"
else
  report FAIL "models.map.md: live-model-list verification guidance present"
fi

# 8b. {{CURSOR_MODEL_FRONTIER}} and {{CURSOR_MODEL_LIGHT}} tokens are both present.
if [[ -f "$MODELS_MAP" ]] \
  && [[ "$(grep -c '{{CURSOR_MODEL_FRONTIER}}' "$MODELS_MAP")" -ge 1 ]] \
  && [[ "$(grep -c '{{CURSOR_MODEL_LIGHT}}' "$MODELS_MAP")" -ge 1 ]]; then
  report PASS "models.map.md: {{CURSOR_MODEL_FRONTIER}} and {{CURSOR_MODEL_LIGHT}} tokens both present"
else
  report FAIL "models.map.md: {{CURSOR_MODEL_FRONTIER}} and {{CURSOR_MODEL_LIGHT}} tokens both present"
fi

# 8c. The coexisting-effort-scheme wording is present.
if grep -qF 'two coexisting forms' "$MODELS_MAP" 2>/dev/null; then
  report PASS "models.map.md: 'two coexisting forms' wording present"
else
  report FAIL "models.map.md: 'two coexisting forms' wording present"
fi

echo
echo "=== cursor-isolation summary ==="
echo "PASS: $pass_count   FAIL: $fail_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
