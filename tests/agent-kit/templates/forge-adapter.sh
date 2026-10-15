#!/usr/bin/env bash
# Regression guard for the forge-adapter-delivery goal: locks the four-branch
# ship-pr create commands and never-executes hand-over, the canonical ORCHESTRATION
# Forge-adapter taxonomy and remote-precedence chain, recursive absence of
# `delete Phase 7` under skills/agent-kit/templates/, setup SKILL manifest forge/forgeHost
# and Upgrading re-detect/reconcile, dual-instance ship-pr anchor parity, and VERSION /
# README / manifest kitVersion consistency at dynamic VERSION with options.forge github.
# Tracked, self-install-independent — checks canonical templates, setup SKILL, instance
# copies, and manifest directly (no network, no LLM).
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
SHIP_PR="$TEMPLATES/skills/ship-pr/SKILL.template.md"
ORCH_TEMPLATE="$TEMPLATES/ORCHESTRATION.md"
SETUP_SKILL="$REPO_ROOT/skills/agent-kit/SKILL.md"
CLAUDE_SHIP_PR="$REPO_ROOT/.claude/skills/ship-pr/SKILL.md"
CURSOR_SHIP_PR="$REPO_ROOT/.cursor/skills/ship-pr/SKILL.md"
VERSION_FILE="$REPO_ROOT/skills/agent-kit/SKILL.md"
CLAUDE_VERSION="$REPO_ROOT/.claude/skills/agent-kit/SKILL.md"
CURSOR_VERSION="$REPO_ROOT/.cursor/skills/agent-kit/SKILL.md"
ROOT_README="$REPO_ROOT/skills/agent-kit/README.md"
MANIFEST="$REPO_ROOT/orchestration-kit.manifest.json"

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
# 1. Canonical ship-pr: three create commands, Forge adapter cross-ref,
#    none-branch never executes, git ls-remote --symref, no hardcoded origin
#    base resolution, disable-model-invocation.
# ===========================================================================
check1_ok=1
check1_detail=""
if [[ ! -f "$SHIP_PR" ]]; then
  check1_ok=0
  check1_detail="missing $SHIP_PR"
else
  grep -qF 'gh pr create' "$SHIP_PR" || { check1_ok=0; check1_detail="gh pr create missing"; }
  grep -qF 'az repos pr create' "$SHIP_PR" || { check1_ok=0; check1_detail="az repos pr create missing"; }
  grep -qF 'glab mr create' "$SHIP_PR" || { check1_ok=0; check1_detail="glab mr create missing"; }
  grep -qF 'Forge adapter (Phase 7 delivery)' "$SHIP_PR" || { check1_ok=0; check1_detail="Forge adapter cross-ref missing"; }
  grep -qF 'never executes' "$SHIP_PR" || { check1_ok=0; check1_detail="never executes anchor missing"; }
  grep -qF 'git ls-remote --symref' "$SHIP_PR" || { check1_ok=0; check1_detail="git ls-remote --symref missing"; }
  if grep -qF 'git fetch origin' "$SHIP_PR" 2>/dev/null; then
    check1_ok=0
    check1_detail="forbidden git fetch origin present"
  fi
  if grep -qF 'origin/"$BASE"' "$SHIP_PR" 2>/dev/null; then
    check1_ok=0
    check1_detail='forbidden origin/"$BASE" present'
  fi
  grep -qF 'disable-model-invocation: true' "$SHIP_PR" || { check1_ok=0; check1_detail="disable-model-invocation: true missing"; }
fi
if [[ $check1_ok -eq 1 ]]; then
  report PASS "canonical ship-pr: three create commands, Forge adapter cross-ref, never executes, ls-remote --symref, no hardcoded origin base, disable-model-invocation"
else
  report FAIL "canonical ship-pr: three create commands, Forge adapter cross-ref, never executes, ls-remote --symref, no hardcoded origin base, disable-model-invocation" \
    "$check1_detail"
fi

