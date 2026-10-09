#!/usr/bin/env bash
# Guard: skills/setup/bin/emit.sh + emit.ps1 determinism (goal D-8, kit v0.27.0).
#
# Behavioral cases (a)–(m) run in mktemp roots only — never emit into the live repo.
# Override EMIT_SH / EMIT_PS1 for mutation runs at the bottom.
#
# Exit 0 when no FAIL; 1 otherwise.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03
export PATH=/tmp/pwsh-tools:$PATH

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/setup/bin/emit.sh}"
EMIT_PS1="${EMIT_PS1:-$REPO_ROOT/skills/setup/bin/emit.ps1}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/setup}"
FIXTURE="$KIT/fixtures/self-answers.json"
BOOTSTRAP_IDS="$KIT/reference/bootstrap-ids.md"

pass=0; fail=0; skip=0
CLEANUP=()

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

mktemp_root() {
  local d; d="$(mktemp -d)"
  CLEANUP+=("$d")
  printf '%s' "$d"
}

mktemp_file() {
  local f; f="$(mktemp)"
  CLEANUP+=("$f")
  printf '%s' "$f"
}

copy_kit() {
  local dest="$1"
  cp -a "$KIT/." "$dest/"
}

class_a_ids() {
  awk -F'|' '
    /^\| [a-z0-9-]+ \|/ && $0 !~ /^\| id \|/ && $0 !~ /^\| flag \|/ {
      id=$2; gsub(/^ +| +$/, "", id)
      cls=$4; gsub(/^ +| +$/, "", cls)
      if (cls == "a text") print id
    }
  ' "$BOOTSTRAP_IDS" | LC_ALL=C sort -u
}

run_emit_sh() { # root --kit DIR [extra args...]
  local root="$1"; shift
  bash "$EMIT_SH" --root "$root" "$@"
}

run_emit_ps1() { # root --kit DIR [extra args...]
  local root="$1"; shift
  pwsh -NoProfile -File "$EMIT_PS1" --root "$root" "$@"
}

manifest_key_order_ok() { # manifest-path — top-level key order per D-3 (not jq's sorted keys)
  local mf="$1" got
  got="$(grep -E '^  "[^"]+":' "$mf" | sed 's/^  "\([^"]*\)".*/\1/' | paste -sd' ' -)"
  [[ "$got" == "kit kitVersion installedAt harnesses primary options seedFiles files answers" ]]
}

manifest_files_hashes_ok() { # root manifest-path
  local root="$1" mf="$2" p disk want
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    want="$(jq -r --arg p "$p" '.files[$p]' "$mf")"
    [[ -n "$want" && "$want" != null ]] || return 1
    [[ -f "$root/$p" ]] || return 1
    disk="$(sha256sum "$root/$p" | awk '{print $1}')"
    [[ "$disk" == "$want" ]] || return 1
  done < <(jq -r '.files | keys[]' "$mf" | LC_ALL=C sort)
}

jq_object_keys_sorted() { # manifest-path jq-path
  local mf="$1" path="$2" orig sorted
  orig="$(jq -c "$path" "$mf")"
  sorted="$(jq -cS "$path" "$mf")"
  [[ "$orig" == "$sorted" ]]
}

leftover_template_markers_empty() { # root
  local root="$1"
  ! grep -rqE '\{\{[A-Z_]+\}\}|<!-- BOOTSTRAP|<!-- IF|<!-- ENDIF' "$root" \
    --exclude='orchestration-kit.manifest.json' 2>/dev/null
}

case_a_twice_identical() {
  local r1 r2 rc
  r1="$(mktemp_root)"; r2="$(mktemp_root)"
  run_emit_sh "$r1" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  run_emit_sh "$r2" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  diff -r "$r1" "$r2" >/dev/null 2>&1
}

case_b_twin_parity() {
  local rsh rps
  rsh="$(mktemp_root)"; rps="$(mktemp_root)"
  run_emit_sh "$rsh" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  run_emit_ps1 "$rps" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  diff -r "$rsh" "$rps" >/dev/null 2>&1
}

