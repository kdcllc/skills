#!/usr/bin/env bash
# Regression guard for the cursor-self-contained-install goal: locks in the Cursor
# emitter's unconditional self-contained emit set, the `.claude`-free pointer-rule
# fence, the templates tree's `.claude/`-reference absence, the ORCHESTRATION
# template's model-map referencing, the agent-kit skill's per-emitter `{{IDE_DIR}}`
# semantics and multiline-safe absence of the pre-fix Cursor-reuse pairing, the
# harness matrix's non-contradictory Cursor model-pin / effort-pin cells, the
# model map's live-verification guidance, root ORCHESTRATION.md's `self-contained`
# anchor (7c), and a dynamic VERSION pin from skills/agent-kit/SKILL.md metadata.version through README,
# instance VERSION copies, and manifest kitVersion (7d). Tracked,
# self-install-independent — checks canonical templates, root docs, and instance
# paths when present.
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
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../lib/kit-version.sh
source "$REPO_ROOT/tests/agent-kit/lib/kit-version.sh"
cd "$REPO_ROOT" || exit 1

CURSOR_MD="$REPO_ROOT/skills/agent-kit/emitters/cursor.md"
ORCH_TEMPLATE="$REPO_ROOT/skills/agent-kit/templates/ORCHESTRATION.md"
TEMPLATES_DIR="$REPO_ROOT/skills/agent-kit/templates"
SETUP_SKILL_MD="$REPO_ROOT/skills/agent-kit/SKILL.md"
HARNESS_MATRIX="$REPO_ROOT/skills/agent-kit/reference/harness-matrix.md"
MODELS_MAP="$REPO_ROOT/skills/agent-kit/templates/models.map.md"
VERSION_FILE="$REPO_ROOT/skills/agent-kit/SKILL.md"
ROOT_README="$REPO_ROOT/skills/agent-kit/README.md"
ROOT_ORCHESTRATION="$REPO_ROOT/docs/agent-kit/README.md"
EMIT_SH="$REPO_ROOT/skills/agent-kit/bin/emit.sh"
EMIT_README="$REPO_ROOT/skills/agent-kit/bin/README.md"

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

# ===========================================================================
# 2. skills/agent-kit/emitters/cursor.md -- unconditional emit set (7 sub-checks).
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

# 2d. models.map.md → per-harness agent-kit-models.map.md: write site + kit-owned predicate.
if [[ -f "$EMIT_SH" ]] \
  && grep -qE 'put_emit "\$\(ide_dir_for "\$h"\)/skills/agent-kit-models\.map\.md"' "$EMIT_SH" 2>/dev/null \
  && grep -qF '.cursor/skills/agent-kit-models.map.md' "$EMIT_SH" 2>/dev/null \
  && grep -qF '.claude/skills/agent-kit-models.map.md|.cursor/skills/agent-kit-models.map.md' "$EMIT_SH" 2>/dev/null; then
  report PASS "emit.sh: put_emit skills/agent-kit-models.map.md write site + is_kit_owned literals"
else
  report FAIL "emit.sh: put_emit skills/agent-kit-models.map.md write site + is_kit_owned literals" \
    "put_emit/ide_dir_for write site or is_kit_owned destination literals not found in $EMIT_SH"
fi

# 2e. Embedded .mdc pointer content in emit.sh contains zero `.claude` substrings.
if [[ -f "$EMIT_SH" ]]; then
  mdc_content="$(awk '/^pointer_cursor_mdc\(\)/,/^}/' "$EMIT_SH")"
  if [[ -n "$mdc_content" ]]; then
    mdc_claude_count="$(grep -c '\.claude' <<<"$mdc_content" || true)"
    if [[ "${mdc_claude_count:-0}" -eq 0 ]]; then
      report PASS "emit.sh: embedded pointer_cursor_mdc contains zero .claude substrings"
    else
      report FAIL "emit.sh: embedded pointer_cursor_mdc contains zero .claude substrings" \
        "found $mdc_claude_count occurrence(s) inside pointer_cursor_mdc"
    fi
  else
    report FAIL "emit.sh: embedded pointer_cursor_mdc contains zero .claude substrings" \
      "pointer_cursor_mdc() block not found"
  fi
else
  report FAIL "emit.sh: embedded pointer_cursor_mdc contains zero .claude substrings" "file missing"
fi

# 2f. An {{IDE_DIR}} -> .cursor resolution statement exists.
if grep -qE '\{\{IDE_DIR\}\}.*\.cursor|resolves .\{\{IDE_DIR\}\}' "$CURSOR_MD" 2>/dev/null; then
  report PASS "cursor.md: {{IDE_DIR}} -> .cursor resolution statement present"