# ===========================================================================
# 2. Canonical ORCHESTRATION: one live ### Forge adapter heading, four taxonomy
#    values (github, azuredevops, gitlab, none), never-delete sentence,
#    precedence upstream before origin.
# ===========================================================================
check2_ok=1
check2_detail=""
if [[ ! -f "$ORCH_TEMPLATE" ]]; then
  check2_ok=0
  check2_detail="missing $ORCH_TEMPLATE"
else
  heading_count="$(grep -cE '^### Forge adapter \(Phase 7 delivery\)$' "$ORCH_TEMPLATE" 2>/dev/null || true)"
  if [[ "${heading_count:-0}" -ne 1 ]]; then
    check2_ok=0
    check2_detail="expected exactly one live ### Forge adapter heading, got ${heading_count:-0}"
  fi
  grep -qF 'gh pr create' "$ORCH_TEMPLATE" || { check2_ok=0; check2_detail="gh pr create missing in ORCHESTRATION"; }
  grep -qF 'az repos pr create' "$ORCH_TEMPLATE" || { check2_ok=0; check2_detail="az repos pr create missing in ORCHESTRATION"; }
  grep -qF 'glab mr create' "$ORCH_TEMPLATE" || { check2_ok=0; check2_detail="glab mr create missing in ORCHESTRATION"; }
  grep -qF 'never creates' "$ORCH_TEMPLATE" || { check2_ok=0; check2_detail="never creates missing in ORCHESTRATION"; }
  grep -qF 'Phase 7 is never deleted' "$ORCH_TEMPLATE" || { check2_ok=0; check2_detail="Phase 7 is never deleted missing"; }
  if ! awk '/precedence/ && /upstream/ && /origin/ { if(index($0,"upstream") < index($0,"origin")) f=1 } END{exit !f}' "$ORCH_TEMPLATE"; then
    check2_ok=0
    check2_detail="precedence chain upstream before origin missing or reversed"
  fi
fi
if [[ $check2_ok -eq 1 ]]; then
  report PASS "canonical ORCHESTRATION: one Forge adapter heading, four taxonomy values, never-delete, precedence upstream before origin"
else
  report FAIL "canonical ORCHESTRATION: one Forge adapter heading, four taxonomy values, never-delete, precedence upstream before origin" \
    "$check2_detail"
fi

# ===========================================================================
# 3. Recursive absence of `delete Phase 7` under skills/agent-kit/templates/.
# ===========================================================================
if grep -rqF 'delete Phase 7' "$TEMPLATES" 2>/dev/null; then
  report FAIL "recursive delete Phase 7 absent under skills/agent-kit/templates/" \
    "found delete Phase 7 under templates tree"
else
  report PASS "recursive delete Phase 7 absent under skills/agent-kit/templates/"
fi

# ===========================================================================
# 4. skills/agent-kit/SKILL.md: delete Phase 7 absent; Step 6 forge example;
#    forgeHost documented; Upgrading re-detect the forge.
# ===========================================================================
check4_ok=1
check4_detail=""
if [[ ! -f "$SETUP_SKILL" ]]; then
  check4_ok=0
  check4_detail="missing skills/agent-kit/SKILL.md"
else
  if grep -qF 'delete Phase 7' "$SETUP_SKILL" 2>/dev/null; then
    check4_ok=0
    check4_detail="delete Phase 7 present in setup SKILL"
  fi
  grep -qF '"forge": "<detected>"' "$SETUP_SKILL" || { check4_ok=0; check4_detail='"forge": "<detected>" missing'; }
  grep -qF 'forgeHost' "$SETUP_SKILL" || { check4_ok=0; check4_detail="forgeHost missing"; }
  grep -qF 're-detect the forge' "$SETUP_SKILL" || { check4_ok=0; check4_detail="re-detect the forge missing"; }
fi
if [[ $check4_ok -eq 1 ]]; then
  report PASS "skills/agent-kit/SKILL.md: delete Phase 7 absent, forge example, forgeHost, re-detect the forge"
else
  report FAIL "skills/agent-kit/SKILL.md: delete Phase 7 absent, forge example, forgeHost, re-detect the forge" \
    "$check4_detail"
fi

