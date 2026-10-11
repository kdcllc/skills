#!/usr/bin/env bash
# Deterministic behavioral test harness for the AI Orchestration Kit's loop /
# breaker / checks tooling (tracked repo tooling — test-ladder rung 3
# territory, run manually or in CI; NOT wired as a manifest-emitted instance
# file). Persisted from the story-002/006/007 session scratchpad harness.
# Exercises:
#   - the canonical breaker.sh state machine (assertions 1-12, 11b, 11c) with
#     injected timestamps -- no wall-clock reads;
#   - the LIVE detect_rate_limit function extracted verbatim from canonical
#     loop.sh (assertions 13-14, 13b, 13c), so the detector under test is the
#     real, perf-fixed (two-stage grep) function, not a reimplementation;
#   - a CB1 carve-out end-to-end stub run of the RE-EMITTED instance
#     _loop/loop.sh + _loop/breaker.sh inside a throwaway git repo (assertion
#     15) — requires the repo's own self-install (_loop/) to exist;
#   - T1a/T1b PowerShell structural guards, A1-A3 emitter/SKILL text coverage,
#     the story-006 T2a herestring SIGPIPE regression + its pre-fix control
#     (assertions 16-19-ish);
#   - story-007 additions: checks J (manifest hash join, self-excluding,
#     seed-aware) and K (ownership-contract shape) mutation-proven via the
#     CHECKS_MANIFEST override and copy-based grep replication; the task-02
#     pristine-clause literal tripwire; and a frozen TMPDIR characterization
#     of the herestring sentinel check under an unwritable TMPDIR.
#   - self-install block (no _loop/ required): assertions 69+ exercise
#     scripts/agent-kit/self-install.sh and self-install.ps1 against a temp fixture —
#     copy-mode, overwrite, --force, dry-run, --dry-run --symlink, unknown-flag,
#     empty-skills, sibling-preservation, rollback, --symlink, mode-transition,
#     .gitignore dest-lines, bash -n, ps1 structural-parity, ps1 parse (pwsh-
#     conditional), ps1 live run (pwsh-conditional), README citation, and
#     checks B/D excluding the compiler copy at .claude/skills/agent-kit/.
#   - greenfield-setup Step 2b contract (no _loop/ required): assertions 125-135
#     lock Step 2b skill-suggestions contract, docs/version claims, and $TMP
#     mutations against skills/agent-kit/SKILL.md, README.md, CHANGELOG.md, and
#     docs/agent-kit/guide/getting-started.md.
#
# Every assertion is outcome-verifying: it inspects the resulting state file /
# stdout / stderr / exit code and FAILs loudly (non-zero exit, explicit FAIL
# line) if behavior regresses. No network, no external services. Mutations
# run ONLY on copies under this run's mktemp workdir -- repo files (including
# .claude/checks.sh and the task template) are never written to.
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location (works
# from any cwd, any clone path -- no hardcoded absolute paths).
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../lib/kit-version.sh
source "$REPO_ROOT/tests/agent-kit/lib/kit-version.sh"
cd "$REPO_ROOT" || exit 1

BREAKER_SH="$REPO_ROOT/skills/agent-kit/templates/loop/breaker.sh"
BREAKER_PS1="$REPO_ROOT/skills/agent-kit/templates/loop/breaker.ps1"
LOOP_SH="${LOOP_DRIVER_SH:-$REPO_ROOT/skills/agent-kit/templates/loop/loop.sh}"
LOOP_PS1="$REPO_ROOT/skills/agent-kit/templates/loop/loop.ps1"
INSTANCE_LOOP_SH="$REPO_ROOT/_loop/loop.sh"
INSTANCE_LOOP_PS1="$REPO_ROOT/_loop/loop.ps1"
INSTANCE_BREAKER_SH="$REPO_ROOT/_loop/breaker.sh"
INSTANCE_PROMPT_MD="$REPO_ROOT/_loop/PROMPT.md"
SETUP_SKILL_MD="$REPO_ROOT/skills/agent-kit/SKILL.md"
CURSOR_MD="$REPO_ROOT/skills/agent-kit/emitters/cursor.md"
CLAUDE_CODE_MD="$REPO_ROOT/skills/agent-kit/emitters/claude-code.md"
CODEX_MD="$REPO_ROOT/skills/agent-kit/emitters/codex.md"
COPILOT_MD="$REPO_ROOT/skills/agent-kit/emitters/copilot.md"
CHECKS_SH="$REPO_ROOT/tests/agent-kit/checks.sh"
TASK_TPL="$REPO_ROOT/skills/agent-kit/templates/skills/feature/templates/task.md"
CRITERIA_TPL="$REPO_ROOT/skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md"
MANIFEST_JSON="$REPO_ROOT/orchestration-kit.manifest.json"
CANON_AGENTS_DIR="$REPO_ROOT/skills/agent-kit/templates/agents"
CONTRACT_TPL="$REPO_ROOT/skills/agent-kit/templates/skills/feature/templates/contract.md"
INSTANCE_AGENTS_DIR="$REPO_ROOT/.claude/agents"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail_count=0
pass_count=0
skip_count=0

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  if [[ "$status" == "PASS" ]]; then
    pass_count=$((pass_count + 1))
    echo "PASS: $name"
  elif [[ "$status" == "SKIP" ]]; then
    skip_count=$((skip_count + 1))
    echo "SKIP: $name"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $name${detail:+ -- $detail}" >&2
  fi
}

# shellcheck source=/dev/null
source "$BREAKER_SH"

# ===========================================================================
# Self-install dogfood assertions (69+, no _loop/ required).
# Exercises scripts/agent-kit/self-install.sh and scripts/agent-kit/self-install.ps1 against a
# temp fixture only — never writes to the live repo dests (.claude/, .cursor/,
# .agents/ under REPO_ROOT).
# ===========================================================================

# Build shared temp fixture: two top-level skills (agent-kit, other) — only
# agent-kit is installed; one nested SKILL.md under skills/agent-kit/templates/…
# that must NOT be installed as a skill named "feature"; installer scripts copied from the repo. cwd during all runs
# is "$TMP" (different from the fixture root) to prove repo-root auto-detection.
SI_FIX="$TMP/si-fix"
mkdir -p "$SI_FIX/scripts/agent-kit" \
         "$SI_FIX/skills/agent-kit/templates/skills/feature" \
         "$SI_FIX/skills/other"
cp "$REPO_ROOT/scripts/agent-kit/self-install.sh"  "$SI_FIX/scripts/agent-kit/self-install.sh"
cp "$REPO_ROOT/scripts/agent-kit/self-install.ps1" "$SI_FIX/scripts/agent-kit/self-install.ps1"
printf 'SKILL:agent-kit\n'          > "$SI_FIX/skills/agent-kit/SKILL.md"
printf 'NESTED:feature-not-a-skill\n' > "$SI_FIX/skills/agent-kit/templates/skills/feature/SKILL.md"
printf 'SKILL:other\n'              > "$SI_FIX/skills/other/SKILL.md"

# ---------------------------------------------------------------------------
# 69. bash -n syntax check on repo scripts/agent-kit/self-install.sh
# ---------------------------------------------------------------------------
if bash -n "$REPO_ROOT/scripts/agent-kit/self-install.sh" 2>/dev/null; then
  report PASS "69: bash -n scripts/agent-kit/self-install.sh"
else
  report FAIL "69: bash -n scripts/agent-kit/self-install.sh" "syntax error in repo script"
fi

# ---------------------------------------------------------------------------
# 70. ps1 structural-parity: four required markers must all be present in the
#     ps1 twin (grep only — does not require pwsh).
# ---------------------------------------------------------------------------
_ps1_requires=0; _ps1_dryrun=0; _ps1_claude=0; _ps1_twin=0
grep -qF '#Requires -Version 7.0'  "$REPO_ROOT/scripts/agent-kit/self-install.ps1" && _ps1_requires=1
grep -qF -- '--dry-run'             "$REPO_ROOT/scripts/agent-kit/self-install.ps1" && _ps1_dryrun=1
grep -qF '.claude/skills/'          "$REPO_ROOT/scripts/agent-kit/self-install.ps1" && _ps1_claude=1
grep -qF 'Twin: self-install.sh'    "$REPO_ROOT/scripts/agent-kit/self-install.ps1" && _ps1_twin=1
if [[ "$_ps1_requires$_ps1_dryrun$_ps1_claude$_ps1_twin" == "1111" ]]; then
  report PASS "70: ps1 structural-parity (#Requires/--dry-run/.claude/skills/Twin markers present)"
else
  report FAIL "70: ps1 structural-parity" \
    "requires=$_ps1_requires dryrun=$_ps1_dryrun claude=$_ps1_claude twin=$_ps1_twin"
fi

# ---------------------------------------------------------------------------
# 71. README (mandatory): repo README.md cites both installer script paths.
# ---------------------------------------------------------------------------
_readme_sh=0; _readme_ps1=0
grep -qF 'scripts/agent-kit/self-install.sh' "$REPO_ROOT/CONTRIBUTING.md" && _readme_sh=1
grep -qF 'self-install.ps1'        "$REPO_ROOT/CONTRIBUTING.md" && _readme_ps1=1
if [[ "$_readme_sh$_readme_ps1" == "11" ]]; then
  report PASS "71: README contains scripts/agent-kit/self-install.sh and self-install.ps1"
else
  report FAIL "71: README missing self-install script references" "sh=$_readme_sh ps1=$_readme_ps1"
fi

# ---------------------------------------------------------------------------
# 72. .gitignore dest-lines: exact lines .cursor/skills/ and .agents/skills/
#     must be present; no wholesale .cursor/ or .agents/ ignore line.
# ---------------------------------------------------------------------------
_gi_cursor_skills=0; _gi_agents_skills=0; _gi_cursor_whole=0; _gi_agents_whole=0
grep -qxF '.cursor/skills/' "$REPO_ROOT/.gitignore" && _gi_cursor_skills=1
grep -qxF '.agents/skills/' "$REPO_ROOT/.gitignore" && _gi_agents_skills=1
grep -qxF '.cursor/'        "$REPO_ROOT/.gitignore" && _gi_cursor_whole=1
grep -qxF '.agents/'        "$REPO_ROOT/.gitignore" && _gi_agents_whole=1
if [[ "$_gi_cursor_skills$_gi_agents_skills" == "11" && \
      "$_gi_cursor_whole$_gi_agents_whole" == "00" ]]; then
  report PASS "72: .gitignore has exact .cursor/skills/ and .agents/skills/ lines; no wholesale .cursor/ or .agents/"
else
  report FAIL "72: .gitignore dest-lines" \
    "cursor_skills=$_gi_cursor_skills agents_skills=$_gi_agents_skills cursor_whole=$_gi_cursor_whole agents_whole=$_gi_agents_whole"
fi

# ---------------------------------------------------------------------------
# 73. copy-mode: both harness dests (.claude/ and .cursor/) exist; SKILL.md
#     bytes match source for agent-kit; other and feature are NOT installed.
# ---------------------------------------------------------------------------
_cm_dir="$TMP/si-cm"
cp -a "$SI_FIX" "$_cm_dir"
_cm_exit=0
( cd "$TMP" && bash "$_cm_dir/scripts/agent-kit/self-install.sh" --no-emit ) 2>/dev/null || _cm_exit=$?
_cm_claude_setup="$_cm_dir/.claude/skills/agent-kit/SKILL.md"
_cm_cursor_setup="$_cm_dir/.cursor/skills/agent-kit/SKILL.md"
_cm_claude_other="$_cm_dir/.claude/skills/other/SKILL.md"
_cm_cursor_other="$_cm_dir/.cursor/skills/other/SKILL.md"
_cm_feature_present=0
{ [[ -d "$_cm_dir/.claude/skills/feature" ]] || [[ -d "$_cm_dir/.cursor/skills/feature" ]]; } \
  && _cm_feature_present=1
_cm_setup_ok=0; _cm_other_ok=0; _cm_bytes_ok=0
[[ -f "$_cm_claude_setup" && -f "$_cm_cursor_setup" ]] && _cm_setup_ok=1
[[ ! -e "$_cm_claude_other" && ! -e "$_cm_cursor_other" ]] && _cm_other_ok=1
if (( _cm_setup_ok == 1 )); then
  diff -q "$_cm_claude_setup" "$_cm_dir/skills/agent-kit/SKILL.md" >/dev/null 2>&1 && \
  diff -q "$_cm_cursor_setup" "$_cm_dir/skills/agent-kit/SKILL.md" >/dev/null 2>&1 && \
  _cm_bytes_ok=1
fi
if [[ "$_cm_exit" -eq 0 && "$_cm_setup_ok" -eq 1 && "$_cm_other_ok" -eq 1 && \
      "$_cm_bytes_ok" -eq 1 && "$_cm_feature_present" -eq 0 ]]; then
  report PASS "73: copy-mode: both dests exist, bytes match source, other and feature not installed"
else
  report FAIL "73: copy-mode" \
    "exit=$_cm_exit setup_ok=$_cm_setup_ok other_ok=$_cm_other_ok bytes_ok=$_cm_bytes_ok feature=$_cm_feature_present"
fi

# ---------------------------------------------------------------------------
# 74. overwrite: seed dest with different bytes, re-run, dest matches source.
# ---------------------------------------------------------------------------
_ow_dir="$TMP/si-ow"
cp -a "$SI_FIX" "$_ow_dir"
( cd "$TMP" && bash "$_ow_dir/scripts/agent-kit/self-install.sh" --no-emit ) 2>/dev/null
printf 'STALE_BYTES\n' > "$_ow_dir/.claude/skills/agent-kit/SKILL.md"
_ow_exit=0
( cd "$TMP" && bash "$_ow_dir/scripts/agent-kit/self-install.sh" --no-emit ) 2>/dev/null || _ow_exit=$?
_ow_bytes_match=0
diff -q "$_ow_dir/.claude/skills/agent-kit/SKILL.md" \
        "$_ow_dir/skills/agent-kit/SKILL.md" >/dev/null 2>&1 && _ow_bytes_match=1
if [[ "$_ow_exit" -eq 0 && "$_ow_bytes_match" -eq 1 ]]; then
  report PASS "74: overwrite: re-run replaces stale dest bytes with source"
else
  report FAIL "74: overwrite" "exit=$_ow_exit bytes_match=$_ow_bytes_match"
fi

# ---------------------------------------------------------------------------
# 75. --force: exit 0, same copy-mode dest layout (not rejected as unknown flag).
# ---------------------------------------------------------------------------
_fo_dir="$TMP/si-fo"
cp -a "$SI_FIX" "$_fo_dir"
_fo_exit=0
( cd "$TMP" && bash "$_fo_dir/scripts/agent-kit/self-install.sh" --force --no-emit ) 2>/dev/null || _fo_exit=$?
_fo_claude_ok=0; _fo_cursor_ok=0
[[ -f "$_fo_dir/.claude/skills/agent-kit/SKILL.md" && \
   ! -e "$_fo_dir/.claude/skills/other" ]] && _fo_claude_ok=1
[[ -f "$_fo_dir/.cursor/skills/agent-kit/SKILL.md" && \
   ! -e "$_fo_dir/.cursor/skills/other" ]] && _fo_cursor_ok=1
if [[ "$_fo_exit" -eq 0 && "$_fo_claude_ok" -eq 1 && "$_fo_cursor_ok" -eq 1 ]]; then
  report PASS "75: --force: exit 0, copy-mode dest layout identical to no-flags run"
else
  report FAIL "75: --force" "exit=$_fo_exit claude_ok=$_fo_claude_ok cursor_ok=$_fo_cursor_ok"
fi

# ---------------------------------------------------------------------------
# 76. dry-run: exit 0, dest skill trees not created.
# ---------------------------------------------------------------------------
_dr_dir="$TMP/si-dr"
cp -a "$SI_FIX" "$_dr_dir"
_dr_exit=0
( cd "$TMP" && bash "$_dr_dir/scripts/agent-kit/self-install.sh" --dry-run --no-emit ) 2>/dev/null || _dr_exit=$?
_dr_claude_absent=0; _dr_cursor_absent=0
[[ ! -d "$_dr_dir/.claude/skills" ]] && _dr_claude_absent=1
[[ ! -d "$_dr_dir/.cursor/skills" ]] && _dr_cursor_absent=1
if [[ "$_dr_exit" -eq 0 && "$_dr_claude_absent" -eq 1 && "$_dr_cursor_absent" -eq 1 ]]; then
  report PASS "76: dry-run: exit 0, no dest skill trees created"
else
  report FAIL "76: dry-run" "exit=$_dr_exit claude_absent=$_dr_claude_absent cursor_absent=$_dr_cursor_absent"
fi

# ---------------------------------------------------------------------------
# 77. --dry-run --symlink: exit 0; stdout names all three dest trees; nothing
#     written under .agents/, .claude/, or .cursor/skills/.
# ---------------------------------------------------------------------------
_ds_dir="$TMP/si-ds"
cp -a "$SI_FIX" "$_ds_dir"
_ds_exit=0
_ds_out="$TMP/si-ds-out.txt"
( cd "$TMP" && bash "$_ds_dir/scripts/agent-kit/self-install.sh" --dry-run --symlink --no-emit ) \
  >"$_ds_out" 2>/dev/null || _ds_exit=$?
_ds_agents_named=0; _ds_claude_named=0; _ds_cursor_named=0
grep -qF '.agents/skills/' "$_ds_out" && _ds_agents_named=1
grep -qF '.claude/skills/' "$_ds_out" && _ds_claude_named=1
grep -qF '.cursor/skills/' "$_ds_out" && _ds_cursor_named=1
_ds_nothing_created=0
[[ ! -d "$_ds_dir/.agents/skills" && \
   ! -d "$_ds_dir/.claude/skills" && \
   ! -d "$_ds_dir/.cursor/skills" ]] && _ds_nothing_created=1
if [[ "$_ds_exit" -eq 0 && \
      "$_ds_agents_named$_ds_claude_named$_ds_cursor_named" == "111" && \
      "$_ds_nothing_created" -eq 1 ]]; then
  report PASS "77: --dry-run --symlink: exit 0, stdout names all three dest trees, nothing written"
else
  report FAIL "77: --dry-run --symlink" \
    "exit=$_ds_exit agents=$_ds_agents_named claude=$_ds_claude_named cursor=$_ds_cursor_named created=$(( 1 - _ds_nothing_created ))"
fi

# ---------------------------------------------------------------------------
# 78. unknown flag: non-zero exit, stderr non-empty, dests unchanged.
# ---------------------------------------------------------------------------
_uf_dir="$TMP/si-uf"
cp -a "$SI_FIX" "$_uf_dir"
_uf_exit=0
_uf_stderr="$TMP/si-uf-err.txt"
( cd "$TMP" && bash "$_uf_dir/scripts/agent-kit/self-install.sh" --no-such-flag ) \
  2>"$_uf_stderr" && _uf_exit=0 || _uf_exit=$?
_uf_nonzero=0; _uf_stderr_ne=0; _uf_dests_unchanged=0
[[ "$_uf_exit" -ne 0 ]] && _uf_nonzero=1
[[ -s "$_uf_stderr" ]] && _uf_stderr_ne=1
[[ ! -d "$_uf_dir/.claude/skills" && ! -d "$_uf_dir/.cursor/skills" ]] && _uf_dests_unchanged=1
if [[ "$_uf_nonzero" -eq 1 && "$_uf_stderr_ne" -eq 1 && "$_uf_dests_unchanged" -eq 1 ]]; then
  report PASS "78: unknown flag: non-zero exit, stderr non-empty, dests unchanged"
else
  report FAIL "78: unknown flag" \
    "exit=$_uf_exit nonzero=$_uf_nonzero stderr_ne=$_uf_stderr_ne dests_unchanged=$_uf_dests_unchanged"
fi

# ---------------------------------------------------------------------------
# 79. empty skills dir: non-zero exit, no dest writes.
# ---------------------------------------------------------------------------
_es_dir="$TMP/si-es"
mkdir -p "$_es_dir/scripts/agent-kit" "$_es_dir/skills"
cp "$REPO_ROOT/scripts/agent-kit/self-install.sh" "$_es_dir/scripts/agent-kit/self-install.sh"
_es_exit=0
( cd "$TMP" && bash "$_es_dir/scripts/agent-kit/self-install.sh" ) 2>/dev/null && _es_exit=0 || _es_exit=$?
_es_nonzero=0; _es_no_dests=0
[[ "$_es_exit" -ne 0 ]] && _es_nonzero=1
[[ ! -d "$_es_dir/.claude" && ! -d "$_es_dir/.cursor" ]] && _es_no_dests=1
if [[ "$_es_nonzero" -eq 1 && "$_es_no_dests" -eq 1 ]]; then
  report PASS "79: empty skills: non-zero exit, no dest writes"
else
  report FAIL "79: empty skills" "exit=$_es_exit nonzero=$_es_nonzero no_dests=$_es_no_dests"
fi

# ---------------------------------------------------------------------------
# 80. sibling preservation: pre-create .claude/skills/keepme/SKILL.md, install,
#     keepme still present after install.
# ---------------------------------------------------------------------------
_kb_dir="$TMP/si-kb"
cp -a "$SI_FIX" "$_kb_dir"
mkdir -p "$_kb_dir/.claude/skills/keepme"
printf 'keepme\n' > "$_kb_dir/.claude/skills/keepme/SKILL.md"
_kb_exit=0
( cd "$TMP" && bash "$_kb_dir/scripts/agent-kit/self-install.sh" --no-emit ) 2>/dev/null || _kb_exit=$?
_kb_keepme=0
[[ -f "$_kb_dir/.claude/skills/keepme/SKILL.md" ]] && _kb_keepme=1
if [[ "$_kb_exit" -eq 0 && "$_kb_keepme" -eq 1 ]]; then
  report PASS "80: sibling preservation: keepme skill survives install"
else
  report FAIL "80: sibling preservation" "exit=$_kb_exit keepme=$_kb_keepme"
fi

# ---------------------------------------------------------------------------
# 81. rollback: pre-seed .claude/skills/agent-kit/SKILL.md with OLD bytes
#     (agent-kit is the only skill installed); make
#     .cursor a plain FILE so mkdir .cursor/skills fails AFTER .claude/skills/agent-kit
#     has been written; exit non-zero; the first-written dest must contain OLD
#     bytes (rollback restored the snapshot). Absent dest after the run = FAIL.
# ---------------------------------------------------------------------------
_rb_dir="$TMP/si-rb"
cp -a "$SI_FIX" "$_rb_dir"
mkdir -p "$_rb_dir/.claude/skills/agent-kit"
printf 'OLD_ROLLBACK_BYTES\n' > "$_rb_dir/.claude/skills/agent-kit/SKILL.md"
printf 'blocker\n' > "$_rb_dir/.cursor"   # .cursor is now a file, not a dir
_rb_exit=0
( cd "$TMP" && bash "$_rb_dir/scripts/agent-kit/self-install.sh" ) 2>/dev/null && _rb_exit=0 || _rb_exit=$?
_rb_nonzero=0; _rb_rollback_ok=0
[[ "$_rb_exit" -ne 0 ]] && _rb_nonzero=1
_rb_bytes="$(cat "$_rb_dir/.claude/skills/agent-kit/SKILL.md" 2>/dev/null)"
[[ "$_rb_bytes" == "OLD_ROLLBACK_BYTES" ]] && _rb_rollback_ok=1
[[ ! -f "$_rb_dir/.claude/skills/agent-kit/SKILL.md" ]] && _rb_rollback_ok=0  # absent dest = FAIL
# load-bearing proof: neuter _do_restore — predicate must FAIL on mutant
_rb_mut_dir="$TMP/si-rb-mut"
mkdir -p "$_rb_mut_dir/fix/scripts/agent-kit"
cp -a "$SI_FIX/." "$_rb_mut_dir/fix/"
mkdir -p "$_rb_mut_dir/fix/.claude/skills/agent-kit"
printf 'OLD_ROLLBACK_BYTES\n' > "$_rb_mut_dir/fix/.claude/skills/agent-kit/SKILL.md"
printf 'blocker\n' > "$_rb_mut_dir/fix/.cursor"
sed '/^_do_restore() {$/a\  return 0' \
    "$REPO_ROOT/scripts/agent-kit/self-install.sh" > "$_rb_mut_dir/fix/scripts/agent-kit/self-install.sh"
_rb_mut_exit=0
( cd "$TMP" && bash "$_rb_mut_dir/fix/scripts/agent-kit/self-install.sh" ) 2>/dev/null \
  && _rb_mut_exit=0 || _rb_mut_exit=$?
_rb_mut_bytes="$(cat "$_rb_mut_dir/fix/.claude/skills/agent-kit/SKILL.md" 2>/dev/null)"
_rb_load_ok=0
[[ "$_rb_mut_bytes" != "OLD_ROLLBACK_BYTES" && "$_rb_mut_exit" -ne 0 ]] && _rb_load_ok=1
if [[ "$_rb_nonzero" -eq 1 && "$_rb_rollback_ok" -eq 1 && "$_rb_load_ok" -eq 1 ]]; then
  report PASS "81: rollback: non-zero exit; .claude dest restored to pre-install (OLD) bytes"
else
  report FAIL "81: rollback" \
    "exit=$_rb_exit nonzero=$_rb_nonzero rollback_ok=$_rb_rollback_ok load_ok=$_rb_load_ok"
fi

# ---------------------------------------------------------------------------
# 82. --symlink: .agents/skills/<name> is a real directory; both harness dests
#     (.claude and .cursor) are symlinks. If OS cannot create symlinks, SKIP.
# ---------------------------------------------------------------------------
if ln -s /dev/null "$TMP/si-symlink-probe" 2>/dev/null; then
  rm -f "$TMP/si-symlink-probe"
  _sl_dir="$TMP/si-sl"
  cp -a "$SI_FIX" "$_sl_dir"
  _sl_exit=0
  ( cd "$TMP" && bash "$_sl_dir/scripts/agent-kit/self-install.sh" --symlink --no-emit ) 2>/dev/null || _sl_exit=$?
  _sl_agents_real=0; _sl_claude_link=0; _sl_cursor_link=0
  _sl_claude_tgt_ok=0; _sl_cursor_tgt_ok=0
  { [[ -d "$_sl_dir/.agents/skills/agent-kit" ]] && [[ ! -L "$_sl_dir/.agents/skills/agent-kit" ]]; } \
    && _sl_agents_real=1
  [[ -L "$_sl_dir/.claude/skills/agent-kit" ]] && _sl_claude_link=1
  [[ -L "$_sl_dir/.cursor/skills/agent-kit" ]] && _sl_cursor_link=1
  _sl_claude_tgt="$(readlink "$_sl_dir/.claude/skills/agent-kit" 2>/dev/null)"
  _sl_cursor_tgt="$(readlink "$_sl_dir/.cursor/skills/agent-kit" 2>/dev/null)"
  [[ "$_sl_claude_tgt" == "$_sl_dir/.agents/skills/agent-kit" ]] && _sl_claude_tgt_ok=1
  [[ "$_sl_cursor_tgt" == "$_sl_dir/.agents/skills/agent-kit" ]] && _sl_cursor_tgt_ok=1
  if [[ "$_sl_exit" -eq 0 && "$_sl_agents_real" -eq 1 && \
        "$_sl_claude_link" -eq 1 && "$_sl_cursor_link" -eq 1 && \
        "$_sl_claude_tgt_ok" -eq 1 && "$_sl_cursor_tgt_ok" -eq 1 ]]; then
    report PASS "82: --symlink: .agents/skills/agent-kit is real dir; .claude and .cursor dests are symlinks"
  else
    report FAIL "82: --symlink" \
      "exit=$_sl_exit agents_real=$_sl_agents_real claude_link=$_sl_claude_link cursor_link=$_sl_cursor_link claude_tgt_ok=$_sl_claude_tgt_ok cursor_tgt_ok=$_sl_cursor_tgt_ok"
  fi
else
  report SKIP "82: --symlink (OS cannot create symlinks)"
fi

# ---------------------------------------------------------------------------
# 83. mode-transition: --symlink then default copy-mode; harness dests must be
#     real directories (not symlinks) with bytes matching source.
# ---------------------------------------------------------------------------
_mt_dir="$TMP/si-mt"
cp -a "$SI_FIX" "$_mt_dir"
_mt_exit1=0; _mt_exit2=0
( cd "$TMP" && bash "$_mt_dir/scripts/agent-kit/self-install.sh" --symlink --no-emit ) 2>/dev/null || _mt_exit1=$?
( cd "$TMP" && bash "$_mt_dir/scripts/agent-kit/self-install.sh" --no-emit ) 2>/dev/null || _mt_exit2=$?
_mt_claude_real=0; _mt_cursor_real=0; _mt_bytes_ok=0
{ [[ -d "$_mt_dir/.claude/skills/agent-kit" ]] && [[ ! -L "$_mt_dir/.claude/skills/agent-kit" ]]; } \
  && _mt_claude_real=1
{ [[ -d "$_mt_dir/.cursor/skills/agent-kit" ]] && [[ ! -L "$_mt_dir/.cursor/skills/agent-kit" ]]; } \
  && _mt_cursor_real=1
diff -q "$_mt_dir/.claude/skills/agent-kit/SKILL.md" \
        "$_mt_dir/skills/agent-kit/SKILL.md" >/dev/null 2>&1 && _mt_bytes_ok=1
if [[ "$_mt_exit2" -eq 0 && "$_mt_claude_real" -eq 1 && \
      "$_mt_cursor_real" -eq 1 && "$_mt_bytes_ok" -eq 1 ]]; then
  report PASS "83: mode-transition: --symlink then copy-mode; harness dests are real dirs with correct bytes"
else
  report FAIL "83: mode-transition" \
    "exit1=$_mt_exit1 exit2=$_mt_exit2 claude_real=$_mt_claude_real cursor_real=$_mt_cursor_real bytes_ok=$_mt_bytes_ok"
fi

# ---------------------------------------------------------------------------
# 84. pwsh: parse repo scripts/agent-kit/self-install.ps1 via .NET parser (zero errors).
#     If pwsh is absent, SKIP.
# ---------------------------------------------------------------------------
if command -v pwsh &>/dev/null; then
  _pwsh_parse_ok=0
  _pwsh_parse_scr="$TMP/si-parse-test.ps1"
  cat > "$_pwsh_parse_scr" <<'EOPWSH'
$src = Get-Content -Raw -LiteralPath $args[0]
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$errors)
exit $errors.Count
EOPWSH
  pwsh -NoProfile -File "$_pwsh_parse_scr" "$REPO_ROOT/scripts/agent-kit/self-install.ps1" 2>/dev/null \
    && _pwsh_parse_ok=1
  if [[ "$_pwsh_parse_ok" -eq 1 ]]; then
    report PASS "84: pwsh parses scripts/agent-kit/self-install.ps1 with zero errors"
  else
    report FAIL "84: pwsh parses scripts/agent-kit/self-install.ps1 with zero errors" "parser reported errors"
  fi
else
  report SKIP "84: pwsh absent -- ps1 parse skipped"
fi

# ---------------------------------------------------------------------------
# 85. pwsh live copy-mode: run ps1 twin against a temp fixture; verify both
#     harness dests have the expected SKILL.md files. If pwsh is absent, SKIP.
# ---------------------------------------------------------------------------
if command -v pwsh &>/dev/null; then
  _pwsh_dir="$TMP/si-pwsh"
  cp -a "$SI_FIX" "$_pwsh_dir"
  _pwsh_exit=0
  ( cd "$TMP" && pwsh -NoProfile -File "$_pwsh_dir/scripts/agent-kit/self-install.ps1" --no-emit ) 2>/dev/null \
    || _pwsh_exit=$?
  _pwsh_claude_ok=0; _pwsh_cursor_ok=0
  [[ -f "$_pwsh_dir/.claude/skills/agent-kit/SKILL.md" && \
     ! -e "$_pwsh_dir/.claude/skills/other" ]] && _pwsh_claude_ok=1
  [[ -f "$_pwsh_dir/.cursor/skills/agent-kit/SKILL.md" && \
     ! -e "$_pwsh_dir/.cursor/skills/other" ]] && _pwsh_cursor_ok=1
  if [[ "$_pwsh_exit" -eq 0 && "$_pwsh_claude_ok" -eq 1 && "$_pwsh_cursor_ok" -eq 1 ]]; then
    report PASS "85: pwsh live copy-mode: ps1 twin installs agent-kit (only) to both harness dests"
  else
    report FAIL "85: pwsh live copy-mode" \
      "exit=$_pwsh_exit claude_ok=$_pwsh_claude_ok cursor_ok=$_pwsh_cursor_ok"
  fi
else
  report SKIP "85: pwsh absent -- ps1 live copy-mode skipped"
fi

# ---------------------------------------------------------------------------
# 86. checks B/D must ignore the self-install compiler copy at
#     .claude/skills/agent-kit/ (unresolved tokens there are required). SKIP if
#     .claude/checks.sh is absent (fresh clone, no /agent-kit). Mutation: a copy
#     with --exclude-dir=setup stripped must still be distinguishable from
#     the live script; the live tree must have tokens under that path so the
#     exclusion is load-bearing.
# ---------------------------------------------------------------------------
if [[ -f "$CHECKS_SH" ]]; then
  _b_exclude=0
  _d_prune=0
  grep -qF -- "--exclude-dir='agent-kit'" "$CHECKS_SH" && _b_exclude=1
  grep -qF ".claude/skills/agent-kit" "$CHECKS_SH" && grep -qF -- '-prune' "$CHECKS_SH" \
    && _d_prune=1
  _setup_has_tokens=0
  if grep -rqE '\{\{[A-Z_]+\}\}|<!-- (BOOTSTRAP|IF|ENDIF)' \
        "$REPO_ROOT/.claude/skills/agent-kit" 2>/dev/null; then
    _setup_has_tokens=1
  fi
  _t86="$TMP/checks_no_exclude.sh"
  cp "$CHECKS_SH" "$_t86"
  sed -i "s/ --exclude-dir='agent-kit'//" "$_t86"
  _mutant_lost_exclude=0
  grep -qF -- "--exclude-dir='agent-kit'" "$_t86" || _mutant_lost_exclude=1
  if [[ "$_b_exclude" -eq 1 && "$_d_prune" -eq 1 \
        && "$_setup_has_tokens" -eq 1 && "$_mutant_lost_exclude" -eq 1 ]]; then
    report PASS "86: checks B/D exclude .claude/skills/agent-kit/ compiler copy (load-bearing)"
  else
    report FAIL "86: checks B/D exclude compiler copy" \
      "b_exclude=$_b_exclude d_prune=$_d_prune tokens=$_setup_has_tokens mutant_stripped=$_mutant_lost_exclude"
  fi
else
  report SKIP "86: .claude/checks.sh absent -- compiler-copy exclusion skipped"
fi

# ===========================================================================
# Greenfield-setup contract assertions (100-114, no _loop/loop.sh required).
# Static structural greps against skills/agent-kit/SKILL.md,
# skills/agent-kit/templates/ORCHESTRATION.md, skills/agent-kit/SKILL.md metadata.version, and
# README.md -- lock the Step 2a greenfield gate, its GREENFIELD ONLY
# BOOTSTRAP template hook, and the dynamic Kit version / 1000-install claims. Mutations
# (108-110) run ONLY on copies under $TMP; the real repo files are read-only.
# ===========================================================================
ORCH_TPL="$REPO_ROOT/skills/agent-kit/templates/ORCHESTRATION.md"
VERSION_FILE="$REPO_ROOT/skills/agent-kit/SKILL.md"
README_MD="$REPO_ROOT/skills/agent-kit/README.md"
KIT_VERSION="$(kit_version "$VERSION_FILE")"

# ---------------------------------------------------------------------------
# 100. SKILL.md carries the Step 2a heading and the options.greenfield flag.
# ---------------------------------------------------------------------------
_100_heading=0; _100_flag=0
grep -qE -- '^## Step 2a — Greenfield gate$' "$SETUP_SKILL_MD" && _100_heading=1
grep -qF -- 'options.greenfield' "$SETUP_SKILL_MD" && _100_flag=1
if [[ "$_100_heading" -eq 1 && "$_100_flag" -eq 1 ]]; then
  report PASS "100: SKILL.md has the '## Step 2a — Greenfield gate' heading and 'options.greenfield'"
else
  report FAIL "100: SKILL.md Step 2a heading + options.greenfield" "heading=$_100_heading flag=$_100_flag"
fi

# ---------------------------------------------------------------------------
# 101. SKILL.md guide-then-confirm: create nothing until the tree is
#      explicitly confirmed.
# ---------------------------------------------------------------------------
_101_sentence=0
grep -qF -- 'create nothing until the user explicitly confirms that tree' "$SETUP_SKILL_MD" \
  && _101_sentence=1
if [[ "$_101_sentence" -eq 1 ]]; then
  report PASS "101: SKILL.md guide-then-confirm sentence present"
else
  report FAIL "101: SKILL.md guide-then-confirm sentence" "sentence=$_101_sentence"
fi

# ---------------------------------------------------------------------------
# 102. SKILL.md frozen trees: TypeScript/Node and Python are first-class,
#      plus a generic Other/src+tests fallback.
# ---------------------------------------------------------------------------
_102_ts=0; _102_py=0; _102_generic=0; _102_src=0; _102_tests=0
grep -qF -- 'TypeScript/Node' "$SETUP_SKILL_MD" && _102_ts=1
grep -qF -- '**Python**' "$SETUP_SKILL_MD" && _102_py=1
grep -qF -- 'Other / generic' "$SETUP_SKILL_MD" && _102_generic=1
grep -qF -- '`src/`' "$SETUP_SKILL_MD" && _102_src=1
grep -qF -- '`tests/`' "$SETUP_SKILL_MD" && _102_tests=1
if [[ "$_102_ts" -eq 1 && "$_102_py" -eq 1 && "$_102_generic" -eq 1 \
      && "$_102_src" -eq 1 && "$_102_tests" -eq 1 ]]; then
  report PASS "102: SKILL.md names TypeScript/Node and Python frozen trees plus a generic src//tests/ fallback"
else
  report FAIL "102: SKILL.md stack trees" \
    "ts=$_102_ts py=$_102_py generic=$_102_generic src=$_102_src tests=$_102_tests"
fi

# ---------------------------------------------------------------------------
# 103. SKILL.md 1000-install floor sentence, naming vercel-labs and
#      anthropics.
# ---------------------------------------------------------------------------
_103_sentence=0; _103_vercel=0; _103_anthropic=0
grep -qF -- 'Offer a skill only if its install count is 1000 or more.' "$SETUP_SKILL_MD" \
  && _103_sentence=1
grep -qF -- 'vercel-labs' "$SETUP_SKILL_MD" && _103_vercel=1
grep -qF -- 'anthropics' "$SETUP_SKILL_MD" && _103_anthropic=1
if [[ "$_103_sentence" -eq 1 && "$_103_vercel" -eq 1 && "$_103_anthropic" -eq 1 ]]; then
  report PASS "103: SKILL.md 1000-install floor sentence names vercel-labs and anthropics"
else
  report FAIL "103: SKILL.md 1000-install floor sentence" \
    "sentence=$_103_sentence vercel=$_103_vercel anthropic=$_103_anthropic"
fi

# ---------------------------------------------------------------------------
# 104. SKILL.md fail-open on missing npx/non-zero/no-network; the install
#      command has --skill and -y; no 'npx skills add' line contains ' -g'
#      (a prose prohibition elsewhere in Step 2a must not fail this check).
# ---------------------------------------------------------------------------
_104_failopen=0; _104_npxskills=0; _104_skillflag=0; _104_yflag=0; _104_no_g=1
_104_y_needs_skill=1
{ grep -qF -- 'Fail-open' "$SETUP_SKILL_MD" || grep -qiF -- 'do not abort' "$SETUP_SKILL_MD"; } \
  && _104_failopen=1
grep -qF -- 'npx skills' "$SETUP_SKILL_MD" && _104_npxskills=1
grep -qF -- '--skill' "$SETUP_SKILL_MD" && _104_skillflag=1
grep -qF -- ' -y' "$SETUP_SKILL_MD" && _104_yflag=1
while IFS= read -r _104_line; do
  [[ "$_104_line" == *' -g'* ]] && _104_no_g=0
  if [[ "$_104_line" == *' -y'* && "$_104_line" != *'--skill'* ]]; then
    _104_y_needs_skill=0
  fi
done < <(grep -F -- 'npx skills add' "$SETUP_SKILL_MD")
if [[ "$_104_failopen" -eq 1 && "$_104_npxskills" -eq 1 && "$_104_skillflag" -eq 1 \
      && "$_104_yflag" -eq 1 && "$_104_no_g" -eq 1 && "$_104_y_needs_skill" -eq 1 ]]; then
  report PASS "104: SKILL.md fail-open + install command carries --skill and -y (paired on the same 'npx skills add' line); no such line passes -g"
else
  report FAIL "104: SKILL.md fail-open/install-flags" \
    "failopen=$_104_failopen npxskills=$_104_npxskills skill=$_104_skillflag y=$_104_yflag no_g=$_104_no_g y_needs_skill=$_104_y_needs_skill"
fi

# ---------------------------------------------------------------------------
# 105. SKILL.md: non-sparse workspaces skip Step 2a entirely; the worked
#      negative example names skills/agent-kit/SKILL.md as not sparse.
# ---------------------------------------------------------------------------
_105_skip_rule=0; _105_named_not_sparse=0
grep -qF -- 'skip **entirely** `## Step 2a — Greenfield gate`' "$SETUP_SKILL_MD" \
  && _105_skip_rule=1
grep -qF -- 'including `skills/agent-kit/SKILL.md`' "$SETUP_SKILL_MD" && _105_named_not_sparse=1
if [[ "$_105_skip_rule" -eq 1 && "$_105_named_not_sparse" -eq 1 ]]; then
  report PASS "105: SKILL.md skips Step 2a for non-sparse workspaces; names skills/agent-kit/SKILL.md as a not-sparse worked example"
else
  report FAIL "105: SKILL.md not-sparse skip rule + worked example" \
    "skip_rule=$_105_skip_rule named_example=$_105_named_not_sparse"
fi

# ---------------------------------------------------------------------------
# 106. templates/ORCHESTRATION.md carries the BOOTSTRAP comment marker,
#      'GREENFIELD ONLY', and 'options.greenfield'.
# ---------------------------------------------------------------------------
_106_bootstrap=0; _106_greenfield_only=0; _106_flag=0
grep -qF -- '<!-- IF greenfield -->' "$ORCH_TPL" && _106_bootstrap=1
grep -qF -- 'GREENFIELD ONLY' "$ORCH_TPL" && _106_greenfield_only=1
grep -qF -- 'options.greenfield' "$ORCH_TPL" && _106_flag=1
if [[ "$_106_bootstrap" -eq 1 && "$_106_greenfield_only" -eq 1 && "$_106_flag" -eq 1 ]]; then
  report PASS "106: templates/ORCHESTRATION.md carries '<!-- IF greenfield -->', 'GREENFIELD ONLY', and 'options.greenfield'"
else
  report FAIL "106: templates/ORCHESTRATION.md IF greenfield/GREENFIELD ONLY/options.greenfield" \
    "if_greenfield=$_106_bootstrap greenfield_only=$_106_greenfield_only flag=$_106_flag"
fi

# ---------------------------------------------------------------------------
# 107. skills/agent-kit/SKILL.md metadata.version semver; README Kit version + TypeScript/Python/1000+;
#      instance VERSION copies and manifest kitVersion (SKIP when absent).
# ---------------------------------------------------------------------------
_107_version_exact=0
[[ "$KIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && _107_version_exact=1
_107_readme_version=0; _107_readme_ts=0; _107_readme_py=0; _107_readme_1000=0
_107_instance_ok=1; _107_manifest_ok=1
grep -qF -- "Kit version: **$KIT_VERSION**" "$README_MD" && _107_readme_version=1
grep -qF -- 'TypeScript' "$README_MD" && _107_readme_ts=1
grep -qF -- 'Python' "$README_MD" && _107_readme_py=1
grep -qF -- '1000+' "$README_MD" && _107_readme_1000=1
for _107_ivf in \
  "$REPO_ROOT/.claude/skills/agent-kit/SKILL.md" \
  "$REPO_ROOT/.cursor/skills/agent-kit/SKILL.md"; do
  _107_rel="${_107_ivf#"$REPO_ROOT"/}"
  if [[ ! -f "$_107_ivf" ]]; then
    report SKIP "107: $_107_rel absent"
    continue
  fi
  if [[ "$(kit_version "$_107_ivf")" != "$KIT_VERSION" ]]; then
    _107_instance_ok=0
  fi
done
if [[ ! -f "$MANIFEST_JSON" ]]; then
  report SKIP "107: orchestration-kit.manifest.json absent"
else
  _107_manifest_ver="$(grep -m1 '"kitVersion"' "$MANIFEST_JSON" 2>/dev/null | \
    sed -E 's/.*"kitVersion"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
  [[ "$_107_manifest_ver" == "$KIT_VERSION" ]] || _107_manifest_ok=0
fi
if [[ "$_107_version_exact" -eq 1 && "$_107_readme_version" -eq 1 && "$_107_readme_ts" -eq 1 \
      && "$_107_readme_py" -eq 1 && "$_107_readme_1000" -eq 1 \
      && "$_107_instance_ok" -eq 1 && "$_107_manifest_ok" -eq 1 ]]; then
  report PASS "107: skills/agent-kit/SKILL.md metadata.version is $KIT_VERSION; README + instance/manifest pins + TypeScript + Python + 1000"
else
  report FAIL "107: VERSION==$KIT_VERSION + README/instance/manifest claims" \
    "version=$_107_version_exact readme_version=$_107_readme_version ts=$_107_readme_ts py=$_107_readme_py 1000=$_107_readme_1000 instance=$_107_instance_ok manifest=$_107_manifest_ok"
fi

# ---------------------------------------------------------------------------
# 108. Mutation (SKILL.md copy, $TMP only): deleting the guide-then-confirm
#      sentence from a copy fails assertion-101's predicate; the real file
#      still passes.
# ---------------------------------------------------------------------------
_108_copy="$TMP/skill_no_confirm_sentence.md"
cp "$SETUP_SKILL_MD" "$_108_copy"
sed -i '/create nothing until the user explicitly confirms that tree/d' "$_108_copy"
_108_copy_fails=0; _108_real_passes=0
grep -qF -- 'create nothing until the user explicitly confirms that tree' "$_108_copy" \
  || _108_copy_fails=1
grep -qF -- 'create nothing until the user explicitly confirms that tree' "$SETUP_SKILL_MD" \
  && _108_real_passes=1
if [[ "$_108_copy_fails" -eq 1 && "$_108_real_passes" -eq 1 ]]; then
  report PASS "108: mutation -- stripping the guide-then-confirm sentence from a SKILL.md copy fails assertion-101's predicate; the real file still passes"
else
  report FAIL "108: mutation (guide-then-confirm sentence)" \
    "copy_fails=$_108_copy_fails real_passes=$_108_real_passes"
fi

# ---------------------------------------------------------------------------
# 109. Mutation (ORCHESTRATION.md template copy, $TMP only): stripping
#      'GREENFIELD ONLY' fails assertion-106's predicate; the real template
#      still passes.
# ---------------------------------------------------------------------------
_109_copy="$TMP/orchestration_no_greenfield_only.md"
cp "$ORCH_TPL" "$_109_copy"
sed -i 's/GREENFIELD ONLY//g' "$_109_copy"
_109_copy_fails=0; _109_real_passes=0
grep -qF -- 'GREENFIELD ONLY' "$_109_copy" || _109_copy_fails=1
grep -qF -- 'GREENFIELD ONLY' "$ORCH_TPL" && _109_real_passes=1
if [[ "$_109_copy_fails" -eq 1 && "$_109_real_passes" -eq 1 ]]; then
  report PASS "109: mutation -- stripping 'GREENFIELD ONLY' from an ORCHESTRATION.md template copy fails assertion-106's predicate; the real template still passes"
else
  report FAIL "109: mutation (GREENFIELD ONLY)" \
    "copy_fails=$_109_copy_fails real_passes=$_109_real_passes"
fi

# ---------------------------------------------------------------------------
# 110. Mutation ($TMP-only VERSION file): a file containing 0.16.0 fails the
#      ==$KIT_VERSION predicate; the real skills/agent-kit/SKILL.md metadata.version passes.
# ---------------------------------------------------------------------------
_110_bad="$TMP/VERSION_bad"
printf '0.16.0\n' > "$_110_bad"
_110_bad_fails=0; _110_real_passes=0
[[ "$(kit_version "$_110_bad")" == "$KIT_VERSION" ]] || _110_bad_fails=1
[[ "$(kit_version "$VERSION_FILE")" == "$KIT_VERSION" ]] && _110_real_passes=1
if [[ "$_110_bad_fails" -eq 1 && "$_110_real_passes" -eq 1 ]]; then
  report PASS "110: mutation -- a temp VERSION file containing 0.16.0 fails the ==$KIT_VERSION predicate; the real skills/agent-kit/SKILL.md metadata.version passes"
else
  report FAIL "110: mutation (VERSION 0.16.0)" \
    "bad_fails=$_110_bad_fails real_passes=$_110_real_passes"
fi

# ---------------------------------------------------------------------------
# 111. SKILL.md names all four greenfield inference-only test/setup tokens
#      and the '(not configured)' literal. Does not require the "14" site
#      count (a cycle-2 error).
# ---------------------------------------------------------------------------
_111_targeted=0; _111_full=0; _111_frameworks=0; _111_setup=0; _111_notconfigured=0
grep -qF -- 'TARGETED_TEST_COMMAND' "$SETUP_SKILL_MD" && _111_targeted=1
grep -qF -- 'FULL_TEST_COMMAND' "$SETUP_SKILL_MD" && _111_full=1
grep -qF -- 'TEST_FRAMEWORKS' "$SETUP_SKILL_MD" && _111_frameworks=1
grep -qF -- 'SETUP_COMMANDS' "$SETUP_SKILL_MD" && _111_setup=1
grep -qF -- '(not configured)' "$SETUP_SKILL_MD" && _111_notconfigured=1
if [[ "$_111_targeted" -eq 1 && "$_111_full" -eq 1 && "$_111_frameworks" -eq 1 \
      && "$_111_setup" -eq 1 && "$_111_notconfigured" -eq 1 ]]; then
  report PASS "111: SKILL.md names TARGETED_TEST_COMMAND, FULL_TEST_COMMAND, TEST_FRAMEWORKS, SETUP_COMMANDS dispositions and '(not configured)'"
else
  report FAIL "111: SKILL.md greenfield token dispositions" \
    "targeted=$_111_targeted full=$_111_full frameworks=$_111_frameworks setup=$_111_setup not_configured=$_111_notconfigured"
fi

# ---------------------------------------------------------------------------
# 112. SKILL.md evaluates the greenfield gate once per /agent-kit session.
# ---------------------------------------------------------------------------
_112_once_per=0
grep -qF -- 'once per' "$SETUP_SKILL_MD" && _112_once_per=1
if [[ "$_112_once_per" -eq 1 ]]; then
  report PASS "112: SKILL.md states the greenfield gate is evaluated 'once per' /agent-kit session"
else
  report FAIL "112: SKILL.md 'once per' session gate" "once_per=$_112_once_per"
fi

# Shared Step 2a section extract for assertions 113-114 (scoped so hits in
# other sections of SKILL.md cannot satisfy these two checks).
_step2a_section="$(awk '/^## Step 2a — Greenfield gate/{flag=1} /^## Step 2 —/{flag=0} flag' \
  "$SETUP_SKILL_MD")"

# ---------------------------------------------------------------------------
# 113. SKILL.md Step 2a section names the Step 2 hand-back as its resume
#      target.
# ---------------------------------------------------------------------------
_113_handback=0
grep -qE -- 'continues at Step 2|Step 2 — Inspect the repo' <<< "$_step2a_section" \
  && _113_handback=1
if [[ "$_113_handback" -eq 1 ]]; then
  report PASS "113: SKILL.md Step 2a section names the Step 2 hand-back as its resume target"
else
  report FAIL "113: SKILL.md Step 2a resume-target hand-back" "handback=$_113_handback"
fi

# ---------------------------------------------------------------------------
# 114. SKILL.md Step 2a never-overwrite: skip an existing confirmed path and
#      report the skip.
# ---------------------------------------------------------------------------
_114_skip=0; _114_overwrite=0
grep -qF -- 'skip' <<< "$_step2a_section" && _114_skip=1
grep -qF -- 'overwrite' <<< "$_step2a_section" && _114_overwrite=1
if [[ "$_114_skip" -eq 1 && "$_114_overwrite" -eq 1 ]]; then
  report PASS "114: SKILL.md Step 2a states never-overwrite: skip an existing confirmed path and report the skip"
else
  report FAIL "114: SKILL.md Step 2a never-overwrite rule" "skip=$_114_skip overwrite=$_114_overwrite"
fi

# ===========================================================================
# Step 2b contract assertions (125-135, no _loop/loop.sh required).
# Static structural greps against skills/agent-kit/SKILL.md, README.md,
# CHANGELOG.md, and docs/agent-kit/guide/getting-started.md — lock the Step 2b
# skill-suggestions contract and docs/version claims landed by tasks 01–02.
# Mutations (133) run ONLY on copies under $TMP; repo files are read-only.
# ===========================================================================
CHANGELOG_MD="$REPO_ROOT/skills/agent-kit/CHANGELOG.md"
GETTING_STARTED_MD="$REPO_ROOT/docs/agent-kit/guide/getting-started.md"

_step2b_section="$(awk '/^## Step 2b — Skill suggestions/{flag=1} /^## Step 3 —/{flag=0} flag' \
  "$SETUP_SKILL_MD")"
_step4_section="$(awk '/^## Step 4 —/{flag=1} /^## Step 5 —/{flag=0} flag' \
  "$SETUP_SKILL_MD")"
_upgrading_section="$(awk '/^## Upgrading/{flag=1} flag' "$SETUP_SKILL_MD")"

# ---------------------------------------------------------------------------
# 125. SKILL.md heading order: Step 2b exists exactly once between Step 2
#      and Step 3.
# ---------------------------------------------------------------------------
_125_count=0; _125_order=0
_125_count="$(grep -cE -- '^## Step 2b — Skill suggestions$' "$SETUP_SKILL_MD")"
_125_ln2="$(grep -nE -- '^## Step 2 — Inspect the repo$' "$SETUP_SKILL_MD" | head -1 | cut -d: -f1)"
_125_ln2b="$(grep -nE -- '^## Step 2b — Skill suggestions$' "$SETUP_SKILL_MD" | head -1 | cut -d: -f1)"
_125_ln3="$(grep -nE -- '^## Step 3 — Interview the user$' "$SETUP_SKILL_MD" | head -1 | cut -d: -f1)"
if [[ "$_125_count" -eq 1 && -n "$_125_ln2" && -n "$_125_ln2b" && -n "$_125_ln3" \
      && "$_125_ln2b" -gt "$_125_ln2" && "$_125_ln2b" -lt "$_125_ln3" ]]; then
  _125_order=1
fi
if [[ "$_125_count" -eq 1 && "$_125_order" -eq 1 ]]; then
  report PASS "125: SKILL.md Step 2b heading exists once between Step 2 and Step 3"
else
  report FAIL "125: SKILL.md Step 2b heading order" \
    "count=$_125_count order=$_125_order ln2=$_125_ln2 ln2b=$_125_ln2b ln3=$_125_ln3"
fi

# ---------------------------------------------------------------------------
# 126. Step 2b section: seven signal names, npx skills find, absent-signal
#      sentence.
# ---------------------------------------------------------------------------
_126_lang=0; _126_web=0; _126_test=0; _126_backend=0; _126_infra=0
_126_docs=0; _126_db=0; _126_find=0; _126_absent=0
grep -qF -- 'Language / runtime' <<< "$_step2b_section" && _126_lang=1
grep -qF -- 'Web UI present' <<< "$_step2b_section" && _126_web=1
grep -qF -- 'Test framework' <<< "$_step2b_section" && _126_test=1
grep -qF -- 'Backend / web framework' <<< "$_step2b_section" && _126_backend=1
grep -qF -- 'Infra / DevOps' <<< "$_step2b_section" && _126_infra=1
grep -qF -- 'Docs surfaces' <<< "$_step2b_section" && _126_docs=1
grep -qF -- 'Databases / ORMs' <<< "$_step2b_section" && _126_db=1
grep -qF -- 'npx skills find' <<< "$_step2b_section" && _126_find=1
grep -qF -- 'A signal that is absent produces no query.' <<< "$_step2b_section" \
  && _126_absent=1
if [[ "$_126_lang" -eq 1 && "$_126_web" -eq 1 && "$_126_test" -eq 1 \
      && "$_126_backend" -eq 1 && "$_126_infra" -eq 1 && "$_126_docs" -eq 1 \
      && "$_126_db" -eq 1 && "$_126_find" -eq 1 && "$_126_absent" -eq 1 ]]; then
  report PASS "126: Step 2b section names all seven signals, npx skills find, and the absent-signal sentence"
else
  report FAIL "126: Step 2b signal table" \
    "lang=$_126_lang web=$_126_web test=$_126_test backend=$_126_backend infra=$_126_infra docs=$_126_docs db=$_126_db find=$_126_find absent=$_126_absent"
fi

# ---------------------------------------------------------------------------
# 127. Step 2b: every project, once per, find-skills URL; Step 2a has no
#      npx skills add line (install moved to Step 2b).
# ---------------------------------------------------------------------------
_127_every=0; _127_once=0; _127_url=0; _127_2a_no_add=1
grep -qF -- 'every project' <<< "$_step2b_section" && _127_every=1
grep -qF -- 'once per' <<< "$_step2b_section" && _127_once=1
grep -qF -- 'https://www.skills.sh/vercel-labs/skills/find-skills' <<< "$_step2b_section" \
  && _127_url=1
grep -qF -- 'npx skills add' <<< "$_step2a_section" && _127_2a_no_add=0
if [[ "$_127_every" -eq 1 && "$_127_once" -eq 1 && "$_127_url" -eq 1 \
      && "$_127_2a_no_add" -eq 1 ]]; then
  report PASS "127: Step 2b carries every-project/once-per/find-skills URL; Step 2a has no npx skills add line"
else
  report FAIL "127: Step 2b scope + Step 2a install absence" \
    "every=$_127_every once=$_127_once url=$_127_url 2a_no_add=$_127_2a_no_add"
fi

# ---------------------------------------------------------------------------
# 128. Step 2b dedupe: four skill dirs and never-re-offer sentence.
# ---------------------------------------------------------------------------
_128_claude=0; _128_cursor=0; _128_agents=0; _128_github=0; _128_never=0
grep -qF -- '.claude/skills' <<< "$_step2b_section" && _128_claude=1
grep -qF -- '.cursor/skills' <<< "$_step2b_section" && _128_cursor=1
grep -qF -- '.agents/skills' <<< "$_step2b_section" && _128_agents=1
grep -qF -- '.github/skills' <<< "$_step2b_section" && _128_github=1
grep -qF -- 'Never re-offer a skill that is already installed.' <<< "$_step2b_section" \
  && _128_never=1
if [[ "$_128_claude" -eq 1 && "$_128_cursor" -eq 1 && "$_128_agents" -eq 1 \
      && "$_128_github" -eq 1 && "$_128_never" -eq 1 ]]; then
  report PASS "128: Step 2b names four skill dirs and the never-re-offer sentence"
else
  report FAIL "128: Step 2b dedupe dirs + never-re-offer" \
    "claude=$_128_claude cursor=$_128_cursor agents=$_128_agents github=$_128_github never=$_128_never"
fi

# ---------------------------------------------------------------------------
# 129. Step 2b cap + floor sentences; whole-file grep -cF equals 1 each.
# ---------------------------------------------------------------------------
_129_cap_in_2b=0; _129_floor_in_2b=0; _129_cap_count=0; _129_floor_count=0
grep -qF -- 'Present at most 8 candidates in total and at most 3 per signal, ranked by install count.' \
  <<< "$_step2b_section" && _129_cap_in_2b=1
grep -qF -- 'Offer a skill only if its install count is 1000 or more.' \
  <<< "$_step2b_section" && _129_floor_in_2b=1
_129_cap_count="$(grep -cF -- 'Present at most 8 candidates in total and at most 3 per signal, ranked by install count.' \
  "$SETUP_SKILL_MD")"
_129_floor_count="$(grep -cF -- 'Offer a skill only if its install count is 1000 or more.' \
  "$SETUP_SKILL_MD")"
if [[ "$_129_cap_in_2b" -eq 1 && "$_129_floor_in_2b" -eq 1 \
      && "$_129_cap_count" -eq 1 && "$_129_floor_count" -eq 1 ]]; then
  report PASS "129: Step 2b cap/floor sentences present once each in SKILL.md"
else
  report FAIL "129: Step 2b cap/floor uniqueness" \
    "cap_in_2b=$_129_cap_in_2b floor_in_2b=$_129_floor_in_2b cap_count=$_129_cap_count floor_count=$_129_floor_count"
fi

# ---------------------------------------------------------------------------
# 130. Whole-file install-syntax: no npx skills add line contains @;
#      Step 2b section contains Fail-open.
# ---------------------------------------------------------------------------
_130_no_at=1; _130_failopen=0
while IFS= read -r _130_line; do
  [[ "$_130_line" == *'@'* ]] && _130_no_at=0
done < <(grep -F -- 'npx skills add' "$SETUP_SKILL_MD")
grep -qF -- 'Fail-open' <<< "$_step2b_section" && _130_failopen=1
if [[ "$_130_no_at" -eq 1 && "$_130_failopen" -eq 1 ]]; then
  report PASS "130: no npx skills add line contains @; Step 2b carries Fail-open"
else
  report FAIL "130: install-syntax hygiene + Step 2b Fail-open" \
    "no_at=$_130_no_at failopen=$_130_failopen"
fi

# ---------------------------------------------------------------------------
# 131. Step 4 hand-off: domain-skill-rows, layer-skill-map, installed-count
#      sentence.
# ---------------------------------------------------------------------------
_131_domain=0; _131_layer=0; _131_installed=0
grep -qF -- 'domain-skill-rows' <<< "$_step4_section" && _131_domain=1
grep -qF -- 'layer-skill-map' <<< "$_step4_section" && _131_layer=1
grep -qF -- 'Only skills actually installed in this session or already present count as installed; printed fail-open commands do not.' \
  <<< "$_step4_section" && _131_installed=1
if [[ "$_131_domain" -eq 1 && "$_131_layer" -eq 1 && "$_131_installed" -eq 1 ]]; then
  report PASS "131: Step 4 section names domain-skill-rows, layer-skill-map, and the installed-count sentence"
else
  report FAIL "131: Step 4 bootstrap hand-off" \
    "domain=$_131_domain layer=$_131_layer installed=$_131_installed"
fi

# ---------------------------------------------------------------------------
# 132. Upgrading section: script-only --upgrade never runs Step 2b.
# ---------------------------------------------------------------------------
_132_upgrade=0
grep -qF -- 'A script-only `--upgrade` never runs Step 2b.' <<< "$_upgrading_section" \
  && _132_upgrade=1
if [[ "$_132_upgrade" -eq 1 ]]; then
  report PASS "132: Upgrading section states script-only --upgrade never runs Step 2b"
else
  report FAIL "132: Upgrading Step 2b skip rule" "upgrade=$_132_upgrade"
fi

# ---------------------------------------------------------------------------
# 133. Mutation (SKILL.md copy, $TMP only): deleting the Step 2b heading
#      from a copy fails assertion-125's predicate; the real file still passes.
# ---------------------------------------------------------------------------
_133_copy="$TMP/skill_no_step2b_heading.md"
cp "$SETUP_SKILL_MD" "$_133_copy"
sed -i '/^## Step 2b — Skill suggestions$/d' "$_133_copy"
_133_copy_fails=0; _133_real_passes=0
_133_copy_count="$(grep -cE -- '^## Step 2b — Skill suggestions$' "$_133_copy")"
_133_copy_ln2="$(grep -nE -- '^## Step 2 — Inspect the repo$' "$_133_copy" | head -1 | cut -d: -f1)"
_133_copy_ln2b="$(grep -nE -- '^## Step 2b — Skill suggestions$' "$_133_copy" | head -1 | cut -d: -f1)"
_133_copy_ln3="$(grep -nE -- '^## Step 3 — Interview the user$' "$_133_copy" | head -1 | cut -d: -f1)"
if [[ "$_133_copy_count" -ne 1 || -z "$_133_copy_ln2b" \
      || -z "$_133_copy_ln2" || -z "$_133_copy_ln3" \
      || "$_133_copy_ln2b" -le "$_133_copy_ln2" || "$_133_copy_ln2b" -ge "$_133_copy_ln3" ]]; then
  _133_copy_fails=1
fi
if [[ "$_125_count" -eq 1 && "$_125_order" -eq 1 ]]; then
  _133_real_passes=1
fi
if [[ "$_133_copy_fails" -eq 1 && "$_133_real_passes" -eq 1 ]]; then
  report PASS "133: mutation -- deleting Step 2b heading from a SKILL.md copy fails assertion-125's predicate; the real file still passes"
else
  report FAIL "133: mutation (Step 2b heading)" \
    "copy_fails=$_133_copy_fails real_passes=$_133_real_passes copy_count=$_133_copy_count"
fi

# ---------------------------------------------------------------------------
# 134. Docs/version: README + getting-started Step 2b headings; no stale
#      'Existing projects are unchanged'; CHANGELOG v$KIT_VERSION entry.
# ---------------------------------------------------------------------------
_134_readme_2b=0; _134_readme_stale=0; _134_gs_heading=0; _134_gs_stale=0
_134_changelog=0
grep -qF -- 'Skill suggestions (Step 2b)' "$README_MD" && _134_readme_2b=1
grep -qF -- 'Existing projects are unchanged' "$README_MD" && _134_readme_stale=1
grep -qE -- '^## Skill suggestions \(Step 2b\)' "$GETTING_STARTED_MD" && _134_gs_heading=1
grep -qF -- 'Existing projects are unchanged' "$GETTING_STARTED_MD" && _134_gs_stale=1
grep -qE -- "^## \\[$KIT_VERSION\\]" "$CHANGELOG_MD" && _134_changelog=1
if [[ "$_134_readme_2b" -eq 1 && "$_134_readme_stale" -eq 0 && "$_134_gs_heading" -eq 1 \
      && "$_134_gs_stale" -eq 0 && "$_134_changelog" -eq 1 ]]; then
  report PASS "134: README/getting-started Step 2b docs present; no stale unchanged-projects phrase; CHANGELOG has v$KIT_VERSION"
else
  report FAIL "134: docs/version claims" \
    "readme_2b=$_134_readme_2b readme_stale=$_134_readme_stale gs_heading=$_134_gs_heading gs_stale=$_134_gs_stale changelog=$_134_changelog"
fi

# ---------------------------------------------------------------------------
# 135. README/getting-started install hygiene: every npx skills add line
#      with -y also has --skill; none contains -g.
# ---------------------------------------------------------------------------
_135_readme_y_skill=1; _135_readme_no_g=1
_135_gs_y_skill=1; _135_gs_no_g=1
while IFS= read -r _135_line; do
  [[ "$_135_line" == *' -g'* ]] && _135_readme_no_g=0
  if [[ "$_135_line" == *' -y'* && "$_135_line" != *'--skill'* ]]; then
    _135_readme_y_skill=0
  fi
done < <(grep -F -- 'npx skills add' "$README_MD")
while IFS= read -r _135_line; do
  [[ "$_135_line" == *' -g'* ]] && _135_gs_no_g=0
  if [[ "$_135_line" == *' -y'* && "$_135_line" != *'--skill'* ]]; then
    _135_gs_y_skill=0
  fi
done < <(grep -F -- 'npx skills add' "$GETTING_STARTED_MD")
if [[ "$_135_readme_y_skill" -eq 1 && "$_135_readme_no_g" -eq 1 \
      && "$_135_gs_y_skill" -eq 1 && "$_135_gs_no_g" -eq 1 ]]; then
  report PASS "135: README/getting-started npx skills add lines pair -y with --skill and never pass -g"
else
  report FAIL "135: README/getting-started install hygiene" \
    "readme_y_skill=$_135_readme_y_skill readme_no_g=$_135_readme_no_g gs_y_skill=$_135_gs_y_skill gs_no_g=$_135_gs_no_g"
fi

# ===========================================================================
# Guard: remaining assertions require a self-install (_loop/loop.sh). On a
# fresh clone (or the canonical templates repo itself, pre-/agent-kit), that dir
# does not exist — skip the loop-instance assertions cleanly (or fail hard if
# the self-install block above already found failures).
# ===========================================================================
if [[ ! -f "$REPO_ROOT/_loop/loop.sh" ]]; then
  if (( fail_count > 0 )); then
    echo
    echo "=== loop-harness summary ==="
    echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
    echo "RESULT: $fail_count assertion(s) FAILED"
    exit 1
  fi
  echo "SKIP: remaining loop-instance assertions require _loop/loop.sh; run /agent-kit first"
  echo
  echo "=== loop-harness summary ==="
  echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
  echo "RESULT: all assertions passed"
  exit 0
fi

# ---------------------------------------------------------------------------
# Assertions 1-10: sequential state-machine scenario over one state file, chain
# of four models so index-advance (8) and chain-end (9) are distinguishable.
# ---------------------------------------------------------------------------
CHAIN="modelA,modelB,modelC,modelD"
S1="$TMP/scenario.json"

# 1. fresh-create -> CLOSED, chain seeded, currentModel=chain[0]
[[ -f "$S1" ]] && rm -f "$S1"
breaker_load "$S1" "$CHAIN"
state="$(_breaker_get "$S1" state)"; chain="$(_breaker_get "$S1" chain)"
model="$(_breaker_get "$S1" currentModel)"
if [[ "$state" == "CLOSED" && "$chain" == "$CHAIN" && "$model" == "modelA" ]]; then
  report PASS "1: fresh-create seeds CLOSED/chain/currentModel"
else
  report FAIL "1: fresh-create seeds CLOSED/chain/currentModel" "state=$state chain=$chain model=$model"
fi

# 2. CLOSED+success -> no-op (file byte-unchanged)
sum_before="$(sha256sum "$S1" | cut -d' ' -f1)"
breaker_record "$S1" 0 1000
sum_after="$(sha256sum "$S1" | cut -d' ' -f1)"
if [[ "$sum_before" == "$sum_after" ]]; then
  report PASS "2: CLOSED+success is a no-op (file byte-unchanged)"
else
  report FAIL "2: CLOSED+success is a no-op (file byte-unchanged)" "checksum changed"
fi

# 3. CLOSED+RL -> OPEN, index 1, model=chain[1], openedAt set, totalFallbacks=1
T0=1000000
breaker_record "$S1" 1 "$T0"
state="$(_breaker_get "$S1" state)"; idx="$(_breaker_get "$S1" fallbackIndex)"
model="$(_breaker_get "$S1" currentModel)"; opened="$(_breaker_get "$S1" openedAt)"
fb="$(_breaker_get "$S1" totalFallbacks)"
if [[ "$state" == "OPEN" && "$idx" == "1" && "$model" == "modelB" && "$opened" == "$T0" && "$fb" == "1" ]]; then
  report PASS "3: CLOSED+RL -> OPEN, index 1, modelB, openedAt, totalFallbacks=1"
else
  report FAIL "3: CLOSED+RL -> OPEN, index 1, modelB, openedAt, totalFallbacks=1" \
    "state=$state idx=$idx model=$model opened=$opened fb=$fb"
fi

# 4. OPEN, now<openedAt+600 -> should_skip echoes remaining, state still OPEN
remaining="$(breaker_should_skip "$S1" $((T0 + 100)))"
state="$(_breaker_get "$S1" state)"
if [[ "$remaining" == "500" && "$state" == "OPEN" ]]; then
  report PASS "4: OPEN + cooldown not elapsed -> echoes remaining, stays OPEN"
else
  report FAIL "4: OPEN + cooldown not elapsed -> echoes remaining, stays OPEN" "remaining=$remaining state=$state"
fi

# 5. clamp guard: now far BEFORE openedAt (backward clock skew) -> remaining
#    clamped to [0, cooldownSeconds]; state unaffected (still OPEN, openedAt
#    unchanged) since remaining>0 never transitions.
remaining="$(breaker_should_skip "$S1" $((T0 - 10000)))"
state="$(_breaker_get "$S1" state)"; opened="$(_breaker_get "$S1" openedAt)"
if [[ "$remaining" -ge 0 && "$remaining" -le 600 && "$remaining" == "600" \
      && "$state" == "OPEN" && "$opened" == "$T0" ]]; then
  report PASS "5: clamp guard on backward clock skew (remaining clamped to 600)"
else
  report FAIL "5: clamp guard on backward clock skew (remaining clamped to 600)" \
    "remaining=$remaining state=$state opened=$opened"
fi

# 6. OPEN, now>=openedAt+600 -> HALF-OPEN, successes=0
remaining="$(breaker_should_skip "$S1" $((T0 + 600)))"
state="$(_breaker_get "$S1" state)"; half="$(_breaker_get "$S1" halfOpenSuccesses)"
if [[ "$remaining" == "0" && "$state" == "HALF-OPEN" && "$half" == "0" ]]; then
  report PASS "6: OPEN + cooldown elapsed -> HALF-OPEN, successes=0"
else
  report FAIL "6: OPEN + cooldown elapsed -> HALF-OPEN, successes=0" "remaining=$remaining state=$state half=$half"
fi

# 7. HALF-OPEN+success x1 -> HALF-OPEN(1); x2 -> CLOSED, counters reset, totalRecoveries=1
breaker_record "$S1" 0 $((T0 + 601))
state="$(_breaker_get "$S1" state)"; half="$(_breaker_get "$S1" halfOpenSuccesses)"
if [[ "$state" == "HALF-OPEN" && "$half" == "1" ]]; then
  report PASS "7a: HALF-OPEN + 1st success -> HALF-OPEN(1)"
else
  report FAIL "7a: HALF-OPEN + 1st success -> HALF-OPEN(1)" "state=$state half=$half"
fi
breaker_record "$S1" 0 $((T0 + 602))
state="$(_breaker_get "$S1" state)"; half="$(_breaker_get "$S1" halfOpenSuccesses)"
opened="$(_breaker_get "$S1" openedAt)"; rec="$(_breaker_get "$S1" totalRecoveries)"
if [[ "$state" == "CLOSED" && "$half" == "0" && "$opened" == "0" && "$rec" == "1" ]]; then
  report PASS "7b: HALF-OPEN + 2nd success -> CLOSED, counters reset, totalRecoveries=1"
else
  report FAIL "7b: HALF-OPEN + 2nd success -> CLOSED, counters reset, totalRecoveries=1" \
    "state=$state half=$half opened=$opened rec=$rec"
fi

# Re-trip to get back to HALF-OPEN with a distinct index/model, so assertion 8
# (HALF-OPEN+RL) exercises a genuine mid-chain index-advance, not chain-end.
T1=2000000
breaker_record "$S1" 1 "$T1"   # CLOSED+RL -> OPEN, index 1->2, modelC, totalFallbacks=2
idx="$(_breaker_get "$S1" fallbackIndex)"; model="$(_breaker_get "$S1" currentModel)"
fb="$(_breaker_get "$S1" totalFallbacks)"
if [[ "$idx" == "2" && "$model" == "modelC" && "$fb" == "2" ]]; then
  report PASS "3b (re-trip): CLOSED+RL advances index 1->2 (modelC), totalFallbacks=2"
else
  report FAIL "3b (re-trip): CLOSED+RL advances index 1->2 (modelC), totalFallbacks=2" "idx=$idx model=$model fb=$fb"
fi
breaker_should_skip "$S1" $((T1 + 600)) >/dev/null   # -> HALF-OPEN

# 8. HALF-OPEN+RL -> OPEN again, index advances (2->3, modelC->modelD)
breaker_record "$S1" 1 $((T1 + 700))
state="$(_breaker_get "$S1" state)"; idx="$(_breaker_get "$S1" fallbackIndex)"
model="$(_breaker_get "$S1" currentModel)"; opened="$(_breaker_get "$S1" openedAt)"
if [[ "$state" == "OPEN" && "$idx" == "3" && "$model" == "modelD" && "$opened" == "$((T1 + 700))" ]]; then
  report PASS "8: HALF-OPEN+RL -> OPEN again, index advances (2->3, modelD)"
else
  report FAIL "8: HALF-OPEN+RL -> OPEN again, index advances (2->3, modelD)" \
    "state=$state idx=$idx model=$model opened=$opened"
fi

# 9. chain end: further trips -> currentModel="" (omit-pin), NO index overflow.
# Chain has 4 entries (indices 0-3); we are already at index 3 (the last).
breaker_should_skip "$S1" $((T1 + 700 + 600)) >/dev/null   # -> HALF-OPEN
breaker_record "$S1" 1 $((T1 + 1400))                       # HALF-OPEN+RL at chain end
state="$(_breaker_get "$S1" state)"; idx="$(_breaker_get "$S1" fallbackIndex)"
model="$(_breaker_get "$S1" currentModel)"
if [[ "$state" == "OPEN" && "$idx" == "3" && "$model" == "" ]]; then
  report PASS "9a: chain-end trip -> currentModel empty, index does not overflow (stays 3)"
else
  report FAIL "9a: chain-end trip -> currentModel empty, index does not overflow (stays 3)" \
    "state=$state idx=$idx model='$model'"
fi
# repeat once more to prove idempotence at chain end (no crash, no overflow)
breaker_should_skip "$S1" $((T1 + 1400 + 600)) >/dev/null
breaker_record "$S1" 1 $((T1 + 2000))
idx="$(_breaker_get "$S1" fallbackIndex)"; model="$(_breaker_get "$S1" currentModel)"
if [[ "$idx" == "3" && "$model" == "" ]]; then
  report PASS "9b: repeated chain-end trip stays idempotent (index still 3, model still empty)"
else
  report FAIL "9b: repeated chain-end trip stays idempotent (index still 3, model still empty)" "idx=$idx model='$model'"
fi

# 10. OPEN + record (defensive, bypassing should_skip) -> behaves as HALF-OPEN
#     input + warning line. State is OPEN from assertion 9b's last transition.
state_before="$(_breaker_get "$S1" state)"
half_before="$(_breaker_get "$S1" halfOpenSuccesses)"
stderr_out="$(breaker_record "$S1" 0 $((T1 + 2600)) 2>&1 >/dev/null)"
state="$(_breaker_get "$S1" state)"; half="$(_breaker_get "$S1" halfOpenSuccesses)"
if [[ "$state_before" == "OPEN" && "$stderr_out" == *"breaker_record called while OPEN"* \
      && "$state" == "HALF-OPEN" && "$half" == "$((half_before + 1))" ]]; then
  report PASS "10: OPEN + breaker_record (defensive) -> treated as HALF-OPEN + warning"
else
  report FAIL "10: OPEN + breaker_record (defensive) -> treated as HALF-OPEN + warning" \
    "state_before=$state_before stderr='$stderr_out' state=$state half=$half half_before=$half_before"
fi

# ---------------------------------------------------------------------------
# 11 (UPDATED, story-009 fail-safe inversion, task-03): corrupted JSON (not
# JSON-like at all -- no keys at all, so _breaker_valid_fields fails outright,
# no retry) -> the NEW contract is fail-SAFE to OPEN (never fresh CLOSED,
# which would have re-armed a full-rate retry silently). openedAt is set from
# the injected `now`; chain is seeded from the <chain> ARGUMENT (the garbage
# has no parseable chain key at all); currentModel is DERIVED as
# chain[fallbackIndex] (0) = modelA, never blindly re-pinned; exactly ONE
# stderr warning containing "failing SAFE to OPEN" (the new message text --
# "unparseable" is no longer part of it).
# ---------------------------------------------------------------------------
S11="$TMP/corrupted.json"
printf 'not json at all\njust garbage\n' > "$S11"
T11=9000000
stderr_file11="$TMP/11-stderr.txt"
breaker_load "$S11" "$CHAIN" "$T11" >/dev/null 2>"$stderr_file11"
state="$(_breaker_get "$S11" state)"; chain="$(_breaker_get "$S11" chain)"
model="$(_breaker_get "$S11" currentModel)"; opened="$(_breaker_get "$S11" openedAt)"
warn_lines11=$(wc -l < "$stderr_file11")
if [[ "$state" == "OPEN" && "$opened" == "$T11" && "$opened" -gt 0 && "$chain" == "$CHAIN" \
      && "$model" == "modelA" && "$warn_lines11" -eq 1 \
      && "$(grep -c "failing SAFE to OPEN" "$stderr_file11")" -eq 1 ]]; then
  report PASS "11: corrupted (non-JSON) state -> fail-safe OPEN, openedAt>0 (=$T11), chain seeded from argument, currentModel derived (modelA), ONE stderr warning ('failing SAFE to OPEN')"
else
  report FAIL "11: corrupted (non-JSON) state -> fail-safe OPEN, openedAt>0, chain seeded from argument, currentModel derived, ONE stderr warning" \
    "state=$state opened=$opened chain=$chain model=$model warn_lines=$warn_lines11 stderr='$(cat "$stderr_file11")'"
fi

# ---------------------------------------------------------------------------
# 11b (UPDATED, story-009 fail-safe inversion, task-03; carries forward the
# task-01 infinite-spin regression guard verbatim): a state file whose STATE
# VALUE carries a leading CR inside the quotes (e.g. "state": "\rCLOSED",) --
# the state enum comparison fails so _breaker_valid_fields is invalid for a
# reason OTHER than the terminator (no retry loop entered) -> the NEW
# contract is fail-SAFE to OPEN (never fresh CLOSED): openedAt set from the
# injected `now`; chain/fallbackIndex/currentModel are all PRESERVED here
# because those key lines parse fine in this fixture (only "state" itself is
# corrupted) -- chain stays $CHAIN, currentModel stays "modelA"; exactly ONE
# stderr warning containing "failing SAFE to OPEN"; still wrapped in
# `timeout 10` as the infinite-spin regression guard (unchanged from task-01).
# ---------------------------------------------------------------------------
S11B="$TMP/leading_cr.json"
{
  printf '{\n'
  printf '"state": "\rCLOSED",\n'
  printf '"chain": "%s",\n' "$CHAIN"
  printf '"fallbackIndex": 0,\n'
  printf '"currentModel": "modelA",\n'
  printf '"cooldownSeconds": 600,\n'
  printf '"openedAt": 0,\n'
  printf '"halfOpenSuccesses": 0,\n'
  printf '"totalFallbacks": 0,\n'
  printf '"totalRecoveries": 0\n'
  printf '}\n'
} > "$S11B"

T11B=9100000
stderr_file="$TMP/11b-stderr.txt"
timeout 10 bash -c "source '$BREAKER_SH'; breaker_load '$S11B' '$CHAIN' '$T11B'" 2>"$stderr_file"
rc=$?
warn_lines=$(wc -l < "$stderr_file")
state="$(_breaker_get "$S11B" state)"; chain="$(_breaker_get "$S11B" chain)"
model="$(_breaker_get "$S11B" currentModel)"; opened="$(_breaker_get "$S11B" openedAt)"
if [[ "$rc" -eq 0 && "$warn_lines" -eq 1 && "$(grep -c "failing SAFE to OPEN" "$stderr_file")" -eq 1 \
      && "$state" == "OPEN" && "$opened" == "$T11B" && "$chain" == "$CHAIN" && "$model" == "modelA" ]]; then
  report PASS "11b: leading-CR corrupted value -> fail-safe OPEN (openedAt=$T11B, chain/currentModel preserved) + ONE warning, terminates under timeout 10 (infinite-spin regression)"
else
  report FAIL "11b: leading-CR corrupted value -> fail-safe OPEN + ONE warning, terminates under timeout 10 (infinite-spin regression)" \
    "rc=$rc warn_lines=$warn_lines state=$state opened=$opened chain=$chain model=$model ($( [[ $rc -eq 124 ]] && echo 'TIMED OUT -- infinite spin regressed!'))"
fi

# ---------------------------------------------------------------------------
# 11c (BINDING carry-forward, task-01 judgment): a fully CRLF-normalized but
# otherwise VALID OPEN state file -> VALIDATES and is preserved (state stays
# OPEN), NOT reset. No stderr warning; file byte-unchanged by the load call.
# ---------------------------------------------------------------------------
S11C_LF="$TMP/valid_open_lf.json"
_breaker_write "$S11C_LF" OPEN "$CHAIN" 2 modelC 600 123456 0 1 0
S11C="$TMP/valid_open_crlf.json"
sed 's/$/\r/' "$S11C_LF" > "$S11C"   # normalize every line ending to CRLF

sum_before="$(sha256sum "$S11C" | cut -d' ' -f1)"
stderr_out="$(breaker_load "$S11C" "$CHAIN" 2>&1 >/dev/null)"
sum_after="$(sha256sum "$S11C" | cut -d' ' -f1)"
state="$(_breaker_get "$S11C" state)"
if [[ -z "$stderr_out" && "$state" == "OPEN" && "$sum_before" == "$sum_after" ]]; then
  report PASS "11c: CRLF-normalized VALID OPEN file validates and is preserved (not reset)"
else
  report FAIL "11c: CRLF-normalized VALID OPEN file validates and is preserved (not reset)" \
    "stderr='$stderr_out' state=$state checksum_changed=$([[ "$sum_before" != "$sum_after" ]] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# 12. empty chain -> tracked state, empty model, no crash (record with RL=1
# against a zero-length chain must not index out of bounds).
# ---------------------------------------------------------------------------
S12="$TMP/empty_chain.json"
breaker_load "$S12" ""
state="$(_breaker_get "$S12" state)"; chain="$(_breaker_get "$S12" chain)"
model="$(_breaker_get "$S12" currentModel)"
ok1=0
[[ "$state" == "CLOSED" && "$chain" == "" && "$model" == "" ]] && ok1=1
# no-crash exercise: rate-limit trip against an empty chain. Guarded via an
# if/else (never a bare `set +e`/`set -e` toggle -- errexit is not enabled in
# this script, and flipping it on by mistake would silently abort every
# subsequent assertion, including 15's non-zero-exit-by-design loop.sh run).
if breaker_record "$S12" 1 5000; then rec_rc=0; else rec_rc=$?; fi
state2="$(_breaker_get "$S12" state)"; idx2="$(_breaker_get "$S12" fallbackIndex)"
model2="$(_breaker_get "$S12" currentModel)"
if [[ "$ok1" -eq 1 && "$rec_rc" -eq 0 && "$state2" == "OPEN" && "$idx2" == "0" && "$model2" == "" ]]; then
  report PASS "12: empty chain -> tracked state, empty model, no crash on trip"
else
  report FAIL "12: empty chain -> tracked state, empty model, no crash on trip" \
    "state=$state chain='$chain' model='$model' rec_rc=$rec_rc state2=$state2 idx2=$idx2 model2='$model2'"
fi

# ---------------------------------------------------------------------------
# 13/14: detector -- the LIVE detect_rate_limit function extracted verbatim
# from canonical loop.sh (never a reimplementation), so these assertions test
# the real, perf-fixed (two-stage grep pipeline) detector.
# ---------------------------------------------------------------------------
detector_src="$(sed -n '/^detect_rate_limit() {/,/^}/p' "$LOOP_SH")"
if [[ -z "$detector_src" ]]; then
  report FAIL "13/14 setup: extract detect_rate_limit from canonical loop.sh" "function not found -- loop.sh structure changed?"
else
  eval "$detector_src"

  # 13. Detector positives -> match (exit 0)
  declare -a positives=(
    "HTTP 429 error"
    "Rate limit exceeded"
    "too many requests"
    "quota exceeded"
  )
  pos_ok=1
  for line in "${positives[@]}"; do
    if detect_rate_limit "$line"; then :; else pos_ok=0; report FAIL "13: detector positive" "'$line' did not match"; fi
  done
  ((pos_ok)) && report PASS "13: detector positives all match (HTTP 429 error / Rate limit exceeded / too many requests / quota exceeded)"

  # 14. Detector negatives (mandated) -> no match (exit 1), plus the mandated
  # multi-line negative proving line-orientation (never merges across lines).
  declare -a negatives=(
    "wrote 429 tokens"
    "sha 429abc0"
    "quota of work"
    "429 files changed"
  )
  neg_ok=1
  for line in "${negatives[@]}"; do
    if detect_rate_limit "$line"; then neg_ok=0; report FAIL "14: detector negative" "'$line' incorrectly matched"; fi
  done
  multiline=$'wrote 429 tokens\nerror: build failed'
  if detect_rate_limit "$multiline"; then
    neg_ok=0
    report FAIL "14: multi-line negative (line-orientation proof)" "'429' on one line + 'error' on another falsely matched"
  fi
  ((neg_ok)) && report PASS "14: detector negatives (mandated) all correctly non-matching, incl. multi-line line-orientation proof"
fi

# ---------------------------------------------------------------------------
# 13b (PHASE 5 REMEDIATION, audit-specified blocker): large-capture SIGPIPE
# regression. Under `set -o pipefail`, a `printf | grep -q` pipeline whose
# `grep -q` matches early and exits can SIGPIPE the still-writing producer on
# captures large enough to exceed the pipe buffer; pipefail then reports the
# pipeline's status as the PRODUCER's non-zero (SIGPIPE, 141) rather than the
# grep's own successful 0 -- silently flipping a real match into "no match".
# The fix (herestrings `<<<`, materialized via a temp file with no live
# producer process to SIGPIPE) is re-verified here: the LIVE detector is
# extracted (same $detector_src as 13/14, never a reimplementation) and run
# inside its OWN `bash -euo pipefail` subshell against a >=256KB capture with
# the rate-limit line FIRST -- must detect. A same-scale multi-line negative
# must still correctly report not-detected.
# ---------------------------------------------------------------------------
if [[ -z "$detector_src" ]]; then
  report FAIL "13b: large-capture SIGPIPE regression" "detect_rate_limit extraction failed (see 13/14 setup)"
else
  detect_script="$TMP/13b_detect.sh"
  {
    printf '%s\n' "$detector_src"
    printf '%s\n' 'output="$(cat "$1")"'
    printf '%s\n' 'if detect_rate_limit "$output"; then exit 0; else exit 1; fi'
  } > "$detect_script"

  # >=256KB capture, rate-limit line FIRST (matches the pinned pattern
  # directly), a large volume of filler after it.
  big_capture="$TMP/13b_big_capture.txt"
  {
    printf 'HTTP 429 rate limit exceeded -- please retry later\n'
    for _ in $(seq 1 6000); do
      printf 'filler filler filler filler filler line padding text here\n'
    done
  } > "$big_capture"
  big_size=$(wc -c < "$big_capture")

  if bash -euo pipefail "$detect_script" "$big_capture"; then big_detected=1; else big_detected=0; fi

  # Same-scale multi-line NEGATIVE: "429" recurs on thousands of lines (so the
  # inner grep|grep pipe streams a large volume), but no line ever carries a
  # keyword alongside it, and the lone "error" line at the end never shares a
  # line with "429" -- must still resolve to not-detected.
  big_negative="$TMP/13b_big_negative.txt"
  {
    printf 'wrote 429 tokens\n'
    for _ in $(seq 1 6000); do
      printf '429 noise filler filler filler filler line here\n'
    done
    printf 'error: build failed\n'
  } > "$big_negative"
  neg_size=$(wc -c < "$big_negative")

  if bash -euo pipefail "$detect_script" "$big_negative"; then big_neg_detected=1; else big_neg_detected=0; fi

  if [[ "$big_size" -ge 262144 && "$big_detected" -eq 1 && "$neg_size" -ge 262144 && "$big_neg_detected" -eq 0 ]]; then
    report PASS "13b: large-capture (>=256KB) SIGPIPE regression -- rate-limit-first capture detected (size=${big_size}B), large multi-line negative still not-detected (size=${neg_size}B)"
  else
    report FAIL "13b: large-capture (>=256KB) SIGPIPE regression" \
      "size=$big_size detected=$big_detected neg_size=$neg_size neg_detected=$big_neg_detected"
  fi
fi

# ---------------------------------------------------------------------------
# 13c (REMEDIATION ROUND 2, audit-specified): closes the residual stage-2
# gap flagged after 13b -- stage 2 used to be `grep '429' | grep -q keyword`
# (still a two-process pipe, still SIGPIPE-able under adversarial flooding
# even after 13b's stage-1 herestring fix). Stage 2 is now ONE grep with a
# bidirectional same-line alternation ('429.*(keyword)|(keyword).*429'), no
# inter-grep pipe at all. This mirrors the exact adversarial reproduction
# that previously false-negatived: a >=2MB capture whose EARLY line matches
# stage 2 ONLY (no rate-limit phrasing, so stage 1 can't short-circuit it),
# followed by thousands of "429"-bearing filler lines -- must still detect.
# ---------------------------------------------------------------------------
if [[ -z "$detector_src" ]]; then
  report FAIL "13c: stage-2 large-capture SIGPIPE regression" "detect_rate_limit extraction failed (see 13/14 setup)"
else
  # detect_script (built for 13b, same $detector_src) is reused as-is.
  big2_capture="$TMP/13c_big_capture.txt"
  {
    printf 'HTTP 429 error\n'   # stage-2-ONLY match: no "rate limit"/"too many requests"/"quota" phrasing
    for _ in $(seq 1 50000); do
      printf '429 noise filler filler filler filler line here\n'
    done
  } > "$big2_capture"
  big2_size=$(wc -c < "$big2_capture")

  if bash -euo pipefail "$detect_script" "$big2_capture"; then big2_detected=1; else big2_detected=0; fi

  if [[ "$big2_size" -ge 2097152 && "$big2_detected" -eq 1 ]]; then
    report PASS "13c: stage-2-only large-capture (>=2MB) SIGPIPE regression -- early stage-2-only match detected (size=${big2_size}B), no inter-grep pipe remains"
  else
    report FAIL "13c: stage-2-only large-capture (>=2MB) SIGPIPE regression" "size=$big2_size detected=$big2_detected"
  fi
fi

# ---------------------------------------------------------------------------
# 15. CB1 carve-out stub (SCAFFOLDING, goal-judge note 2): the RE-EMITTED
# instance _loop/loop.sh + _loop/breaker.sh (resolved tokens) copied alongside
# PROMPT.md into a throwaway git-init repo under this run's mktemp workdir. A
# stub CLI always prints a real rate-limit line. max-iterations=4,
# cooldownSeconds=0 via a pre-seeded state file (tiny/instant cooldown --
# fully deterministic, no real sleeps). Verifies the CB1-exempt log line
# appears and the run does NOT exit 2 after 3+ rate-limited passes.
# ---------------------------------------------------------------------------
if [[ ! -f "$INSTANCE_LOOP_SH" || ! -f "$INSTANCE_BREAKER_SH" ]]; then
  report FAIL "15: CB1 carve-out stub" "instance _loop/loop.sh or _loop/breaker.sh missing"
else
  CB1_DIR="$TMP/cb1-repo"
  rm -rf "$CB1_DIR"
  mkdir -p "$CB1_DIR/_loop" "$CB1_DIR/_goals"
  cp "$INSTANCE_LOOP_SH" "$CB1_DIR/_loop/loop.sh"
  cp "$INSTANCE_BREAKER_SH" "$CB1_DIR/_loop/breaker.sh"
  cp "$INSTANCE_PROMPT_MD" "$CB1_DIR/_loop/PROMPT.md"
  chmod +x "$CB1_DIR/_loop/loop.sh"

  cat > "$CB1_DIR/_loop/stub-cli.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Deterministic stub CLI for the CB1 carve-out scaffolding test: always prints
# a real rate-limit line (so the driver's detector fires every iteration) and
# never commits (so every pass is a no-progress pass).
echo "HTTP 429 rate limit exceeded -- please retry later"
exit 0
STUBEOF
  chmod +x "$CB1_DIR/_loop/stub-cli.sh"

  # Backlog required by the task-01 gate (missing/unreadable -> exit 5).
  # Two eligible stories provide 4 dispatch slots before attempts-exhaustion
  # so the loop reaches MAX_ITER=4 and exits 1 (not 0 "no eligible stories"):
  # STORY-CB1A gets 3 dispatches (attempts 0->1->2->3 = exhausted), then
  # STORY-CB1B gets dispatch 4 (MAX_ITER reached after reap -> exit 1).
  # Each dispatch is rate-limited -> CB1-exempt (no_progress counter never
  # increments), so the run proves CB1 never fires even with 4 exempt passes.
  cat > "$CB1_DIR/_goals/backlog.md" <<'BACKLOGEOF'
# backlog

## STORY-CB1A: rate-limit carve-out test story A
- priority: 1
- passes: false
- attempts: 0
- blocked: false

## STORY-CB1B: rate-limit carve-out test story B
- priority: 2
- passes: false
- attempts: 0
- blocked: false
BACKLOGEOF

  cat > "$CB1_DIR/_goals/breaker-state.json" <<STATEEOF
{
"state": "CLOSED",
"chain": "sonnet",
"fallbackIndex": 0,
"currentModel": "sonnet",
"cooldownSeconds": 0,
"openedAt": 0,
"halfOpenSuccesses": 0,
"totalFallbacks": 0,
"totalRecoveries": 0
}
STATEEOF

  (
    cd "$CB1_DIR" && \
    git init -q && \
    git config user.email test@example.com && \
    git config user.name "cb1-test" && \
    git add -A && \
    git commit -qm init
  )

  cb1_log="$TMP/cb1-run.log"
  (
    cd "$CB1_DIR" && \
    LOOP_CLI="$CB1_DIR/_loop/stub-cli.sh" ./_loop/loop.sh 4
  ) > "$cb1_log" 2>&1
  cb1_status=$?

  exempt_count=$(grep -c "rate-limited pass — CB1 exempt (breaker owns it)" "$cb1_log")
  if [[ "$exempt_count" -ge 3 && "$cb1_status" -ne 2 && "$cb1_status" -eq 1 ]]; then
    report PASS "15: CB1 carve-out stub -- $exempt_count exempt passes logged, exit=$cb1_status (not 2, breaker survives its own cooldown)"
  else
    report FAIL "15: CB1 carve-out stub" "exempt_count=$exempt_count status=$cb1_status (log: $cb1_log)"
    sed 's/^/    /' "$cb1_log" >&2
  fi
fi

# ---------------------------------------------------------------------------
# 16 (T2a regression, story-006 task 03): the LIVE sentinel-check line PLUS
# the SENTINEL='...' assignment, extracted VERBATIM from the RE-EMITTED
# instance _loop/loop.sh (never a reimplementation), wrapped in a minimal
# function. Mirrors 13b's shape: sentinel EARLY in a >=256KB capture, run
# under `bash -euo pipefail` -> must detect. The herestring form has no live
# producer process for a downstream grep match to SIGPIPE, closing the
# false-negative path the piped form (assertion 17) is still exposed to.
# ---------------------------------------------------------------------------
sentinel_line="$(grep -m1 '^SENTINEL=' "$INSTANCE_LOOP_SH" || true)"
sentinel_check_line="$(grep -m1 'grep -qF "\$SENTINEL" <<< "\$output"' "$INSTANCE_LOOP_SH" || true)"

if [[ -z "$sentinel_line" || -z "$sentinel_check_line" ]]; then
  report FAIL "16 setup: extract sentinel line + check line from instance loop.sh" \
    "sentinel_line='$sentinel_line' sentinel_check_line='$sentinel_check_line' -- instance re-emit missing or loop.sh structure changed?"
else
  t2a_script="$TMP/t2a_check.sh"
  cat > "$t2a_script" <<'SCRIPTEOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPTEOF
  printf '%s\n' "$sentinel_line" >> "$t2a_script"
  cat >> "$t2a_script" <<'SCRIPTEOF'
check_sentinel() {
  local output="$1"
SCRIPTEOF
  printf '  %s\n' "$sentinel_check_line" >> "$t2a_script"
  cat >> "$t2a_script" <<'SCRIPTEOF'
    return 0
  else
    return 1
  fi
}
output="$(cat "$1")"
if check_sentinel "$output"; then exit 0; else exit 1; fi
SCRIPTEOF

  # >=256KB capture, sentinel line FIRST, large filler volume after it (mirrors
  # 13b's shape: match up front, huge write still in flight behind it).
  t2a_capture="$TMP/t2a_big_capture.txt"
  {
    printf '<promise>COMPLETE</promise>\n'
    for _ in $(seq 1 4500); do
      printf 'filler filler filler filler filler line padding text here padding more text\n'
    done
  } > "$t2a_capture"
  t2a_size=$(wc -c < "$t2a_capture")

  if bash -euo pipefail "$t2a_script" "$t2a_capture"; then t2a_detected=1; else t2a_detected=0; fi

  if [[ "$t2a_size" -ge 262144 && "$t2a_detected" -eq 1 ]]; then
    report PASS "16: T2a regression -- LIVE-extracted herestring sentinel check detects sentinel early in >=256KB capture (size=${t2a_size}B) under bash -euo pipefail"
  else
    report FAIL "16: T2a regression" "size=$t2a_size detected=$t2a_detected"
  fi

  # -------------------------------------------------------------------------
  # 17 (T2a PRE-FIX CONTROL, story-006 task 03): the OLD piped form
  # (`printf '%s' "$output" | grep -qF "$SENTINEL"`) against the IDENTICAL
  # capture used in 16 must FALSE-NEGATIVE under pipefail -- the downstream
  # grep's early match SIGPIPEs the still-writing printf producer, and
  # pipefail then reports the pipeline's status as the producer's non-zero
  # (SIGPIPE/141), flipping a real match into "no match". story-006 task 01
  # already demonstrated this deterministically at 282027 bytes; this capture
  # is >=256KB so it is expected to reproduce here. If it unexpectedly PASSES
  # (detects) at this size, the capture is grown and the measured failing
  # size is recorded in the FAIL detail below.
  # -------------------------------------------------------------------------
  t2a_oldform_script="$TMP/t2a_oldform_check.sh"
  cat > "$t2a_oldform_script" <<'SCRIPTEOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPTEOF
  printf '%s\n' "$sentinel_line" >> "$t2a_oldform_script"
  cat >> "$t2a_oldform_script" <<'SCRIPTEOF'
output="$(cat "$1")"
if printf '%s' "$output" | grep -qF "$SENTINEL"; then
  exit 0
else
  exit 1
fi
SCRIPTEOF

  run_oldform() { # run_oldform <capture-file> -> sets old_detected 0|1
    local cap="$1"
    if bash -euo pipefail "$t2a_oldform_script" "$cap"; then old_detected=1; else old_detected=0; fi
  }

  run_oldform "$t2a_capture"
  control_size="$t2a_size"
  control_capture="$t2a_capture"
  grow_attempts=0
  # Growth loop (story-002 pattern: 131072->141): if the control unexpectedly
  # PASSES at this box's current size, double the filler volume and retry,
  # recording the measured size that finally reproduces the false-negative.
  while [[ "$old_detected" -eq 1 && "$grow_attempts" -lt 6 ]]; do
    grow_attempts=$((grow_attempts + 1))
    grown_capture="$TMP/t2a_big_capture_grown_${grow_attempts}.txt"
    {
      printf '<promise>COMPLETE</promise>\n'
      for _ in $(seq 1 $((4500 * (2 ** grow_attempts)))); do
        printf 'filler filler filler filler filler line padding text here padding more text\n'
      done
    } > "$grown_capture"
    control_capture="$grown_capture"
    control_size=$(wc -c < "$grown_capture")
    run_oldform "$control_capture"
  done

  if [[ "$old_detected" -eq 0 ]]; then
    if [[ "$grow_attempts" -eq 0 ]]; then
      report PASS "17: T2a PRE-FIX CONTROL -- old piped form ('printf | grep -qF') FALSE-NEGATIVES on the identical >=256KB sentinel-early capture (size=${control_size}B) that 16's herestring fix correctly detects"
    else
      report PASS "17: T2a PRE-FIX CONTROL -- old piped form FALSE-NEGATIVES after growing the capture ${grow_attempts} time(s); measured failing size=${control_size}B (256KB capture unexpectedly passed on this box)"
    fi
  else
    report FAIL "17: T2a PRE-FIX CONTROL" "old piped form still detected=1 after ${grow_attempts} growth attempt(s), final size=${control_size}B -- could not reproduce the false-negative on this box"
  fi
fi

# ---------------------------------------------------------------------------
# 18 (T1a, structural -- pwsh absent on this box; PRECISION FIX story-006
# task-03 judge): the RE-EMITTED instance _loop/loop.ps1 carries the
# Get-Command guard AND the exit 127 it triggers COUPLED within the same
# guard block -- a line-window match anchored at the Get-Command line, not
# two independent file-wide greps (which a decoy `exit 127` elsewhere in the
# file, with no guard of its own, could satisfy). Structural by construction
# -- never runtime-verified here.
# ---------------------------------------------------------------------------
t1a_check() { # t1a_check <file> -> 0 if Get-Command git + exit 127 are coupled within a 6-line window
  local f="$1" ln window
  [[ -f "$f" ]] || return 1
  ln="$(grep -n 'Get-Command git' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 5))p" "$f")"
  grep -qE 'exit 127' <<< "$window"
}
if t1a_check "$INSTANCE_LOOP_PS1"; then
  report PASS "18 (structural, coupled): T1a -- instance loop.ps1 carries Get-Command git + exit 127 within the SAME guard block (6-line window), not two independent file-wide greps; not runtime-verified, pwsh absent"
else
  report FAIL "18 (structural, coupled): T1a" "Get-Command guard and exit 127 not found coupled within a 6-line window in $INSTANCE_LOOP_PS1"
fi

# 18-mutation-proof: a copy carrying a decoy `exit 127` elsewhere in the file
# (not inside any Get-Command guard) must FAIL the coupled check even though
# the old two-independent-greps form would have PASSED it.
# FIX-CYCLE-2 (routed from task 04's escalation, seam inherited via the
# instance re-emit, not a defect introduced here): task 02's 126/127
# documentation clause puts a plain-text `exit 127` inside a COMMENT ahead of
# the real Get-Command guard, so the old FIRST-textual-hit neutralization
# below (`sed -i '0,/exit 127/{...}'`) silently neutralized the COMMENT's
# occurrence instead of the real guard's, leaving the real guard's own
# `exit 127` intact -- the decoy then satisfied the coupled check via the
# untouched real guard, and the mutation-proof FAILed. Fixed by anchoring the
# neutralization at the guard itself (content-anchored on 'Get-Command git',
# a small window forward), the same anchoring style already used by
# t1a_check/the assertion-23 row-scoped precedent -- this survives future
# line drift (e.g. more comment text landing above the guard) because it
# locates the guard by content, never by an absolute line number or a
# first-textual-hit assumption.
t18_decoy="$TMP/loop_decoy.ps1"
cp "$INSTANCE_LOOP_PS1" "$t18_decoy"
# neutralize the real guard's own exit 127 (content-anchored at the guard, not
# a first-textual-hit assumption) so only the decoy remains
guard_ln="$(grep -n 'Get-Command git' "$t18_decoy" | head -1 | cut -d: -f1)"
sed -i "${guard_ln},$((guard_ln + 5)){s/exit 127/exit 99/}" "$t18_decoy"
printf '\nexit 127  # decoy, unrelated to any git guard\n' >> "$t18_decoy"
if t1a_check "$t18_decoy"; then
  report FAIL "18-mutation-proof: decoy exit 127 (uncoupled) must FAIL the coupled check" "decoy copy incorrectly PASSED"
else
  report PASS "18-mutation-proof: decoy exit 127 (uncoupled, no guard) correctly FAILS the coupled check -- precision fix confirmed"
fi

# ---------------------------------------------------------------------------
# 19 (T1b, structural -- pwsh absent on this box): the RE-EMITTED instance
# _loop/loop.ps1 carries the NULL-ONLY coalescing guard (`$null -eq`) around
# the PROMPT.md -Raw read, guarding exactly the literal-null case (0-byte
# file) without coalescing whitespace-only content. Structural by
# construction -- never runtime-verified here.
# ---------------------------------------------------------------------------
if [[ -f "$INSTANCE_LOOP_PS1" ]] && grep -qE '\$null -eq \$raw' "$INSTANCE_LOOP_PS1"; then
  report PASS "19 (structural): T1b -- instance loop.ps1 carries the null-only guard (\$null -eq \$raw) around the PROMPT.md read; not runtime-verified, pwsh absent"
else
  report FAIL "19 (structural): T1b" "null-only guard (\$null -eq \$raw) not found in $INSTANCE_LOOP_PS1"
fi

# ---------------------------------------------------------------------------
# 20 (A1, task-02 coverage): cursor.md's loop row carries the literal per-OS
# invocation forms inline, matching the copilot/codex emitter cells, while
# keeping the "as in the Claude Code emitter" pointer.
# ---------------------------------------------------------------------------
if [[ -f "$ORCH_TPL" ]]; then
  _orch_loop_flat="$(tr -s '[:space:]' ' ' < "$ORCH_TPL")"
  if grep -qF '_loop/loop.sh [max-iterations]' <<< "$_orch_loop_flat" \
     && grep -qF 'pwsh _loop/loop.ps1 [MaxIterations]' <<< "$_orch_loop_flat"; then
    report PASS "20: A1 -- ORCHESTRATION.md carries literal bash + pwsh loop invocation forms"
  else
    report FAIL "20: A1" "literal invocation forms not found in $ORCH_TPL (whitespace-flattened grep)"
  fi
else
  report FAIL "20: A1" "ORCHESTRATION template missing"
fi

# ---------------------------------------------------------------------------
# 21 (A2, task-02 coverage): the Windows-gate clause is gone from
# skills/agent-kit/SKILL.md -- the checks-script guidance keys purely on
# adoption, not on "and the loop is enabled or Windows is a target
# platform". Whole-file, newline-folded grep (the clause could wrap across
# lines), expects a zero count.
# ---------------------------------------------------------------------------
a2_count="$(tr '\n' ' ' < "$SETUP_SKILL_MD" | grep -c 'Windows is a target platform')"
if [[ "$a2_count" -eq 0 ]]; then
  report PASS "21: A2 -- 'Windows is a target platform' gate clause absent from skills/agent-kit/SKILL.md (count=0)"
else
  report FAIL "21: A2" "gate clause still present, count=$a2_count"
fi

# ---------------------------------------------------------------------------
# 22 (A3, task-02 coverage): the seedFiles contract lands in BOTH Step 6's
# manifest schema example AND the Upgrading section of skills/agent-kit/SKILL.md.
# ---------------------------------------------------------------------------
step6_block="$(awk '/^## Step 6 —/{flag=1} /^## Upgrading/{flag=0} flag' "$SETUP_SKILL_MD")"
upgrading_block="$(awk '/^## Upgrading \//{flag=1} flag' "$SETUP_SKILL_MD")"
if grep -qF 'seedFiles' <<< "$step6_block" && grep -qF 'seedFiles' <<< "$upgrading_block"; then
  report PASS "22: A3 -- 'seedFiles' present in both Step 6's schema example and the Upgrading section"
else
  report FAIL "22: A3" "seedFiles missing from Step 6 block and/or Upgrading block"
fi

# ---------------------------------------------------------------------------
# 23 (A3, task-02 coverage; PRECISION FIX story-006 task-03 judge): the line
# naming "_goals/backlog.md" in each emitter caveat file must carry a
# "create if missing" note WITHIN THAT SAME LINE -- not a whole-file grep,
# which a decoy note elsewhere on an unrelated line (e.g. codex.md's AGENTS.md
# mention) could satisfy even if the backlog line itself lost its note.
# ---------------------------------------------------------------------------
a3_row_check() { # a3_row_check <file> -> 0 if the _goals/backlog.md row contains "create if missing"
  local f="$1" row
  [[ -f "$f" ]] || return 1
  row="$(grep -F '_goals/backlog.md' "$f" | head -1)"
  [[ -n "$row" ]] && grep -qF 'create if missing' <<< "$row"
}
a3_missing=()
for f in "$CLAUDE_CODE_MD" "$CODEX_MD" "$COPILOT_MD" "$CURSOR_MD"; do
  a3_row_check "$f" || a3_missing+=("$f")
done
if ((${#a3_missing[@]} == 0)); then
  report PASS "23 (row-scoped): A3 -- 'create if missing' present WITHIN the _goals/backlog.md line in all four emitter caveat files"
else
  report FAIL "23 (row-scoped): A3" "'create if missing' absent from the _goals/backlog.md line of: ${a3_missing[*]}"
fi

# 23-mutation-proof: a codex.md copy with the backlog-cell note deleted but
# the unrelated :12 AGENTS.md decoy note left intact must FAIL the row-scoped
# check (the old whole-file grep tolerated exactly this case).
t23_decoy="$TMP/codex_decoy.md"
cp "$CODEX_MD" "$t23_decoy"
backlog_ln="$(grep -nF '_goals/backlog.md' "$t23_decoy" | head -1 | cut -d: -f1)"
sed -i "${backlog_ln}s/ (create if missing; never overwrite)//" "$t23_decoy"
if grep -qF 'create if missing' "$t23_decoy" && a3_row_check "$t23_decoy"; then
  report FAIL "23-mutation-proof: codex.md :12 decoy (AGENTS.md note intact, backlog-cell note removed) must FAIL the row-scoped check" "decoy copy incorrectly PASSED"
elif grep -qF 'create if missing' "$t23_decoy" && ! a3_row_check "$t23_decoy"; then
  report PASS "23-mutation-proof: codex.md :12 decoy correctly FAILS the row-scoped check (whole-file grep would have wrongly passed via the AGENTS.md note) -- precision fix confirmed"
else
  report FAIL "23-mutation-proof" "decoy setup broken -- 'create if missing' unexpectedly absent entirely from $t23_decoy"
fi

# ---------------------------------------------------------------------------
# 24 (story-007, check J mutation -- NEGATIVE): a manifest COPY with one
# managed (non-seed, non-self) entry's hash corrupted, run through the REAL
# .claude/checks.sh via the CHECKS_MANIFEST override (a hard feature of
# check J -- no function extraction needed) -- must FAIL and name the path.
# ---------------------------------------------------------------------------
j_neg_manifest="$TMP/j_negative_manifest.json"
j_target_path=".claude/agents/evaluator.md"
python3 - "$MANIFEST_JSON" "$j_neg_manifest" "$j_target_path" <<'PY'
import json, sys
manifest_path, out_path, target = sys.argv[1:4]
with open(manifest_path) as f:
    data = json.load(f)
h = data["files"][target]
data["files"][target] = ("0" if h[0] != "0" else "1") + h[1:]
with open(out_path, "w") as f:
    json.dump(data, f, indent=2)
PY
j_neg_out="$TMP/j_neg_out.txt"
j_neg_err="$TMP/j_neg_err.txt"
CHECKS_MANIFEST="$j_neg_manifest" "$CHECKS_SH" > "$j_neg_out" 2> "$j_neg_err"
if grep -qE '^FAIL  J: manifest hash join' "$j_neg_out" \
   && grep -qF "$j_target_path" "$j_neg_err"; then
  report PASS "24: check J mutation (NEGATIVE) -- corrupted managed hash for $j_target_path FAILS and names the path"
else
  report FAIL "24: check J mutation (NEGATIVE)" "expected FAIL naming $j_target_path; stdout/stderr did not match"
fi

# ---------------------------------------------------------------------------
# 25 (story-007, check J mutation -- POSITIVE): an INTERNALLY-CONSISTENT
# manifest copy -- every managed (non-seed) entry's hash recomputed against
# the CURRENT working tree first (so this proves the seed join itself, not
# story-induced drift), _goals/backlog.md seed-only (absent from manifest
# `files`, present in `seedFiles`), the seed file exists on disk, and
# a tests/agent-kit/checks.sh entry injected at a STALE hash (emit never lists
# the checks script, so the entry is added here to exercise "self, excluded";
# a stale value proves the self entry is skipped rather than hash-checked) --
# must PASS with the J line present and the self-excluded line on stdout.
# ---------------------------------------------------------------------------
j_pos_manifest="$TMP/j_positive_manifest.json"
python3 - "$REPO_ROOT" "$MANIFEST_JSON" "$j_pos_manifest" <<'PY'
import hashlib, json, os, sys
repo_root, manifest_path, out_path = sys.argv[1:4]
with open(manifest_path) as f:
    data = json.load(f)
seed = set(data.get("seedFiles", []))
for path in list(data["files"].keys()):
    if path in seed:
        continue  # keep the seed's existing recorded value (drift tolerated)
    with open(os.path.join(repo_root, path), "rb") as fh:
        data["files"][path] = hashlib.sha256(fh.read()).hexdigest()
data["files"]["tests/agent-kit/checks.sh"] = "0" * 64
with open(out_path, "w") as f:
    json.dump(data, f, indent=2)
PY
j_pos_out="$TMP/j_pos_out.txt"
j_pos_err="$TMP/j_pos_err.txt"
CHECKS_MANIFEST="$j_pos_manifest" "$CHECKS_SH" > "$j_pos_out" 2> "$j_pos_err"
if grep -qE '^PASS  J: manifest hash join' "$j_pos_out" \
   && jq -e '.files|has("_goals/backlog.md")|not' "$REPO_ROOT/orchestration-kit.manifest.json" \
   && jq -e '.seedFiles|index("_goals/backlog.md")!=null' "$REPO_ROOT/orchestration-kit.manifest.json" \
   && [[ -f "$REPO_ROOT/_goals/backlog.md" ]] \
   && grep -qF 'J: self, excluded -- tests/agent-kit/checks.sh' "$j_pos_out"; then
  report PASS "25: check J mutation (POSITIVE) -- manifest PASSES; backlog seed-only (not in files); seed exists; self excluded line present"
else
  report FAIL "25: check J mutation (POSITIVE)" "expected PASS J + seed-only backlog manifest shape + seed file + self excluded line"
fi

# ---------------------------------------------------------------------------
# 26 (story-007, check K mutation -- NEGATIVE + POSITIVE): check K's own
# five-field grep set (writes/reads/depends_on/owner/rewrite_semantics,
# anchored at column 0, expected count exactly 1) run verbatim against a
# task-template COPY with one field deleted -- must fail; against the
# current canonical template -- must pass. No CHECKS_MANIFEST-style override
# exists for the task-template path, so this replicates check K's exact grep
# logic against the copy's path (CHECKS-style), per the task-03 spec.
# ---------------------------------------------------------------------------
k_check() { # k_check <task-template-path> -> prints missing field names (empty = all present)
  local f="$1" field n bad=()
  for field in '^writes:' '^reads:' '^depends_on:' '^owner:' '^rewrite_semantics:'; do
    n="$(grep -cE "$field" "$f")"
    [[ "$n" -ne 1 ]] && bad+=("$field:$n")
  done
  printf '%s\n' "${bad[@]}"
}
k_copy_missing_owner="$TMP/task_missing_owner.md"
grep -v '^owner:' "$TASK_TPL" > "$k_copy_missing_owner"
k_neg_result="$(k_check "$k_copy_missing_owner")"
k_pos_result="$(k_check "$TASK_TPL")"
if [[ -n "$k_neg_result" && -z "$k_pos_result" ]]; then
  report PASS "26: check K mutation -- task-template copy missing 'owner:' FAILS ($k_neg_result), current canonical template PASSES"
else
  report FAIL "26: check K mutation" "neg_result='$k_neg_result' pos_result='$k_pos_result' (expected neg non-empty, pos empty)"
fi

# ---------------------------------------------------------------------------
# 27 (story-007, task-02 clause tripwire): the normative literal
# 'bracket-literal placeholder values' (declared constant, goal pin) is
# present in the canonical goal-criteria template's Ownership contract
# section -- a PRESENCE check (grep -q), never a count.
# ---------------------------------------------------------------------------
if grep -qF 'bracket-literal placeholder values' "$CRITERIA_TPL"; then
  report PASS "27: task-02 clause tripwire -- 'bracket-literal placeholder values' present in canonical goal-criteria"
else
  report FAIL "27: task-02 clause tripwire" "'bracket-literal placeholder values' not found in $CRITERIA_TPL"
fi

# ---------------------------------------------------------------------------
# 28 (story-007, addendum 2 / TMPDIR characterization): the same
# LIVE-extracted herestring sentinel check as assertion 16, run with TMPDIR
# pointed at a directory that exists but is NOT writable (0555), against the
# identical >=256KB sentinel-early capture. OBSERVED ONCE on this box (bash
# 5.1.16): bash's here-string implementation silently falls back to its
# default temp directory (verified via strace: it does NOT attempt to write
# under the unwritable TMPDIR; no error surfaces) -- exit 0 (sentinel still
# detected), empty stderr. This is the FROZEN expected value: a future
# bash/loop change that alters this fallback behavior (e.g. a hard failure,
# or -- the disposition case that matters -- a silent false negative where
# the sentinel goes undetected with no error) flips this assertion.
#
# DISPOSITION: no false-negative was found on this box -- unwritable TMPDIR
# does not affect the sentinel check's correctness (silent, safe fallback to
# the platform default temp dir). Per the task-03 spec, only a DISCOVERED
# false-negative routes to the STORY-009 backlog addendum item (c); since
# none was discovered here, no further routing is needed this cycle.
# ---------------------------------------------------------------------------
if [[ -z "$sentinel_line" || -z "$sentinel_check_line" ]]; then
  report FAIL "28: TMPDIR characterization" "sentinel extraction failed upstream (see assertion 16 setup)"
else
  ro_tmpdir="$TMP/readonly_tmpdir"
  mkdir -p "$ro_tmpdir"
  chmod 555 "$ro_tmpdir"

  tmpdir_out="$TMP/tmpdir_stdout.txt"
  tmpdir_err="$TMP/tmpdir_stderr.txt"
  TMPDIR="$ro_tmpdir" bash -euo pipefail "$t2a_script" "$t2a_capture" > "$tmpdir_out" 2> "$tmpdir_err"
  tmpdir_rc=$?
  tmpdir_err_content="$(cat "$tmpdir_err")"

  # FROZEN expected value (observed once on this box): exit 0, empty stderr.
  frozen_expected_rc=0
  frozen_expected_err=""

  if [[ "$tmpdir_rc" -eq "$frozen_expected_rc" && "$tmpdir_err_content" == "$frozen_expected_err" ]]; then
    report PASS "28: TMPDIR characterization -- unwritable TMPDIR (0555) frozen behavior confirmed: exit=$tmpdir_rc, stderr empty, sentinel still detected (bash silently falls back to its default temp dir; no false negative found -- STORY-009 addendum item (c) not triggered)"
  else
    report FAIL "28: TMPDIR characterization -- frozen behavior REGRESSED" \
      "expected exit=$frozen_expected_rc/stderr='' got exit=$tmpdir_rc/stderr='$tmpdir_err_content' -- if this now shows exit implying not-found with sentinel actually present, this is the silent false-negative that files under the STORY-009 backlog addendum item (c)"
  fi

  chmod 755 "$ro_tmpdir" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 29 (NEW, story-009 task-03 hardening): torn-file retry/fail-safe. A valid
# OPEN state (chain "modelA,modelB", fallbackIndex 1, currentModel modelB) has
# EXACTLY its final `}` line deleted -- all nine keys stay intact, only the
# terminator is missing (the ONLY shape that reaches the terminator-only
# retry branch, per the goal pin). The file never heals on its own, so all
# 3 retries (3x~50ms backoff) exhaust and fall through to fail-safe OPEN:
# openedAt is set from the injected `now` (NOT preserved from the pre-tear
# file); chain/fallbackIndex/currentModel are all PRESERVED (their key lines
# parse fine). Elapsed time is loosely checked >= ~100ms to prove the retry
# loop actually ran (contrasts with 30's ~0ms immediate path).
# ---------------------------------------------------------------------------
S29_valid="$TMP/torn_valid.json"
_breaker_write "$S29_valid" OPEN "modelA,modelB" 1 modelB 600 555000 0 1 0
S29="$TMP/torn.json"
cp "$S29_valid" "$S29"
sed -i '$d' "$S29"   # delete EXACTLY the final `}` line

T29=20000000
stderr_file29="$TMP/29-stderr.txt"
start_ns=$(date +%s%N)
breaker_load "$S29" "$CHAIN" "$T29" 2>"$stderr_file29"
end_ns=$(date +%s%N)
elapsed_ms29=$(( (end_ns - start_ns) / 1000000 ))

state="$(_breaker_get "$S29" state)"; chain="$(_breaker_get "$S29" chain)"
idx="$(_breaker_get "$S29" fallbackIndex)"; model="$(_breaker_get "$S29" currentModel)"
opened="$(_breaker_get "$S29" openedAt)"
warn_lines29=$(wc -l < "$stderr_file29")
if [[ "$state" == "OPEN" && "$opened" == "$T29" && "$chain" == "modelA,modelB" \
      && "$idx" == "1" && "$model" == "modelB" && "$elapsed_ms29" -ge 100 \
      && "$warn_lines29" -eq 1 ]]; then
  report PASS "29: torn-file (final \`}\` line deleted, nine keys intact) -> after ~3 retries seeds fail-safe OPEN (openedAt=$T29), preserved chain/fallbackIndex/currentModel (=modelB), elapsed=${elapsed_ms29}ms (>=100ms loose bound proves retries ran)"
else
  report FAIL "29: torn-file (final \`}\` line deleted, nine keys intact) -> after ~3 retries seeds fail-safe OPEN, preserved chain/fallbackIndex/currentModel" \
    "state=$state opened=$opened chain=$chain idx=$idx model=$model elapsed_ms=$elapsed_ms29 warn_lines=$warn_lines29"
fi

# ---------------------------------------------------------------------------
# 30 (NEW, story-009 task-03 hardening; "the common real tear"): key-dropping
# truncation. A writer process killed almost immediately after opening the
# file leaves only `{` and the state line on disk -- chain and every field
# after it, INCLUDING chain itself, never made it out. _breaker_valid_fields
# fails OUTRIGHT (multiple required keys absent, not merely the terminator),
# so breaker_load takes the IMMEDIATE fail-safe path with NO retry sleep at
# all (elapsed checked < 100ms -- fix-cycle-1: loosened from <50ms, which had
# only 1.7x margin under CPU saturation [worst observed 29ms]; 100ms still
# sits far under the retry path's hard 150ms sleep floor [3x50ms], so
# discrimination from 29's >=100ms is fully preserved). Because the chain key
# itself never made it to disk, chain is seeded
# from the <chain> ARGUMENT (not preserved), and currentModel is DERIVED as
# chain[0] = modelA.
# ---------------------------------------------------------------------------
S30_valid="$TMP/trunc_valid.json"
_breaker_write "$S30_valid" OPEN "modelA,modelB" 1 modelB 600 555000 0 1 0
S30="$TMP/trunc.json"
head -n 2 "$S30_valid" > "$S30"   # only `{` and the state line survive

T30=21000000
stderr_file30="$TMP/30-stderr.txt"
start_ns=$(date +%s%N)
breaker_load "$S30" "$CHAIN" "$T30" 2>"$stderr_file30"
end_ns=$(date +%s%N)
elapsed_ms30=$(( (end_ns - start_ns) / 1000000 ))

state="$(_breaker_get "$S30" state)"; chain="$(_breaker_get "$S30" chain)"
model="$(_breaker_get "$S30" currentModel)"; opened="$(_breaker_get "$S30" openedAt)"
warn_lines30=$(wc -l < "$stderr_file30")
if [[ "$state" == "OPEN" && "$opened" == "$T30" && "$chain" == "$CHAIN" && "$model" == "modelA" \
      && "$elapsed_ms30" -lt 100 && "$warn_lines30" -eq 1 \
      && "$(grep -c "failing SAFE to OPEN" "$stderr_file30")" -eq 1 ]]; then
  report PASS "30: key-dropping truncation (chain + trailing keys missing) -> IMMEDIATE fail-safe OPEN, chain seeded from argument, currentModel derived (modelA), NO retry (elapsed=${elapsed_ms30}ms < 100ms)"
else
  report FAIL "30: key-dropping truncation (chain + trailing keys missing) -> IMMEDIATE fail-safe OPEN, chain seeded from argument, NO retry" \
    "state=$state chain=$chain model=$model opened=$opened elapsed_ms=$elapsed_ms30 warn_lines=$warn_lines30"
fi

# ---------------------------------------------------------------------------
# 31 (NEW, story-009 task-03 hardening; FIX-CYCLE-1 REWORK -- deterministic,
# no wall-clock dependence): retry-RECOVERY. The file is torn exactly as in
# 29 (final `}` deleted). Fix-cycle-1 instrumented proof: the goal pin's
# `sleep 0.03` background-restore recipe is NOT "generous" in practice -- the
# INITIAL `_breaker_valid` check inside breaker_load (9 greps + 6
# `_breaker_get` forks) alone costs ~30ms on this box, so a 0.03s background
# restore can land INSIDE that initial check's own window and heal the file
# before the retry loop is ever entered at all -- coin-flip-at-best coverage
# of the actual retry branch (judge-measured: retry-block deletion still
# passed 5/8 runs; the exact retry-never-recovers defect passed 2/4). Fixed
# by shadowing `sleep` for this assertion's scope ONLY: a bash function named
# `sleep` shadows the external command for anything executing in THIS shell
# -- including breaker_load's own bare `sleep 0.05` call inside its retry
# loop, since breaker_load runs in-process here (no subshell). The shadow
# performs the atomic restore (goal-judge's atomic recipe: `cp` to a
# `.restore.$$` sibling, then `mv -f` onto the live path -- a bare `cp` onto
# the live path would reproduce the very race under test) on its FIRST
# invocation and increments a counter, then delegates to the real `sleep` via
# `command sleep`. Because the restore can now ONLY happen inside a `sleep`
# call, and `sleep` can only be called from INSIDE the retry loop, the retry
# loop is GUARANTEED to run at least once before recovery -- zero wall-clock
# race, zero flakiness. `retry_sleep_calls31 >= 1` is asserted IN ADDITION TO
# (not instead of) the existing checksum/openedAt-unchanged/no-warning
# proofs, so this assertion now proves the retry loop itself ran and itself
# recovered mid-loop, not merely that some code path left the state healed.
# The shadow is `unset -f` immediately after use so it cannot leak into any
# later assertion.
# ---------------------------------------------------------------------------
S31_valid="$TMP/recovery_valid.json"
_breaker_write "$S31_valid" OPEN "modelA,modelB" 1 modelB 600 777000 0 1 0
valid_sum31="$(sha256sum "$S31_valid" | cut -d' ' -f1)"

S31="$TMP/recovery.json"
cp "$S31_valid" "$S31"
sed -i '$d' "$S31"   # tear: delete EXACTLY the final `}` line

retry_sleep_calls31=0
sleep() { # shadow, scoped to this assertion only -- unset immediately below
  retry_sleep_calls31=$((retry_sleep_calls31 + 1))
  if [[ "$retry_sleep_calls31" -eq 1 ]]; then
    cp "$S31_valid" "$S31.restore.$$"
    mv -f "$S31.restore.$$" "$S31"
  fi
  command sleep "$@"
}

T31=22000000
stderr_file31="$TMP/31-stderr.txt"
breaker_load "$S31" "$CHAIN" "$T31" 2>"$stderr_file31"
unset -f sleep   # restore the real `sleep` immediately -- no leakage downstream

sum_after31="$(sha256sum "$S31" | cut -d' ' -f1)"
warn_lines31=$(wc -l < "$stderr_file31")
state="$(_breaker_get "$S31" state)"; model="$(_breaker_get "$S31" currentModel)"
opened="$(_breaker_get "$S31" openedAt)"
if [[ "$sum_after31" == "$valid_sum31" && "$warn_lines31" -eq 0 && "$opened" == "777000" \
      && "$retry_sleep_calls31" -ge 1 ]]; then
  report PASS "31: retry-RECOVERY (deterministic, shadowed-sleep) -- torn file restored ATOMICALLY on the retry loop's FIRST sleep(0.05) invocation (retry_sleep_calls=$retry_sleep_calls31, proving the retry branch itself ran -- not merely the initial validity check) -> restored state preserved (checksum == valid source, state=$state, currentModel=$model, openedAt UNCHANGED=$opened -- itself proof the fail-safe path did not fire), NO stderr warning, NO fail-safe reseed"
else
  report FAIL "31: retry-RECOVERY (deterministic, shadowed-sleep)" \
    "sum_match=$([[ "$sum_after31" == "$valid_sum31" ]] && echo yes || echo no) state=$state model=$model opened=$opened stderr='$(cat "$stderr_file31")' warn_lines=$warn_lines31 retry_sleep_calls=$retry_sleep_calls31"
fi

# ---------------------------------------------------------------------------
# 32 (NEW, story-009 task-03 hardening): atomic write. Behavioral half: after
# a real breaker_record transition (CLOSED+RL -> OPEN, which writes), no
# `*.tmp.*` sibling of the state file remains and the resulting file still
# parses (_breaker_valid). Structural half: the canonical breaker.sh source
# itself is grepped -- _breaker_write's schema block redirects to `"$tmp"`,
# never a bare `> "$file"` (the pre-story non-atomic truncate-then-write this
# story closed).
# ---------------------------------------------------------------------------
S32="$TMP/atomic.json"
S32_dir="$(dirname "$S32")"; S32_base="$(basename "$S32")"
breaker_load "$S32" "$CHAIN" 30000000
tmp_before32=$(find "$S32_dir" -maxdepth 1 -name "${S32_base}.tmp.*" 2>/dev/null | wc -l)
breaker_record "$S32" 1 30000100
tmp_after32=$(find "$S32_dir" -maxdepth 1 -name "${S32_base}.tmp.*" 2>/dev/null | wc -l)
parses_ok32=0
_breaker_valid "$S32" && parses_ok32=1

write_func_body="$(sed -n '/^_breaker_write() {/,/^}/p' "$BREAKER_SH")"
structural_ok32=0
if grep -qF '} > "$tmp"' <<< "$write_func_body" && ! grep -qE '> "\$file"' <<< "$write_func_body"; then
  structural_ok32=1
fi

if [[ "$tmp_before32" -eq 0 && "$tmp_after32" -eq 0 && "$parses_ok32" -eq 1 && "$structural_ok32" -eq 1 ]]; then
  report PASS "32: atomic write -- no *.tmp.* sibling remains after breaker_record's OPEN transition (state still parses), and _breaker_write's source redirects the schema block to \"\$tmp\" (mv -f onto the target) with no stray '> \"\$file\"' bare redirect remaining"
else
  report FAIL "32: atomic write" "tmp_before=$tmp_before32 tmp_after=$tmp_after32 parses_ok=$parses_ok32 structural_ok=$structural_ok32"
fi

# ---------------------------------------------------------------------------
# 33 (NEW, story-009 task-03, routed addendum item a): 126/127 contract-clause
# parity. Extracts the appended 126/127 clause from BOTH canonical loop
# twins' exit-code contract blocks (marker-normalized: leading `# ` comment
# markers stripped before compare, since the twins otherwise differ in
# comment-marker convention on other lines) and requires the clause text be
# byte-identical, plus that both extracted blocks literally mention "126"
# and "127".
# ---------------------------------------------------------------------------
extract_126127_clause() { # extract_126127_clause <file>
  awk '/^# 126\/127 \(shell-propagated edge cases/{flag=1} flag{print} /\(the 126 case is Unix-host-only\)\.$/{if (flag) exit}' "$1"
}
clause_sh33="$(extract_126127_clause "$LOOP_SH")"
clause_ps133="$(extract_126127_clause "$LOOP_PS1")"
norm_sh33="$(sed 's/^# \{0,1\}//' <<< "$clause_sh33")"
norm_ps133="$(sed 's/^# \{0,1\}//' <<< "$clause_ps133")"

if [[ -z "$clause_sh33" || -z "$clause_ps133" ]]; then
  report FAIL "33 setup: extract 126/127 clause from canonical loop twins" \
    "clause_sh empty=$([[ -z "$clause_sh33" ]] && echo yes || echo no) clause_ps1 empty=$([[ -z "$clause_ps133" ]] && echo yes || echo no)"
elif [[ "$norm_sh33" == "$norm_ps133" && "$norm_sh33" == *"126"* && "$norm_sh33" == *"127"* \
        && "$norm_ps133" == *"126"* && "$norm_ps133" == *"127"* ]]; then
  report PASS "33: 126/127 contract-clause parity -- canonical loop.sh + loop.ps1 exit-code contract blocks carry a byte-identical (marker-normalized) appended clause, both mentioning 126 and 127"
else
  report FAIL "33: 126/127 contract-clause parity" "clause_sh='$clause_sh33' clause_ps1='$clause_ps133'"
fi

# ---------------------------------------------------------------------------
# 34 (NEW, story-009 task-03, cycle-1 MAJOR-3 / Check-G-parity-guard
# deviation landing site; FIX-CYCLE-1: t34_move_check re-scoped): ps1
# mechanics structural guard. The canonical breaker.ps1 is grepped for three
# mechanics, block-scoped per the assertion-18 coupling precedent (a
# line-window anchored at the relevant function/message, not independent
# file-wide greps a decoy could satisfy):
#   - ::Move( with the overwrite argument ($true), inside the
#     Write-BreakerState function body (fix-cycle-1: a file-wide grep was
#     mutation-proven decoy-satisfiable -- breaker.ps1:138 is a COMMENT
#     containing this exact literal; deleting the real :171 call left the
#     old check green, so it is now anchored at `function Write-BreakerState`
#     the same way the other two sub-checks below are already anchored);
#   - the terminator condition (-eq '}') inside Test-BreakerTerminatorOk;
#   - the fail-safe OPEN branch: the "failing SAFE to OPEN" warning coupled
#     (within a few lines) to the New-BreakerFailsafeOpen call, and that
#     function's own body in turn coupled to -State 'OPEN'.
# ---------------------------------------------------------------------------
t34_move_check() {
  local f="$1" ln window
  ln="$(grep -n 'function Write-BreakerState' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 35))p" "$f")"
  grep -qF '::Move($tmp, $Path, $true)' <<< "$window"
}
t34_term_check() {
  local f="$1" ln window
  ln="$(grep -n 'function Test-BreakerTerminatorOk' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 15))p" "$f")"
  grep -qE -- "-eq '\}'" <<< "$window"
}
t34_failsafe_msg_check() {
  local f="$1" ln window
  ln="$(grep -n 'failing SAFE to OPEN' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 5))p" "$f")"
  grep -qF 'New-BreakerFailsafeOpen' <<< "$window"
}
t34_failsafe_state_check() {
  local f="$1" ln window
  ln="$(grep -n 'function New-BreakerFailsafeOpen' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 30))p" "$f")"
  grep -qE -- "-State 'OPEN'" <<< "$window"
}
if t34_move_check "$BREAKER_PS1" && t34_term_check "$BREAKER_PS1" \
   && t34_failsafe_msg_check "$BREAKER_PS1" && t34_failsafe_state_check "$BREAKER_PS1"; then
  report PASS "34: ps1 mechanics structural guard -- canonical breaker.ps1 carries ::Move( with the overwrite arg (\$true), the terminator condition (-eq '}') inside Test-BreakerTerminatorOk, and the fail-safe OPEN branch (New-BreakerFailsafeOpen coupled to the 'failing SAFE to OPEN' warning, itself writing -State 'OPEN') -- not runtime-verified, pwsh absent"
else
  report FAIL "34: ps1 mechanics structural guard" \
    "move=$(t34_move_check "$BREAKER_PS1" && echo ok || echo FAIL) term=$(t34_term_check "$BREAKER_PS1" && echo ok || echo FAIL) failsafe_msg=$(t34_failsafe_msg_check "$BREAKER_PS1" && echo ok || echo FAIL) failsafe_state=$(t34_failsafe_state_check "$BREAKER_PS1" && echo ok || echo FAIL)"
fi

# ---------------------------------------------------------------------------
# 35 (NEW, story-009 task-03, routed addendum item b): CRLF prompt parity --
# bash behavioral. The read line (`p="$(cat "$PROMPT_FILE")"`) and the strip
# line (the both-CR/LF iterative while-loop) are extracted LIVE from the
# canonical loop.sh by CONTENT match (never a reimplementation, never line
# numbers -- the task pin explicitly warns these lines move), wrapped in a
# minimal script that repoints PROMPT_FILE at each fixture. All seven pinned
# tail vectors (\n, \r\n, \r\r\n, \r, \r\n\r\n, \n\r\n, \r\n\r\n\r\n) must
# yield exactly "text" -- the \r\n\r\n and \n\r\n tails are the discriminating
# cases a CR-only strip would fail (goal.md's empirically-disproven original
# pin).
# ---------------------------------------------------------------------------
read_ln_num35="$(grep -nF 'cat "$PROMPT_FILE"' "$LOOP_SH" | head -1 | cut -d: -f1)"
strip_ln_num35="$(grep -nF 'p%?' "$LOOP_SH" | head -1 | cut -d: -f1)"
read_line35="$( [[ -n "$read_ln_num35" ]] && sed -n "${read_ln_num35}p" "$LOOP_SH" )"
strip_line35="$( [[ -n "$strip_ln_num35" ]] && sed -n "${strip_ln_num35}p" "$LOOP_SH" )"

if [[ -z "$read_line35" || -z "$strip_line35" ]]; then
  report FAIL "35 setup: extract read+strip lines from canonical loop.sh" \
    "read_line='$read_line35' strip_line='$strip_line35' -- loop.sh structure changed?"
else
  crlf_script35="$TMP/35_crlf.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'PROMPT_FILE="$1"\n'
    printf '%s\n' "$read_line35"
    printf '%s\n' "$strip_line35"
    printf 'printf %%s "$p"\n'
  } > "$crlf_script35"

  declare -a tail_names35=('\n' '\r\n' '\r\r\n' '\r' '\r\n\r\n' '\n\r\n' '\r\n\r\n\r\n')
  declare -a tails35=($'\n' $'\r\n' $'\r\r\n' $'\r' $'\r\n\r\n' $'\n\r\n' $'\r\n\r\n\r\n')
  all_ok35=1
  declare -a fail_details35=()
  for i in "${!tails35[@]}"; do
    vec_file35="$TMP/35_vec_${i}.txt"
    printf 'text%s' "${tails35[$i]}" > "$vec_file35"
    result35="$(bash "$crlf_script35" "$vec_file35")"
    if [[ "$result35" != "text" ]]; then
      all_ok35=0
      fail_details35+=("tail='${tail_names35[$i]}' got='$result35'")
    fi
  done

  if [[ "$all_ok35" -eq 1 ]]; then
    report PASS "35: CRLF prompt parity (bash) -- all seven tail vectors (\\n, \\r\\n, \\r\\r\\n, \\r, \\r\\n\\r\\n, \\n\\r\\n, \\r\\n\\r\\n\\r\\n) yield 'text' through the LIVE-extracted canonical loop.sh read+strip lines"
  else
    report FAIL "35: CRLF prompt parity (bash)" "${fail_details35[*]}"
  fi
fi

# ---------------------------------------------------------------------------
# 36 (NEW, story-009 task-03, routed addendum item b; FIX-CYCLE-1: TrimEnd
# check re-scoped): CRLF prompt parity -- ps1 structural. The canonical
# loop.ps1 is grepped for the corrected comment (the original CR-only-strip
# pin was empirically disproven at cycle 1; the comment now accurately
# states both twins strip trailing CR/LF) and the TrimEnd("`r", "`n") line
# itself, which strips BOTH characters -- exact parity with the bash twin's
# iterative both-char strip loop verified behaviorally in 35. Fix-cycle-1: a
# file-wide grep for the TrimEnd(...) literal was mutation-proven
# decoy-satisfiable -- loop.ps1:168 applies the SAME TrimEnd("`r", "`n") call
# to the CLI OUTPUT (not the PROMPT.md read); deleting the prompt-side :153
# line left the old check green. Now block-scoped: anchored at the line that
# reads PROMPT.md into $raw (Get-Content -Raw -LiteralPath $PromptFile), a
# small window forward to the TrimEnd call that consumes that same $raw.
# ---------------------------------------------------------------------------
comment_ok36=0
grep -qF 'both twins strip trailing CR/LF from the prompt tail' "$LOOP_PS1" && comment_ok36=1

trimend_ok36=0
prompt_read_ln36="$(grep -nF 'Get-Content -Raw -LiteralPath $PromptFile' "$LOOP_PS1" | head -1 | cut -d: -f1)"
if [[ -n "$prompt_read_ln36" ]]; then
  prompt_window36="$(sed -n "${prompt_read_ln36},$((prompt_read_ln36 + 5))p" "$LOOP_PS1")"
  grep -qF 'TrimEnd("`r", "`n")' <<< "$prompt_window36" && trimend_ok36=1
fi

if [[ "$comment_ok36" -eq 1 && "$trimend_ok36" -eq 1 ]]; then
  report PASS "36: CRLF prompt parity (ps1 structural) -- canonical loop.ps1 carries the corrected comment ('both twins strip trailing CR/LF from the prompt tail') and the TrimEnd(\`r,\`n) line matching bash's iterative both-char strip -- not runtime-verified, pwsh absent"
else
  report FAIL "36: CRLF prompt parity (ps1 structural)" "comment_ok=$comment_ok36 trimend_ok=$trimend_ok36"
fi

# ===========================================================================
# STORY-010/011 slot-supervision + driver-dispatch coverage (assertions
# 37-53, extended by task 05's 54+). Shared fixture helpers: sandbox_write_loop
# substitutes the three instance tokens ({{PROJECT_NAME}}/{{LOOP_MODEL_CHAIN}}/
# {{IDE_DIR}}) into COPIES of the CANONICAL loop.sh/breaker.sh BEFORE any run
# (pinned) -- these fixtures never drive the instance _loop/ files (that
# remains assertion 15's own lane, and the goal's extraction-survival
# requirement is already proven by assertions 13/14/13b/13c/16/33/35 above,
# which re-extract against these same canonical files on every run of this
# harness). make_sandbox wraps the substituted copy in a throwaway git repo
# under this run's mktemp workdir, with independently-controllable
# tracked/gitignored _goals and {{IDE_DIR}} state (needed by the two
# preflight-failure fixtures, 44/45).
#
# STORY-011 note (task 05): PROMPT.md now carries the two dispatch-time
# substitution points (%%STORY_ID%%/%%OUTBOX_DIR%%) the driver requires --
# their ABSENCE is a loud exit-5 setup failure (see 61 below), so every
# sandbox needs them present pre-substitution, same as the shipped template.
# The fixture prompt no longer instructs a stub to print the sentinel (a
# dispatched slot emitting the sentinel is now itself an ITERATION-mismatch,
# per the sentinel-from-dispatched-slot rule) -- it documents the ITERATION:
# line contract instead, matching the shipped PROMPT.md's own dispatch text.
# _goals/backlog.md now seeds N generic eligible story blocks (STORY-101,
# STORY-102, ...) in the shipped seed shape (priority/passes/attempts/blocked
# pinned fields; writes: omitted -- writes-absent runs alone, the simplest
# admission outcome), so driver-owned selection has something to dispatch;
# n_stories defaults to 1 for fixtures needing exactly one dispatch, and is
# raised for fixtures whose per-SLOT circuit-breaker counters (CB1/CB2) need
# more consecutive dispatches than the 3-attempts eligibility cap would allow
# a single story to survive (51/52, below).
# ===========================================================================
sandbox_write_loop() { # sandbox_write_loop <dest_dir> <ide_dir_name>
  local dest="$1" ide="$2"
  mkdir -p "$dest/_loop"
  sed -e 's/{{PROJECT_NAME}}/sandbox-project/g' \
      -e 's/{{LOOP_MODEL_CHAIN}}/sonnet/g' \
      -e "s/{{IDE_DIR}}/$ide/g" \
      "$LOOP_SH" > "$dest/_loop/loop.sh"
  chmod +x "$dest/_loop/loop.sh"
  sed -e 's/{{PROJECT_NAME}}/sandbox-project/g' \
      "$BREAKER_SH" > "$dest/_loop/breaker.sh"
  printf 'Fixture prompt for %%%%STORY_ID%%%%: do the task; outbox %%%%OUTBOX_DIR%%%%; end with an ITERATION: %%%%STORY_ID%%%% <verdict> line.\n' > "$dest/_loop/PROMPT.md"
}

make_sandbox() { # make_sandbox <dest_dir> <ide_dir_name> <track_goals:0|1> <track_ide:0|1> [n_stories:1]
  local dest="$1" ide="$2" track_goals="$3" track_ide="$4" n_stories="${5:-1}"
  rm -rf "$dest"
  mkdir -p "$dest"
  sandbox_write_loop "$dest" "$ide"
  (
    cd "$dest"
    git init -q
    git config user.email test@example.com
    git config user.name "story010-test"
    mkdir -p _goals "$ide"
    {
      printf '# backlog\n'
      i=1
      while [[ "$i" -le "$n_stories" ]]; do
        printf '\n## STORY-1%02d: fixture story %d\n\n' "$i" "$i"
        printf -- '- priority: %d\n- passes: false\n- attempts: 0\n- blocked: false\n' "$i"
        i=$((i + 1))
      done
    } > _goals/backlog.md
    printf 'placeholder\n' > "$ide/.keep"
    : > .gitignore
    if [[ "$track_goals" != "1" ]]; then printf '_goals/\n' >> .gitignore; fi
    if [[ "$track_ide" != "1" ]]; then printf '%s/\n' "$ide" >> .gitignore; fi
    git add -A
    git commit -qm init
  )
}

# ---------------------------------------------------------------------------
# 37-40: LOOP_SLOTS clamp/guard/banner surface. The banner ("slots: N — ...")
# and the STORY-011 guard warning both print BEFORE the iteration loop body
# ever runs (loop.sh:85-94), so MAX_ITER=0 exercises them with ZERO CLI
# invocations -- no stub CLI, no git repo needed (nothing before the for-loop
# touches git).
# ---------------------------------------------------------------------------
CLAMP_DIR="$TMP/clamp-sandbox"
mkdir -p "$CLAMP_DIR/_goals"
sandbox_write_loop "$CLAMP_DIR" ".claude"

run_slots_probe() { # run_slots_probe <value|__UNSET__> -> sets slots_out/slots_err
  local val="$1" out err
  rm -f "$CLAMP_DIR/_goals/breaker-state.json"
  out="$TMP/slots_stdout_${RANDOM}.txt"; err="$TMP/slots_stderr_${RANDOM}.txt"
  if [[ "$val" == "__UNSET__" ]]; then
    ( cd "$CLAMP_DIR" && unset LOOP_SLOTS && bash ./_loop/loop.sh 0 ) >"$out" 2>"$err"
  else
    ( cd "$CLAMP_DIR" && LOOP_SLOTS="$val" bash ./_loop/loop.sh 0 ) >"$out" 2>"$err"
  fi
  slots_out="$(cat "$out")"; slots_err="$(cat "$err")"
}

# 37: LOOP_SLOTS=0 -> effective 1, NO warning.
run_slots_probe "0"
if grep -qF 'slots: 1 (mode: main-tree)' <<< "$slots_out" \
   && [[ -z "$slots_err" ]]; then
  report PASS "37: LOOP_SLOTS=0 -> effective 1, banner correct, stderr empty (no warning)"
else
  report FAIL "37: LOOP_SLOTS=0 -> effective 1, no warning" "stdout='$slots_out' stderr='$slots_err'"
fi

# 38: LOOP_SLOTS=5 -> internally clamped to 3 (structural, since the guard's
# collapse-to-1 makes the intermediate 3 behaviorally invisible on its own),
# THEN the >1 dark-launch guard holds effective at 1 WITH the STORY-011
# warning (explicitly set >1).
t38_clamp_check() { # t38_clamp_check <file> -> 0 if SLOTS>3 clamp-to-3 exists, block-scoped
  local f="$1" ln window
  ln="$(grep -n 'SLOTS="\${LOOP_SLOTS:-2}"' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 10))p" "$f")"
  grep -qE 'SLOTS > 3' <<< "$window" && grep -qE '^\s*SLOTS=3\s*$' <<< "$window"
}
run_slots_probe "5"
if t38_clamp_check "$LOOP_SH" \
   && grep -qF 'slots: 1 (mode: main-tree)' <<< "$slots_out" \
   && grep -qF 'LOOP_SLOTS>1 requires LOOP_WORKTREE=1 (worktree isolation); running with 1' <<< "$slots_err"; then
  report PASS "38: LOOP_SLOTS=5 -> structural clamp-to-3 present in canonical loop.sh, effective 1 WITH the STORY-011 warning"
else
  report FAIL "38: LOOP_SLOTS=5 -> clamp 3 -> guard 1 WITH warning" \
    "clamp_present=$(t38_clamp_check "$LOOP_SH" && echo yes || echo no) stdout='$slots_out' stderr='$slots_err'"
fi

# 39: LOOP_SLOTS=3 -> warning + effective 1 (in-range, no upper clamp needed,
# still >1 so the dark-launch guard applies).
run_slots_probe "3"
if grep -qF 'slots: 1 (mode: main-tree)' <<< "$slots_out" \
   && grep -qF 'LOOP_SLOTS>1 requires LOOP_WORKTREE=1 (worktree isolation); running with 1' <<< "$slots_err"; then
  report PASS "39: LOOP_SLOTS=3 -> effective 1 WITH the STORY-011 warning"
else
  report FAIL "39: LOOP_SLOTS=3 -> warning + effective 1" "stdout='$slots_out' stderr='$slots_err'"
fi

# 40: UNSET -> effective 1, PLAIN banner, stderr COMPLETELY warning-free (the
# anti-warning-fatigue contract: the default path never warns).
run_slots_probe "__UNSET__"
if grep -qF 'slots: 1 (mode: main-tree)' <<< "$slots_out" \
   && [[ -z "$slots_err" ]]; then
  report PASS "40: LOOP_SLOTS unset -> effective 1, plain banner, stderr entirely warning-free (anti-warning-fatigue)"
else
  report FAIL "40: LOOP_SLOTS unset -> effective 1, warning-free stderr" "stdout='$slots_out' stderr='$slots_err'"
fi

# 40-mutation-proof: delete the dark-launch guard (the SLOTS>1-AND-WORKTREE!=1
# collapse-to-1 block, STORY-011's guard REPLACEMENT shape) in a COPY,
# content-anchored (not by line number) -> with an in-range explicit value
# (3) and LOOP_WORKTREE left unset, the banner must now show >1 (i.e. 3,
# unclamped by the removed guard) -- proving the guard, not some other code
# path, is what holds the banner at 1 above. Anchor updated (STORY-011): the
# guard's own condition line now reads `if (( SLOTS > 1 )) && (( WORKTREE !=
# 1 )); then` (was a bare `SLOTS > 1` test pre-story) -- the 5-line
# if/EFFECTIVE_SLOTS=1/else/EFFECTIVE_SLOTS=$SLOTS/fi shape itself is
# unchanged, so skip=4 still swallows the whole block.
MUT40_DIR="$TMP/clamp-sandbox-mut40"
rm -rf "$MUT40_DIR"; mkdir -p "$MUT40_DIR/_goals" "$MUT40_DIR/_loop"
awk '
  /^if \(\( SLOTS > 1 \)\) && \(\( WORKTREE != 1 \)\); then$/ && !done {
    print "EFFECTIVE_SLOTS=$SLOTS   # mutation (test 40): dark-launch guard removed"
    skip=4; done=1; next
  }
  skip>0 { skip--; next }
  { print }
' "$CLAMP_DIR/_loop/loop.sh" > "$MUT40_DIR/_loop/loop.sh"
chmod +x "$MUT40_DIR/_loop/loop.sh"
cp "$CLAMP_DIR/_loop/breaker.sh" "$MUT40_DIR/_loop/breaker.sh"
mut40_guard_removed=0
grep -qF 'EFFECTIVE_SLOTS=$SLOTS   # mutation (test 40)' "$MUT40_DIR/_loop/loop.sh" && \
  ! grep -qE '^if \(\( SLOTS > 1 \)\) && \(\( WORKTREE != 1 \)\); then$' "$MUT40_DIR/_loop/loop.sh" && mut40_guard_removed=1
mut40_out="$TMP/mut40_stdout.txt"
( cd "$MUT40_DIR" && LOOP_SLOTS=3 bash ./_loop/loop.sh 0 ) >"$mut40_out" 2>/dev/null
mut40_banner="$(grep -oE 'slots: [0-9]+' "$mut40_out" | head -1 | grep -oE '[0-9]+')"
if [[ "$mut40_guard_removed" -eq 1 && -n "$mut40_banner" && "$mut40_banner" -gt 1 ]]; then
  report PASS "40-mutation-proof: dark-launch guard deleted in a COPY -> banner shows $mut40_banner (>1) with LOOP_SLOTS=3, confirming the guard (not other code) holds it at 1 on the real driver"
else
  report FAIL "40-mutation-proof: guard deletion must show banner >1" "guard_removed=$mut40_guard_removed banner='$mut40_banner'"
fi

# ---------------------------------------------------------------------------
# 41 (goal's flag=0 equivalence contract, items a/b/c/e): LOOP_WORKTREE
# unset/0 (default) + LOOP_SLOTS unset -> (a) no worktree created, no
# .loop-worktrees/ path; (b) no new branch; (c) an identical stub run yields
# the identical exit code (same sandbox, invoked twice); (e) stderr free of
# the guard warning. Item (d) -- CB0/CB1/CB2 semantics/thresholds unchanged
# -- is covered by the CB fixtures below: 50-52 run at these SAME default
# flags (49 is the flag=1 CB0-scoped fixture, not a default-flags proof).
# Item (f) is assertion 42 (its own literal enumeration proof, below).
#
# STORY-011 fixture-input update (task 05): driver-owned selection means a
# dispatch only happens when the backlog has an eligible story (the new seed
# shape, via make_sandbox's default single STORY-101), and a dispatched slot
# emitting the sentinel is now itself an ITERATION-mismatch, so the old
# stub-sentinel.sh is replaced with a stub that commits real progress and
# ends with a matching `ITERATION: STORY-101 passed` line -- proving the
# "attempts+passes end state driver-written" half of the equivalence
# contract actually happens, not merely a vacuous no-dispatch run. Invoked
# with MAX_ITER=2 (one round to dispatch+integrate STORY-101, a second round
# to observe the driver's own no-eligible-stories completion once the story
# has passed) rather than 1, so exit 0 (today's real "backlog complete"
# code) is reachable at all under the new one-dispatch-per-MAX_ITER-unit
# accounting. env -u hardened (addendum 3d): strips any LOOP_SLOTS/
# LOOP_WORKTREE leaking in from the CALLER's environment before this
# default-flags run, same hardening applied to every 41-52 invocation below.
# ---------------------------------------------------------------------------
EQUIV_DIR="$TMP/equiv-sandbox"
make_sandbox "$EQUIV_DIR" ".claude" 1 1
cat > "$EQUIV_DIR/_loop/stub-sentinel.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Deterministic single-pass stub: commits real progress (so the driver's
# no-progress counter never fires) and reports success via the ITERATION:
# line the driver now requires -- never the sentinel (a dispatched slot
# printing it is itself an ITERATION-mismatch under STORY-011).
echo "committing progress" > progress.txt
git add progress.txt
git commit -qm "equivalence-contract progress"
echo "ITERATION: STORY-101 passed"
exit 0
STUBEOF
chmod +x "$EQUIV_DIR/_loop/stub-sentinel.sh"

equiv_out_a="$TMP/equiv_a_stdout.txt"; equiv_err_a="$TMP/equiv_a_stderr.txt"
( cd "$EQUIV_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$EQUIV_DIR/_loop/stub-sentinel.sh" bash ./_loop/loop.sh 2 ) \
  >"$equiv_out_a" 2>"$equiv_err_a"
equiv_rc_a=$?

equiv_out_b="$TMP/equiv_b_stdout.txt"; equiv_err_b="$TMP/equiv_b_stderr.txt"
( cd "$EQUIV_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$EQUIV_DIR/_loop/stub-sentinel.sh" bash ./_loop/loop.sh 2 ) \
  >"$equiv_out_b" 2>"$equiv_err_b"
equiv_rc_b=$?

no_worktree_dir=1; [[ -e "$EQUIV_DIR/.loop-worktrees" ]] && no_worktree_dir=0
no_new_branch=1
equiv_branch_count="$(git -C "$EQUIV_DIR" branch --list 'loop/*' | wc -l)"
[[ "$equiv_branch_count" -ne 0 ]] && no_new_branch=0
identical_exit=0
[[ "$equiv_rc_a" -eq "$equiv_rc_b" && "$equiv_rc_a" -eq 0 ]] && identical_exit=1
stderr_warning_free=1
grep -qF 'LOOP_SLOTS>1 requires LOOP_WORKTREE=1' "$equiv_err_a" && stderr_warning_free=0

if [[ "$no_worktree_dir" -eq 1 && "$no_new_branch" -eq 1 && "$identical_exit" -eq 1 \
      && "$stderr_warning_free" -eq 1 ]]; then
  report PASS "41: flag=0 equivalence contract (a)(b)(c)(e) -- no .loop-worktrees/ path, no new branch, identical stub run (same sandbox, invoked twice) -> identical exit code ($equiv_rc_a == $equiv_rc_b), stderr free of the guard warning"
else
  report FAIL "41: flag=0 equivalence contract (a)(b)(c)(e)" \
    "no_worktree_dir=$no_worktree_dir no_new_branch=$no_new_branch(count=$equiv_branch_count) identical_exit=$identical_exit(rc_a=$equiv_rc_a rc_b=$equiv_rc_b) stderr_warning_free=$stderr_warning_free"
fi

# ---------------------------------------------------------------------------
# 42 (flag=0 equivalence contract, item f): the ONLY new stdout line versus
# the pre-story driver is the slot banner -- the expected stdout line set is
# enumerated LITERALLY here (never derived from git/HEAD, per the goal pin,
# which would degrade into a self-comparison against the NEW driver), with
# the iteration banner's embedded $(date -Is) timestamp normalized to a
# placeholder (marker-normalization precedent: this file's own sed-based
# clause normalization at assertion 33, run.sh:1163-1164 pre-story).
# ---------------------------------------------------------------------------
expected_f42="slots: 1 (mode: main-tree)
=== fill round: dispatched=0/2 active=0 <TS> ===
ITERATION: STORY-101 passed
=== fill round: dispatched=1/2 active=0 <TS> ===
=== no eligible stories remain -- exiting ==="
normalized_f42="$(sed -E 's|=== fill round: dispatched=([0-9]+/[0-9]+) active=[0-9]+ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} ===|=== fill round: dispatched=\1 active=0 <TS> ===|g' "$equiv_out_a")"
if [[ "$normalized_f42" == "$expected_f42" ]]; then
  report PASS "42: flag=0 equivalence contract (f) -- normalized stdout exactly matches the literally-enumerated expected line set (banner + iteration + tail-25 CLI output + completion line), timestamp normalized"
else
  report FAIL "42: flag=0 equivalence contract (f)" "expected='$expected_f42' actual(normalized)='$normalized_f42'"
fi

# ---------------------------------------------------------------------------
# 43: worktree lifecycle, flag=1, TRACKED sandbox (both _goals/backlog.md and
# {{IDE_DIR}} tracked/committed, so the preflight passes). The stub probes
# its OWN cwd (the worktree, per the driver/child boundary pin) into a file
# OUTSIDE the repo, commits progress, then prints the sentinel so the run
# completes via the pinned ff-only-integrate -> worktree-remove -> branch -d
# ordering.
# ---------------------------------------------------------------------------
LIFECYCLE_DIR="$TMP/lifecycle-sandbox"
make_sandbox "$LIFECYCLE_DIR" ".claude" 1 1
lifecycle_probe="$TMP/lifecycle-wt-probe.txt"
rm -f "$lifecycle_probe"

cat > "$LIFECYCLE_DIR/_loop/stub-lifecycle.sh" <<STUBEOF
#!/usr/bin/env bash
pwd > "$lifecycle_probe"
echo "progress" > progress.txt
git add progress.txt
git commit -qm "lifecycle progress"
# STORY-011 fixture-input update: dispatched slots must emit ITERATION: <id> <verdict>
# (not the sentinel -- a dispatched slot emitting it is itself an ITERATION-mismatch).
echo "ITERATION: STORY-101 passed"
exit 0
STUBEOF
chmod +x "$LIFECYCLE_DIR/_loop/stub-lifecycle.sh"
# Commit the stub CLI itself so it is not mistaken for post-run litter below.
( cd "$LIFECYCLE_DIR" && git add -A && git commit -qm "add stub CLI" )

lifecycle_log="$TMP/lifecycle-run.log"
# MAX_ITER=2: budget for fill-round-1 (dispatch STORY-101) + fill-round-2
# (no eligible stories remain -> exit 0). MAX_ITER=1 exits 1 "max iterations
# reached" because the while condition fails before the "no eligible" branch.
( cd "$LIFECYCLE_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 LOOP_CLI="$LIFECYCLE_DIR/_loop/stub-lifecycle.sh" \
    bash ./_loop/loop.sh 2 ) >"$lifecycle_log" 2>&1
lifecycle_rc=$?

expected_wt_path="$LIFECYCLE_DIR/.loop-worktrees/slot-1"
probed_pwd="$( [[ -f "$lifecycle_probe" ]] && cat "$lifecycle_probe" )"
worktree_existed=0
[[ "$probed_pwd" == "$expected_wt_path" ]] && worktree_existed=1

worktree_removed_after=1
[[ -e "$expected_wt_path" ]] && worktree_removed_after=0

branch_deleted=1
[[ -n "$(git -C "$LIFECYCLE_DIR" branch --list 'loop/iter-1')" ]] && branch_deleted=0

zero_stray_branches=1
[[ -n "$(git -C "$LIFECYCLE_DIR" branch --list 'loop/*')" ]] && zero_stray_branches=0

# zero_litter: `.loop-worktrees` itself is not removed by `git worktree
# remove` (only the slot-N entry under it is), so an empty parent is
# expected, not litter -- verified empirically before writing this check.
# breaker-state.json is likewise an expected, non-litter byproduct.
zero_litter=1
if [[ -d "$LIFECYCLE_DIR/.loop-worktrees" ]]; then
  [[ -z "$(ls -A "$LIFECYCLE_DIR/.loop-worktrees" 2>/dev/null)" ]] || zero_litter=0
fi
litter_status="$(git -C "$LIFECYCLE_DIR" status --porcelain -- . ':(exclude)_goals/breaker-state.json' ':(exclude)_goals/backlog.md')"
[[ -n "$litter_status" ]] && zero_litter=0

worktree_list_count="$(git -C "$LIFECYCLE_DIR" worktree list | wc -l)"
main_only=1
[[ "$worktree_list_count" -ne 1 ]] && main_only=0

integrated=1
git -C "$LIFECYCLE_DIR" log --oneline | grep -qF "lifecycle progress" || integrated=0

if [[ "$lifecycle_rc" -eq 0 && "$worktree_existed" -eq 1 && "$worktree_removed_after" -eq 1 \
      && "$branch_deleted" -eq 1 && "$zero_stray_branches" -eq 1 && "$zero_litter" -eq 1 \
      && "$main_only" -eq 1 && "$integrated" -eq 1 ]]; then
  report PASS "43: worktree lifecycle (flag=1, tracked sandbox) -- worktree existed during the run (probed cwd=$probed_pwd), removed after, branch loop/iter-1 integrated ff-only into main (progress commit present) + deleted, zero litter, zero stray branches"
else
  report FAIL "43: worktree lifecycle" \
    "rc=$lifecycle_rc existed=$worktree_existed removed_after=$worktree_removed_after branch_deleted=$branch_deleted zero_stray=$zero_stray_branches zero_litter=$zero_litter(status='$litter_status') main_only=$main_only(count=$worktree_list_count) integrated=$integrated probe='$probed_pwd' expected='$expected_wt_path'"
  sed 's/^/    /' "$lifecycle_log" >&2
fi

# ---------------------------------------------------------------------------
# 44 (preflight failure, fixture i): _goals/ GITIGNORED (this repo's own
# shape). `git worktree add` SUCCEEDS (the branch does not pre-exist), so the
# failure is the PREFLIGHT's own exit 5, not git's add failing with its own
# status. Stub carries a marker so "stub never ran" is an assertable fact.
# ---------------------------------------------------------------------------
PREFLIGHT_I_DIR="$TMP/preflight-i-sandbox"
make_sandbox "$PREFLIGHT_I_DIR" ".claude" 0 1   # _goals GITIGNORED, IDE_DIR tracked
preflight_i_marker="$TMP/preflight-i-stub-ran.marker"
rm -f "$preflight_i_marker"

cat > "$PREFLIGHT_I_DIR/_loop/stub-never.sh" <<STUBEOF
#!/usr/bin/env bash
touch "$preflight_i_marker"
echo "<promise>COMPLETE</promise>"
exit 0
STUBEOF
chmod +x "$PREFLIGHT_I_DIR/_loop/stub-never.sh"

preflight_i_log="$TMP/preflight-i-run.log"
( cd "$PREFLIGHT_I_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 LOOP_CLI="$PREFLIGHT_I_DIR/_loop/stub-never.sh" \
    bash ./_loop/loop.sh 1 ) >"$preflight_i_log" 2>&1
preflight_i_rc=$?

stub_never_ran_i=1
[[ -f "$preflight_i_marker" ]] && stub_never_ran_i=0
worktree_removed_i=1
[[ -e "$PREFLIGHT_I_DIR/.loop-worktrees/slot-1" ]] && worktree_removed_i=0
branch_removed_i=1
[[ -n "$(git -C "$PREFLIGHT_I_DIR" branch --list 'loop/iter-1')" ]] && branch_removed_i=0
names_requirement_i=0
grep -qF "must be committed (not gitignored) for LOOP_WORKTREE=1" "$preflight_i_log" \
  && grep -qF "_goals/backlog.md" "$preflight_i_log" && names_requirement_i=1

if [[ "$preflight_i_rc" -eq 5 && "$stub_never_ran_i" -eq 1 && "$worktree_removed_i" -eq 1 \
      && "$branch_removed_i" -eq 1 && "$names_requirement_i" -eq 1 ]]; then
  report PASS "44: preflight failure fixture (i, gitignored _goals/) -- exit 5, loud error naming the tracked-instance requirement + _goals/backlog.md, worktree removed, branch removed, stub never ran (no silent fallback)"
else
  report FAIL "44: preflight failure fixture (i, gitignored _goals/)" \
    "rc=$preflight_i_rc(expected 5) stub_never_ran=$stub_never_ran_i worktree_removed=$worktree_removed_i branch_removed=$branch_removed_i names_requirement=$names_requirement_i"
  sed 's/^/    /' "$preflight_i_log" >&2
fi

# ---------------------------------------------------------------------------
# 45 (preflight failure, fixture ii): _goals/ TRACKED but {{IDE_DIR}}
# GITIGNORED (the cycle-2 mirror case). Same assertions as 44, mirrored;
# `git worktree add` SUCCEEDS here too.
# ---------------------------------------------------------------------------
PREFLIGHT_II_DIR="$TMP/preflight-ii-sandbox"
make_sandbox "$PREFLIGHT_II_DIR" ".claude" 1 0   # _goals TRACKED, IDE_DIR gitignored
preflight_ii_marker="$TMP/preflight-ii-stub-ran.marker"
rm -f "$preflight_ii_marker"

cat > "$PREFLIGHT_II_DIR/_loop/stub-never.sh" <<STUBEOF
#!/usr/bin/env bash
touch "$preflight_ii_marker"
echo "<promise>COMPLETE</promise>"
exit 0
STUBEOF
chmod +x "$PREFLIGHT_II_DIR/_loop/stub-never.sh"

preflight_ii_log="$TMP/preflight-ii-run.log"
( cd "$PREFLIGHT_II_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 LOOP_CLI="$PREFLIGHT_II_DIR/_loop/stub-never.sh" \
    bash ./_loop/loop.sh 1 ) >"$preflight_ii_log" 2>&1
preflight_ii_rc=$?

stub_never_ran_ii=1
[[ -f "$preflight_ii_marker" ]] && stub_never_ran_ii=0
worktree_removed_ii=1
[[ -e "$PREFLIGHT_II_DIR/.loop-worktrees/slot-1" ]] && worktree_removed_ii=0
branch_removed_ii=1
[[ -n "$(git -C "$PREFLIGHT_II_DIR" branch --list 'loop/iter-1')" ]] && branch_removed_ii=0
names_requirement_ii=0
grep -qF "must be committed (not gitignored) for LOOP_WORKTREE=1" "$preflight_ii_log" \
  && grep -qF ".claude" "$preflight_ii_log" && names_requirement_ii=1

if [[ "$preflight_ii_rc" -eq 5 && "$stub_never_ran_ii" -eq 1 && "$worktree_removed_ii" -eq 1 \
      && "$branch_removed_ii" -eq 1 && "$names_requirement_ii" -eq 1 ]]; then
  report PASS "45: preflight failure fixture (ii, tracked _goals/ + gitignored {{IDE_DIR}}=.claude) -- exit 5, loud error naming the tracked-instance requirement + .claude, worktree removed, branch removed, stub never ran (no silent fallback)"
else
  report FAIL "45: preflight failure fixture (ii, tracked _goals/ + gitignored IDE_DIR)" \
    "rc=$preflight_ii_rc(expected 5) stub_never_ran=$stub_never_ran_ii worktree_removed=$worktree_removed_ii branch_removed=$branch_removed_ii names_requirement=$names_requirement_ii"
  sed 's/^/    /' "$preflight_ii_log" >&2
fi

# ---------------------------------------------------------------------------
# 46: abnormal slot exit -- stub exits nonzero AND leaves an uncommitted
# (dirty) worktree -> quarantine-lite: NOT integrated, --force cleanup,
# branch RETAINED (never deleted) and named in the closing output (the
# EXIT-trap-printed retained-branches summary).
# ---------------------------------------------------------------------------
ABNORMAL_DIR="$TMP/abnormal-sandbox"
make_sandbox "$ABNORMAL_DIR" ".claude" 1 1
abnormal_main_head_before="$(git -C "$ABNORMAL_DIR" rev-parse HEAD)"

cat > "$ABNORMAL_DIR/_loop/stub-abnormal.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Leaves the worktree dirty (uncommitted change) and exits nonzero -- neither
# a recognized CB1/CB2 disposition (single iteration, thresholds 3/5 not
# reached) nor a clean tree, so the driver's abnormal-exit branch fires.
echo "dirty, uncommitted" > dirty.txt
echo "boom"
exit 7
STUBEOF
chmod +x "$ABNORMAL_DIR/_loop/stub-abnormal.sh"

abnormal_log="$TMP/abnormal-run.log"
( cd "$ABNORMAL_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 LOOP_CLI="$ABNORMAL_DIR/_loop/stub-abnormal.sh" \
    bash ./_loop/loop.sh 1 ) >"$abnormal_log" 2>&1
abnormal_rc=$?

abnormal_main_head_after="$(git -C "$ABNORMAL_DIR" rev-parse HEAD)"
names_branch=0
grep -qF "retaining branch 'loop/iter-1'" "$abnormal_log" && names_branch=1
closing_summary=0
grep -qF "retained branches from quarantined slots (NOT integrated): loop/iter-1" "$abnormal_log" && closing_summary=1
worktree_cleaned=1
[[ -e "$ABNORMAL_DIR/.loop-worktrees/slot-1" ]] && worktree_cleaned=0
branch_retained=1
[[ -z "$(git -C "$ABNORMAL_DIR" branch --list 'loop/iter-1')" ]] && branch_retained=0
no_integration=1
[[ "$abnormal_main_head_before" != "$abnormal_main_head_after" ]] && no_integration=0

if [[ "$abnormal_rc" -eq 1 && "$names_branch" -eq 1 && "$closing_summary" -eq 1 \
      && "$worktree_cleaned" -eq 1 && "$branch_retained" -eq 1 && "$no_integration" -eq 1 ]]; then
  report PASS "46: abnormal slot exit -- dirty worktree + nonzero exit -> NOT integrated, --force cleanup, branch loop/iter-1 RETAINED (not deleted) and named in the closing retained-branches summary"
else
  report FAIL "46: abnormal slot exit" \
    "rc=$abnormal_rc names_branch=$names_branch closing_summary=$closing_summary worktree_cleaned=$worktree_cleaned branch_retained=$branch_retained no_integration=$no_integration"
  sed 's/^/    /' "$abnormal_log" >&2
fi

# ---------------------------------------------------------------------------
# 47 (RE-ANCHORED AGAIN, STORY-012 task 06 -- red-window repair, harness-lag
# not a regression): the STORY-011-era anchor this assertion pinned (a bare
# `if [[ "${slot_state[SLOT]}" == "running" ]]; then` gate) no longer matches
# byte-for-byte: STORY-012 task 01 (D2 retirement) widened that SAME line
# with an explicit `|| (( slot_retired[SLOT] == 1 ))` disjunct, so a retired
# slot is ALSO skipped by FILL, on top of the pre-existing "already running"
# skip -- the gate is strictly STRONGER, never weaker (diagnosed harness-lag:
# assertion 47 is in the goal's permitted-update set). Re-anchored to the
# shipped disjunctive line; the check now additionally requires the
# `slot_retired[SLOT]` disjunct so a REGRESSION that dropped the retirement
# skip (re-widening the window to accept the old narrower line) would fail
# this assertion, not silently pass it. Meaning preserved: still proves "one
# dispatch per idle, non-retired row, never over-subscribed" -- now ALSO
# proving a retired row is skipped -- plus the SAME refill-on-slot-exit site
# as before (active_slots decrement + 'refill trigger' comment,
# byte-unchanged).
t47_accounting_check() { # per-row running-OR-retired-skip gate, block-scoped
  # at the FILL loop's own gate line (NOT the shared `for ((SLOT = 0; ...))`
  # header, which also appears at the slot-table init/poll/reap loops --
  # anchoring there would grab the wrong occurrence via `head -1`).
  local f="$1" ln window
  ln="$(grep -n 'if \[\[ "\${slot_state\[SLOT\]}" == "running" \]\] || (( slot_retired\[SLOT\] == 1 )); then' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 3))p" "$f")"
  grep -qF 'slot_state[SLOT]' <<< "$window" && grep -qF 'slot_retired[SLOT]' <<< "$window" \
    && grep -qF 'continue' <<< "$window"
}
t47_refill_check() { # refill-on-slot-exit, block-scoped at the decrement site
  local f="$1" ln window
  ln="$(grep -n 'active_slots=\$((active_slots - 1))' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "$((ln - 1)),$((ln + 1))p" "$f")"
  grep -qF 'refill trigger' <<< "$window"
}
if t47_accounting_check "$LOOP_SH" && t47_refill_check "$LOOP_SH"; then
  report PASS "47: per-row FILL gate (slot_state[SLOT]=='running' OR slot_retired[SLOT]==1 -> continue, over-subscription AND retired-refill both impossible by construction -- re-anchored STORY-012 task 06 to the D2-widened disjunctive line, meaning preserved and strictly stronger) + refill-on-slot-exit (active_slots decrement + 'refill trigger' comment), both present in canonical loop.sh, block-scoped"
else
  report FAIL "47: per-row FILL gate / refill" \
    "accounting=$(t47_accounting_check "$LOOP_SH" && echo ok || echo FAIL) refill=$(t47_refill_check "$LOOP_SH" && echo ok || echo FAIL)"
fi

# ---------------------------------------------------------------------------
# 48 (mutation-prove by fixture): ff-only integration stop. The stub commits
# progress inside its OWN worktree, but ALSO makes an EXTERNAL commit
# directly against the sandbox's MAIN tree (simulating a concurrent
# modification landing on main while the slot was running) before it exits
# -- by the time the driver reaps the child and attempts
# `git merge --ff-only`, main has diverged, so the branch is no longer a
# fast-forward. Driver stops loudly at integration: exit 5, branch NOT
# force-merged (main's log never gains the slot's commit).
# ---------------------------------------------------------------------------
FFONLY_DIR="$TMP/ffonly-sandbox"
make_sandbox "$FFONLY_DIR" ".claude" 1 1

cat > "$FFONLY_DIR/_loop/stub-ffonly.sh" <<STUBEOF
#!/usr/bin/env bash
echo "slot progress" > slot-progress.txt
git add slot-progress.txt
git commit -qm "slot-side commit (never integrated)"
# Simulate an EXTERNAL, concurrent commit landing on the sandbox's MAIN tree
# that modifies the SAME file as the slot -- this creates a rebase CONFLICT
# when the driver attempts the pre-merge rebase (judged deviation, task-02
# accepted) so the ff-only merge fails. Uses non-empty content to guarantee
# a real content conflict (not just an --allow-empty commit, which would
# rebase cleanly and make the merge succeed).
echo "conflict from main" > "$FFONLY_DIR/slot-progress.txt"
git -C "$FFONLY_DIR" add slot-progress.txt
git -C "$FFONLY_DIR" commit -qm "external main-tree commit (concurrent, conflicting)"
# STORY-011: dispatched slot must emit ITERATION: <id> <verdict> (not sentinel)
echo "ITERATION: STORY-101 passed"
exit 0
STUBEOF
chmod +x "$FFONLY_DIR/_loop/stub-ffonly.sh"

ffonly_log="$TMP/ffonly-run.log"
( cd "$FFONLY_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 LOOP_CLI="$FFONLY_DIR/_loop/stub-ffonly.sh" \
    bash ./_loop/loop.sh 1 ) >"$ffonly_log" 2>&1
ffonly_rc=$?

names_failure=0
grep -qF "integration failed: 'loop/iter-1' is not a fast-forward" "$ffonly_log" && names_failure=1
not_force_merged=1
git -C "$FFONLY_DIR" log --oneline 2>/dev/null | grep -qF "slot-side commit" && not_force_merged=0

if [[ "$ffonly_rc" -eq 5 && "$names_failure" -eq 1 && "$not_force_merged" -eq 1 ]]; then
  report PASS "48: ff-only integration stop (mutation-prove: external main-tree commit forces a non-fast-forward) -- exit 5, loud 'not a fast-forward' stop, worktree branch NOT force-merged into main"
else
  report FAIL "48: ff-only integration stop" "rc=$ffonly_rc(expected 5) names_failure=$names_failure not_force_merged=$not_force_merged"
  sed 's/^/    /' "$ffonly_log" >&2
fi

# ---------------------------------------------------------------------------
# 49: CB0 scoped revert (LOOP_WORKTREE=1). Stub commits a PROTECTED-path
# change (_loop/loop.sh itself) inside its own worktree -> CB0 fires: exit 4,
# the SANDBOX MAIN TREE's HEAD is unchanged (the revert + --force removal
# happen entirely on the worktree side), no integration, worktree cleaned up.
# ---------------------------------------------------------------------------
CB0_DIR="$TMP/cb0-sandbox"
make_sandbox "$CB0_DIR" ".claude" 1 1
cb0_main_head_before="$(git -C "$CB0_DIR" rev-parse HEAD)"

cat > "$CB0_DIR/_loop/stub-cb0.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Modifies a PROTECTED path (_loop/, per the CB0 path list) inside the
# worktree -- must trigger the run-fatal revert, never reach CB1/CB2.
echo "# protected-path tamper" >> _loop/loop.sh
git add _loop/loop.sh
git commit -qm "oops: touched protected _loop/"
echo "irrelevant output"
exit 0
STUBEOF
chmod +x "$CB0_DIR/_loop/stub-cb0.sh"

cb0_log="$TMP/cb0-run.log"
( cd "$CB0_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 LOOP_CLI="$CB0_DIR/_loop/stub-cb0.sh" \
    bash ./_loop/loop.sh 1 ) >"$cb0_log" 2>&1
cb0_rc=$?

cb0_main_head_after="$(git -C "$CB0_DIR" rev-parse HEAD)"
main_head_unchanged=0
[[ "$cb0_main_head_before" == "$cb0_main_head_after" ]] && main_head_unchanged=1
cb0_worktree_cleaned=1
[[ -e "$CB0_DIR/.loop-worktrees/slot-1" ]] && cb0_worktree_cleaned=0
cb0_no_integration=1
git -C "$CB0_DIR" log --oneline | grep -qF "protected _loop/" && cb0_no_integration=0
cb0_named=0
grep -qF "protected-path modification detected" "$cb0_log" && cb0_named=1

if [[ "$cb0_rc" -eq 4 && "$main_head_unchanged" -eq 1 && "$cb0_worktree_cleaned" -eq 1 \
      && "$cb0_no_integration" -eq 1 && "$cb0_named" -eq 1 ]]; then
  report PASS "49: CB0 scoped revert (LOOP_WORKTREE=1) -- protected-path commit inside the worktree -> exit 4, sandbox MAIN TREE HEAD unchanged ($cb0_main_head_before), no integration, worktree cleaned up"
else
  report FAIL "49: CB0 scoped revert" \
    "rc=$cb0_rc(expected 4) main_head_unchanged=$main_head_unchanged(before=$cb0_main_head_before after=$cb0_main_head_after) worktree_cleaned=$cb0_worktree_cleaned no_integration=$cb0_no_integration named=$cb0_named"
  sed 's/^/    /' "$cb0_log" >&2
fi

# ---------------------------------------------------------------------------
# 50 (per-slot CB1 meaning-preserved proof): assertion 15 already covers the
# CB1 rate-limited carve-out end-to-end against the RE-EMITTED instance
# driver (pre-story until task 05); this proves the SAME CB1 threshold (3
# consecutive no-progress iterations) against the CANONICAL, newly
# -restructured (slot-table-based counters) driver directly, at the default
# flags (LOOP_WORKTREE=0). Stub never commits, never rate-limits -> exit 2
# after exactly 3 no-progress iterations.
# ---------------------------------------------------------------------------
CB1_CANON_DIR="$TMP/cb1-canonical-sandbox"
make_sandbox "$CB1_CANON_DIR" ".claude" 1 1

cat > "$CB1_CANON_DIR/_loop/stub-cb1.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Deliberately avoids any wording detect_rate_limit's pattern could match
# (rate/limit/quota/429/too many requests) -- an earlier draft's own
# incidental phrasing false-positived the detector and OPENED the breaker,
# derailing this fixture into a 600s cooldown sleep.
echo "steady state, nothing new this pass"
exit 0
STUBEOF
chmod +x "$CB1_CANON_DIR/_loop/stub-cb1.sh"

cb1c_log="$TMP/cb1-canonical-run.log"
( cd "$CB1_CANON_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$CB1_CANON_DIR/_loop/stub-cb1.sh" bash ./_loop/loop.sh 5 ) \
  >"$cb1c_log" 2>&1
cb1c_rc=$?

if [[ "$cb1c_rc" -eq 2 ]] && grep -qF -- '--- no progress (3/3)' "$cb1c_log" \
   && grep -qF 'circuit breaker: 3 iterations without a commit' "$cb1c_log"; then
  report PASS "50: per-slot CB1 (canonical driver, default flags) -- meaning preserved: exit 2 after exactly 3 no-progress iterations (slot-table counter reaches 3/3)"
else
  report FAIL "50: per-slot CB1 (canonical driver)" "rc=$cb1c_rc(expected 2)"
  sed 's/^/    /' "$cb1c_log" >&2
fi

# ---------------------------------------------------------------------------
# 51 (per-slot CB2 -- NEW, previously ZERO CB2 coverage): stub commits
# progress every iteration (so CB1's no-progress counter never fires) but
# prints an IDENTICAL 5-line failure signature and exits nonzero every time
# -> the per-slot same-error counter reaches 5 -> exit 3.
# ---------------------------------------------------------------------------
CB2_DIR="$TMP/cb2-sandbox"
make_sandbox "$CB2_DIR" ".claude" 1 1 2
cb2_counter_file="$TMP/cb2-counter.txt"
rm -f "$cb2_counter_file"

cat > "$CB2_DIR/_loop/stub-cb2.sh" <<STUBEOF
#!/usr/bin/env bash
counter_file="$cb2_counter_file"
n=0
[[ -f "\$counter_file" ]] && n="\$(cat "\$counter_file")"
n=\$((n + 1))
echo "\$n" > "\$counter_file"
echo "progress \$n" >> progress.txt
git add progress.txt
git commit -qm "progress \$n"
printf 'ERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\n'
exit 1
STUBEOF
chmod +x "$CB2_DIR/_loop/stub-cb2.sh"

cb2_log="$TMP/cb2-run.log"
( cd "$CB2_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$CB2_DIR/_loop/stub-cb2.sh" bash ./_loop/loop.sh 6 ) >"$cb2_log" 2>&1
cb2_rc=$?

if [[ "$cb2_rc" -eq 3 ]] && grep -qF 'circuit breaker: same error 5 times' "$cb2_log" \
   && ! grep -qF 'no progress' "$cb2_log"; then
  report PASS "51: per-slot CB2 (NEW behavioral coverage) -- 5 identical failure outputs (each iteration still committing progress, so CB1 never fires) -> exit 3"
else
  report FAIL "51: per-slot CB2 behavioral" "rc=$cb2_rc(expected 3)"
  sed 's/^/    /' "$cb2_log" >&2
fi

# ---------------------------------------------------------------------------
# 52 (per-slot CB2 control): 4 identical failure outputs, then a DIFFERENT
# 5th -> the same-error counter resets on the 5th, never reaching 5 -> the
# run must NOT exit 3 (it exhausts MAX_ITER=5 and exits 1).
# ---------------------------------------------------------------------------
CB2_CTRL_DIR="$TMP/cb2-control-sandbox"
make_sandbox "$CB2_CTRL_DIR" ".claude" 1 1 2
cb2_ctrl_counter_file="$TMP/cb2-control-counter.txt"
rm -f "$cb2_ctrl_counter_file"

cat > "$CB2_CTRL_DIR/_loop/stub-cb2-control.sh" <<STUBEOF
#!/usr/bin/env bash
counter_file="$cb2_ctrl_counter_file"
n=0
[[ -f "\$counter_file" ]] && n="\$(cat "\$counter_file")"
n=\$((n + 1))
echo "\$n" > "\$counter_file"
echo "progress \$n" >> progress.txt
git add progress.txt
git commit -qm "progress \$n"
if [[ "\$n" -eq 5 ]]; then
  printf 'ERROR: a totally different failure on the 5th pass\n'
else
  printf 'ERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\n'
fi
exit 1
STUBEOF
chmod +x "$CB2_CTRL_DIR/_loop/stub-cb2-control.sh"

cb2_ctrl_log="$TMP/cb2-control-run.log"
( cd "$CB2_CTRL_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$CB2_CTRL_DIR/_loop/stub-cb2-control.sh" bash ./_loop/loop.sh 5 ) \
  >"$cb2_ctrl_log" 2>&1
cb2_ctrl_rc=$?

if [[ "$cb2_ctrl_rc" -eq 1 ]] && ! grep -qF 'circuit breaker: same error 5 times' "$cb2_ctrl_log" \
   && grep -qF 'max iterations (5) reached' "$cb2_ctrl_log"; then
  report PASS "52: per-slot CB2 control -- 4 identical + 1 DIFFERENT failure -> same-error counter resets, run does NOT exit 3 (exhausts MAX_ITER, exits 1)"
else
  report FAIL "52: per-slot CB2 control" "rc=$cb2_ctrl_rc(expected 1)"
  sed 's/^/    /' "$cb2_ctrl_log" >&2
fi

# ---------------------------------------------------------------------------
# 53: ps1 structural parity, block-scoped (assertion-18/34 coupling
# precedent) against the CANONICAL loop.ps1 -- not runtime-verified, pwsh
# absent, same disposition as this file's other ps1 structural guards.
# ---------------------------------------------------------------------------
t53_slots_check() { # $env:LOOP_SLOTS read + clamp, block-scoped
  local f="$1" ln window
  ln="$(grep -n '\$SlotsRaw = \$env:LOOP_SLOTS' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 10))p" "$f")"
  grep -qF '$Slots -lt 1' <<< "$window" && grep -qF '$Slots -gt 3' <<< "$window"
}
t53_worktree_check() { grep -qF '$env:LOOP_WORKTREE' "$1"; }
t53_guard_msg_check() { grep -qF 'LOOP_SLOTS>1 requires LOOP_WORKTREE=1' "$1"; }
t53_preflight_check() { # two-path preflight, block-scoped
  local f="$1" ln window
  ln="$(grep -n 'backlogOk = Test-Path' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 6))p" "$f")"
  grep -qF 'ideDirOk = Test-Path' <<< "$window" && grep -qF 'PathType Container' <<< "$window"
}
t53_startjob_wait_check() { # Start-Job dispatch + Wait-Job reap -- RE-ANCHORED
  # (task 05, STORY-011 restructure note): task 03's fill/reap split moved
  # Wait-Job out of Start-Job's own neighborhood (dispatch and reap are now
  # separate functions, mirroring the bash twin's _loop_fill_slot/
  # _loop_reap_slot split), so a small fixed-line window from Start-Job no
  # longer reaches it. Re-scoped to each mechanic's OWN function: Start-Job
  # anywhere (dispatch exists) + Wait-Job inside Invoke-LoopReapSlot's own
  # body (reap actually waits for the job).
  local f="$1" ln window
  grep -qF 'Start-Job -ScriptBlock' "$f" || return 1
  ln="$(grep -n 'function Invoke-LoopReapSlot' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 40))p" "$f")"
  grep -qF 'Wait-Job' <<< "$window"
}
t53_removal_ordering_check() { # wait-then-remove comment + --force/prune fallback
  local f="$1" ln window
  ln="$(grep -n 'Windows removal ordering' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 12))p" "$f")"
  grep -qF 'Wait-Job' <<< "$window" || return 1
  grep -qF -- '--force' "$f" && grep -qF 'prune' "$f"
}
t53_abnormal_check() { # abnormal-exit branch, block-scoped -- anchor updated
  # (task 05): the message interpolates $Slot BETWEEN "slot" and "exited"
  # ("slot $Slot exited abnormally"), so the old literal 'slot exited
  # abnormally' (no variable) never matches; anchored on the
  # variable-agnostic remainder 'exited abnormally' instead, window widened
  # to reach the retainedBranches append a few lines later.
  # WINDOW RE-WIDENED (STORY-012 task 06, red-window repair -- harness-lag,
  # not a regression): task 02's D4 quarantine-marker call
  # (Write-LoopQuarantineMarker) landed BETWEEN the abnormal-exit message and
  # the pre-existing `$script:retainedBranches +=` append, pushing the append
  # from anchor+10 to anchor+11 (measured against the shipped file) -- one
  # line past the old anchor+10 window ceiling. Widened to anchor+12 (>= the
  # goal's required anchor+12 floor) for margin against any further
  # single-line insertion in that block.
  local f="$1" ln window
  ln="$(grep -n 'exited abnormally' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 12))p" "$f")"
  grep -qF 'retainedBranches +=' <<< "$window"
}
t53_capacity_check() { grep -qF 'Capacity-contention rationale' "$1"; }
t53_exit5_check() { grep -qF 'Exit 5 = setup or integration failure' "$1"; }
# New mechanics (STORY-011): block-scoped checks anchored on each construct's
# own function/call site (not whole-file single-token greps).
t53_parser_check() { # ConvertTo-LoopBacklogEntry: function defined with param block
  local f="$1" ln window
  ln="$(grep -n 'function ConvertTo-LoopBacklogEntry' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 5))p" "$f")"
  grep -qF 'param(' <<< "$window"
}
t53_admission_fn_check() { # Select-LoopStory: function + conflict calls inside body
  local f="$1" ln window
  ln="$(grep -n 'function Select-LoopStory' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 40))p" "$f")"
  grep -qF 'Test-LoopWritesConflict' <<< "$window" && grep -qF 'Test-LoopHotspotConflict' <<< "$window"
}
t53_claim_hashtable_check() { # $slots[Slot].Story and .Writes assigned on consecutive rows
  local f="$1" ln window
  ln="$(grep -n '\$slots\[.*\]\.Story = ' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 3))p" "$f")"
  grep -qF '.Story =' <<< "$window" && grep -qF '.Writes =' <<< "$window"
}
t53_substitution_check() { # Replace('%%STORY_ID%%'...) and Replace('%%OUTBOX_DIR%%'...) at substitution site
  local f="$1" ln window
  ln="$(grep -n "Replace.*'%%STORY_ID%%'" "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 2))p" "$f")"
  grep -qF '%%STORY_ID%%' <<< "$window" && grep -qF '%%OUTBOX_DIR%%' <<< "$window"
}
t53_integrator_mismatch_check() { # $mismatch = $true scoped to ITERATION-validation block (anchored on $mismatch = $false)
  local f="$1" ln window
  ln="$(grep -n '\$mismatch = \$false' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 20))p" "$f")"
  grep -qF '$mismatch = $true' <<< "$window"
}
t53_subset_check() { # Get-LoopSubsetViolation at its pre-merge call site, gated on $mismatch
  local f="$1" ln window
  ln="$(grep -n 'Get-LoopSubsetViolation.*-Tree' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "$((ln - 2)),$((ln + 2))p" "$f")"
  grep -qF 'Get-LoopSubsetViolation' <<< "$window" && grep -qF '$mismatch' <<< "$window"
}
t53_prune_gate_check() { # $pruneRc = $LASTEXITCODE after git worktree prune
  local f="$1" ln window
  ln="$(grep -n '\$pruneRc = \$LASTEXITCODE' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "$((ln - 1)),$((ln + 3))p" "$f")"
  grep -qF 'worktree prune' <<< "$window" && grep -qF '$pruneRc' <<< "$window"
}
t53_guard_replacement_check() { # $LoopSlotsExplicit = $env:LOOP_SLOTS, coupled to guard message in same block
  local f="$1" ln window
  ln="$(grep -n '\$LoopSlotsExplicit = \$env:LOOP_SLOTS' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 50))p" "$f")"
  grep -qF '$LoopSlotsExplicit' <<< "$window" && grep -qF 'LOOP_SLOTS>1' <<< "$window"
}

if t53_slots_check "$LOOP_PS1" && t53_worktree_check "$LOOP_PS1" && t53_guard_msg_check "$LOOP_PS1" \
   && t53_preflight_check "$LOOP_PS1" && t53_startjob_wait_check "$LOOP_PS1" \
   && t53_removal_ordering_check "$LOOP_PS1" && t53_abnormal_check "$LOOP_PS1" \
   && t53_capacity_check "$LOOP_PS1" && t53_exit5_check "$LOOP_PS1" \
   && t53_parser_check "$LOOP_PS1" && t53_admission_fn_check "$LOOP_PS1" \
   && t53_claim_hashtable_check "$LOOP_PS1" && t53_substitution_check "$LOOP_PS1" \
   && t53_integrator_mismatch_check "$LOOP_PS1" && t53_subset_check "$LOOP_PS1" \
   && t53_prune_gate_check "$LOOP_PS1" && t53_guard_replacement_check "$LOOP_PS1"; then
  report PASS "53: ps1 structural parity -- \$env:LOOP_SLOTS+clamp, \$env:LOOP_WORKTREE, the STORY-011 guard message, the two-path preflight (backlogOk/ideDirOk, Container test), Start-Job/Wait-Job, removal ordering (wait-then-remove + --force/prune fallback), the abnormal-exit branch (retainedBranches +=), the capacity-contention comment, the appended exit-5 sentence, AND new mechanics (parser ConvertTo-LoopBacklogEntry, admission Select-LoopStory, claim-hashtable \$slots[...].Story, %%STORY_ID%%/%%OUTBOX_DIR%% substitution, integrator \$mismatch, subset-check Get-LoopSubsetViolation, prune-gate \$pruneRc, guard-replacement \$LoopSlotsExplicit) all present in canonical loop.ps1 -- not runtime-verified, pwsh absent"
else
  report FAIL "53: ps1 structural parity" \
    "slots=$(t53_slots_check "$LOOP_PS1" && echo ok || echo FAIL) worktree=$(t53_worktree_check "$LOOP_PS1" && echo ok || echo FAIL) guard_msg=$(t53_guard_msg_check "$LOOP_PS1" && echo ok || echo FAIL) preflight=$(t53_preflight_check "$LOOP_PS1" && echo ok || echo FAIL) startjob_wait=$(t53_startjob_wait_check "$LOOP_PS1" && echo ok || echo FAIL) removal_ordering=$(t53_removal_ordering_check "$LOOP_PS1" && echo ok || echo FAIL) abnormal=$(t53_abnormal_check "$LOOP_PS1" && echo ok || echo FAIL) capacity=$(t53_capacity_check "$LOOP_PS1" && echo ok || echo FAIL) exit5=$(t53_exit5_check "$LOOP_PS1" && echo ok || echo FAIL) parser=$(t53_parser_check "$LOOP_PS1" && echo ok || echo FAIL) admission=$(t53_admission_fn_check "$LOOP_PS1" && echo ok || echo FAIL) claim=$(t53_claim_hashtable_check "$LOOP_PS1" && echo ok || echo FAIL) subst=$(t53_substitution_check "$LOOP_PS1" && echo ok || echo FAIL) mismatch=$(t53_integrator_mismatch_check "$LOOP_PS1" && echo ok || echo FAIL) subset=$(t53_subset_check "$LOOP_PS1" && echo ok || echo FAIL) prune=$(t53_prune_gate_check "$LOOP_PS1" && echo ok || echo FAIL) guard_rep=$(t53_guard_replacement_check "$LOOP_PS1" && echo ok || echo FAIL)"
fi

# ===========================================================================
# 54-70+: STORY-011 new driver mechanics -- selection/prompt pinning/guard
# replacement/structural/chain[fallbackIndex]/mid-path glob/refused-ids/
# integrator/admission(a-e)/subset-check. Every mechanic has a behavioral or
# structural assertion; mutation-proven where the task file requires it.
# ===========================================================================

# ---------------------------------------------------------------------------
# 54: Selection -- priority order, eligibility filter, attempts incremented
# driver-side BEFORE stub runs, passes:true driver-written. Sandbox (main-
# tree mode) with 4 stories: STORY-101 (priority=1, eligible), STORY-102
# (priority=2, passes=true -> ineligible), STORY-103 (priority=3,
# attempts=3 -> ineligible), STORY-104 (priority=4, eligible).
# MAX_ITER=1 to dispatch exactly one story; assert STORY-101 dispatched.
# ---------------------------------------------------------------------------
SEL_DIR="$TMP/selection-sandbox"
rm -rf "$SEL_DIR"; mkdir -p "$SEL_DIR"
sandbox_write_loop "$SEL_DIR" ".claude"
(
  cd "$SEL_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "sel-test"
  mkdir -p _goals .claude
  cat > _goals/backlog.md << 'EOF'
# backlog

## STORY-101: first eligible by priority
- priority: 1
- passes: false
- attempts: 0
- blocked: false

## STORY-102: passes=true, ineligible
- priority: 2
- passes: true
- attempts: 1
- blocked: false

## STORY-103: attempts=3, ineligible
- priority: 3
- passes: false
- attempts: 3
- blocked: false

## STORY-104: second eligible (lower priority)
- priority: 4
- passes: false
- attempts: 0
- blocked: false
EOF
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

sel_dispatched_file="$TMP/sel-dispatched.txt"
sel_attempts_file="$TMP/sel-attempts-at-dispatch.txt"
rm -f "$sel_dispatched_file" "$sel_attempts_file"
cat > "$SEL_DIR/_loop/stub-sel.sh" <<STUBEOF
#!/usr/bin/env bash
# Record story id; read attempts from backlog AT DISPATCH TIME (driver increments
# attempts at claim, before the stub runs -- this proves the ordering).
story_id="\$(echo "\$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "\$story_id" >> "$sel_dispatched_file"
# cwd == sandbox root in main-tree mode; _goals/backlog.md is accessible directly
grep -A5 "## \$story_id" _goals/backlog.md 2>/dev/null | grep -oE 'attempts: [0-9]+' | head -1 \
  >> "$sel_attempts_file"
echo "ITERATION: \$story_id passed"
exit 0
STUBEOF
chmod +x "$SEL_DIR/_loop/stub-sel.sh"

( cd "$SEL_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$SEL_DIR/_loop/stub-sel.sh" bash ./_loop/loop.sh 1 ) >/dev/null 2>&1

dispatched_id="$(cat "$sel_dispatched_file" 2>/dev/null | head -1)"
priority_ok=0
[[ "$dispatched_id" == "STORY-101" ]] && priority_ok=1
attempts_ok=0
grep -A5 '## STORY-101' "$SEL_DIR/_goals/backlog.md" 2>/dev/null | grep -q 'attempts: 1' \
  && attempts_ok=1
passes_ok=0
grep -A5 '## STORY-101' "$SEL_DIR/_goals/backlog.md" 2>/dev/null | grep -q 'passes: true' \
  && passes_ok=1
elig_filter_ok=0
[[ "$dispatched_id" != "STORY-102" && "$dispatched_id" != "STORY-103" ]] && elig_filter_ok=1
# Ordering proof: stub saw attempts: 1 AT dispatch time (claim precedes stub invocation)
attempts_before_dispatch_ok=0
grep -qF 'attempts: 1' "$sel_attempts_file" 2>/dev/null && attempts_before_dispatch_ok=1

if [[ "$priority_ok" -eq 1 && "$attempts_ok" -eq 1 && "$passes_ok" -eq 1 && "$elig_filter_ok" -eq 1 \
      && "$attempts_before_dispatch_ok" -eq 1 ]]; then
  report PASS "54: selection (priority order + eligibility filter + attempts/passes driver-written) -- STORY-101 (priority=1) dispatched, STORY-102 (passes=true) and STORY-103 (attempts=3) correctly skipped, stub observed attempts:1 AT dispatch time (proves claim-before-run ordering), passes:true written after success"
else
  report FAIL "54: selection" \
    "priority_ok=$priority_ok attempts_ok=$attempts_ok passes_ok=$passes_ok elig_filter_ok=$elig_filter_ok attempts_before_dispatch_ok=$attempts_before_dispatch_ok dispatched='$dispatched_id'"
fi

# ---------------------------------------------------------------------------
# 55: Prompt pinning -- stub receives the substituted story id + outbox dir;
# assert both %%STORY_ID%% and %%OUTBOX_DIR%% are ABSENT in the received
# prompt (substitution actually happened), and that the actual story id IS
# present. Uses the same selection sandbox (post-54 run has STORY-101 done;
# STORY-104 is the only eligible story for a second run, proving the
# substitution uses the actual dispatched story, not a static token).
# ---------------------------------------------------------------------------
PINNING_DIR="$TMP/pinning-sandbox"
rm -rf "$PINNING_DIR"; mkdir -p "$PINNING_DIR"
sandbox_write_loop "$PINNING_DIR" ".claude"
(
  cd "$PINNING_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "pinning-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n## STORY-201: pinning test story\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

pinning_received="$TMP/pinning-received-prompt.txt"
rm -f "$pinning_received"
cat > "$PINNING_DIR/_loop/stub-pinning.sh" <<STUBEOF
#!/usr/bin/env bash
# Write the full received prompt to a file for the harness to inspect
printf '%s' "\$1" > "$pinning_received"
story_id="\$(echo "\$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "ITERATION: \$story_id passed"
exit 0
STUBEOF
chmod +x "$PINNING_DIR/_loop/stub-pinning.sh"

( cd "$PINNING_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$PINNING_DIR/_loop/stub-pinning.sh" bash ./_loop/loop.sh 1 ) >/dev/null 2>&1

pin_no_story_token=1; pin_no_outbox_token=1; pin_has_story_id=0; pin_has_outbox_path=0
if [[ -f "$pinning_received" ]]; then
  received_prompt="$(cat "$pinning_received")"
  grep -qF '%%STORY_ID%%' "$pinning_received" && pin_no_story_token=0
  grep -qF '%%OUTBOX_DIR%%' "$pinning_received" && pin_no_outbox_token=0
  grep -qF 'STORY-201' "$pinning_received" && pin_has_story_id=1
  grep -qE '/tmp/' "$pinning_received" && pin_has_outbox_path=1
fi
if [[ "$pin_no_story_token" -eq 1 && "$pin_no_outbox_token" -eq 1 \
      && "$pin_has_story_id" -eq 1 && "$pin_has_outbox_path" -eq 1 ]]; then
  report PASS "55: prompt pinning -- %%STORY_ID%% and %%OUTBOX_DIR%% absent in received prompt (substitution happened), STORY-201 id and actual outbox path present"
else
  report FAIL "55: prompt pinning" \
    "no_story_token=$pin_no_story_token no_outbox_token=$pin_no_outbox_token has_story_id=$pin_has_story_id has_outbox_path=$pin_has_outbox_path"
fi

# ---------------------------------------------------------------------------
# 56: Guard replacement -- LOOP_SLOTS=2 + LOOP_WORKTREE=1 -> effective 2,
# banner "slots: 2 (mode: worktree)", no guard warning. Completes the guard-
# replacement coverage (37-40 cover the flag=0 and unset cases; this is the
# flag=1 N>1 ACTIVATION case — guard does NOT apply when WORKTREE=1).
# ---------------------------------------------------------------------------
( cd "$CLAMP_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 bash ./_loop/loop.sh 0 ) \
  >"$TMP/guard56_out.txt" 2>"$TMP/guard56_err.txt"
guard56_out="$(cat "$TMP/guard56_out.txt")"
guard56_err="$(cat "$TMP/guard56_err.txt")"
if grep -qF 'slots: 2 (mode: worktree)' <<< "$guard56_out" \
   && ! grep -qF 'requires LOOP_WORKTREE=1' <<< "$guard56_err"; then
  report PASS "56: guard replacement -- LOOP_SLOTS=2 + LOOP_WORKTREE=1 -> effective 2, banner 'slots: 2 (mode: worktree)', no guard warning (N>1 activation path, guard does not fire)"
else
  report FAIL "56: guard replacement (LOOP_SLOTS=2 + LOOP_WORKTREE=1)" \
    "stdout='$guard56_out' stderr='$guard56_err'"
fi

# ---------------------------------------------------------------------------
# 57: §3.2-part-4 structural -- no breaker_* call inside the child subshell
# block (driver/child boundary pin: the child only cd's + runs the CLI, the
# breaker calls live OUTSIDE at driver level). Block-scoped on the child
# subshell's CLI invocation line in canonical loop.sh and canonical loop.ps1
# (the Start-Job scriptblock is also breaker-free by construction).
# ---------------------------------------------------------------------------
t57_no_breaker_in_bash_child() {
  local f="$1" ln window
  ln="$(grep -n '\$LOOP_CLI \$model_arg "\$p" > "\$out_file"' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "$((ln - 3)),$((ln + 3))p" "$f")"
  ! grep -qF 'breaker_' <<< "$window"
}
t57_no_breaker_in_ps1_job() {
  # The Start-Job scriptblock in loop.ps1 should not contain breaker calls
  local f="$1" ln window
  ln="$(grep -n 'Start-Job -ScriptBlock' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 10))p" "$f")"
  ! grep -qF 'breaker' <<< "$window"
}
if t57_no_breaker_in_bash_child "$LOOP_SH" && t57_no_breaker_in_ps1_job "$LOOP_PS1"; then
  report PASS "57: §3.2-part-4 structural -- no breaker_* call inside the bash child subshell (CLI-invocation window) and no breaker call inside the ps1 Start-Job scriptblock; boundary discipline intact after dispatch restructure"
else
  report FAIL "57: §3.2-part-4 structural" \
    "bash_child=$(t57_no_breaker_in_bash_child "$LOOP_SH" && echo ok || echo FAIL) ps1_job=$(t57_no_breaker_in_ps1_job "$LOOP_PS1" && echo ok || echo FAIL)"
fi

# ---------------------------------------------------------------------------
# 58 + 58-mutation-proof: chain[fallbackIndex] fixture (standing note, attaches
# here). A valid OPEN state file with currentModel KEY ABSENT + fallbackIndex=2
# (non-zero) -> fail-safe derives chain[2] (not chain[0]).
# Mutation-prove: a blind-chain[0] mutant of a COPY of breaker.sh (where the
# fail-safe always uses entries[0] regardless of fallbackIndex) -> fixture
# model becomes "modelA" (chain[0]), not "modelC" (chain[2]) -> assertion FAILS
# on the mutant, confirming the guard is load-bearing.
# ---------------------------------------------------------------------------
S58="$TMP/chainfix-absent-model.json"
{
  printf '{\n'
  printf '"state": "OPEN",\n'
  printf '"chain": "modelA,modelB,modelC,modelD",\n'
  printf '"fallbackIndex": 2,\n'
  printf '"cooldownSeconds": 600,\n'
  printf '"openedAt": 1000000,\n'
  printf '"halfOpenSuccesses": 0,\n'
  printf '"totalFallbacks": 3,\n'
  printf '"totalRecoveries": 1\n'
  printf '}\n'
} > "$S58"
T58=2000000
stderr58="$TMP/58-stderr.txt"
breaker_load "$S58" "modelA,modelB,modelC,modelD" "$T58" 2>"$stderr58"
model58="$(_breaker_get "$S58" currentModel)"
warn_count58="$(wc -l < "$stderr58")"

if [[ "$model58" == "modelC" && "$warn_count58" -eq 1 \
      && "$(grep -c 'failing SAFE to OPEN' "$stderr58")" -eq 1 ]]; then
  report PASS "58: chain[fallbackIndex] fixture -- valid OPEN state with currentModel KEY ABSENT + fallbackIndex=2 -> fail-safe derives chain[2]=modelC (not chain[0]=modelA), one warning 'failing SAFE to OPEN'"
else
  report FAIL "58: chain[fallbackIndex] fixture" \
    "model=$model58(expected modelC) warn_count=$warn_count58(expected 1) stderr='$(cat "$stderr58")'"
fi

# 58-mutation-proof: blind-chain[0] mutant always uses entries[0], ignoring
# fallbackIndex -> model becomes modelA, proving assertion 58 would FAIL.
MUT58_BREAKER="$TMP/breaker-blind-chain0-mutant.sh"
awk '
  /if \(\( idx < \$\{#entries\[@\]\} \)\); then$/ && !done {
    print "  if (( ${#entries[@]} > 0 )); then   # mutation: blind-chain[0] (always entries[0])"
    print "    model=\"${entries[0]}\""
    skip_lines = 2; done = 1; next
  }
  skip_lines > 0 { skip_lines--; next }
  { print }
' "$BREAKER_SH" > "$MUT58_BREAKER"
chmod +x "$MUT58_BREAKER"
S58_MUT="$TMP/chainfix-mut-model.json"
{
  printf '{\n'
  printf '"state": "OPEN",\n'
  printf '"chain": "modelA,modelB,modelC,modelD",\n'
  printf '"fallbackIndex": 2,\n'
  printf '"cooldownSeconds": 600,\n'
  printf '"openedAt": 1000000,\n'
  printf '"halfOpenSuccesses": 0,\n'
  printf '"totalFallbacks": 3,\n'
  printf '"totalRecoveries": 1\n'
  printf '}\n'
} > "$S58_MUT"
bash -c "source '$MUT58_BREAKER'; breaker_load '$S58_MUT' 'modelA,modelB,modelC,modelD' '$T58'" \
  2>/dev/null
model58_mut="$(_breaker_get "$S58_MUT" currentModel)"
mut58_flipped=0
[[ "$model58_mut" != "modelC" ]] && mut58_flipped=1

if [[ "$mut58_flipped" -eq 1 ]]; then
  report PASS "58-mutation-proof: blind-chain[0] mutant of breaker.sh (COPY) -> fail-safe derives chain[0]=$model58_mut (NOT chain[2]=modelC) -- proves assertion 58 would FAIL on the mutant, making the guard load-bearing"
else
  report FAIL "58-mutation-proof: blind-chain[0] mutant" \
    "expected model != modelC but got model=$model58_mut"
fi

# ---------------------------------------------------------------------------
# 59: Mid-path glob rejection -- a story declaring `skills/*/SKILL.md` (a
# `*` NOT in a trailing position) triggers a loud parse rejection naming
# story+glob; the story runs alone (treated as writes-absent) -- not refused
# or skipped, just admitted in isolation with a stderr note.
# ---------------------------------------------------------------------------
MIDGLOB_DIR="$TMP/midglob-sandbox"
rm -rf "$MIDGLOB_DIR"; mkdir -p "$MIDGLOB_DIR"
sandbox_write_loop "$MIDGLOB_DIR" ".claude"
(
  cd "$MIDGLOB_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "midglob-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n## STORY-301: mid-path glob story\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: skills/*/SKILL.md\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

midglob_log="$TMP/midglob-run.log"
cat > "$MIDGLOB_DIR/_loop/stub-midglob.sh" <<'STUBEOF'
#!/usr/bin/env bash
story_id="$(echo "$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "ITERATION: $story_id passed"
exit 0
STUBEOF
chmod +x "$MIDGLOB_DIR/_loop/stub-midglob.sh"

( cd "$MIDGLOB_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$MIDGLOB_DIR/_loop/stub-midglob.sh" bash ./_loop/loop.sh 1 ) \
  >"$TMP/midglob-stdout.txt" 2>"$midglob_log"

midglob_names_story=0
grep -qF 'STORY-301' "$midglob_log" && midglob_names_story=1
midglob_names_glob=0
grep -qF 'skills/*/SKILL.md' "$midglob_log" && midglob_names_glob=1
midglob_dispatched=0
grep -qF 'STORY-301' "$TMP/midglob-stdout.txt" && midglob_dispatched=1

if [[ "$midglob_names_story" -eq 1 && "$midglob_names_glob" -eq 1 \
      && "$midglob_dispatched" -eq 1 ]]; then
  report PASS "59: mid-path glob rejection -- story declaring 'skills/*/SKILL.md' triggers loud parse rejection naming story+glob (stderr names both), story still dispatched (writes-absent treatment, runs alone)"
else
  report FAIL "59: mid-path glob rejection" \
    "names_story=$midglob_names_story names_glob=$midglob_names_glob dispatched=$midglob_dispatched"
  sed 's/^/    /' "$midglob_log" >&2
fi

# ---------------------------------------------------------------------------
# 60: Refused-ids completion visibility -- a run whose ONLY story has a
# protected-path writes: (_loop/) -> exit 0 (completion, not an error) AND
# the no-eligible completion output names the refused story id. No attempts
# increment (assert backlog unchanged after run).
# ---------------------------------------------------------------------------
REFUSEDCOMP_DIR="$TMP/refusedcomp-sandbox"
rm -rf "$REFUSEDCOMP_DIR"; mkdir -p "$REFUSEDCOMP_DIR"
sandbox_write_loop "$REFUSEDCOMP_DIR" ".claude"
(
  cd "$REFUSEDCOMP_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "refused-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n## STORY-401: protected-path story\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: _loop/loop.sh\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

backlog_sha_before="$(sha256sum "$REFUSEDCOMP_DIR/_goals/backlog.md" | cut -d' ' -f1)"
refusedcomp_out="$TMP/refusedcomp-stdout.txt"
refusedcomp_err="$TMP/refusedcomp-stderr.txt"
( cd "$REFUSEDCOMP_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    bash ./_loop/loop.sh 1 ) >"$refusedcomp_out" 2>"$refusedcomp_err"
refusedcomp_rc=$?
backlog_sha_after="$(sha256sum "$REFUSEDCOMP_DIR/_goals/backlog.md" | cut -d' ' -f1)"

refusedcomp_exit0=0; [[ "$refusedcomp_rc" -eq 0 ]] && refusedcomp_exit0=1
refusedcomp_names_id=0
grep -qF 'STORY-401' "$refusedcomp_out" && refusedcomp_names_id=1
refusedcomp_names_refused_stderr=0
grep -qF 'STORY-401' "$refusedcomp_err" && grep -qF 'REFUSED' "$refusedcomp_err" \
  && refusedcomp_names_refused_stderr=1
refusedcomp_backlog_unchanged=0
[[ "$backlog_sha_before" == "$backlog_sha_after" ]] && refusedcomp_backlog_unchanged=1

if [[ "$refusedcomp_exit0" -eq 1 && "$refusedcomp_names_id" -eq 1 \
      && "$refusedcomp_names_refused_stderr" -eq 1 && "$refusedcomp_backlog_unchanged" -eq 1 ]]; then
  report PASS "60: refused-ids completion visibility -- run with only a protected-path story (STORY-401, writes:_loop/loop.sh) -> exit 0 (completion), stdout names STORY-401 as refused, stderr loud REFUSED notice, backlog unchanged (no attempts increment)"
else
  report FAIL "60: refused-ids completion visibility" \
    "exit0=$refusedcomp_exit0 names_id=$refusedcomp_names_id names_refused_stderr=$refusedcomp_names_refused_stderr backlog_unchanged=$refusedcomp_backlog_unchanged"
fi

# ---------------------------------------------------------------------------
# 61: Integrator -- passes/blocked transitions driver-written, verified by
# content; also covers ITERATION-mismatch -> no backlog transition (story
# fields unchanged). One sandbox, two runs:
#   Run A: stub emits ITERATION: STORY-501 passed -> driver writes passes:true
#   Run B: stub emits ITERATION: STORY-502 blocked -> driver writes blocked:true
# A third story (STORY-503) in the backlog has NO eligible run (the stub for
# run A doesn't dispatch it); checked only to confirm driver leaves it alone.
# ---------------------------------------------------------------------------
INTEG_DIR="$TMP/integrator-sandbox"
rm -rf "$INTEG_DIR"; mkdir -p "$INTEG_DIR"
sandbox_write_loop "$INTEG_DIR" ".claude"
(
  cd "$INTEG_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "integ-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n'
    printf '## STORY-501: will be passed\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n\n'
    printf '## STORY-502: will be blocked\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n\n'
    printf '## STORY-503: untouched\n'
    printf -- '- priority: 3\n- passes: false\n- attempts: 0\n- blocked: false\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)
# Stub: cycles through stories in dispatch order, emitting appropriate verdicts
cat > "$INTEG_DIR/_loop/stub-integ.sh" <<'STUBEOF'
#!/usr/bin/env bash
story_id="$(echo "$1" | grep -oE 'STORY-[0-9]+' | head -1)"
case "$story_id" in
  STORY-501) echo "ITERATION: STORY-501 passed"; exit 0 ;;
  STORY-502) echo "ITERATION: STORY-502 blocked"; exit 0 ;;
  *)         echo "ITERATION: $story_id passed"; exit 0 ;;
esac
STUBEOF
chmod +x "$INTEG_DIR/_loop/stub-integ.sh"

( cd "$INTEG_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$INTEG_DIR/_loop/stub-integ.sh" bash ./_loop/loop.sh 2 ) \
  >/dev/null 2>/dev/null

# Check transitions: passes:true for STORY-501, blocked:true for STORY-502
integ_passes_ok=0
grep -A5 '## STORY-501' "$INTEG_DIR/_goals/backlog.md" | grep -q 'passes: true' \
  && integ_passes_ok=1
integ_blocked_ok=0
grep -A5 '## STORY-502' "$INTEG_DIR/_goals/backlog.md" | grep -q 'blocked: true' \
  && integ_blocked_ok=1
# STORY-503 should be untouched (still passes:false, attempts:0)
integ_503_untouched=0
story503_passes="$(grep -A5 '## STORY-503' "$INTEG_DIR/_goals/backlog.md" | grep 'passes:' | head -1)"
story503_attempts="$(grep -A5 '## STORY-503' "$INTEG_DIR/_goals/backlog.md" | grep 'attempts:' | head -1)"
[[ "$story503_passes" == *"false"* && "$story503_attempts" == *": 0"* ]] && integ_503_untouched=1

if [[ "$integ_passes_ok" -eq 1 && "$integ_blocked_ok" -eq 1 && "$integ_503_untouched" -eq 1 ]]; then
  report PASS "61: integrator passes/blocked transitions driver-written -- STORY-501 verdict 'passed' -> passes:true in backlog (driver-written, not stub); STORY-502 verdict 'blocked' -> blocked:true; STORY-503 untouched (not dispatched in MAX_ITER=2)"
else
  report FAIL "61: integrator transitions" \
    "passes_ok=$integ_passes_ok blocked_ok=$integ_blocked_ok 503_untouched=$integ_503_untouched"
fi

# ---------------------------------------------------------------------------
# 62: ITERATION-mismatch -> quarantine-lite: story fields unchanged (no
# backlog transition), branch retained (flag=1 / LOOP_WORKTREE=1). Asserts
# the mismatch itself as well as that the backlog is bytewise unchanged after
# the quarantined run.
# ---------------------------------------------------------------------------
MISMATCH_DIR="$TMP/mismatch-sandbox"
make_sandbox "$MISMATCH_DIR" ".claude" 1 1

cat > "$MISMATCH_DIR/_loop/stub-mismatch.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Stub that emits the WRONG story id in its ITERATION line -> mismatch
echo "progress" > progress.txt
git add progress.txt
git commit -qm "mismatch-test progress"
echo "ITERATION: STORY-WRONG passed"
exit 0
STUBEOF
chmod +x "$MISMATCH_DIR/_loop/stub-mismatch.sh"
( cd "$MISMATCH_DIR" && git add -A && git commit -qm "add stub" )

mismatch_log="$TMP/mismatch-run.log"
( cd "$MISMATCH_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 \
    LOOP_CLI="$MISMATCH_DIR/_loop/stub-mismatch.sh" bash ./_loop/loop.sh 1 ) \
  >"$mismatch_log" 2>&1
mismatch_rc=$?

mismatch_logged=0
grep -qF 'ITERATION-mismatch' "$mismatch_log" && mismatch_logged=1
mismatch_branch_retained=0
[[ -n "$(git -C "$MISMATCH_DIR" branch --list 'loop/iter-1')" ]] && mismatch_branch_retained=1
# Story-scoped checks (house pattern: grep -A5 '## STORY-ID'):
# (a) attempts: 1 -- driver incremented at claim time before dispatch
# (b) passes: false -- no passes transition (mismatch quarantine skipped it)
# (c) blocked: false -- no blocked transition
mismatch_attempts_incremented=0
grep -A5 '## STORY-101' "$MISMATCH_DIR/_goals/backlog.md" | grep -qF 'attempts: 1' \
  && mismatch_attempts_incremented=1
mismatch_no_passes_transition=0
grep -A5 '## STORY-101' "$MISMATCH_DIR/_goals/backlog.md" | grep -qF 'passes: false' \
  && mismatch_no_passes_transition=1
mismatch_no_blocked_transition=0
grep -A5 '## STORY-101' "$MISMATCH_DIR/_goals/backlog.md" | grep -qF 'blocked: false' \
  && mismatch_no_blocked_transition=1

if [[ "$mismatch_logged" -eq 1 && "$mismatch_branch_retained" -eq 1 \
      && "$mismatch_attempts_incremented" -eq 1 \
      && "$mismatch_no_passes_transition" -eq 1 && "$mismatch_no_blocked_transition" -eq 1 ]]; then
  report PASS "62: ITERATION-mismatch quarantine-lite (flag=1) -- mismatch logged (wrong story id), branch loop/iter-1 retained, STORY-101 scoped: attempts:1 (claim at dispatch time), passes:false + blocked:false (no transition on mismatch, confirmed story-scoped)"
else
  report FAIL "62: ITERATION-mismatch quarantine" \
    "mismatch_logged=$mismatch_logged branch_retained=$mismatch_branch_retained attempts_incremented=$mismatch_attempts_incremented no_passes_transition=$mismatch_no_passes_transition no_blocked_transition=$mismatch_no_blocked_transition"
  sed 's/^/    /' "$mismatch_log" >&2
fi

# ---------------------------------------------------------------------------
# 63 + 63-mutation-proof: Subset-check violation -- stub commits a file
# OUTSIDE its declared writes: (_goals/extra.txt declared only src/widget.txt)
# -> quarantine-lite, loud naming of offending path, NOT integrated.
# Mutation-prove: delete the subset check in a COPY of loop.sh -> the
# violating branch integrates (observable as the offending commit landing on
# main), confirming the check is load-bearing.
# ---------------------------------------------------------------------------
SUBSET_DIR="$TMP/subset-sandbox"
rm -rf "$SUBSET_DIR"; mkdir -p "$SUBSET_DIR"
sandbox_write_loop "$SUBSET_DIR" ".claude"
(
  cd "$SUBSET_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "subset-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n## STORY-601: subset-check story\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/widget.txt\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

cat > "$SUBSET_DIR/_loop/stub-subset.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Commit a file OUTSIDE declares writes: (declared: src/widget.txt;
# actual commit: _goals/extra.txt -> subset violation)
mkdir -p _goals
echo "outside writes" > _goals/extra.txt
git add _goals/extra.txt
git commit -qm "subset-violation commit (outside declared writes:)"
story_id="$(echo "$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "ITERATION: $story_id passed"
exit 0
STUBEOF
chmod +x "$SUBSET_DIR/_loop/stub-subset.sh"

subset_main_before="$(git -C "$SUBSET_DIR" rev-parse HEAD)"
subset_log="$TMP/subset-run.log"
( cd "$SUBSET_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 \
    LOOP_CLI="$SUBSET_DIR/_loop/stub-subset.sh" bash ./_loop/loop.sh 1 ) \
  >"$subset_log" 2>&1
subset_main_after="$(git -C "$SUBSET_DIR" rev-parse HEAD)"

subset_quarantined=0
grep -qF 'touched paths outside its declared writes:' "$subset_log" && subset_quarantined=1
subset_names_path=0
grep -qF '_goals/extra.txt' "$subset_log" && subset_names_path=1
subset_not_integrated=0
[[ "$subset_main_before" == "$subset_main_after" ]] && subset_not_integrated=1

if [[ "$subset_quarantined" -eq 1 && "$subset_names_path" -eq 1 && "$subset_not_integrated" -eq 1 ]]; then
  report PASS "63: subset-check violation -- stub commits '_goals/extra.txt' outside declared 'writes: src/widget.txt' -> quarantine-lite (not integrated, main HEAD unchanged), loud naming of offending path"
else
  report FAIL "63: subset-check violation" \
    "quarantined=$subset_quarantined names_path=$subset_names_path not_integrated=$subset_not_integrated"
  sed 's/^/    /' "$subset_log" >&2
fi

# 63-mutation-proof: delete the subset check in a COPY of the sandbox driver
# -> the violating branch integrates (commit lands on main)
MUT63_DIR="$TMP/subset-sandbox-mut63"
rm -rf "$MUT63_DIR"; mkdir -p "$MUT63_DIR"
sandbox_write_loop "$MUT63_DIR" ".claude"
(
  cd "$MUT63_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "subset-mut-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n## STORY-601: subset-check story\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/widget.txt\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)
cp "$SUBSET_DIR/_loop/stub-subset.sh" "$MUT63_DIR/_loop/stub-subset.sh"
# Mutate loop.sh: remove the subset-violation early-exit by replacing the
# subset_bad computation with a forced-empty result (same approach as the
# content-anchored mutation proofs above).
awk '
  /subset_bad=.*_loop_subset_violation/ && !done {
    print "  subset_bad=\"\"   # mutation-63: subset check deleted"
    done = 1; next
  }
  { print }
' "$MUT63_DIR/_loop/loop.sh" > "$TMP/loop-mut63.sh"
mv "$TMP/loop-mut63.sh" "$MUT63_DIR/_loop/loop.sh"
chmod +x "$MUT63_DIR/_loop/loop.sh"

mut63_log="$TMP/subset-mut63-run.log"
( cd "$MUT63_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 \
    LOOP_CLI="$MUT63_DIR/_loop/stub-subset.sh" bash ./_loop/loop.sh 1 ) \
  >"$mut63_log" 2>&1
mut63_main_after="$(git -C "$MUT63_DIR" rev-parse HEAD)"
mut63_integrated=0
git -C "$MUT63_DIR" log --oneline | grep -qF "subset-violation commit" && mut63_integrated=1

if [[ "$mut63_integrated" -eq 1 ]]; then
  report PASS "63-mutation-proof: subset-check deleted in a COPY -> violating branch integrates (subset-violation commit lands on main), confirming the check is load-bearing"
else
  report FAIL "63-mutation-proof: subset-check delete did not integrate violating branch" \
    "integrated=$mut63_integrated"
  sed 's/^/    /' "$mut63_log" >&2
fi

# ---------------------------------------------------------------------------
# 64: Admission (e) -- protected-path writes: REFUSED loudly, no attempts
# increment, stderr names story+glob. The stub NEVER runs (no dispatch).
# (Covered structurally by assertion 60 for a run-as-only-story scenario;
# this asserts the specific stderr content and no-dispatch outcome.)
# ---------------------------------------------------------------------------
ADMIT_E_DIR="$TMP/admit-e-sandbox"
rm -rf "$ADMIT_E_DIR"; mkdir -p "$ADMIT_E_DIR"
sandbox_write_loop "$ADMIT_E_DIR" ".claude"
(
  cd "$ADMIT_E_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "admit-e-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n'
    printf '## STORY-701: protected-path story\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: _loop/loop.sh\n\n'
    printf '## STORY-702: normal story\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

admit_e_marker="$TMP/admit-e-stub-ran.marker"
rm -f "$admit_e_marker"
cat > "$ADMIT_E_DIR/_loop/stub-admit-e.sh" <<STUBEOF
#!/usr/bin/env bash
touch "$admit_e_marker"
story_id="\$(echo "\$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "ITERATION: \$story_id passed"
exit 0
STUBEOF
chmod +x "$ADMIT_E_DIR/_loop/stub-admit-e.sh"

admit_e_out="$TMP/admit-e-out.txt"
admit_e_err="$TMP/admit-e-err.txt"
backlog_before_e="$(sha256sum "$ADMIT_E_DIR/_goals/backlog.md" | cut -d' ' -f1)"
( cd "$ADMIT_E_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$ADMIT_E_DIR/_loop/stub-admit-e.sh" bash ./_loop/loop.sh 1 ) \
  >"$admit_e_out" 2>"$admit_e_err"

# STORY-701 should be refused (no dispatch for it); STORY-702 dispatched
e_refused_loud=0
grep -qF 'STORY-701' "$admit_e_err" && grep -qF 'REFUSED' "$admit_e_err" && e_refused_loud=1
e_no_attempts_increment=0
backlog_after_e="$(sha256sum "$ADMIT_E_DIR/_goals/backlog.md" | cut -d' ' -f1)"
# attempts for STORY-701 must remain 0 (no increment on refused story)
grep -A5 '## STORY-701' "$ADMIT_E_DIR/_goals/backlog.md" | grep -q 'attempts: 0' \
  && e_no_attempts_increment=1
# STORY-702 should have been dispatched (stub ran, marker exists)
e_702_dispatched=0
[[ -f "$admit_e_marker" ]] && e_702_dispatched=1

if [[ "$e_refused_loud" -eq 1 && "$e_no_attempts_increment" -eq 1 && "$e_702_dispatched" -eq 1 ]]; then
  report PASS "64: admission (e) -- STORY-701 with writes:_loop/loop.sh -> REFUSED loudly (stderr names story+REFUSED), no attempts increment (STORY-701 attempts stays 0), STORY-702 (non-protected) dispatched normally"
else
  report FAIL "64: admission (e) protected-path refused" \
    "refused_loud=$e_refused_loud no_attempts=$e_no_attempts_increment 702_dispatched=$e_702_dispatched"
fi

# ---------------------------------------------------------------------------
# 65: Admission (d) -- empty-writes story runs alone: a story with NO
# writes: field declared is treated as intersecting-everything, so a
# disjoint second story is NOT co-dispatched even with LOOP_SLOTS=2 +
# LOOP_WORKTREE=1. MAX_ITER=2: both stories complete serially (never
# concurrently). Inflight marker + bounded poll proves peak is always 1.
# ---------------------------------------------------------------------------
ADMIT_D_DIR="$TMP/admit-d-sandbox"
rm -rf "$ADMIT_D_DIR"; mkdir -p "$ADMIT_D_DIR"
sandbox_write_loop "$ADMIT_D_DIR" ".claude"
(
  cd "$ADMIT_D_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "admit-d-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n'
    printf '## STORY-801: empty-writes (runs alone)\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n\n'
    printf '## STORY-802: disjoint writes\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/widget.txt\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

admit_d_dispatched_file="$TMP/admit-d-dispatched.txt"
admit_d_inflight_dir="$TMP/admit-d-inflight"; mkdir -p "$admit_d_inflight_dir"
admit_d_overlap_log="$TMP/admit-d-overlap.txt"
rm -f "$admit_d_dispatched_file" "$admit_d_overlap_log"
cat > "$ADMIT_D_DIR/_loop/stub-admit-d.sh" <<STUBEOF
#!/usr/bin/env bash
sid="\$(echo "\$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "\$sid" >> "$admit_d_dispatched_file"
touch "${admit_d_inflight_dir}/inflight.\$\$"
c=0; while (( c < 25 )); do
  n=\$(ls "${admit_d_inflight_dir}"/inflight.* 2>/dev/null | wc -l)
  (( n >= 2 )) && break
  sleep 0.1; c=\$((c + 1))
done
echo "peak=\$(ls "${admit_d_inflight_dir}"/inflight.* 2>/dev/null | wc -l)" >> "$admit_d_overlap_log"
case "\$sid" in
  STORY-801) mkdir -p src; echo "p \$sid" > src/progress-801.txt; git add src/progress-801.txt ;;
  STORY-802) mkdir -p src; echo "p \$sid" > src/widget.txt; git add src/widget.txt ;;
  *) : ;;
esac
git commit -qm "dispatch of \$sid"
rm -f "${admit_d_inflight_dir}/inflight.\$\$"
echo "ITERATION: \$sid passed"
exit 0
STUBEOF
chmod +x "$ADMIT_D_DIR/_loop/stub-admit-d.sh"

# MAX_ITER=2: STORY-801 fills round 1 alone (absent writes: intersects everything,
# STORY-802 deferred); STORY-802 fills round 2 after STORY-801 integrates. Serial.
admit_d_log="$TMP/admit-d-run.log"
( cd "$ADMIT_D_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 \
    LOOP_CLI="$ADMIT_D_DIR/_loop/stub-admit-d.sh" bash ./_loop/loop.sh 2 ) \
  >"$TMP/admit-d-out.txt" 2>"$admit_d_log"

dispatched_d_count="$(wc -l < "$admit_d_dispatched_file" 2>/dev/null || echo 0)"
dispatched_d_head="$(head -1 "$admit_d_dispatched_file" 2>/dev/null)"
dispatched_d_tail="$(tail -1 "$admit_d_dispatched_file" 2>/dev/null)"
d_both_dispatched=0; d_order_ok=0; d_no_overlap=0
[[ "$dispatched_d_count" -eq 2 ]] && d_both_dispatched=1
[[ "$dispatched_d_head" == "STORY-801" && "$dispatched_d_tail" == "STORY-802" ]] && d_order_ok=1
grep -qF 'peak=2' "$admit_d_overlap_log" 2>/dev/null || d_no_overlap=1

if [[ "$d_both_dispatched" -eq 1 && "$d_order_ok" -eq 1 && "$d_no_overlap" -eq 1 ]]; then
  report PASS "65: admission (d) empty-writes runs alone -- STORY-801 (no writes:) dispatched first, STORY-802 (writes: src/widget.txt) deferred until STORY-801 completes; both dispatched serially (peak always 1, priority order preserved)"
else
  report FAIL "65: admission (d) empty-writes runs alone" \
    "both_dispatched=$d_both_dispatched(count=$dispatched_d_count) order_ok=$d_order_ok(head='$dispatched_d_head' tail='$dispatched_d_tail') no_overlap=$d_no_overlap"
  sed 's/^/    /' "$admit_d_log" >&2
fi

# ---------------------------------------------------------------------------
# 66 + 66-mutation-proof: Admission (b) -- INTERSECTING writes: -> only ONE
# dispatched per fill round (deferred-then-serial). Two stories both declare
# writes: src/shared.txt (intersection). LOOP_SLOTS=2, LOOP_WORKTREE=1.
# Mutation-prove: delete the admission check in a COPY -> BOTH stories
# dispatched concurrently (interleaved start markers observable).
# ---------------------------------------------------------------------------
ADMIT_B_DIR="$TMP/admit-b-sandbox"
rm -rf "$ADMIT_B_DIR"; mkdir -p "$ADMIT_B_DIR"
sandbox_write_loop "$ADMIT_B_DIR" ".claude"
(
  cd "$ADMIT_B_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "admit-b-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n'
    printf '## STORY-901: intersecting writes\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/shared.txt\n\n'
    printf '## STORY-902: same intersecting writes\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/shared.txt\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

admit_b_dispatched_file="$TMP/admit-b-dispatched.txt"
admit_b_inflight_dir="$TMP/admit-b-inflight"; mkdir -p "$admit_b_inflight_dir"
admit_b_overlap_log="$TMP/admit-b-overlap.txt"
rm -f "$admit_b_dispatched_file" "$admit_b_overlap_log"
cat > "$ADMIT_B_DIR/_loop/stub-admit-b.sh" <<STUBEOF
#!/usr/bin/env bash
sid="\$(echo "\$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "\$sid" >> "$admit_b_dispatched_file"
touch "${admit_b_inflight_dir}/inflight.\$\$"
c=0; while (( c < 25 )); do
  n=\$(ls "${admit_b_inflight_dir}"/inflight.* 2>/dev/null | wc -l)
  (( n >= 2 )) && break
  sleep 0.1; c=\$((c + 1))
done
echo "peak=\$(ls "${admit_b_inflight_dir}"/inflight.* 2>/dev/null | wc -l)" >> "$admit_b_overlap_log"
mkdir -p src; echo "p \$sid" > src/shared.txt; git add src/shared.txt
git commit -qm "progress from \$sid"
rm -f "${admit_b_inflight_dir}/inflight.\$\$"
echo "ITERATION: \$sid passed"
exit 0
STUBEOF
chmod +x "$ADMIT_B_DIR/_loop/stub-admit-b.sh"

# MAX_ITER=2: STORY-901 fills round 1 (STORY-902 deferred -- same writes: intersection);
# STORY-902 fills round 2 after STORY-901 integrates. Serial, never concurrent.
admit_b_log="$TMP/admit-b-run.log"
( cd "$ADMIT_B_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 \
    LOOP_CLI="$ADMIT_B_DIR/_loop/stub-admit-b.sh" bash ./_loop/loop.sh 2 ) \
  >/dev/null 2>"$admit_b_log"

dispatched_b_count="$(wc -l < "$admit_b_dispatched_file" 2>/dev/null || echo 0)"
dispatched_b_head="$(head -1 "$admit_b_dispatched_file" 2>/dev/null)"
dispatched_b_tail="$(tail -1 "$admit_b_dispatched_file" 2>/dev/null)"
# Both dispatched serially, priority order (901 first, 902 second), peak never 2
b_both_dispatched=0; b_order_ok=0; b_no_overlap=0
[[ "$dispatched_b_count" -eq 2 ]] && b_both_dispatched=1
[[ "$dispatched_b_head" == "STORY-901" && "$dispatched_b_tail" == "STORY-902" ]] && b_order_ok=1
grep -qF 'peak=2' "$admit_b_overlap_log" 2>/dev/null || b_no_overlap=1

if [[ "$b_both_dispatched" -eq 1 && "$b_order_ok" -eq 1 && "$b_no_overlap" -eq 1 ]]; then
  report PASS "66: admission (b) intersecting writes deferred-then-serial -- STORY-901 and STORY-902 both declare 'writes: src/shared.txt' (intersection); STORY-901 dispatched first, STORY-902 deferred until STORY-901 completes, both finish serially (peak always 1, priority order preserved)"
else
  report FAIL "66: admission (b) intersecting writes deferred" \
    "both_dispatched=$b_both_dispatched(count=$dispatched_b_count) order_ok=$b_order_ok(head='$dispatched_b_head' tail='$dispatched_b_tail') no_overlap=$b_no_overlap"
  sed 's/^/    /' "$admit_b_log" >&2
fi

# 66-mutation-proof: delete the admission conflict check in a COPY -> STORY-901
# dispatched to BOTH slots concurrently. Two discriminators per judge spec:
# (i) grep -q 'peak=2' overlap_log -- concurrent dispatch of intersecting stories
# (ii) sort -u dispatch_log == "STORY-901" -- double-claim, not STORY-902
# Both FAIL on the real driver (ids=[901,902], peaks=[1,1]) and HOLD on the mutant.
MUT66_DIR="$TMP/admit-b-sandbox-mut66"
rm -rf "$MUT66_DIR"; mkdir -p "$MUT66_DIR"
sandbox_write_loop "$MUT66_DIR" ".claude"
(
  cd "$MUT66_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "admit-b-mut66-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n'
    printf '## STORY-901: intersecting writes\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/shared.txt\n\n'
    printf '## STORY-902: same intersecting writes\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/shared.txt\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

mut66_dispatch_log="$TMP/mut66-dispatch.log"
mut66_inflight_dir="$TMP/mut66-inflight"; mkdir -p "$mut66_inflight_dir"
mut66_overlap_log="$TMP/mut66-overlap.txt"
rm -f "$mut66_dispatch_log" "$mut66_overlap_log"
cat > "$MUT66_DIR/_loop/stub-admit-b-mut.sh" <<STUBEOF
#!/usr/bin/env bash
story_id="\$(echo "\$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "\$story_id" >> "$mut66_dispatch_log"
touch "${mut66_inflight_dir}/inflight.\$\$"
c=0; while (( c < 25 )); do
  n=\$(ls "${mut66_inflight_dir}"/inflight.* 2>/dev/null | wc -l)
  (( n >= 2 )) && break
  sleep 0.1; c=\$((c + 1))
done
echo "peak=\$(ls "${mut66_inflight_dir}"/inflight.* 2>/dev/null | wc -l)" >> "$mut66_overlap_log"
mkdir -p src
echo "progress from \$story_id" > src/shared.txt
git add src/shared.txt
git commit -qm "progress from \$story_id"
rm -f "${mut66_inflight_dir}/inflight.\$\$"
echo "ITERATION: \$story_id passed"
exit 0
STUBEOF
chmod +x "$MUT66_DIR/_loop/stub-admit-b-mut.sh"

# Mutate loop.sh: remove the admission conflict check (writes/hotspot guard)
# by zeroing defer inside _loop_select_story's admission block.
awk '
  /if _loop_writes_conflict "\$writes" "\$\{slot_writes\[/ && !done {
    print "      # mutation-66: admission conflict check deleted"
    skip_lines = 4; done = 1; next
  }
  skip_lines > 0 { skip_lines--; next }
  { print }
' "$MUT66_DIR/_loop/loop.sh" > "$TMP/loop-mut66.sh"
mv "$TMP/loop-mut66.sh" "$MUT66_DIR/_loop/loop.sh"
chmod +x "$MUT66_DIR/_loop/loop.sh"

mut66_log="$TMP/admit-b-mut66-run.log"
# MAX_ITER=2: conflict check deleted -> STORY-901 fills BOTH slots in round 1
# (double-dispatch), both run concurrently producing peak=2.
( cd "$MUT66_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 \
    LOOP_CLI="$MUT66_DIR/_loop/stub-admit-b-mut.sh" bash ./_loop/loop.sh 2 ) \
  >/dev/null 2>"$mut66_log"

# Predicate (i): peak=2 observed (concurrent dispatch of intersecting stories)
mut66_peak_2=0; grep -qF 'peak=2' "$mut66_overlap_log" && mut66_peak_2=1
# Predicate (ii): only STORY-901 in dispatch log (double-claim, not STORY-902)
mut66_only_901=0
[[ "$(sort -u "$mut66_dispatch_log" 2>/dev/null)" == "STORY-901" ]] && mut66_only_901=1

if [[ "$mut66_peak_2" -eq 1 && "$mut66_only_901" -eq 1 ]]; then
  report PASS "66-mutation-proof: admission-check deleted in a COPY -> STORY-901 dispatched concurrently to BOTH slots (peak=2 in overlap log, sort-u dispatch log == 'STORY-901' proves double-claim), confirming the conflict guard is load-bearing against concurrent intersecting-writes dispatch"
else
  report FAIL "66-mutation-proof: admission-check delete did not yield concurrent dispatch" \
    "peak_2=$mut66_peak_2 only_901=$mut66_only_901"
  sed 's/^/    /' "$mut66_log" >&2
fi

# ---------------------------------------------------------------------------
# 67: Admission (a) -- DISJOINT writes: -> CONCURRENT dispatch (N=2 slots
# both filled in the same fill round). Two stories with disjoint writes:
# (src/foo.txt vs src/bar.txt). Stubs coordinate via marker files + bounded
# polling to prove they ran SIMULTANEOUSLY (STORY-010 (b)-fixture pattern
# extended). Both integrated, both passes:true, LEARNINGS carries outbox
# lines in reap order.
# ---------------------------------------------------------------------------
ADMIT_A_DIR="$TMP/admit-a-sandbox"
rm -rf "$ADMIT_A_DIR"; mkdir -p "$ADMIT_A_DIR"
sandbox_write_loop "$ADMIT_A_DIR" ".claude"
(
  cd "$ADMIT_A_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "admit-a-test"
  mkdir -p _goals .claude src
  {
    printf '# backlog\n\n'
    printf '## STORY-001A: disjoint-writes foo\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/foo.txt\n\n'
    printf '## STORY-002A: disjoint-writes bar\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: src/bar.txt\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

a_mark1="$TMP/admit-a-mark-001A.txt"
a_mark2="$TMP/admit-a-mark-002A.txt"
rm -f "$a_mark1" "$a_mark2"

cat > "$ADMIT_A_DIR/_loop/stub-admit-a.sh" <<STUBEOF
#!/usr/bin/env bash
story_id="\$(echo "\$1" | grep -oE 'STORY-[0-9A-Z]+' | head -1)"
outbox_dir="\$(echo "\$1" | sed 's/.*outbox \\([^;]*\\).*/\\1/')"
mark1="$a_mark1"
mark2="$a_mark2"

case "\$story_id" in
  STORY-001A)
    touch "\$mark1"
    # Bounded poll: wait up to 5s for STORY-002A's mark (proves overlap)
    count=0
    while [[ ! -f "\$mark2" ]] && (( count < 50 )); do
      sleep 0.1; count=\$((count + 1))
    done
    mkdir -p src; echo "foo" > src/foo.txt
    git add src/foo.txt; git commit -qm "progress from STORY-001A"
    [[ -n "\$outbox_dir" ]] && printf 'learning from slot-001A\n' > "\$outbox_dir/learnings.md"
    echo "ITERATION: STORY-001A passed"
    ;;
  STORY-002A)
    touch "\$mark2"
    count=0
    while [[ ! -f "\$mark1" ]] && (( count < 50 )); do
      sleep 0.1; count=\$((count + 1))
    done
    mkdir -p src; echo "bar" > src/bar.txt
    git add src/bar.txt; git commit -qm "progress from STORY-002A"
    [[ -n "\$outbox_dir" ]] && printf 'learning from slot-002A\n' > "\$outbox_dir/learnings.md"
    echo "ITERATION: STORY-002A passed"
    ;;
  *) echo "ITERATION: \$story_id passed" ;;
esac
exit 0
STUBEOF
chmod +x "$ADMIT_A_DIR/_loop/stub-admit-a.sh"

admit_a_log="$TMP/admit-a-run.log"
( cd "$ADMIT_A_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 \
    LOOP_CLI="$ADMIT_A_DIR/_loop/stub-admit-a.sh" bash ./_loop/loop.sh 2 ) \
  >"$TMP/admit-a-out.txt" 2>"$admit_a_log"
admit_a_rc=$?

a_both_markers=0; [[ -f "$a_mark1" && -f "$a_mark2" ]] && a_both_markers=1
a_both_integrated=0
git -C "$ADMIT_A_DIR" log --oneline 2>/dev/null | grep -qF "STORY-001A" \
  && git -C "$ADMIT_A_DIR" log --oneline 2>/dev/null | grep -qF "STORY-002A" \
  && a_both_integrated=1
a_both_passes=0
grep -A5 '## STORY-001A' "$ADMIT_A_DIR/_goals/backlog.md" 2>/dev/null | grep -q 'passes: true' \
  && grep -A5 '## STORY-002A' "$ADMIT_A_DIR/_goals/backlog.md" 2>/dev/null | grep -q 'passes: true' \
  && a_both_passes=1
a_learnings_ok=0
[[ -f "$ADMIT_A_DIR/_goals/LEARNINGS.md" ]] \
  && grep -q 'slot-001A' "$ADMIT_A_DIR/_goals/LEARNINGS.md" \
  && grep -q 'slot-002A' "$ADMIT_A_DIR/_goals/LEARNINGS.md" \
  && a_learnings_ok=1

if [[ "$a_both_markers" -eq 1 && "$a_both_integrated" -eq 1 \
      && "$a_both_passes" -eq 1 && "$a_learnings_ok" -eq 1 ]]; then
  report PASS "67: admission (a) disjoint-writes CONCURRENT -- STORY-001A (src/foo.txt) and STORY-002A (src/bar.txt) both dispatched simultaneously (interleaved start-markers prove overlap via bounded poll), both integrated into main, both passes:true, LEARNINGS carries both outbox lines in reap order"
else
  report FAIL "67: admission (a) disjoint concurrent" \
    "both_markers=$a_both_markers(rc=$admit_a_rc) both_integrated=$a_both_integrated both_passes=$a_both_passes learnings_ok=$a_learnings_ok"
  sed 's/^/    /' "$admit_a_log" >&2
fi

# ---------------------------------------------------------------------------
# 68 + 68-mutation-proof: Admission (c) -- HOTSPOT serialization: two stories
# with DISJOINT writes under _loop_writes_conflict that BOTH intersect the
# ORCHESTRATION.md hotspot member are serialized by _loop_hotspot_conflict
# (loop.sh:383-391) alone. STORY-950 writes: ORCHESTRATION.md.bak,
# STORY-951 writes: ORCHESTRATION.mdx. Neither literal is a prefix of the
# other (disjoint under _loop_writes_conflict), while ORCHESTRATION.md IS a
# prefix of both (shared hotspot member, prefix-promotion conservatism) --
# the only shape where the hotspot rule is independently observable from the
# writes-conflict rule.
# Mutation-prove: replace the _loop_hotspot_conflict condition with `false`
# in a COPY -> both dispatched concurrently (peak=2).
# ---------------------------------------------------------------------------
ADMIT_C_DIR="$TMP/admit-c-sandbox"
rm -rf "$ADMIT_C_DIR"; mkdir -p "$ADMIT_C_DIR"
sandbox_write_loop "$ADMIT_C_DIR" ".claude"
(
  cd "$ADMIT_C_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "admit-c-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n'
    printf '## STORY-950: hotspot holder A\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: ORCHESTRATION.md.bak\n\n'
    printf '## STORY-951: hotspot holder B\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: ORCHESTRATION.mdx\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

admit_c_dispatched_file="$TMP/admit-c-dispatched.txt"
admit_c_inflight_dir="$TMP/admit-c-inflight"; mkdir -p "$admit_c_inflight_dir"
admit_c_overlap_log="$TMP/admit-c-overlap.txt"
rm -f "$admit_c_dispatched_file" "$admit_c_overlap_log"
cat > "$ADMIT_C_DIR/_loop/stub-admit-c.sh" <<STUBEOF
#!/usr/bin/env bash
sid="\$(echo "\$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "\$sid" >> "$admit_c_dispatched_file"
touch "${admit_c_inflight_dir}/inflight.\$\$"
c=0; while (( c < 25 )); do
  n=\$(ls "${admit_c_inflight_dir}"/inflight.* 2>/dev/null | wc -l)
  (( n >= 2 )) && break
  sleep 0.1; c=\$((c + 1))
done
echo "peak=\$(ls "${admit_c_inflight_dir}"/inflight.* 2>/dev/null | wc -l)" >> "$admit_c_overlap_log"
case "\$sid" in
  STORY-950) echo "p \$sid" > ORCHESTRATION.md.bak; git add ORCHESTRATION.md.bak ;;
  STORY-951) echo "p \$sid" > ORCHESTRATION.mdx; git add ORCHESTRATION.mdx ;;
  *) : ;;
esac
git commit -qm "progress from \$sid"
rm -f "${admit_c_inflight_dir}/inflight.\$\$"
echo "ITERATION: \$sid passed"
exit 0
STUBEOF
chmod +x "$ADMIT_C_DIR/_loop/stub-admit-c.sh"

# LOOP_SLOTS=2, LOOP_WORKTREE=1, MAX_ITER=2: STORY-950 fills round 1 (STORY-951
# deferred by hotspot conflict with ORCHESTRATION.md); STORY-951 fills round 2.
admit_c_log="$TMP/admit-c-run.log"
( cd "$ADMIT_C_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 \
    LOOP_CLI="$ADMIT_C_DIR/_loop/stub-admit-c.sh" bash ./_loop/loop.sh 2 ) \
  >"$TMP/admit-c-out.txt" 2>"$admit_c_log"

dispatched_c_count="$(wc -l < "$admit_c_dispatched_file" 2>/dev/null || echo 0)"
dispatched_c_head="$(head -1 "$admit_c_dispatched_file" 2>/dev/null)"
dispatched_c_tail="$(tail -1 "$admit_c_dispatched_file" 2>/dev/null)"
c_both_dispatched=0; c_order_ok=0; c_no_overlap=0
[[ "$dispatched_c_count" -eq 2 ]] && c_both_dispatched=1
[[ "$dispatched_c_head" == "STORY-950" && "$dispatched_c_tail" == "STORY-951" ]] && c_order_ok=1
grep -qF 'peak=2' "$admit_c_overlap_log" 2>/dev/null || c_no_overlap=1

if [[ "$c_both_dispatched" -eq 1 && "$c_order_ok" -eq 1 && "$c_no_overlap" -eq 1 ]]; then
  report PASS "68: admission (c) hotspot serialization -- STORY-950 (writes: ORCHESTRATION.md.bak) and STORY-951 (writes: ORCHESTRATION.mdx) are disjoint under _loop_writes_conflict but share ORCHESTRATION.md hotspot; _loop_hotspot_conflict serializes them (STORY-951 deferred until STORY-950 completes, peak always 1, both dispatched serially in priority order)"
else
  report FAIL "68: admission (c) hotspot serialization" \
    "both_dispatched=$c_both_dispatched(count=$dispatched_c_count) order_ok=$c_order_ok(head='$dispatched_c_head' tail='$dispatched_c_tail') no_overlap=$c_no_overlap"
  sed 's/^/    /' "$admit_c_log" >&2
fi

# 68-mutation-proof: replace the _loop_hotspot_conflict condition with `false`
# in a COPY -> both stories admitted concurrently (peak=2 in overlap log).
# Judge-verified awk: exactly one match in the current loop.sh.
MUT68_DIR="$TMP/admit-c-sandbox-mut68"
rm -rf "$MUT68_DIR"; mkdir -p "$MUT68_DIR"
sandbox_write_loop "$MUT68_DIR" ".claude"
(
  cd "$MUT68_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "admit-c-mut68-test"
  mkdir -p _goals .claude
  {
    printf '# backlog\n\n'
    printf '## STORY-950: hotspot holder A\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: ORCHESTRATION.md.bak\n\n'
    printf '## STORY-951: hotspot holder B\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: ORCHESTRATION.mdx\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

mut68_dispatch_log="$TMP/mut68-dispatch.log"
mut68_inflight_dir="$TMP/mut68-inflight"; mkdir -p "$mut68_inflight_dir"
mut68_overlap_log="$TMP/mut68-overlap.txt"
rm -f "$mut68_dispatch_log" "$mut68_overlap_log"
cat > "$MUT68_DIR/_loop/stub-admit-c-mut.sh" <<STUBEOF
#!/usr/bin/env bash
sid="\$(echo "\$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "\$sid" >> "$mut68_dispatch_log"
touch "${mut68_inflight_dir}/inflight.\$\$"
c=0; while (( c < 25 )); do
  n=\$(ls "${mut68_inflight_dir}"/inflight.* 2>/dev/null | wc -l)
  (( n >= 2 )) && break
  sleep 0.1; c=\$((c + 1))
done
echo "peak=\$(ls "${mut68_inflight_dir}"/inflight.* 2>/dev/null | wc -l)" >> "$mut68_overlap_log"
case "\$sid" in
  STORY-950) echo "p \$sid" > ORCHESTRATION.md.bak; git add ORCHESTRATION.md.bak ;;
  STORY-951) echo "p \$sid" > ORCHESTRATION.mdx; git add ORCHESTRATION.mdx ;;
  *) : ;;
esac
git commit -qm "progress from \$sid"
rm -f "${mut68_inflight_dir}/inflight.\$\$"
echo "ITERATION: \$sid passed"
exit 0
STUBEOF
chmod +x "$MUT68_DIR/_loop/stub-admit-c-mut.sh"

# Verify the awk pattern matches exactly one line (single-match guard)
_mut68_match_count="$(grep -cF '|| _loop_hotspot_conflict "$writes"' "$MUT68_DIR/_loop/loop.sh")"
# Mutate: replace the _loop_hotspot_conflict condition with `false` (hotspot rule deleted)
awk '{ if ($0 ~ /\|\| _loop_hotspot_conflict "\$writes"/) print "         false; then   # mutation-68: hotspot rule deleted"; else print }' \
  "$MUT68_DIR/_loop/loop.sh" > "$TMP/loop-mut68.sh"
mv "$TMP/loop-mut68.sh" "$MUT68_DIR/_loop/loop.sh"
chmod +x "$MUT68_DIR/_loop/loop.sh"

# D10 candidate 4 (STORY-012 task 06): the label below has always CLAIMED
# "bash -n clean" for the mutant, but no predicate ever checked it -- the
# awk substitution is a single textual replacement inside an `if` condition
# ("false; then"), and nothing upstream verified it stays syntactically
# valid bash. Added here so the label's claim is actually load-bearing: a
# future mutation that broke parsing would now FAIL this assertion instead
# of silently keeping the (untrue) "clean" wording.
_mut68_bash_n_clean=0
bash -n "$MUT68_DIR/_loop/loop.sh" 2>/dev/null && _mut68_bash_n_clean=1

mut68_log="$TMP/admit-c-mut68-run.log"
( cd "$MUT68_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 \
    LOOP_CLI="$MUT68_DIR/_loop/stub-admit-c-mut.sh" bash ./_loop/loop.sh 2 ) \
  >/dev/null 2>"$mut68_log"

mut68_peak_2=0
grep -qF 'peak=2' "$mut68_overlap_log" && mut68_peak_2=1

if [[ "$mut68_peak_2" -eq 1 && "$_mut68_match_count" -eq 1 && "$_mut68_bash_n_clean" -eq 1 ]]; then
  report PASS "68-mutation-proof: hotspot-check deleted in a COPY (awk matched $_mut68_match_count line, bash -n clean -- now actually checked) -> STORY-950 and STORY-951 dispatched concurrently (peak=2 in overlap log), confirming _loop_hotspot_conflict is the sole serializer for disjoint-writes / shared-hotspot story pairs"
else
  report FAIL "68-mutation-proof: hotspot deletion did not yield concurrent dispatch" \
    "peak_2=$mut68_peak_2 awk_match_count=$_mut68_match_count bash_n_clean=$_mut68_bash_n_clean"
  sed 's/^/    /' "$mut68_log" >&2
fi

# ===========================================================================
# 87+: STORY-012 exit-aggregation coverage (D2 retirement, D3 aggregation
# funnel + precedence, D1 exit-0 quarantine gating, D4 quarantine markers,
# D5 dispatch-prompt capture, D6 ps1 $status normalization, D7 contract-
# block byte-parity, D8 check-G/tripwire). Numbered from 87 -- the
# self-install block (69-86) is a parallel workstream's committed surface,
# never touched here; 68-mutation-proof above is the prior tail.
# ===========================================================================

# ---------------------------------------------------------------------------
# 87: Retirement -- run continues past a stuck slot (D2). N=2 worktree
# sandbox, disjoint writes: on every story (required for genuine N=2
# concurrency -- an absent/empty writes: story runs alone, per admission
# rule (d)/assertion 65). Priority order pins scheduling deterministically:
# STORY-301 (prio 1) never commits and never emits a matching-verdict
# ITERATION line's content changes anything (status=0, no diff -> CB1's
# no-progress counter climbs every reap on whichever slot keeps drawing it);
# STORY-302/STORY-303 (prio 2/3) each commit + pass immediately, so they
# occupy the OTHER slot concurrently while STORY-301 grinds through 3
# no-progress reaps on its own slot. Asserts: the P2 retirement stderr line,
# STORY-302's passes:true transition, the run NOT halting (both later
# stories still complete via the surviving slot), and a clean drained exit
# rc=0 (STORY-301 exhausts its attempts cap at the same round CB1 trips, so
# nothing is left to quarantine). "Never refilled" is the STRUCTURAL claim
# assertion 47 already proves (the FILL gate's slot_retired[SLOT]==1 skip,
# by construction) -- this behavioral fixture corroborates it observably: no
# SECOND "slot 0 retired" line ever appears (would require FILL to have
# re-considered the same already-retired row), and the assertion's checked
# predicate -- STORY-301's own attempts field capped at exactly 3 in the
# backlog -- holds even though the run's total dispatch budget (MAX_ITER=8)
# is only 5/8 spent when the backlog drains (measured: 3 dispatches of
# budget go unused), so a re-fill would have had room to happen if the gate
# ever allowed it.
# ---------------------------------------------------------------------------
RETIRE_DIR="$TMP/retire-sandbox"
rm -rf "$RETIRE_DIR"; mkdir -p "$RETIRE_DIR"
sandbox_write_loop "$RETIRE_DIR" ".claude"
(
  cd "$RETIRE_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "retire-test"
  mkdir -p _goals .claude dummy
  {
    printf '# backlog\n\n'
    printf '## STORY-301: never commits (retires its slot via CB1)\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: dummy/a.txt\n\n'
    printf '## STORY-302: passes immediately\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: dummy/b.txt\n\n'
    printf '## STORY-303: passes immediately\n'
    printf -- '- priority: 3\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: dummy/c.txt\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

cat > "$RETIRE_DIR/_loop/stub-retire.sh" <<'STUBEOF'
#!/usr/bin/env bash
story_id="$(echo "$1" | grep -oE 'STORY-[0-9]+' | head -1)"
case "$story_id" in
  STORY-301)
    echo "steady state, nothing new this pass"
    echo "ITERATION: STORY-301 failed"
    ;;
  STORY-302)
    mkdir -p dummy; echo "progress" > dummy/b.txt
    git add dummy/b.txt; git commit -qm "story-302 progress"
    echo "ITERATION: STORY-302 passed"
    ;;
  STORY-303)
    mkdir -p dummy; echo "progress" > dummy/c.txt
    git add dummy/c.txt; git commit -qm "story-303 progress"
    echo "ITERATION: STORY-303 passed"
    ;;
esac
exit 0
STUBEOF
chmod +x "$RETIRE_DIR/_loop/stub-retire.sh"

retire_log="$TMP/retire-run.log"
( cd "$RETIRE_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 \
    LOOP_CLI="$RETIRE_DIR/_loop/stub-retire.sh" bash ./_loop/loop.sh 8 ) \
  >"$TMP/retire-out.txt" 2>"$retire_log"
retire_rc=$?

retire_p2_count="$(grep -cF '!!! circuit breaker: 3 iterations without a commit' "$retire_log")"
retire_p2_slot0=0
grep -qE 'circuit breaker: 3 iterations without a commit — slot 0 retired \(not refilled\)' "$retire_log" \
  && retire_p2_slot0=1
retire_302_passed=0
grep -A5 '## STORY-302' "$RETIRE_DIR/_goals/backlog.md" 2>/dev/null | grep -qF 'passes: true' \
  && retire_302_passed=1
retire_303_passed=0
grep -A5 '## STORY-303' "$RETIRE_DIR/_goals/backlog.md" 2>/dev/null | grep -qF 'passes: true' \
  && retire_303_passed=1
retire_301_attempts_capped=0
grep -A5 '## STORY-301' "$RETIRE_DIR/_goals/backlog.md" 2>/dev/null | grep -qF 'attempts: 3' \
  && retire_301_attempts_capped=1
retire_clean_rc=0
[[ "$retire_rc" -eq 0 ]] && retire_clean_rc=1

if [[ "$retire_p2_count" -eq 1 && "$retire_p2_slot0" -eq 1 && "$retire_302_passed" -eq 1 \
      && "$retire_303_passed" -eq 1 && "$retire_301_attempts_capped" -eq 1 \
      && "$retire_clean_rc" -eq 1 ]]; then
  report PASS "87: retirement -- run continues past a stuck slot (D2): P2 line fires EXACTLY once for slot 0 (never a second time -- corroborates assertion 47's structural never-refilled proof), STORY-302/STORY-303 both transition passes:true via the surviving slot while slot 0 grinds through 3 no-progress reaps, STORY-301 attempts capped at 3, backlog drains clean -> rc=0"
else
  report FAIL "87: retirement -- run continues" \
    "p2_count=$retire_p2_count(expected 1) p2_slot0=$retire_p2_slot0 302_passed=$retire_302_passed 303_passed=$retire_303_passed 301_capped=$retire_301_attempts_capped rc=$retire_rc(expected 0)"
  sed 's/^/    /' "$retire_log" >&2
fi

# ---------------------------------------------------------------------------
# 88: Aggregation precedence 3-vs-2 (D3) -- MIXED-reason precedence proof.
# N=2 worktree sandbox: slot 0's track (STORY-CB1X, never commits) retires
# via CB1 after 3 rounds; slot 1's track (STORY-CB2A then STORY-CB2B, two
# stories needed since the attempts cap (3) is below CB2's threshold (5))
# commits progress every dispatch (so CB1 never fires on slot 1) but emits
# an IDENTICAL 5-line failure signature each time -> CB2 retires slot 1
# after its 5th consecutive same-signature reap. Once BOTH slots are
# retired, D3 requires the precedence rule "ANY cb2 retirement anywhere in
# the lineage wins" -> rc=3, never rc=2, even though slot 0's own reason was
# cb1. The all-CB1-only control (symmetric, no CB2 anywhere -> rc=2) is
# already covered by assertion 50 (N=1, unchanged, still green) -- goal.md's
# permitted-update-set trace explicitly allows reusing it rather than
# duplicating a fresh fixture.
# ---------------------------------------------------------------------------
PREC_DIR="$TMP/precedence-sandbox"
rm -rf "$PREC_DIR"; mkdir -p "$PREC_DIR"
sandbox_write_loop "$PREC_DIR" ".claude"
(
  cd "$PREC_DIR"
  git init -q
  git config user.email test@example.com
  git config user.name "precedence-test"
  mkdir -p _goals .claude dummy
  {
    printf '# backlog\n\n'
    printf '## STORY-CB1X: never commits (CB1 track)\n'
    printf -- '- priority: 1\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: dummy/x.txt\n\n'
    printf '## STORY-CB2A: same-signature failures (CB2 track, part 1)\n'
    printf -- '- priority: 2\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: dummy/cb2a.txt\n\n'
    printf '## STORY-CB2B: same-signature failures (CB2 track, part 2)\n'
    printf -- '- priority: 3\n- passes: false\n- attempts: 0\n- blocked: false\n'
    printf -- '- writes: dummy/cb2b.txt\n'
  } > _goals/backlog.md
  printf 'placeholder\n' > .claude/.keep
  : > .gitignore
  git add -A
  git commit -qm init
)

cat > "$PREC_DIR/_loop/stub-precedence.sh" <<'STUBEOF'
#!/usr/bin/env bash
story_id="$(echo "$1" | grep -oE 'STORY-[A-Z0-9]+' | head -1)"
case "$story_id" in
  STORY-CB1X)
    echo "steady state, nothing new this pass"
    echo "ITERATION: STORY-CB1X failed"
    exit 0
    ;;
  STORY-CB2A)
    mkdir -p dummy; echo "p" > dummy/cb2a.txt
    git add dummy/cb2a.txt; git commit -qm "cb2a progress"
    echo "ITERATION: $story_id failed"
    printf 'ERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\n'
    exit 1
    ;;
  STORY-CB2B)
    mkdir -p dummy; echo "p" > dummy/cb2b.txt
    git add dummy/cb2b.txt; git commit -qm "cb2b progress"
    echo "ITERATION: $story_id failed"
    printf 'ERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\n'
    exit 1
    ;;
esac
STUBEOF
chmod +x "$PREC_DIR/_loop/stub-precedence.sh"

prec_log="$TMP/precedence-run.log"
( cd "$PREC_DIR" && LOOP_SLOTS=2 LOOP_WORKTREE=1 \
    LOOP_CLI="$PREC_DIR/_loop/stub-precedence.sh" bash ./_loop/loop.sh 10 ) \
  >"$TMP/precedence-out.txt" 2>"$prec_log"
prec_rc=$?

prec_cb1_fired=0
grep -qF 'circuit breaker: 3 iterations without a commit' "$prec_log" && prec_cb1_fired=1
prec_cb2_fired=0
grep -qF 'circuit breaker: same error 5 times' "$prec_log" && prec_cb2_fired=1
prec_p3_present=0
grep -qF '!!! all slots retired — stopping' "$prec_log" && prec_p3_present=1
prec_rc3=0
[[ "$prec_rc" -eq 3 ]] && prec_rc3=1

if [[ "$prec_cb1_fired" -eq 1 && "$prec_cb2_fired" -eq 1 && "$prec_p3_present" -eq 1 && "$prec_rc3" -eq 1 ]]; then
  report PASS "88: aggregation precedence 3-vs-2 (D3), MIXED-reason proof -- slot 0 retires cb1 (3 no-commit reaps), slot 1 retires cb2 (5 consecutive identical failure signatures across STORY-CB2A then STORY-CB2B), P3 line present, rc=3 (never 2) since ANY cb2 retirement anywhere in the lineage wins the precedence table; all-CB1-only control (rc=2) already covered unchanged by assertion 50"
else
  report FAIL "88: aggregation precedence 3-vs-2 (mixed)" \
    "cb1_fired=$prec_cb1_fired cb2_fired=$prec_cb2_fired p3_present=$prec_p3_present rc=$prec_rc(expected 3)"
  sed 's/^/    /' "$prec_log" >&2
fi

# ---------------------------------------------------------------------------
# 89: Exit-0 quarantine gating (D1/§7.1(b)(iii)). N=1 worktree sandbox, one
# story, MAX_ITER=3 (== the attempts cap): every dispatch emits the WRONG
# story id (ITERATION-mismatch) -> quarantine-lite every time, branch
# retained every time. By the 3rd dispatch attempts=3, so the final backlog
# re-scan finds NO eligible survivor AND >=1 retained branch -> D1 requires
# exit 1 (P4), NEVER the lying exit 0 a pre-story driver would report.
# Control: a single passing story (no quarantine ever) -> exit 0 unchanged,
# P4 absent.
# ---------------------------------------------------------------------------
QGATE_DIR="$TMP/qgate-sandbox"
make_sandbox "$QGATE_DIR" ".claude" 1 1

cat > "$QGATE_DIR/_loop/stub-qgate.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Always emits the WRONG story id -> ITERATION-mismatch, every dispatch.
echo "ITERATION: STORY-WRONG-ID failed"
exit 0
STUBEOF
chmod +x "$QGATE_DIR/_loop/stub-qgate.sh"
( cd "$QGATE_DIR" && git add -A && git commit -qm "add stub" )

qgate_log="$TMP/qgate-run.log"
qgate_out="$TMP/qgate-out.txt"
( cd "$QGATE_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 \
    LOOP_CLI="$QGATE_DIR/_loop/stub-qgate.sh" bash ./_loop/loop.sh 3 ) \
  >"$qgate_out" 2>"$qgate_log"
qgate_rc=$?

qgate_p4_present=0
grep -qF 'no eligible stories remain, but quarantined branches were retained this run — exiting 1' "$qgate_out" \
  && qgate_p4_present=1
qgate_rc1=0
[[ "$qgate_rc" -eq 1 ]] && qgate_rc1=1
qgate_attempts_capped=0
grep -A5 '## STORY-101' "$QGATE_DIR/_goals/backlog.md" 2>/dev/null | grep -qF 'attempts: 3' \
  && qgate_attempts_capped=1

# Control: no quarantine ever -> rc=0 unchanged, P4 absent.
QGATE_CTRL_DIR="$TMP/qgate-control-sandbox"
make_sandbox "$QGATE_CTRL_DIR" ".claude" 1 1
cat > "$QGATE_CTRL_DIR/_loop/stub-qgate-control.sh" <<'STUBEOF'
#!/usr/bin/env bash
echo "progress" > progress.txt
git add progress.txt
git commit -qm "qgate-control progress"
echo "ITERATION: STORY-101 passed"
exit 0
STUBEOF
chmod +x "$QGATE_CTRL_DIR/_loop/stub-qgate-control.sh"
qgate_ctrl_out="$TMP/qgate-control-out.txt"
qgate_ctrl_err="$TMP/qgate-control-err.txt"
( cd "$QGATE_CTRL_DIR" && env -u LOOP_SLOTS LOOP_WORKTREE=1 \
    LOOP_CLI="$QGATE_CTRL_DIR/_loop/stub-qgate-control.sh" bash ./_loop/loop.sh 3 ) \
  >"$qgate_ctrl_out" 2>"$qgate_ctrl_err"
qgate_ctrl_rc=$?
qgate_ctrl_rc0=0
[[ "$qgate_ctrl_rc" -eq 0 ]] && qgate_ctrl_rc0=1
qgate_ctrl_p4_absent=0
grep -qF 'exiting 1 (inspect before trusting the backlog)' "$qgate_ctrl_out" || qgate_ctrl_p4_absent=1

if [[ "$qgate_p4_present" -eq 1 && "$qgate_rc1" -eq 1 && "$qgate_attempts_capped" -eq 1 \
      && "$qgate_ctrl_rc0" -eq 1 && "$qgate_ctrl_p4_absent" -eq 1 ]]; then
  report PASS "89: exit-0 quarantine gating (D1/§7.1(b)(iii)) -- 3 consecutive ITERATION-mismatch quarantines exhaust attempts (3/3), no eligible survivor remains, P4 line printed, rc=1 (never the lying exit 0); control (a single cleanly-passing story, zero quarantines) is unaffected: rc=0, P4 absent"
else
  report FAIL "89: exit-0 quarantine gating" \
    "p4_present=$qgate_p4_present rc1=$qgate_rc1(rc=$qgate_rc) attempts_capped=$qgate_attempts_capped ctrl_rc0=$qgate_ctrl_rc0(rc=$qgate_ctrl_rc) ctrl_p4_absent=$qgate_ctrl_p4_absent"
  sed 's/^/    /' "$qgate_log" >&2
fi

# ---------------------------------------------------------------------------
# 90: MAX_ITER-drained-clean (D3 row 0, "bottom" banner P5). N=1 main-tree
# sandbox, MAX_ITER == the exact number of eligible stories, so the LAST
# allowed dispatch is also the one that drains the backlog -- the run falls
# through the while loop's own condition (never re-entering the loop body's
# in-loop terminal check) and lands on the bottom `_loop_aggregate_exit
# "bottom"` call directly. Zero quarantines -> P5 + rc=0 (an intentional D3
# behavior change from the pre-story driver's unconditional exit 1 there).
# Control: MAX_ITER too small to drain a 2-story backlog -> rc=1 with
# today's unchanged "max iterations (N) reached; backlog not complete"
# banner (P5 absent).
# ---------------------------------------------------------------------------
MAXCLEAN_DIR="$TMP/maxclean-sandbox"
make_sandbox "$MAXCLEAN_DIR" ".claude" 1 1

cat > "$MAXCLEAN_DIR/_loop/stub-maxclean.sh" <<'STUBEOF'
#!/usr/bin/env bash
echo "progress" > progress.txt
git add progress.txt
git commit -qm "maxclean progress"
echo "ITERATION: STORY-101 passed"
exit 0
STUBEOF
chmod +x "$MAXCLEAN_DIR/_loop/stub-maxclean.sh"

maxclean_out="$TMP/maxclean-out.txt"
maxclean_err="$TMP/maxclean-err.txt"
( cd "$MAXCLEAN_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$MAXCLEAN_DIR/_loop/stub-maxclean.sh" bash ./_loop/loop.sh 1 ) \
  >"$maxclean_out" 2>"$maxclean_err"
maxclean_rc=$?

maxclean_p5_present=0
grep -qF 'max iterations reached and no eligible stories remain — backlog complete' "$maxclean_out" \
  && maxclean_p5_present=1
maxclean_rc0=0
[[ "$maxclean_rc" -eq 0 ]] && maxclean_rc0=1

# Control: 2-story backlog, MAX_ITER=1 -> one story survives -> rc=1, banner
# unchanged, P5 absent.
MAXCLEAN_CTRL_DIR="$TMP/maxclean-control-sandbox"
make_sandbox "$MAXCLEAN_CTRL_DIR" ".claude" 1 1 2
cat > "$MAXCLEAN_CTRL_DIR/_loop/stub-maxclean-control.sh" <<'STUBEOF'
#!/usr/bin/env bash
story_id="$(echo "$1" | grep -oE 'STORY-[0-9]+' | head -1)"
echo "progress" > "progress-$story_id.txt"
git add "progress-$story_id.txt"
git commit -qm "maxclean-control progress $story_id"
echo "ITERATION: $story_id passed"
exit 0
STUBEOF
chmod +x "$MAXCLEAN_CTRL_DIR/_loop/stub-maxclean-control.sh"
maxclean_ctrl_out="$TMP/maxclean-control-out.txt"
( cd "$MAXCLEAN_CTRL_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$MAXCLEAN_CTRL_DIR/_loop/stub-maxclean-control.sh" bash ./_loop/loop.sh 1 ) \
  >"$maxclean_ctrl_out" 2>/dev/null
maxclean_ctrl_rc=$?
maxclean_ctrl_rc1=0
[[ "$maxclean_ctrl_rc" -eq 1 ]] && maxclean_ctrl_rc1=1
maxclean_ctrl_banner=0
grep -qF 'max iterations (1) reached; backlog not complete' "$maxclean_ctrl_out" && maxclean_ctrl_banner=1
maxclean_ctrl_p5_absent=0
grep -qF 'backlog complete' "$maxclean_ctrl_out" || maxclean_ctrl_p5_absent=1

if [[ "$maxclean_p5_present" -eq 1 && "$maxclean_rc0" -eq 1 && "$maxclean_ctrl_rc1" -eq 1 \
      && "$maxclean_ctrl_banner" -eq 1 && "$maxclean_ctrl_p5_absent" -eq 1 ]]; then
  report PASS "90: MAX_ITER-drained-clean (D3 row 0, bottom-path P5 banner) -- MAX_ITER exactly matches the one eligible story, the run falls through to the bottom aggregation call, zero quarantines -> P5 line + rc=0 (D3's intentional change from the pre-story unconditional exit 1); control (an eligible story still remains after budget exhausts) -> rc=1 with today's unchanged 'max iterations (N) reached' banner, P5 absent"
else
  report FAIL "90: MAX_ITER-drained-clean" \
    "p5_present=$maxclean_p5_present rc0=$maxclean_rc0(rc=$maxclean_rc) ctrl_rc1=$maxclean_ctrl_rc1(rc=$maxclean_ctrl_rc) ctrl_banner=$maxclean_ctrl_banner ctrl_p5_absent=$maxclean_ctrl_p5_absent"
  sed 's/^/    /' "$maxclean_err" >&2
fi

# ---------------------------------------------------------------------------
# 91: MAX_ITER-coincident retirement (cycle-1 blocker regression, standing
# assertion -- task 01 micro-test (h) promoted here). N=1 default flags,
# MAX_ITER=3 EXACTLY matching both the attempts cap AND the CB1 threshold,
# one never-progressing story: the 3rd dispatch both exhausts MAX_ITER AND
# trips CB1 on the SAME reap, so the while loop exits to the bottom
# aggregation call with active_slots==0 purely from the loop condition (NOT
# from the in-loop terminal check, which never runs again after this
# round). D3's single funnel evaluates rows 3/2 (all-retired) BEFORE the
# eligibility rescan on EVERY call site -- including this "fell through the
# while condition" bottom call -- so this must NEVER report a lying exit
# 0/1: rc MUST be 2, P3 MUST be present.
# ---------------------------------------------------------------------------
COINCIDE_DIR="$TMP/coincide-sandbox"
make_sandbox "$COINCIDE_DIR" ".claude" 1 1

cat > "$COINCIDE_DIR/_loop/stub-coincide.sh" <<'STUBEOF'
#!/usr/bin/env bash
echo "steady state, nothing new this pass"
exit 0
STUBEOF
chmod +x "$COINCIDE_DIR/_loop/stub-coincide.sh"

coincide_log="$TMP/coincide-run.log"
( cd "$COINCIDE_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_CLI="$COINCIDE_DIR/_loop/stub-coincide.sh" bash ./_loop/loop.sh 3 ) \
  >"$TMP/coincide-out.txt" 2>"$coincide_log"
coincide_rc=$?

coincide_rc_never_0_or_1=0
[[ "$coincide_rc" -ne 0 && "$coincide_rc" -ne 1 ]] && coincide_rc_never_0_or_1=1
coincide_rc2=0
[[ "$coincide_rc" -eq 2 ]] && coincide_rc2=1
coincide_p3_present=0
grep -qF '!!! all slots retired — stopping' "$coincide_log" && coincide_p3_present=1
coincide_attempts3=0
grep -A5 '## STORY-101' "$COINCIDE_DIR/_goals/backlog.md" 2>/dev/null | grep -qF 'attempts: 3' \
  && coincide_attempts3=1

if [[ "$coincide_rc_never_0_or_1" -eq 1 && "$coincide_rc2" -eq 1 && "$coincide_p3_present" -eq 1 \
      && "$coincide_attempts3" -eq 1 ]]; then
  report PASS "91: MAX_ITER-coincident retirement (cycle-1 blocker regression, standing assertion) -- N=1, MAX_ITER=3 exactly coincides with the attempts cap and the CB1 threshold on the SAME reap; the single D3 funnel still evaluates all-retired FIRST at the bottom call -> rc=2 (never 0 or 1), P3 present"
else
  report FAIL "91: MAX_ITER-coincident retirement" \
    "rc_never_0_or_1=$coincide_rc_never_0_or_1 rc2=$coincide_rc2(rc=$coincide_rc) p3_present=$coincide_p3_present attempts3=$coincide_attempts3"
  sed 's/^/    /' "$coincide_log" >&2
fi

# ---------------------------------------------------------------------------
# 92: Quarantine marker (D4) -- reuses assertion 62's already-computed
# ITERATION-mismatch fixture (MISMATCH_DIR/mismatch_log, unchanged, flag=1,
# branch loop/iter-1) rather than re-deriving an identical scenario: exactly
# one .loop-worktrees/QUARANTINE-loop-iter-*.md file exists, and it contains
# every pinned field (QUARANTINE, story:, slot:, branch:, status:,
# reason: mismatch, dirty_paths:) plus a distinctive substring of the
# substituted dispatched prompt (the story id embedded in the fixture's own
# %%STORY_ID%% substitution).
# ---------------------------------------------------------------------------
qmark_files=("$MISMATCH_DIR"/.loop-worktrees/QUARANTINE-loop-iter-*.md)
qmark_count=0
[[ -e "${qmark_files[0]}" ]] && qmark_count="${#qmark_files[@]}"
qmark_exactly_one=0
[[ "$qmark_count" -eq 1 ]] && qmark_exactly_one=1
qmark_fields_ok=0
if [[ "$qmark_exactly_one" -eq 1 ]]; then
  qmark_file="${qmark_files[0]}"
  if grep -qxF 'QUARANTINE' "$qmark_file" \
     && grep -qE '^story: ' "$qmark_file" \
     && grep -qE '^slot: ' "$qmark_file" \
     && grep -qE '^branch: loop/iter-1$' "$qmark_file" \
     && grep -qE '^status: ' "$qmark_file" \
     && grep -qxF 'reason: mismatch' "$qmark_file" \
     && grep -qE '^dirty_paths: ' "$qmark_file" \
     && grep -qF 'Fixture prompt for STORY-101' "$qmark_file"; then
    qmark_fields_ok=1
  fi
fi

if [[ "$qmark_exactly_one" -eq 1 && "$qmark_fields_ok" -eq 1 ]]; then
  report PASS "92: quarantine marker (D4) -- exactly one .loop-worktrees/QUARANTINE-loop-iter-*.md exists after assertion 62's mismatch quarantine, carrying every pinned field (QUARANTINE/story/slot/branch/status/reason: mismatch/dirty_paths) plus a distinctive substring of the substituted dispatched prompt (STORY-101)"
else
  report FAIL "92: quarantine marker" \
    "count=$qmark_count(expected 1) fields_ok=$qmark_fields_ok"
  [[ "$qmark_exactly_one" -eq 1 ]] && sed 's/^/    /' "${qmark_files[0]}" >&2
fi

# ---------------------------------------------------------------------------
# 93: Dispatch-prompt capture, structural (D5) -- both canonical drivers
# write the substituted prompt to dispatch-prompt.md AFTER both %%...%%
# substitutions and BEFORE the child spawns (assertion 92 above is the
# behavioral half, via the marker's embedded prompt on the quarantine path).
# Block-scoped: anchored on each twin's OWN final substitution line, window
# forward to the child-spawn site, requiring the write to fall strictly
# between them.
# ---------------------------------------------------------------------------
t93_sh_check() {
  local f="$1" ln window
  ln="$(grep -n 'OUTBOX_DIR%%/\$outbox_dir' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 10))p" "$f")"
  grep -qF '> "$outbox_dir/dispatch-prompt.md"' <<< "$window" || return 1
  # the write must precede the child-spawn subshell, not follow it
  local write_ln spawn_ln
  write_ln="$(grep -n '> "\$outbox_dir/dispatch-prompt.md"' "$f" | head -1 | cut -d: -f1)"
  spawn_ln="$(grep -n '\$LOOP_CLI \$model_arg "\$p"' "$f" | head -1 | cut -d: -f1)"
  [[ -n "$write_ln" && -n "$spawn_ln" ]] && (( write_ln < spawn_ln ))
}
t93_ps1_check() {
  local f="$1" subst_ln window
  # Anchor on the FINAL substitution call itself (.Replace('%%OUTBOX_DIR%%'
  # ...), matches exactly once) rather than the earlier missing-token GUARD
  # line, which also contains the literal 'OUTBOX_DIR%%' substring and would
  # otherwise bind first under head -1.
  subst_ln="$(grep -n "\.Replace('%%OUTBOX_DIR%%'" "$f" | head -1 | cut -d: -f1)"
  [[ -z "$subst_ln" ]] && return 1
  window="$(sed -n "${subst_ln},$((subst_ln + 15))p" "$f")"
  # Anchor the write on the Set-Content call itself, not the bare Join-Path
  # fragment (which also matches the unrelated read-back at reap time) --
  # disambiguates the write site deterministically.
  grep -qF "Set-Content -LiteralPath (Join-Path \$outboxDir 'dispatch-prompt.md')" <<< "$window" || return 1
  local write_ln spawn_ln
  write_ln="$(grep -n "Set-Content -LiteralPath (Join-Path \$outboxDir 'dispatch-prompt.md')" "$f" | head -1 | cut -d: -f1)"
  spawn_ln="$(grep -n 'Start-Job -ScriptBlock' "$f" | head -1 | cut -d: -f1)"
  [[ -n "$write_ln" && -n "$spawn_ln" ]] || return 1
  (( subst_ln < write_ln )) && (( write_ln < spawn_ln ))
}
if t93_sh_check "$LOOP_SH" && t93_ps1_check "$LOOP_PS1"; then
  report PASS "93: dispatch-prompt capture, structural (D5) -- both canonical drivers write the fully-substituted prompt to <outbox>/dispatch-prompt.md strictly AFTER the final %%OUTBOX_DIR%% substitution and strictly BEFORE the child/job spawn site, in loop.sh AND loop.ps1"
else
  report FAIL "93: dispatch-prompt capture, structural" \
    "sh=$(t93_sh_check "$LOOP_SH" && echo ok || echo FAIL) ps1=$(t93_ps1_check "$LOOP_PS1" && echo ok || echo FAIL)"
fi

# ---------------------------------------------------------------------------
# 94: Contract-block byte-parity, FULL (D7) -- SUPERSEDES assertion 33
# (strictly stronger: 33 checked only the appended 126/127 clause; this
# extracts the ENTIRE P1 block, from the `# Exit codes` header line through
# the `# branch for inspection).` closer line, inclusive) from both
# canonical twins and requires the extracted text be byte-identical
# (marker-normalized, same technique as 33), covering every one of the six
# aggregated exit codes (0-5) AND the 126/127 clause 33 already proved --
# 33 itself is left untouched (byte-identical, in the permitted-update set
# but not modified) since it still holds and this assertion is additive.
# No-weakening mapping: 33 (126/127 clause only) -> 94 (full six-code block,
# superset).
# ---------------------------------------------------------------------------
extract_p1_block() { # extract_p1_block <file>
  awk '/^# Exit codes \(driver-aggregated/{flag=1} flag{print} /branch for inspection\)\.$/{if (flag) exit}' "$1"
}
p1_sh94="$(extract_p1_block "$LOOP_SH")"
p1_ps194="$(extract_p1_block "$LOOP_PS1")"
p1_norm_sh94="$(sed 's/^# \{0,1\}//' <<< "$p1_sh94")"
p1_norm_ps194="$(sed 's/^# \{0,1\}//' <<< "$p1_ps194")"

p1_nonempty=0
[[ -n "$p1_sh94" && -n "$p1_ps194" ]] && p1_nonempty=1
p1_identical=0
[[ "$p1_norm_sh94" == "$p1_norm_ps194" ]] && p1_identical=1
p1_all_codes=1
for _code_marker in '0 = backlog complete' '1 = stopped without completing' \
                    '2 = circuit breaker' '3 = circuit breaker' \
                    '4 = protected-path modification' 'Exit 5 = setup or integration failure' \
                    '126' '127'; do
  grep -qF "$_code_marker" <<< "$p1_norm_sh94" || p1_all_codes=0
done

if [[ "$p1_nonempty" -eq 1 && "$p1_identical" -eq 1 && "$p1_all_codes" -eq 1 ]]; then
  report PASS "94: contract-block byte-parity, FULL (D7, supersedes 33) -- the entire pinned exit-code contract block (six aggregated codes 0-5 plus the 126/127 shell-propagated clause) is byte-identical (marker-normalized) between canonical loop.sh and loop.ps1"
else
  report FAIL "94: contract-block byte-parity, FULL" \
    "nonempty=$p1_nonempty identical=$p1_identical all_codes=$p1_all_codes"
fi

# ---------------------------------------------------------------------------
# 95: ps1 structural parity for the STORY-012 mechanics not covered by
# assertion 53 (which pins the pre-story/STORY-011 surface). Block-scoped,
# same discipline as 53/34/18: Retired/RetireReason slot fields; the
# Invoke-LoopAggregateExit funnel's rows-3/2 (all-retired) branch; the P4
# and P5 stdout literals (byte-exact); the $status normalization to -1 plus
# the P6 stderr literal. Not runtime-verified -- pwsh absent, same
# disposition as every other ps1 structural guard in this file.
# ---------------------------------------------------------------------------
t95_retired_fields_check() {
  local f="$1" ln window
  ln="$(grep -n '^\$slots = @()$' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 20))p" "$f")"
  grep -qF 'Retired' <<< "$window" && grep -qF 'RetireReason' <<< "$window"
}
t95_funnel_check() {
  local f="$1" ln window
  ln="$(grep -n 'function Invoke-LoopAggregateExit' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 40))p" "$f")"
  grep -qF '$allRetired' <<< "$window" && grep -qF '$anyCb2' <<< "$window" \
    && grep -qE '^\s*exit 3\s*$' <<< "$window" && grep -qE '^\s*exit 2\s*$' <<< "$window"
}
t95_p4_check() { grep -qF 'no eligible stories remain, but quarantined branches were retained this run — exiting 1' "$1"; }
t95_p5_check() { grep -qF 'max iterations reached and no eligible stories remain — backlog complete' "$1"; }
t95_status_norm_check() {
  local f="$1" ln window
  ln="$(grep -n 'Receive-Job -Job \$job' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 25))p" "$f")"
  grep -qF '$status = -1' <<< "$window" \
    && grep -qF 'job produced no usable exit status — normalizing to -1 (abnormal)' <<< "$window"
}
if t95_retired_fields_check "$LOOP_PS1" && t95_funnel_check "$LOOP_PS1" \
   && t95_p4_check "$LOOP_PS1" && t95_p5_check "$LOOP_PS1" && t95_status_norm_check "$LOOP_PS1"; then
  report PASS "95: ps1 structural parity, STORY-012 mechanics -- Retired/RetireReason slot fields, Invoke-LoopAggregateExit's rows-3/2 all-retired branch (\$allRetired/\$anyCb2/exit 3/exit 2), the P4 and P5 literals, and the \$status normalization to -1 with its P6 stderr note all present in canonical loop.ps1, block-scoped -- not runtime-verified, pwsh absent"
else
  report FAIL "95: ps1 structural parity, STORY-012 mechanics" \
    "retired_fields=$(t95_retired_fields_check "$LOOP_PS1" && echo ok || echo FAIL) funnel=$(t95_funnel_check "$LOOP_PS1" && echo ok || echo FAIL) p4=$(t95_p4_check "$LOOP_PS1" && echo ok || echo FAIL) p5=$(t95_p5_check "$LOOP_PS1" && echo ok || echo FAIL) status_norm=$(t95_status_norm_check "$LOOP_PS1" && echo ok || echo FAIL)"
fi

# ---------------------------------------------------------------------------
# 96: exit-5 site count == 5 in BOTH canonical twins (D3's [AMENDED]
# five-site pin). Nothing at HEAD previously counted the exit-5 SITES
# themselves (only their prose, via check G/assertion 33/94) -- this counts
# the literal, standalone `exit 5` STATEMENT lines only (anchored `^\s*exit
# 5\s*$`, never matching prose mentions like "exit 5, setup-failure
# category" inside comments, which do not end the line at the digit).
# ---------------------------------------------------------------------------
exit5_sh_count="$(grep -cE '^\s*exit 5\s*$' "$LOOP_SH")"
exit5_ps1_count="$(grep -cE '^\s*exit 5\s*$' "$LOOP_PS1")"
if [[ "$exit5_sh_count" -eq 5 && "$exit5_ps1_count" -eq 5 ]]; then
  report PASS "96: exit-5 site count == 5 in both canonical twins (loop.sh=$exit5_sh_count loop.ps1=$exit5_ps1_count) -- matches D3's [AMENDED] five-site pin (preflight, PROMPT.md substitution, missing/unreadable backlog at fill-time, non-ff integration, missing/unreadable backlog at the funnel's bottom-path re-scan)"
else
  report FAIL "96: exit-5 site count" "loop.sh=$exit5_sh_count(expected 5) loop.ps1=$exit5_ps1_count(expected 5)"
fi

# ---------------------------------------------------------------------------
# 97: check-G/tripwire mutation, NEGATIVE (D8) -- CHECKS_VERSION_FILE
# pointed at a temp file containing a deliberately-wrong "0.99.0" while the
# real manifest's kitVersion is left untouched -> the REAL .claude/checks.sh
# (CHECKS_MANIFEST-override precedent, assertions 24/25) must FAIL the
# "J: kitVersion==VERSION join" line and name BOTH values.
# ---------------------------------------------------------------------------
j_real_kitversion="$(grep -m1 '"kitVersion"' "$MANIFEST_JSON" 2>/dev/null | \
  sed -E 's/.*"kitVersion"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
if [[ -f "$CHECKS_SH" && -f "$MANIFEST_JSON" && -n "$j_real_kitversion" ]]; then
  j_tripwire_neg_file="$TMP/version-mismatch.txt"
  printf '0.99.0\n' > "$j_tripwire_neg_file"
  j_tripwire_neg_out="$TMP/tripwire-neg-out.txt"
  j_tripwire_neg_err="$TMP/tripwire-neg-err.txt"
  CHECKS_VERSION_FILE="$j_tripwire_neg_file" "$CHECKS_SH" \
    >"$j_tripwire_neg_out" 2>"$j_tripwire_neg_err"
  j_tripwire_neg_rc=$?
  j_tripwire_neg_fails=0
  grep -qE '^FAIL  J: kitVersion==VERSION join' "$j_tripwire_neg_out" && j_tripwire_neg_fails=1
  j_tripwire_neg_names_both=0
  grep -qF "VERSION=0.99.0" "$j_tripwire_neg_err" \
    && grep -qF "kitVersion=$j_real_kitversion" "$j_tripwire_neg_err" \
    && j_tripwire_neg_names_both=1
  if [[ "$j_tripwire_neg_rc" -ne 0 && "$j_tripwire_neg_fails" -eq 1 && "$j_tripwire_neg_names_both" -eq 1 ]]; then
    report PASS "97: check-G/tripwire mutation, NEGATIVE (D8) -- CHECKS_VERSION_FILE=0.99.0 (real kitVersion=$j_real_kitversion) FAILS 'J: kitVersion==VERSION join' naming both values, non-zero overall exit"
  else
    report FAIL "97: check-G/tripwire mutation, NEGATIVE" \
      "rc=$j_tripwire_neg_rc fails=$j_tripwire_neg_fails names_both=$j_tripwire_neg_names_both"
    sed 's/^/    /' "$j_tripwire_neg_err" >&2
  fi
else
  report SKIP "97: check-G/tripwire mutation, NEGATIVE (.claude/checks.sh or manifest absent, or kitVersion unreadable)"
fi

# ---------------------------------------------------------------------------
# 98: check-G/tripwire mutation, POSITIVE (D8) -- the REAL tree (no
# override) must PASS 'J: kitVersion==VERSION join' with overall exit 0.
# ---------------------------------------------------------------------------
if [[ -f "$CHECKS_SH" ]]; then
  j_tripwire_pos_out="$TMP/tripwire-pos-out.txt"
  "$CHECKS_SH" >"$j_tripwire_pos_out" 2>"$TMP/tripwire-pos-err.txt"
  j_tripwire_pos_rc=$?
  j_tripwire_pos_pass=0
  grep -qE '^PASS  J: kitVersion==VERSION join' "$j_tripwire_pos_out" && j_tripwire_pos_pass=1
  if [[ "$j_tripwire_pos_rc" -eq 0 && "$j_tripwire_pos_pass" -eq 1 ]]; then
    report PASS "98: check-G/tripwire mutation, POSITIVE (D8) -- real tree (no override) PASSES 'J: kitVersion==VERSION join', overall checks.sh exit 0"
  else
    report FAIL "98: check-G/tripwire mutation, POSITIVE" "rc=$j_tripwire_pos_rc pass_line=$j_tripwire_pos_pass"
  fi
else
  report SKIP "98: check-G/tripwire mutation, POSITIVE (.claude/checks.sh absent)"
fi

# ---------------------------------------------------------------------------
# 99: check G mutation -- exit-5-stripped loop.sh COPY -> FAIL (D8). Check
# G's `local sh=`/`local ps1=`/`local brk_sh=`/`local brk_ps1=` paths are
# RELATIVE to cwd, not truly hardcoded-absolute, so a cwd-mirrored sandbox
# (skills/agent-kit/templates/loop/{loop.sh,loop.ps1,breaker.sh,breaker.ps1}
# under a throwaway root) achieves a clean copy-mutation without needing the
# assertion-26-class `$sh`-sed-repoint-the-checks.sh-copy fallback the task
# anticipated for a truly hardcoded-absolute case -- noted here since that
# fallback technique was considered and found unnecessary. The REAL check_g
# function body is extracted verbatim (eval, same technique as
# detect_rate_limit at assertion 13/14) and invoked with report() shadowed
# locally (subshell-scoped, never touching this harness's own pass/fail
# counters) against BOTH the mutant and an unmutated mirror (positive
# control, mutation must discriminate).
#
# Mutation design note (measured, not assumed): check G's own detector is
# `grep -qE "exit 5([^0-9]|$)"` over the WHOLE file -- it is satisfied by a
# bare PROSE mention of "exit 5," in a comment just as readily as by a real
# `exit 5` statement (verified: a code-statement-only mutation, `^\s*exit
# 5\s*$` -> `exit 55`, left 3 prose comment mentions of "exit 5," intact and
# check G still PASSED -- a false negative for THIS harness assertion's own
# purpose, not a flaw in check G's actual job of detecting a missing exit-5
# CAPABILITY prose-or-code). To make the mutation discriminate against check
# G's real regex, every substring "exit 5" (code AND prose, global) becomes
# "exit 55", which removes every match of `exit 5([^0-9]|$)` file-wide
# (confirmed zero matches remain) while staying `bash -n` clean.
# ---------------------------------------------------------------------------
if [[ -f "$CHECKS_SH" ]]; then
  checkg_src99="$(sed -n '/^check_g() {/,/^}/p' "$CHECKS_SH")"
  if [[ -z "$checkg_src99" ]]; then
    report FAIL "99 setup: extract check_g from .claude/checks.sh" "function not found -- checks.sh structure changed?"
  else
    CHECKG_POS_DIR="$TMP/checkg-pos"
    CHECKG_MUT_DIR="$TMP/checkg-mut"
    for _d in "$CHECKG_POS_DIR" "$CHECKG_MUT_DIR"; do
      mkdir -p "$_d/skills/agent-kit/templates/loop"
      cp "$LOOP_SH" "$_d/skills/agent-kit/templates/loop/loop.sh"
      cp "$LOOP_PS1" "$_d/skills/agent-kit/templates/loop/loop.ps1"
      cp "$BREAKER_SH" "$_d/skills/agent-kit/templates/loop/breaker.sh"
      cp "$BREAKER_PS1" "$_d/skills/agent-kit/templates/loop/breaker.ps1"
    done
    sed -i 's/exit 5/exit 55/g' "$CHECKG_MUT_DIR/skills/agent-kit/templates/loop/loop.sh"

    checkg_mut_bash_n_ok=0
    bash -n "$CHECKG_MUT_DIR/skills/agent-kit/templates/loop/loop.sh" 2>/dev/null && checkg_mut_bash_n_ok=1

    checkg_mut_result="$(
      cd "$CHECKG_MUT_DIR" || exit 1
      eval "$checkg_src99"
      report() { echo "$1|$2|${3:-}"; }
      check_g 2>&1
    )"
    checkg_pos_result="$(
      cd "$CHECKG_POS_DIR" || exit 1
      eval "$checkg_src99"
      report() { echo "$1|$2|${3:-}"; }
      check_g 2>&1
    )"

    checkg_mut_fails=0
    grep -qE '^FAIL\|G: loop driver parity heuristic' <<< "$checkg_mut_result" && checkg_mut_fails=1
    checkg_mut_names_exit5=0
    grep -qF 'missing exit 5' <<< "$checkg_mut_result" && checkg_mut_names_exit5=1
    checkg_pos_passes=0
    grep -qE '^PASS\|G: loop driver parity heuristic' <<< "$checkg_pos_result" && checkg_pos_passes=1

    if [[ "$checkg_mut_bash_n_ok" -eq 1 && "$checkg_mut_fails" -eq 1 && "$checkg_mut_names_exit5" -eq 1 \
          && "$checkg_pos_passes" -eq 1 ]]; then
      report PASS "99: check G mutation -- every 'exit 5' substring (code AND prose) rewritten to 'exit 55' in a loop.sh COPY (relative-path-mirrored sandbox, real check_g function extracted verbatim) removes all matches of check G's own exit 5([^0-9]|\$) detector -> FAILS naming 'missing exit 5' (bash -n still clean on the mutant), while the SAME extracted function PASSES against an unmutated mirror of the real files -- discriminates correctly in both directions"
    else
      report FAIL "99: check G mutation" \
        "bash_n_ok=$checkg_mut_bash_n_ok mut_fails=$checkg_mut_fails names_exit5=$checkg_mut_names_exit5 pos_passes=$checkg_pos_passes"
      printf '%s\n' "$checkg_mut_result" "$checkg_pos_result" | sed 's/^/    /' >&2
    fi
  fi
else
  report SKIP "99: check G mutation (.claude/checks.sh absent)"
fi

# ---------------------------------------------------------------------------
# 115 (harness-evaluator-upgrade, canonical): skills/agent-kit/templates/agents/
# evaluator.md and qa-evaluator.md exist and declare `name: evaluator` /
# `name: qa-evaluator`; no judge.md/qa-judge.md template exists alongside
# them (clean one-shot rename, no alias stubs -- goal Discovery policy).
# Numbered 115+ (not 100+) to stay clear of the Greenfield-setup contract
# assertions' reserved 100-114 block above.
# ---------------------------------------------------------------------------
canon_eval_md="$CANON_AGENTS_DIR/evaluator.md"
canon_qa_eval_md="$CANON_AGENTS_DIR/qa-evaluator.md"
canon_115_ok=1
[[ -f "$canon_eval_md" ]] && grep -qxF 'name: evaluator' "$canon_eval_md" || canon_115_ok=0
[[ -f "$canon_qa_eval_md" ]] && grep -qxF 'name: qa-evaluator' "$canon_qa_eval_md" || canon_115_ok=0
[[ -f "$CANON_AGENTS_DIR/judge.md" ]] && canon_115_ok=0
[[ -f "$CANON_AGENTS_DIR/qa-judge.md" ]] && canon_115_ok=0
if [[ "$canon_115_ok" -eq 1 ]]; then
  report PASS "115: canonical evaluator.md/qa-evaluator.md exist with name: evaluator/qa-evaluator; no judge.md/qa-judge.md template exists"
else
  report FAIL "115: canonical evaluator.md/qa-evaluator.md exist with name: evaluator/qa-evaluator; no judge.md/qa-judge.md template exists" \
    "evaluator.md=$([[ -f "$canon_eval_md" ]] && echo present || echo missing) qa-evaluator.md=$([[ -f "$canon_qa_eval_md" ]] && echo present || echo missing) judge.md=$([[ -f "$CANON_AGENTS_DIR/judge.md" ]] && echo present || echo absent) qa-judge.md=$([[ -f "$CANON_AGENTS_DIR/qa-judge.md" ]] && echo present || echo absent)"
fi

# ---------------------------------------------------------------------------
# 116 (harness-evaluator-upgrade, instance -- aggregate-skip when the
# instance itself is absent, matching the CHECKS_SH-absent convention above
# (assertions 86/99): the gate keys on $INSTANCE_AGENTS_DIR (the directory)
# and $MANIFEST_JSON, NOT on evaluator.md (the artifact under test), so a
# missing evaluator.md scores as a FAIL below, not a SKIP. .claude/agents/
# evaluator.md exists, no .claude/agents/judge.md, and
# orchestration-kit.manifest.json carries no judge-named key (task 08's
# re-emit + stale-file prune; this repo's own harness must never carry both
# names at once).
# ---------------------------------------------------------------------------
if [[ -d "$INSTANCE_AGENTS_DIR" && -f "$MANIFEST_JSON" ]]; then
  inst_116_ok=1
  [[ -f "$INSTANCE_AGENTS_DIR/evaluator.md" ]] || inst_116_ok=0
  [[ -f "$INSTANCE_AGENTS_DIR/judge.md" ]] && inst_116_ok=0
  manifest_judge_keys="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print('\n'.join(k for k in data.get('files', {}) if 'judge' in k.lower()))
" "$MANIFEST_JSON" 2>/dev/null)"
  [[ -n "$manifest_judge_keys" ]] && inst_116_ok=0
  if [[ "$inst_116_ok" -eq 1 ]]; then
    report PASS "116: instance .claude/agents/evaluator.md exists, no .claude/agents/judge.md, no judge-named manifest key"
  else
    report FAIL "116: instance state" "evaluator.md present=$([[ -f "$INSTANCE_AGENTS_DIR/evaluator.md" ]] && echo yes || echo no) judge.md present=$([[ -f "$INSTANCE_AGENTS_DIR/judge.md" ]] && echo yes || echo no) manifest judge keys=[$manifest_judge_keys]"
  fi
else
  report SKIP "116: .claude/agents directory or manifest absent -- instance-state check skipped"
fi

# ---------------------------------------------------------------------------
# 117 (feature-skill-slimming): feature/templates/contract.md must stay absent
# (acceptance criteria live in task files; contract gate removed).
# ---------------------------------------------------------------------------
if [[ ! -f "$CONTRACT_TPL" ]]; then
  report PASS "117: feature/templates/contract.md absent (contract gate removed)"
else
  report FAIL "117: feature/templates/contract.md absent (contract gate removed)" \
    "contract.md still present at $CONTRACT_TPL"
fi

# ---------------------------------------------------------------------------
# 118 (harness-evaluator-upgrade, eval_depth): feature/templates/task.md
# carries the eval_depth field (task 06's evaluation-intensity routing,
# orchestrator-set, never a skip).
# ---------------------------------------------------------------------------
if grep -qF 'eval_depth' "$TASK_TPL"; then
  report PASS "118: feature/templates/task.md contains eval_depth"
else
  report FAIL "118: feature/templates/task.md contains eval_depth" "no 'eval_depth' match in $TASK_TPL"
fi

# ===========================================================================
# 119–124 (token-efficiency-c-metric / LOOP_USAGE_FORMAT): new numbered
# assertions AFTER the current last one. Do not renumber 42 (expected_f42
# silent-none golden) or 57 (CLI-invocation grep) — both stay byte-identical.
# ===========================================================================

# Shared envelope stub: records argv (one arg per line) and prints a claude
# result envelope whose `result` carries a valid ITERATION: line.
usage_write_claude_stub() { # usage_write_claude_stub <stub_path> <argv_file>
  local stub="$1" argv_file="$2"
  cat > "$stub" <<STUBEOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$argv_file"
printf '%s\n' '{"type":"result","result":"ITERATION: STORY-101 passed","total_cost_usd":0.01,"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":3,"cache_creation_input_tokens":2}}'
exit 0
STUBEOF
  chmod +x "$stub"
}

usage_write_codex_stub() { # usage_write_codex_stub <stub_path>
  local stub="$1"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":4,"output_tokens":2,"cached_input_tokens":1}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":6,"output_tokens":3,"cached_input_tokens":2}}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"ITERATION: STORY-101 passed"}}'
exit 0
STUBEOF
  chmod +x "$stub"
}

usage_write_text_stub() { # usage_write_text_stub <stub_path>
  local stub="$1"
  cat > "$stub" <<'STUBEOF'
#!/usr/bin/env bash
echo "ITERATION: STORY-101 passed"
exit 0
STUBEOF
  chmod +x "$stub"
}

usage_story_passed() { # usage_story_passed <sandbox> → 0 iff STORY-101 passes: true
  grep -A5 '## STORY-101' "$1/_goals/backlog.md" 2>/dev/null | grep -qF 'passes: true'
}

# ---------------------------------------------------------------------------
# 119 (a): LOOP_USAGE_FORMAT=claude — stub prints a type=result envelope.
# If jq is absent, assert the unavailable banner and SKIP field checks.
# ---------------------------------------------------------------------------
USAGE_A_DIR="$TMP/usage-claude-sandbox"
make_sandbox "$USAGE_A_DIR" ".claude" 1 1
usage_a_argv="$TMP/usage-a-argv.txt"
usage_a_log="$TMP/usage-a.log"
rm -f "$usage_a_argv" "$usage_a_log"
usage_write_claude_stub "$USAGE_A_DIR/_loop/stub-claude.sh" "$usage_a_argv"
usage_a_out="$TMP/usage-a-stdout.txt"
usage_a_err="$TMP/usage-a-stderr.txt"
( cd "$USAGE_A_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
    LOOP_USAGE_FORMAT=claude LOOP_USAGE_LOG="$usage_a_log" \
    LOOP_CLI="$USAGE_A_DIR/_loop/stub-claude.sh" bash ./_loop/loop.sh 2 ) \
  >"$usage_a_out" 2>"$usage_a_err"
usage_a_rc=$?

if ! command -v jq >/dev/null 2>&1; then
  if grep -qF 'usage: unavailable (jq not on PATH)' "$usage_a_out"; then
    report PASS "119: (a) claude usage — jq absent, unavailable (jq not on PATH) banner present"
  else
    report FAIL "119: (a) claude usage (jq absent)" "missing jq-unavailable banner rc=$usage_a_rc"
  fi
  report SKIP "119: (a) claude usage field checks" "jq not on PATH"
else
  usage_a_line_ok=0
  grep -qF 'usage: input=10 output=5 cache_read=3 cache_write=2 cost_usd=0.01 format=claude' "$usage_a_out" \
    && usage_a_line_ok=1
  usage_a_banner_ok=0
  grep -qF 'usage format: claude' "$usage_a_out" && usage_a_banner_ok=1
  usage_a_story_ok=0
  usage_story_passed "$USAGE_A_DIR" && usage_a_story_ok=1
  if [[ "$usage_a_rc" -eq 0 && "$usage_a_line_ok" -eq 1 && "$usage_a_banner_ok" -eq 1 \
        && "$usage_a_story_ok" -eq 1 ]]; then
    report PASS "119: (a) claude usage — usage: input=10 … format=claude and STORY-101 passed"
  else
    report FAIL "119: (a) claude usage" \
      "rc=$usage_a_rc line_ok=$usage_a_line_ok banner_ok=$usage_a_banner_ok story_ok=$usage_a_story_ok"
  fi
fi

# ---------------------------------------------------------------------------
# 120 (b): LOOP_USAGE_FORMAT=codex — JSONL with two turn.completed + agent_message.
# ---------------------------------------------------------------------------
USAGE_B_DIR="$TMP/usage-codex-sandbox"
make_sandbox "$USAGE_B_DIR" ".claude" 1 1
usage_write_codex_stub "$USAGE_B_DIR/_loop/stub-codex.sh"
usage_b_out="$TMP/usage-b-stdout.txt"
if ! command -v jq >/dev/null 2>&1; then
  report SKIP "120: (b) codex usage field checks" "jq not on PATH"
else
  ( cd "$USAGE_B_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE \
      LOOP_USAGE_FORMAT=codex LOOP_CLI="$USAGE_B_DIR/_loop/stub-codex.sh" \
      bash ./_loop/loop.sh 2 ) >"$usage_b_out" 2>"$TMP/usage-b-stderr.txt"
  usage_b_rc=$?
  usage_b_line_ok=0
  grep -qF 'usage: input=10 output=5 cache_read=3 cache_write=n/a cost_usd=n/a format=codex' "$usage_b_out" \
    && usage_b_line_ok=1
  usage_b_story_ok=0
  usage_story_passed "$USAGE_B_DIR" && usage_b_story_ok=1
  if [[ "$usage_b_rc" -eq 0 && "$usage_b_line_ok" -eq 1 && "$usage_b_story_ok" -eq 1 ]]; then
    report PASS "120: (b) codex usage — summed input=10 output=5 cache_read=3 cache_write=n/a format=codex and STORY-101 passed"
  else
    report FAIL "120: (b) codex usage" \
      "rc=$usage_b_rc line_ok=$usage_b_line_ok story_ok=$usage_b_story_ok"
  fi
fi

# ---------------------------------------------------------------------------
# 121 (c): explicit LOOP_USAGE_FORMAT=none prints unavailable (format none);
#         same stub with the knob unset → grep -c usage == 0 (silent-none).
# ---------------------------------------------------------------------------
USAGE_C_DIR="$TMP/usage-none-sandbox"
make_sandbox "$USAGE_C_DIR" ".claude" 1 1
usage_write_text_stub "$USAGE_C_DIR/_loop/stub-text.sh"
usage_c_out="$TMP/usage-c-stdout.txt"
( cd "$USAGE_C_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE -u LOOP_USAGE_LOG \
    LOOP_USAGE_FORMAT=none LOOP_CLI="$USAGE_C_DIR/_loop/stub-text.sh" \
    bash ./_loop/loop.sh 2 ) >"$usage_c_out" 2>"$TMP/usage-c-stderr.txt"
usage_c_rc=$?
usage_c_unavail=0
grep -qF 'usage: unavailable (format none)' "$usage_c_out" && usage_c_unavail=1
usage_c_banner=0
grep -qF 'usage format: none' "$usage_c_out" && usage_c_banner=1
usage_c_story_ok=0
usage_story_passed "$USAGE_C_DIR" && usage_c_story_ok=1

USAGE_C2_DIR="$TMP/usage-silent-sandbox"
make_sandbox "$USAGE_C2_DIR" ".claude" 1 1
usage_write_text_stub "$USAGE_C2_DIR/_loop/stub-text.sh"
usage_c2_out="$TMP/usage-c2-stdout.txt"
( cd "$USAGE_C2_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE -u LOOP_USAGE_FORMAT -u LOOP_USAGE_LOG \
    LOOP_CLI="$USAGE_C2_DIR/_loop/stub-text.sh" bash ./_loop/loop.sh 2 ) \
  >"$usage_c2_out" 2>"$TMP/usage-c2-stderr.txt"
usage_c2_count="$(grep -c usage "$usage_c2_out" || true)"

if [[ "$usage_c_rc" -eq 0 && "$usage_c_unavail" -eq 1 && "$usage_c_banner" -eq 1 \
      && "$usage_c_story_ok" -eq 1 && "$usage_c2_count" == "0" ]]; then
  report PASS "121: (c) explicit none → usage: unavailable (format none); unset knob → grep -c usage = 0"
else
  report FAIL "121: (c) explicit none / silent-none" \
    "rc=$usage_c_rc unavail=$usage_c_unavail banner=$usage_c_banner story_ok=$usage_c_story_ok silent_count=$usage_c2_count"
fi

# ---------------------------------------------------------------------------
# 122 (d): LOOP_USAGE_LOG from (a) has one line with slot= and story=.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  report SKIP "122: (d) LOOP_USAGE_LOG" "jq not on PATH (a skipped field checks)"
elif [[ -f "$usage_a_log" ]] \
     && [[ "$(wc -l < "$usage_a_log" | tr -d ' ')" == "1" ]] \
     && grep -qF 'slot=' "$usage_a_log" && grep -qF 'story=' "$usage_a_log"; then
  report PASS "122: (d) LOOP_USAGE_LOG — one line with slot= and story="
else
  report FAIL "122: (d) LOOP_USAGE_LOG" "file=$( [[ -f "$usage_a_log" ]] && echo present || echo missing ) contents=$(head -2 "$usage_a_log" 2>/dev/null | tr '\n' '|')"
fi

# ---------------------------------------------------------------------------
# 123 (e): argv proof for (a) — --output-format json precedes the prompt.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  report SKIP "123: (e) argv --output-format json precedes prompt" "jq not on PATH"
else
  usage_e_ok=0
  if [[ -f "$usage_a_argv" ]]; then
    fmt_ln="$(grep -nxF -- '--output-format' "$usage_a_argv" | head -1 | cut -d: -f1)"
    last_ln="$(wc -l < "$usage_a_argv" | tr -d ' ')"
    if [[ -n "$fmt_ln" && -n "$last_ln" ]] \
       && [[ "$(sed -n "$((fmt_ln + 1))p" "$usage_a_argv")" == "json" ]] \
       && (( fmt_ln < last_ln )); then
      usage_e_ok=1
    fi
  fi
  if [[ "$usage_e_ok" -eq 1 ]]; then
    report PASS "123: (e) argv proof — --output-format json precedes the prompt"
  else
    report FAIL "123: (e) argv proof" "argv=$(tr '\n' ' ' < "$usage_a_argv" 2>/dev/null)"
  fi
fi

# ---------------------------------------------------------------------------
# 124 (f): basename auto — symlink <tmp>/bin/claude → stub, LOOP_CLI with -p,
#          LOOP_USAGE_FORMAT unset → banner usage format: claude.
# ---------------------------------------------------------------------------
USAGE_F_DIR="$TMP/usage-basename-sandbox"
make_sandbox "$USAGE_F_DIR" ".claude" 1 1
usage_f_bin="$TMP/usage-f-bin"
mkdir -p "$usage_f_bin"
usage_f_argv="$TMP/usage-f-argv.txt"
rm -f "$usage_f_argv"
usage_write_claude_stub "$USAGE_F_DIR/_loop/stub-claude.sh" "$usage_f_argv"
if ln -s "$USAGE_F_DIR/_loop/stub-claude.sh" "$usage_f_bin/claude" 2>/dev/null; then
  usage_f_out="$TMP/usage-f-stdout.txt"
  ( cd "$USAGE_F_DIR" && env -u LOOP_SLOTS -u LOOP_WORKTREE -u LOOP_USAGE_FORMAT -u LOOP_USAGE_LOG \
      LOOP_CLI="$usage_f_bin/claude -p" bash ./_loop/loop.sh 2 ) \
    >"$usage_f_out" 2>"$TMP/usage-f-stderr.txt"
  if grep -qF 'usage format: claude' "$usage_f_out"; then
    report PASS "124: (f) basename auto — LOOP_CLI=<tmp>/bin/claude -p, unset format → usage format: claude"
  else
    report FAIL "124: (f) basename auto" "stdout missing 'usage format: claude'"
  fi
else
  report SKIP "124: (f) basename auto (symlink unsupported)"
fi

echo
echo "=== loop-harness summary ==="
echo "PASS: $pass_count   FAIL: $fail_count   SKIP: $skip_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