else
  report FAIL "cursor.md: {{IDE_DIR}} -> .cursor resolution statement present"
fi

# 2g. loop.cmd is documented; loop.ps1 and breaker.ps1 are not.
if [[ -f "$CURSOR_MD" ]] \
  && grep -qF 'loop.cmd' "$CURSOR_MD" \
  && [[ "$(grep -c 'loop\.ps1' "$CURSOR_MD")" -eq 0 ]] \
  && [[ "$(grep -c 'breaker\.ps1' "$CURSOR_MD")" -eq 0 ]]; then
  report PASS "cursor.md: loop.cmd present; loop.ps1 and breaker.ps1 absent"
else
  report FAIL "cursor.md: loop.cmd present; loop.ps1 and breaker.ps1 absent"
fi

# ===========================================================================
# 3. skills/agent-kit/templates/ORCHESTRATION.md -- model-map referencing.
# ===========================================================================
if [[ -f "$ORCH_TEMPLATE" ]]; then
  model_token_count="$(grep -c '{{MODEL_' "$ORCH_TEMPLATE" || true)"
  setup_map_count="$(grep -c 'agent-kit-models.map.md' "$ORCH_TEMPLATE" || true)"
  if [[ "${model_token_count:-0}" -eq 2 && "${setup_map_count:-0}" -ge 1 ]]; then
    report PASS "templates/ORCHESTRATION.md: two {{MODEL_ tokens, >=1 agent-kit-models.map.md reference"
  else
    report FAIL "templates/ORCHESTRATION.md: two {{MODEL_ tokens, >=1 agent-kit-models.map.md reference" \
      "{{MODEL_ count=${model_token_count:-0}, agent-kit-models.map.md count=${setup_map_count:-0}"
  fi
else
  report FAIL "templates/ORCHESTRATION.md: two {{MODEL_ tokens, >=1 agent-kit-models.map.md reference" "file missing"
fi

# ===========================================================================
# 4. skills/agent-kit/templates/ tree -- .claude/ reference absence.
#    Today's tree has zero occurrences anywhere under templates/ (the allowlist is
#    empty), so this is a plain zero-occurrence absence assertion, not an allowlist
#    walk -- per the task's own reality-anchoring instruction. Any future `.claude/`
#    reintroduction anywhere in the tree FAILs this check.
# ===========================================================================
if [[ -d "$TEMPLATES_DIR" ]]; then
  templates_claude_total="$(grep -rc '\.claude' "$TEMPLATES_DIR" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
  if [[ "${templates_claude_total:-0}" -eq 0 ]]; then
    report PASS "templates/ tree: zero .claude occurrences anywhere under skills/agent-kit/templates/"
  else
    report FAIL "templates/ tree: zero .claude occurrences anywhere under skills/agent-kit/templates/" \
      "found $templates_claude_total occurrence(s)"
  fi
else
  report FAIL "templates/ tree: zero .claude occurrences anywhere under skills/agent-kit/templates/" "directory missing"
fi

# ===========================================================================
# 5. skills/agent-kit/SKILL.md -- reuse-pairing absence and {{IDE_DIR}}/Step-4 semantics.
# ===========================================================================

# 5a. The pre-fix wrapped sentence fragment "-- Cursor and\nVS Code reuse parts of
#     the emitted `.claude/` tree." spans two physical lines in the pre-fix file, so
#     a naive single-line `grep -c "Cursor and VS Code reuse"` is a documented
#     TAUTOLOGY: it returns 0 on BOTH the pre-fix and post-fix file, because the
#     phrase never appears on one physical line either way -- it is NOT the check
#     this script relies on (see the mutation spot-check report for a live
#     side-by-side demonstration). The actual assertion below is multiline-aware: it
#     flattens the file with `tr '\n' ' '` first (mirroring this repo's own
#     tests/agent-kit/templates/invocation-flags.sh convention for multiline prose checks), so
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

# 5c. Token resolution per harness: README prose + emit.sh ide_dir_for behaviour.
if grep -qF 'translates per harness' "$EMIT_README" 2>/dev/null \
   && grep -qF 'ide_dir_for()' "$EMIT_SH" 2>/dev/null \
   && grep -qF 'map_set TOKENS IDE_DIR "$(ide_dir_for "$h")"' "$EMIT_SH" 2>/dev/null; then
  report PASS "bin/README.md + emit.sh: tokens resolved per harness (ide_dir_for + IDE_DIR via map_set)"