# ===========================================================================
# 5. Instance ship-pr copies: same create/never-executes anchors; no {{ placeholders.
# ===========================================================================
check5_ok=1
check5_detail=""
for inst in "$CLAUDE_SHIP_PR" "$CURSOR_SHIP_PR"; do
  rel="${inst#"$REPO_ROOT"/}"
  if [[ ! -f "$inst" ]]; then
    check5_ok=0
    check5_detail="missing $rel"
    break
  fi
  grep -qF 'gh pr create' "$inst" 2>/dev/null || { check5_ok=0; check5_detail="$rel: gh pr create missing"; break; }
  grep -qF 'az repos pr create' "$inst" 2>/dev/null || { check5_ok=0; check5_detail="$rel: az repos pr create missing"; break; }
  grep -qF 'glab mr create' "$inst" 2>/dev/null || { check5_ok=0; check5_detail="$rel: glab mr create missing"; break; }
  grep -qF 'never executes' "$inst" 2>/dev/null || { check5_ok=0; check5_detail="$rel: never executes missing"; break; }
done
if [[ $check5_ok -eq 1 ]] && grep -qF '{{' "$CLAUDE_SHIP_PR" "$CURSOR_SHIP_PR" 2>/dev/null; then
  check5_ok=0
  check5_detail="{{ placeholder still present in instance ship-pr copy"
fi
if [[ $check5_ok -eq 1 ]]; then
  report PASS "instance ship-pr (.claude + .cursor): three create commands, never executes, no {{ placeholders"
else
  report FAIL "instance ship-pr (.claude + .cursor): three create commands, never executes, no {{ placeholders" \
    "$check5_detail"
fi

# ===========================================================================
# 6. Dynamic VERSION consistency (skills/agent-kit/SKILL.md metadata.version drives README + manifest).
# ===========================================================================
check6_ok=1
check6_detail=""
KIT_VERSION="$(kit_version "$VERSION_FILE" 2>/dev/null || true)"
if [[ ! "$KIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  check6_ok=0
  check6_detail="skills/agent-kit/SKILL.md metadata.version not semver: '${KIT_VERSION:-<missing>}'"
fi
for vf in "$VERSION_FILE" "$CLAUDE_VERSION" "$CURSOR_VERSION"; do
  rel="${vf#"$REPO_ROOT"/}"
  if [[ ! -f "$vf" ]]; then
    if [[ "$vf" == "$VERSION_FILE" ]]; then
      check6_ok=0
      check6_detail="$rel missing"
      break
    fi
    skip_report "check 6: $rel absent"
    continue
  fi
  if [[ "$(kit_version "$vf")" != "$KIT_VERSION" ]]; then
    check6_ok=0
    check6_detail="$rel != $KIT_VERSION"
    break
  fi
done
if [[ $check6_ok -eq 1 ]] && ! grep -qF -- "Kit version: **$KIT_VERSION**" "$ROOT_README" 2>/dev/null; then
  check6_ok=0
  check6_detail="README Kit version line missing or wrong"
fi
if [[ $check6_ok -eq 1 ]] && [[ -f "$MANIFEST" ]]; then
  manifest_ver="$(grep -m1 '"kitVersion"' "$MANIFEST" 2>/dev/null | \
    sed -E 's/.*"kitVersion"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
  if [[ "$manifest_ver" != "$KIT_VERSION" ]]; then
    check6_ok=0
    check6_detail="manifest kitVersion '$manifest_ver' != $KIT_VERSION"
  elif ! grep -qF '"forge": "github"' "$MANIFEST" 2>/dev/null; then
    check6_ok=0
    check6_detail="manifest options.forge != github"
  fi
elif [[ $check6_ok -eq 1 ]]; then
  skip_report "check 6: orchestration-kit.manifest.json absent"
fi
if [[ $check6_ok -eq 1 ]]; then
  report PASS "VERSION $KIT_VERSION at skills/agent-kit/SKILL.md metadata.version, nested VERSIONs, README Kit version, manifest kitVersion; options.forge github"
else
  report FAIL "VERSION $KIT_VERSION at skills/agent-kit/SKILL.md metadata.version, nested VERSIONs, README Kit version, manifest kitVersion; options.forge github" \
    "$check6_detail"
fi

echo
echo "=== forge-adapter summary ==="
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