case_c_manifest_shape() {
  local root mf
  root="$(mktemp_root)"
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  mf="$root/orchestration-kit.manifest.json"
  jq -e '.answers.schema == 1' "$mf" >/dev/null 2>&1 || return 1
  jq -e '.options.forge | type == "string"' "$mf" >/dev/null 2>&1 || return 1
  jq -e '.seedFiles | index("_goals/backlog.md") != null' "$mf" >/dev/null 2>&1 || return 1
  jq -e '.files | has("_goals/backlog.md") | not' "$mf" >/dev/null 2>&1 || return 1
  manifest_key_order_ok "$mf" || return 1
  manifest_files_hashes_ok "$root" "$mf" || return 1
  jq_object_keys_sorted "$mf" '.answers' || return 1
  jq_object_keys_sorted "$mf" '.options' || return 1
  jq_object_keys_sorted "$mf" '.answers.bootstrap' || return 1
  jq_object_keys_sorted "$mf" '.answers.tokens' || return 1
  jq_object_keys_sorted "$mf" '.answers.models' || return 1
  jq_object_keys_sorted "$mf" '.files' || return 1
}

case_d_no_leftovers() {
  local root
  root="$(mktemp_root)"
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  leftover_template_markers_empty "$root"
}

case_e1_template_rogue() {
  local kit root rc files err rogue_rel='agents/terminal.md'
  kit="$(mktemp_root)"; root="$(mktemp_root)"
  copy_kit "$kit"
  echo '{{ROGUE}}' >> "$kit/templates/agents/terminal.md"
  set +e
  err="$(run_emit_sh "$root" --kit "$kit" --answers "$FIXTURE" 2>&1)"
  rc=$?
  set -e
  files="$(find "$root" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$rc" -eq 3 && "$files" == "0" ]] \
    && grep -qF 'ROGUE' <<<"$err" \
    && grep -qF "$rogue_rel" <<<"$err"
}

case_e2_bootstrap_rogue() {
  local ans root rc err
  ans="$(mktemp_file)"; root="$(mktemp_root)"
  jq '.bootstrap["stack-note"]="{{ROGUE}}"' "$FIXTURE" > "$ans"
  set +e
  err="$(run_emit_sh "$root" --kit "$KIT" --answers "$ans" 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 5 ]] \
    && grep -qF 'verify: .claude/ORCHESTRATION.md: leftover token' <<<"$err" \
    && grep -qF 'verify: .cursor/ORCHESTRATION.md: leftover token' <<<"$err"
}

case_f_unbalanced_if() {
  local kit root rc err
  kit="$(mktemp_root)"; root="$(mktemp_root)"
  copy_kit "$kit"
  printf '\n<!-- IF loop -->\n' >> "$kit/templates/loop/SKILL.template.md"
  set +e
  err="$(run_emit_sh "$root" --kit "$kit" --answers "$FIXTURE" 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 6 ]] && grep -qE 'loop/SKILL.template.md:[0-9]+' <<<"$err"
}

case_g_check_answers() {
  local empty ids out rc got
  empty="$(mktemp_file)"
  jq '.bootstrap={}' "$FIXTURE" > "$empty"
  mapfile -t ids < <(class_a_ids)
  set +e
  out="$(run_emit_sh "$(mktemp_root)" --kit "$KIT" --check-answers --answers "$empty" 2>/dev/null)"
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || return 1
  mapfile -t got < <(printf '%s\n' "$out" | cut -f1 | LC_ALL=C sort -u)
  [[ "${#got[@]}" -eq "${#ids[@]}" ]] || return 1
  local i
  for i in "${!ids[@]}"; do
    [[ "${got[$i]}" == "${ids[$i]}" ]] || return 1
  done
  set +e
  out="$(run_emit_sh "$(mktemp_root)" --kit "$KIT" --check-answers --answers "$FIXTURE" 2>/dev/null)"
  rc=$?
  set -e
  [[ "$rc" -eq 0 && -z "$out" ]]
}

