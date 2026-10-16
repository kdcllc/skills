#!/usr/bin/env bash
# Regression guard for orchestration-degraded-mode: locks degraded-mode reference,
# feature-skill and ORCHESTRATION wiring, harness-matrix and Cursor emitter caveats,
# ship-pr self-evaluated gates section, emitted degraded-mode instances, and a negative
# self-test on a copied template. Tracked, self-install-independent — no network, no LLM.
#
# Copy degraded-mode.md into a mktemp dir, mutate under test, then run check logic
# against the copy — never the live repo (see check 6).
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location.
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
DEGRADED_REF="$TEMPLATES/skills/feature/reference/degraded-mode.md"
FEATURE_SKILL="$TEMPLATES/skills/feature/SKILL.template.md"
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"
SHIP_PR="$TEMPLATES/skills/ship-pr/SKILL.template.md"
HARNESS_MATRIX="$REPO_ROOT/skills/agent-kit/reference/harness-matrix.md"
EMITTER_CURSOR="$REPO_ROOT/skills/agent-kit/emitters/cursor.md"
DEGRADED_CURSOR="$REPO_ROOT/.cursor/skills/feature/reference/degraded-mode.md"
DEGRADED_CLAUDE="$REPO_ROOT/.claude/skills/feature/reference/degraded-mode.md"

# Gate-disclosure anchor (grep -c → 1); used in check 1 and negative self-test.
GATE_DISCLOSURE_ANCHOR='before the user approves the PR'

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

check_canonical_degraded_mode() { # check_canonical_degraded_mode <file> → 0 if all anchors present
  local f="$1"
  reject_empty_path "$f" || return 1
  [[ -f "$f" ]] || return 1
  grep -qF '## Case 1 — model argument rejected' "$f" || return 1
  grep -qF 'spawn rejected: model argument' "$f" || return 1
  grep -qF 'never reuse the rejected spawn'"'"'s NN' "$f" || return 1
  grep -qF 'harness default / **`inherit`**' "$f" || return 1
  grep -qF 'log a new `spawn` with `--model-requested inherit`' "$f" || return 1
  grep -qF '## Case 2 — no spawn tool' "$f" || return 1
  grep -qF '**You never write or edit product code yourself**' "$f" || return 1
  grep -qF '**Terminal spawn rule**' "$f" || return 1
  grep -qF -- '--model-requested self --context <that file>' "$f" || return 1
  grep -qF 'spawn NN --report <that file> --verdict' "$f" || return 1
  grep -qF -- '--model-reported self --note "self-evaluation, not independent"' "$f" || return 1
  grep -qF "$GATE_DISCLOSURE_ANCHOR" "$f" || return 1
  grep -qF 'The **final report** (end-of-goal summary to the user)' "$f" || return 1
  grep -qF 'If a spawn tool **exists** and accepts spawns' "$f" || return 1
  if grep -qF 'harness-matrix' "$f" 2>/dev/null; then
    return 1
  fi
  return 0
}

check_emitted_degraded_mode() { # check_emitted_degraded_mode <file> → 0 if Case 1/2 anchors
  local f="$1"
  reject_empty_path "$f" || return 1
  [[ -f "$f" ]] || return 1
  grep -qF '## Case 1 — model argument rejected' "$f" || return 1
  grep -qF '## Case 2 — no spawn tool' "$f" || return 1
}

# ===========================================================================
# 1. Canonical degraded-mode.md anchors.
# ===========================================================================
if check_canonical_degraded_mode "$DEGRADED_REF"; then
  report PASS "canonical degraded-mode.md: Case 1/2, self ledger, gates, no harness-matrix link"
else
  report FAIL "canonical degraded-mode.md: Case 1/2, self ledger, gates, no harness-matrix link" \
    "missing file or anchor in $DEGRADED_REF"
fi

# ===========================================================================
# 2. Feature skill iron-rules pointer.
# ===========================================================================
check2_ok=1
if [[ ! -f "$FEATURE_SKILL" ]]; then
  check2_ok=0
else
  grep -qF 'Model arg rejected / no spawn tool → `reference/degraded-mode.md`' "$FEATURE_SKILL" || check2_ok=0
fi
if [[ $check2_ok -eq 1 ]]; then
  report PASS "feature skill: iron-rules pointer to reference/degraded-mode.md"
else
  report FAIL "feature skill: iron-rules pointer to reference/degraded-mode.md"
fi

# ===========================================================================
# 3. ORCHESTRATION.md degraded wiring and file trees.
# ===========================================================================
check3_ok=1
if [[ ! -f "$ORCH_TEMPLATE" ]]; then
  check3_ok=0
else
  grep -qF 'A rejected **model** argument or a missing spawn tool is **not** transient' "$ORCH_TEMPLATE" || check3_ok=0
  tree_count="$(grep -cF 'ready-groups.md,degraded-mode.md,' "$ORCH_TEMPLATE" 2>/dev/null || true)"
  [[ "$tree_count" == 4 ]] || check3_ok=0
fi
if [[ $check3_ok -eq 1 ]]; then
  report PASS "ORCHESTRATION.md: Subagent Invocation degraded pointer + file-tree entry (×4)"
else
  report FAIL "ORCHESTRATION.md: Subagent Invocation degraded pointer + file-tree entry (×4)" \
    "tree_count=${tree_count:-missing}"