else
  report FAIL "bin/README.md + emit.sh: tokens resolved per harness (ide_dir_for + IDE_DIR via map_set)"
fi

# 5d. Single-copy artifacts are written from the primary harness in emit.sh.
if grep -qF 'emit_single_copy' "$EMIT_SH" 2>/dev/null \
   && grep -qF 'PRIMARY' "$EMIT_SH" 2>/dev/null; then
  report PASS "emit.sh: single-copy artifacts emitted from the primary harness"
else
  report FAIL "emit.sh: single-copy artifacts emitted from the primary harness"
fi

# 5e. _loop/PROMPT.md is a single-copy artifact named in emit.sh.
if grep -qF 'PROMPT.md' "$EMIT_SH" 2>/dev/null; then
  report PASS "emit.sh: _loop/PROMPT.md named as a single-copy loop artifact"
else
  report FAIL "emit.sh: _loop/PROMPT.md named as a single-copy loop artifact"
fi

# ===========================================================================
# 6. skills/agent-kit/reference/harness-matrix.md -- Kit policy, non-contradictory
#    Cursor cells. The Cursor column is located via the capability table's own
#    header row (matching the field whose trimmed text is exactly "Cursor"), never
#    via a hardcoded field index or a whole-line grep -- a whole-line date grep
#    could pass on a date sitting in a different harness's cell.
# ===========================================================================

# 6a. self-containment policy note exists.
if grep -qF 'Kit policy:' "$HARNESS_MATRIX" 2>/dev/null; then
  report PASS "harness-matrix.md: self-containment Kit policy: note present"
else
  report FAIL "harness-matrix.md: self-containment Kit policy: note present"
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
# 7. README.md, root ORCHESTRATION.md, skills/agent-kit/SKILL.md metadata.version.
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

# 7c. Root ORCHESTRATION.md mentions self-contained (pointer, not version history).
if grep -qF 'self-contained' "$ROOT_ORCHESTRATION" 2>/dev/null; then
  report PASS "docs hub: mentions self-contained"
else
  report FAIL "docs hub: mentions self-contained"
fi

# 7d. skills/agent-kit/SKILL.md metadata.version semver, README Kit version line, instance VERSIONs (SKIP if absent).
KIT_VERSION="$(kit_version "$VERSION_FILE" 2>/dev/null || true)"
check7d_ok=1
check7d_detail=""
if [[ ! "$KIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  check7d_ok=0
  check7d_detail="VERSION not semver: '${KIT_VERSION:-<missing>}'"
elif ! grep -qF -- "Kit version: **$KIT_VERSION**" "$ROOT_README" 2>/dev/null; then
  check7d_ok=0
  check7d_detail="README missing Kit version: **$KIT_VERSION**"
else
  for ivf in "$REPO_ROOT/.claude/skills/agent-kit/SKILL.md" "$REPO_ROOT/.cursor/skills/agent-kit/SKILL.md"; do
    rel="${ivf#"$REPO_ROOT"/}"
    if [[ ! -f "$ivf" ]]; then
      skip_report "7d: $rel absent"
      continue
    fi
    if [[ "$(kit_version "$ivf")" != "$KIT_VERSION" ]]; then
      check7d_ok=0
      check7d_detail="$rel != $KIT_VERSION"
      break
    fi
  done
  if [[ $check7d_ok -eq 1 ]] && [[ -f "$REPO_ROOT/orchestration-kit.manifest.json" ]]; then
    manifest_ver="$(grep -m1 '"kitVersion"' "$REPO_ROOT/orchestration-kit.manifest.json" 2>/dev/null | \
      sed -E 's/.*"kitVersion"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
    if [[ "$manifest_ver" != "$KIT_VERSION" ]]; then
      check7d_ok=0
      check7d_detail="manifest kitVersion != $KIT_VERSION"
    fi
  elif [[ $check7d_ok -eq 1 ]]; then
    skip_report "7d: orchestration-kit.manifest.json absent"
  fi
fi
if [[ $check7d_ok -eq 1 ]]; then
  report PASS "skills/agent-kit/SKILL.md metadata.version semver + README Kit version **$KIT_VERSION** (+ instance/manifest when present)"
else
  report FAIL "skills/agent-kit/SKILL.md metadata.version semver + README Kit version **$KIT_VERSION** (+ instance/manifest when present)" \
    "$check7d_detail"
fi

# ===========================================================================
# 8. skills/agent-kit/templates/models.map.md -- live-verification guidance + tokens.
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
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