CASE_H_DETAIL=""

case_h_upgrade() {
  local root rc out mf target='.claude/agents/implementer.md' snap before after
  root="$(mktemp_root)"
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  snap="$(sha256sum "$root/$target" | awk '{print $1}')"
  printf '\nUSER_EDIT\n' >> "$root/$target"
  set +e
  out="$(run_emit_sh "$root" --kit "$KIT" --upgrade 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 4 && "$out" == *"blocked $target"* ]] || return 1
  set +e
  out="$(run_emit_sh "$root" --kit "$KIT" --dry-run --upgrade 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 4 && "$out" == *"blocked $target"* ]] || return 1
  run_emit_sh "$root" --kit "$KIT" --force --upgrade >/dev/null 2>&1 || return 1
  after="$(sha256sum "$root/$target" | awk '{print $1}')"
  CASE_H_DETAIL="before=$snap after=$after"
  [[ "$after" == "$snap" ]] || return 1

  # stale kit-owned manifest entry pruned when hash matches
  mf="$root/orchestration-kit.manifest.json"
  echo stale > "$root/.claude/agents/removed-stale.md"
  local stale_hash
  stale_hash="$(sha256sum "$root/.claude/agents/removed-stale.md" | awk '{print $1}')"
  jq --arg h "$stale_hash" '.files[".claude/agents/removed-stale.md"]=$h' "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
  run_emit_sh "$root" --kit "$KIT" --force --upgrade >/dev/null 2>&1 || return 1
  [[ ! -f "$root/.claude/agents/removed-stale.md" ]] || return 1

  # foreign entry kept
  mkdir -p "$root/.claude"
  echo '# checks' > "$root/.claude/checks.sh"
  local fh
  fh="$(sha256sum "$root/.claude/checks.sh" | awk '{print $1}')"
  jq --arg h "$fh" '.files[".claude/checks.sh"]=$h' "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
  run_emit_sh "$root" --kit "$KIT" --force --upgrade >/dev/null 2>&1 || return 1
  [[ -f "$root/.claude/checks.sh" ]] || return 1
  jq -e --arg h "$fh" '.files[".claude/checks.sh"] == $h' "$root/orchestration-kit.manifest.json" >/dev/null || return 1

  # seed edited stays untouched
  [[ -f "$root/_goals/backlog.md" ]] || return 1
  printf '\nSEED_EDIT\n' >> "$root/_goals/backlog.md"
  local seed_before
  seed_before="$(sha256sum "$root/_goals/backlog.md" | awk '{print $1}')"
  run_emit_sh "$root" --kit "$KIT" --force --upgrade >/dev/null 2>&1 || return 1
  [[ "$(sha256sum "$root/_goals/backlog.md" | awk '{print $1}')" == "$seed_before" ]] || return 1

  # manifest without answers
  jq 'del(.answers)' "$root/orchestration-kit.manifest.json" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
  set +e
  out="$(run_emit_sh "$root" --kit "$KIT" --upgrade 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 3 && "$out" == *"answers missing from manifest"* ]]
}