fi

# ===========================================================================
# 4. harness-matrix row, Cursor emitter caveat, retired Cloud L1-only phrases.
# ===========================================================================
check4_ok=1
if [[ ! -f "$HARNESS_MATRIX" ]]; then
  check4_ok=0
elif ! grep -qF '**Degraded-spawn row 2026-10-16**' "$HARNESS_MATRIX" 2>/dev/null; then
  check4_ok=0
elif ! grep -qF 'Degraded spawn conditions (model pin rejected / no spawn tool)' "$HARNESS_MATRIX" 2>/dev/null; then
  check4_ok=0
fi
if [[ ! -f "$EMITTER_CURSOR" ]]; then
  check4_ok=0
elif ! grep -qF '**Degraded mode**:' "$EMITTER_CURSOR" 2>/dev/null; then
  check4_ok=0
fi
for bad_phrase in \
  'Cloud Agents (L1 only)' \
  'cloud: L1 only' \
  'Cloud Agents support only main→L1'; do
  if grep -rqF "$bad_phrase" "$REPO_ROOT/skills/agent-kit" 2>/dev/null; then
    check4_ok=0
    break
  fi
done
if [[ $check4_ok -eq 1 ]]; then
  report PASS "harness-matrix degraded row + Cursor emitter caveat; no retired Cloud L1-only phrases"
else
  report FAIL "harness-matrix degraded row + Cursor emitter caveat; no retired Cloud L1-only phrases"
fi

# ===========================================================================
# 4b. ship-pr conditional Self-evaluated gates section.
# ===========================================================================
check4b_ok=1
if [[ ! -f "$SHIP_PR" ]]; then
  check4b_ok=0
else
  grep -qF 'any log contains `self-evaluation, not independent`, include `## Self-evaluated gates`' "$SHIP_PR" || check4b_ok=0
fi
if [[ $check4b_ok -eq 1 ]]; then
  report PASS "ship-pr Step 5: conditional Self-evaluated gates keyed on non-independent note"
else
  report FAIL "ship-pr Step 5: conditional Self-evaluated gates keyed on non-independent note"
fi

# ===========================================================================
# 5. Emitted degraded-mode instances (SKIP when absent).
# ===========================================================================
for inst_pair in \
  ".cursor:$DEGRADED_CURSOR" \
  ".claude:$DEGRADED_CLAUDE"; do
  inst_label="${inst_pair%%:*}"
  inst_path="${inst_pair#*:}"
  if [[ ! -f "$inst_path" ]]; then
    skip_report "emitted $inst_label/skills/feature/reference/degraded-mode.md absent"
    continue
  fi
  if check_emitted_degraded_mode "$inst_path"; then
    report PASS "emitted $inst_label/skills/feature/reference/degraded-mode.md: Case 1 and Case 2 headings"
  else
    report FAIL "emitted $inst_label/skills/feature/reference/degraded-mode.md: Case 1 and Case 2 headings" \
      "regression in $inst_path"
  fi
done

# ===========================================================================
# 6. Negative self-test: mutated copy must fail check-1 logic.
# ===========================================================================
neg_ok=0
neg_root="$(mktemp -d "${TMPDIR:-/tmp}/degradedmodeneg.XXXXXX")" || neg_root=""
if [[ -z "$neg_root" || ! -d "$neg_root" ]]; then
  report FAIL "negative self-test: check-1 fails when gate-disclosure line removed from copy" \
    "mktemp -d failed"
else
  mkdir -p "$neg_root/skills/agent-kit/templates/skills/feature/reference" || true
  if cp "$DEGRADED_REF" "$neg_root/skills/agent-kit/templates/skills/feature/reference/degraded-mode.md"; then
    sed "/$(printf '%s' "$GATE_DISCLOSURE_ANCHOR" | sed 's/[\/&]/\\&/g')/d" \
      "$neg_root/skills/agent-kit/templates/skills/feature/reference/degraded-mode.md" > \
      "$neg_root/skills/agent-kit/templates/skills/feature/reference/degraded-mode.md.tmp" \
      && mv "$neg_root/skills/agent-kit/templates/skills/feature/reference/degraded-mode.md.tmp" \
         "$neg_root/skills/agent-kit/templates/skills/feature/reference/degraded-mode.md"
    neg_ref="$neg_root/skills/agent-kit/templates/skills/feature/reference/degraded-mode.md"
    gate_remaining="$(grep -cF "$GATE_DISCLOSURE_ANCHOR" "$neg_ref" 2>/dev/null)"
    gate_remaining="${gate_remaining:-0}"
    echo "negative self-test: gate-disclosure anchor remaining count in copy: $gate_remaining"
    if check_canonical_degraded_mode "$neg_ref"; then
      neg_ok=0
    else
      neg_ok=1
    fi
  fi
  rm -rf "$neg_root"
fi
if [[ $neg_ok -eq 1 ]]; then
  report PASS "negative self-test: check-1 fails when gate-disclosure line removed from copied degraded-mode.md"
else
  report FAIL "negative self-test: check-1 fails when gate-disclosure line removed from copied degraded-mode.md"
fi

if check_canonical_degraded_mode ""; then
  report FAIL "check-1 rejects empty path arguments"
else
  report PASS "check-1 rejects empty path arguments"
fi

echo
echo "=== degraded-mode summary ==="
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