case_i_cursor_isolation_and_variants() {
  local root ans cc_ans
  root="$(mktemp_root)"
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  local claude_refs ro_files=() f agent base
  claude_refs="$(grep -rc '\.claude/' "$root/.cursor" --exclude-dir=setup 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
  [[ "${claude_refs:-0}" -eq 0 ]] || return 1
  for f in "$root/.cursor/agents"/*.md; do
    [[ -f "$f" ]] || continue
    if grep -qF 'readonly: true' "$f"; then
      ro_files+=("$f")
    fi
  done
  [[ "${#ro_files[@]}" -eq 3 ]] || return 1
  for agent in evaluator qa-evaluator diagnostician; do
    [[ -f "$root/.cursor/agents/$agent.md" ]] \
      && grep -qF 'readonly: true' "$root/.cursor/agents/$agent.md" || return 1
  done
  cmp -s "$root/.claude/skills/setup-models.map.md" "$root/.cursor/skills/setup-models.map.md" || return 1

  ans="$(mktemp_file)"
  cc_ans="$(mktemp_root)"
  jq '.harnesses=["copilot","codex"] | .primary="copilot"
    | .models["copilot"]={"frontier":"gpt-4.1","light":"gpt-4.1-mini","alt_family":"gpt-4.1","frontier_alt_family":"gpt-4.1","loop_chain":"gpt-4.1-mini","arbiter_same_family":true}
    | .models["codex"]={"frontier":"o3","light":"o4-mini","alt_family":"o3","frontier_alt_family":"o4-mini","loop_chain":"o4-mini"}' \
    "$FIXTURE" > "$ans"
  run_emit_sh "$cc_ans" --kit "$KIT" --answers "$ans" >/dev/null 2>&1 || return 1
  [[ "$(find "$cc_ans" -maxdepth 1 -name 'ORCHESTRATION.md' | wc -l)" -eq 1 ]] || return 1
  for f in "$cc_ans/.github/agents"/*.agent.md; do
    [[ -f "$f" ]] || return 1
    grep -qE '^model: \[' "$f" || return 1
  done
  # Copilot: feature lands as BOTH the native agent and a complete skill tree —
  # SKILL.md must exist next to reference/ + templates/ (regression: it was skipped).
  [[ -f "$cc_ans/.github/agents/feature.agent.md" ]] || return 1
  [[ -f "$cc_ans/.github/skills/feature/SKILL.md" ]] || return 1
  grep -qxF 'name: feature' "$cc_ans/.github/skills/feature/SKILL.md" || return 1
  [[ -f "$cc_ans/.github/skills/feature/templates/goal.md" ]] || return 1
  [[ -f "$cc_ans/.github/skills/feature/reference/continuation-ladder.md" ]] || return 1
}

case_j_executables() {
  local root
  root="$(mktemp_root)"
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  [[ -x "$root/_kit/log-spawn.sh" && -x "$root/_kit/memory.sh" && -x "$root/_loop/loop.sh" && -x "$root/_loop/breaker.sh" ]]
}

case_n_memory_emit_paths() {
  local root gi ga
  root="$(mktemp_root)"
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  [[ -f "$root/_kit/memory.ps1" && -f "$root/_memory/README.md" ]] || return 1
  gi="$(grep -cxF '_memory/.index/' "$root/.gitignore" || true)"
  gr="$(grep -cxF '_memory/raw/' "$root/.gitignore" || true)"
  [[ "$gi" -eq 1 && "$gr" -eq 1 ]] || return 1
  grep -qxF '_memory/' "$root/.gitignore" && return 1
  ga="$(grep -cxF '_memory/** text eol=lf' "$root/.gitattributes" || true)"
  [[ "$ga" -eq 1 ]]
}

case_o_memory_readme_prune() {
  local kit root user before after
  kit="$(mktemp_root)"; root="$(mktemp_root)"
  copy_kit "$kit"
  rm -f "$kit/templates/memory/README.md"
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  mkdir -p "$root/_memory/records/2026/10"
  user="$root/_memory/records/2026/10/20261009T120000Z-user0001.md"
  printf -- '---\nid: 20261009T120000Z-user0001\nkind: fact\ntitle: "u"\ndate: 2026-10-09\nsource: ""\ncommit: none\nharness: ""\ntags: []\nsupersedes: []\nsha256: aa\n---\nuser\n' > "$user"
  before="$(sha256sum "$user" | awk '{print $1}')"
  run_emit_sh "$root" --kit "$kit" --upgrade >/dev/null 2>&1 || return 1
  after="$(sha256sum "$user" | awk '{print $1}')"
  [[ ! -f "$root/_memory/README.md" && -f "$user" && "$before" == "$after" ]]
}

case_k_parse_twins() {
  bash -n "$EMIT_SH" 2>/dev/null || return 1
  command -v pwsh >/dev/null 2>&1 || return 0
  local perr
  perr="$(pwsh -NoProfile -Command "\$e=\$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$EMIT_PS1',[ref]\$null,[ref]\$e); \$e.Count" 2>/dev/null | tr -d '\r ')"
  [[ "$perr" == "0" ]]
}

case_l_dry_run_no_writes() {
  local root out n
  root="$(mktemp_root)"
  run_emit_sh "$root" --kit "$KIT" --answers "$FIXTURE" >/dev/null 2>&1 || return 1
  set +e
  out="$(run_emit_sh "$root" --kit "$KIT" --dry-run --upgrade 2>&1)"
  set -e
  n="$(printf '%s\n' "$out" | grep -c '^write ' || true)"
  [[ "$n" -eq 0 ]] \
    && grep -qF 'keep .gitattributes' <<<"$out" \
    && grep -qF 'keep .gitignore' <<<"$out" \
    && grep -qF 'keep CLAUDE.md' <<<"$out"
}

case_m_verify_sort_order() {
  local ans err_sh err_ps rc_sh rc_ps
  ans="$(mktemp_file)"
  jq '.bootstrap["stack-note"]="{{ROGUE_B}}" | .bootstrap["skills-tree"]="{{ROGUE_A}}"' "$FIXTURE" > "$ans"
  set +e
  err_sh="$(run_emit_sh "$(mktemp_root)" --kit "$KIT" --answers "$ans" 2>&1)"
  rc_sh=$?
  err_ps="$(run_emit_ps1 "$(mktemp_root)" --kit "$KIT" --answers "$ans" 2>&1)"
  rc_ps=$?
  set -e
  [[ "$rc_sh" -eq 5 && "$rc_ps" -eq 5 ]] || return 1
  [[ "$err_sh" == "$err_ps" ]] || return 1
  [[ "$err_sh" == "$(printf '%s\n' "$err_sh" | LC_ALL=C sort)" ]] || return 1
}

cleanup() {
  local d
  for d in "${CLEANUP[@]}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Cases (a)–(m)
# ---------------------------------------------------------------------------
if case_a_twice_identical; then
  report PASS "(a) fixture emitted twice → diff -r empty"
else
  report FAIL "(a) fixture emitted twice → diff -r empty"
fi

if command -v pwsh >/dev/null 2>&1; then
  if case_b_twin_parity; then
    report PASS "(b) emit.sh vs emit.ps1 → diff -r empty incl. manifest"
  else
    report FAIL "(b) emit.sh vs emit.ps1 → diff -r empty incl. manifest"
  fi
else
  report SKIP "(b) emit.sh vs emit.ps1 twin parity" "pwsh not on PATH"
fi

if case_c_manifest_shape; then
  report PASS "(c) manifest hashes, key order, seedFiles vs files"
else
  report FAIL "(c) manifest hashes, key order, seedFiles vs files"
fi

if case_d_no_leftovers; then
  report PASS "(d) emitted tree has no leftover template markers"
else
  report FAIL "(d) emitted tree has no leftover template markers"
fi

if case_e1_template_rogue; then
  report PASS "(e1) {{ROGUE}} in --kit template → exit 3, nothing written"
else
  report FAIL "(e1) {{ROGUE}} in --kit template → exit 3, nothing written"
fi

if case_e2_bootstrap_rogue; then
  report PASS "(e2) {{ROGUE}} in bootstrap answer → exit 5 naming emitted file"
else
  report FAIL "(e2) {{ROGUE}} in bootstrap answer → exit 5 naming emitted file"
fi

if case_f_unbalanced_if; then
  report PASS "(f) unbalanced <!-- IF loop --> → exit 6 with file:line"
else
  report FAIL "(f) unbalanced <!-- IF loop --> → exit 6 with file:line"
fi

if case_g_check_answers; then
  report PASS "(g) --check-answers: empty bootstrap ids vs fixture"
else
  report FAIL "(g) --check-answers: empty bootstrap ids vs fixture"
fi

if case_h_upgrade; then
  report PASS "(h) upgrade blocked/dry-run/force, prune, foreign, seed, missing answers" "${CASE_H_DETAIL:-}"
else
  report FAIL "(h) upgrade blocked/dry-run/force, prune, foreign, seed, missing answers" "${CASE_H_DETAIL:-}"
fi

if case_i_cursor_isolation_and_variants; then
  report PASS "(i) .cursor isolation, readonly agents, models.map parity, copilot+codex ORCH, copilot feature agent+SKILL.md"
else
  report FAIL "(i) .cursor isolation, readonly agents, models.map parity, copilot+codex ORCH, copilot feature agent+SKILL.md"
fi

if case_j_executables; then
  report PASS "(j) _kit/log-spawn.sh, memory.sh, _loop/{loop,breaker}.sh are executable"
else
  report FAIL "(j) _kit/log-spawn.sh, memory.sh, _loop/{loop,breaker}.sh are executable"
fi

if case_n_memory_emit_paths; then
  report PASS "(n) memory.ps1 + _memory/README.md; gitignore/gitattributes lines"
else
  report FAIL "(n) memory.ps1 + _memory/README.md; gitignore/gitattributes lines"
fi

if case_o_memory_readme_prune; then
  report PASS "(o) kit README removed → _memory/README.md pruned; user record kept"
else
  report FAIL "(o) kit README removed → _memory/README.md pruned; user record kept"
fi

if case_k_parse_twins; then
  report PASS "(k) bash -n emit.sh + pwsh parse emit.ps1"
else
  report FAIL "(k) bash -n emit.sh + pwsh parse emit.ps1"
fi

if case_l_dry_run_no_writes; then
  report PASS "(l) --dry-run --upgrade on fresh root prints zero write lines"
else
  report FAIL "(l) --dry-run --upgrade on fresh root prints zero write lines"
fi

if command -v pwsh >/dev/null 2>&1; then
  if case_m_verify_sort_order; then
    report PASS "(m) two rogue bootstrap answers → sorted identical stderr sh/ps1"
  else
    report FAIL "(m) two rogue bootstrap answers → sorted identical stderr sh/ps1"
  fi
else
  report SKIP "(m) verify stderr twin parity" "pwsh not on PATH"
fi

# ---------------------------------------------------------------------------
# Mutation evidence (only when running canonical twins — not when EMIT_SH overridden)
# ---------------------------------------------------------------------------
if [[ "$EMIT_SH" == "$REPO_ROOT/skills/setup/bin/emit.sh" ]]; then
  mut_j="$(mktemp_file)"
  cp "$EMIT_SH" "$mut_j"
  sed -i 's/chmod +x "$dest"/: # chmod disabled/' "$mut_j"
  EMIT_SH_SAVE="$EMIT_SH"
  EMIT_SH="$mut_j"
  if case_j_executables; then
    report FAIL "mutation (j): chmod +x disabled must fail executable assertion"
  else
    report PASS "mutation (j): chmod +x disabled → executable assertion fails (exit 1 expected from case)"
  fi
  EMIT_SH="$EMIT_SH_SAVE"

  mut_e="$(mktemp_file)"
  cp "$EMIT_SH" "$mut_e"
  sed -i 's/if ! verify_all; then/if false; then # verify disabled/' "$mut_e"
  EMIT_SH="$mut_e"
  if case_e2_bootstrap_rogue; then
    report FAIL "mutation (e2): verify disabled must fail bootstrap-rogue assertion"
  else
    report PASS "mutation (e2): verify disabled → bootstrap-rogue assertion fails"
  fi
  if case_m_verify_sort_order; then
    report FAIL "mutation (m): verify disabled must fail sorted-verify assertion"
  else
    report PASS "mutation (m): verify disabled → sorted-verify assertion fails"
  fi
  EMIT_SH="$EMIT_SH_SAVE"
  rm -f "$mut_j" "$mut_e"
fi

echo
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if [[ $fail -eq 0 ]]; then echo "RESULT: all assertions passed"; exit 0; fi
echo "RESULT: $fail assertion(s) FAILED"; exit 1
