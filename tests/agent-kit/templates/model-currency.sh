#!/usr/bin/env bash
# Regression guard for model-currency goal (kit v0.29.0): fast tier, arbiter warnings,
# loop denylist, upgrade compatibility, log-spawn model_check, template/guidance text,
# dogfood pins. Tracked, self-install-independent — no network, no LLM.
#
# Synthetic emits use mktemp roots only; nothing is written inside the live repo.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

. "$HERE/../lib/parallel.sh"
. "$HERE/../lib/emit-cache.sh"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"
LOG_SPAWN_SH="$REPO_ROOT/skills/agent-kit/templates/tools/log-spawn.sh"

TEMPLATES="$REPO_ROOT/skills/agent-kit/templates"
SETUP_SKILL="$REPO_ROOT/skills/agent-kit/SKILL.md"
EMITTER_CURSOR="$REPO_ROOT/skills/agent-kit/emitters/cursor.md"
EMITTER_CLAUDE="$REPO_ROOT/skills/agent-kit/emitters/claude-code.md"

TMP_BASE="$(mktemp -d)"
TMP_N=0
_suite_cleanup() {
  rm -rf "$TMP_BASE"
  par_cleanup
  emit_cache_cleanup
}
trap _suite_cleanup EXIT

pass=0
fail=0
skip=0

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

alloc_path() { # <prefix> → sets ALLOC_PATH (unique per call for parallel blocks)
  ALLOC_PATH="$(mktemp "$TMP_BASE/${1}.XXXXXX")"
}

alloc_root() {
  ALLOC_PATH="$(mktemp -d "$TMP_BASE/root.XXXXXX")"
}

alloc_answers() {
  alloc_path answers
  printf '' > "$ALLOC_PATH"
}

run_emit_sh() { # root [emit args...]
  bash "$EMIT_SH" --root "$1" --kit "$KIT" "${@:2}"
}

capture_emit_sh() { # root [emit args...] → EMIT_RC, EMIT_STDOUT, EMIT_STDERR files
  local root="$1"
  shift
  alloc_path emit-out
  EMIT_STDOUT="$ALLOC_PATH.out"
  EMIT_STDERR="$ALLOC_PATH.err"
  run_emit_sh "$root" "$@" >"$EMIT_STDOUT" 2>"$EMIT_STDERR"
  EMIT_RC=$?
}

warnings_from_stdout_file() {
  sed -n 's/.*warnings \([0-9][0-9]*\).*/\1/p' "$1" | head -1
}

assert_warn_stderr_only() { # stderr_file stdout_file exact_line
  local err="$1" out="$2" line="$3"
  grep -qxF "$line" "$err" || return 1
  ! grep -qxF "$line" "$out"
}

assert_problem_stderr_only() { # stderr_file stdout_file exact_line
  assert_warn_stderr_only "$@"
}

emit_cc_base() { # outfile — minimal claude-code answers from fixture
  jq '
    .harnesses = ["claude-code"] |
    .primary = "claude-code" |
    del(.models.cursor) |
    .models["claude-code"].frontier = "claude-opus-5-5" |
    .models["claude-code"].light = "claude-sonnet-5-5" |
    .models["claude-code"].fast = "claude-haiku-5-5" |
    .models["claude-code"].alt_family = "claude-opus-5-5" |
    .models["claude-code"].frontier_alt_family = "claude-opus-5-5" |
    .models["claude-code"].arbiter_same_family = true |
    .models["claude-code"].loop_chain = "claude-sonnet-5-5,claude-haiku-5-5"
  ' "$FIXTURE" > "$1"
}

emit_v028_answers() { # outfile — no fast, no arbiter_same_family, alt arbiter slot
  jq '
    .harnesses = ["claude-code"] |
    .primary = "claude-code" |
    del(.models.cursor) |
    .models["claude-code"].frontier = "claude-opus-5-5" |
    .models["claude-code"].light = "claude-sonnet-5-5" |
    del(.models["claude-code"].fast) |
    .models["claude-code"].alt_family = "claude-sonnet-5-5" |
    .models["claude-code"].frontier_alt_family = "claude-sonnet-5-5" |
    del(.models["claude-code"].arbiter_same_family) |
    .models["claude-code"].loop_chain = "claude-sonnet-5-5,claude-haiku-5-5"
  ' "$FIXTURE" > "$1"
}

frontmatter_block() { # file → prints YAML between first two --- lines
  awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f{print}' "$1"
}

frontmatter_field() { # file field → value
  awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f && $0 ~ /^'"$2"':/ {sub(/^'"$2"':[[:space:]]*/, ""); print; exit}' "$1"
}

skill_step3_section() {
  awk '/^## Step 3/{p=1; next} p && /^## Step/{exit} p' "$SETUP_SKILL"
}

answers_case1() { # outfile
  jq '
    .harnesses = ["claude-code", "cursor", "copilot", "codex"] |
    .primary = "claude-code" |
    .models["claude-code"] |= (. + {"fast": "cc-fast-id"}) |
    .models.cursor = {
      "frontier": "cur-front", "light": "cur-light", "fast": "cur-fast-id",
      "alt_family": "cur-alt", "frontier_alt_family": "cur-front",
      "arbiter_same_family": true, "loop_chain": "cur-light"
    } |
    .models.copilot = {
      "frontier": "cop-front", "light": "cop-light", "fast": "cop-fast-id",
      "alt_family": "cop-alt", "frontier_alt_family": "cop-front",
      "arbiter_same_family": true, "loop_chain": "cop-light"
    } |
    .models.codex = {
      "frontier": "cod-front", "light": "cod-light", "fast": "cod-fast-id",
      "alt_family": "cod-alt", "frontier_alt_family": "cod-front", "loop_chain": "cod-light"
    }
  ' "$FIXTURE" > "$1"
}

answers_case2() { # outfile
  jq '
    .harnesses = ["claude-code", "cursor"] |
    .primary = "claude-code" |
    .models["claude-code"] |= del(.fast) |
    .models.cursor |= del(.fast)
  ' "$FIXTURE" > "$1"
}

# ---------------------------------------------------------------------------
# Case 1 — fast tier on terminal (four harnesses)
# ---------------------------------------------------------------------------
case_1() {
  local ans root
  alloc_answers
  ans="$ALLOC_PATH"
  answers_case1 "$ans"
  alloc_root
  root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  grep -qxF 'model: cc-fast-id' "$root/.claude/agents/terminal.md" || return 1
  grep -qxF 'model: cur-fast-id' "$root/.cursor/agents/terminal.md" || return 1
  grep -qxF 'model: ["cop-fast-id"]' "$root/.github/agents/terminal.agent.md" || return 1
  grep -qxF 'model = "cod-fast-id"' "$root/.codex/agents/terminal.toml" || return 1
}

# Case 2 — no fast → light on terminal (IDs from fixture)
case_2() {
  local ans root cc_light cur_light
  cc_light="$(jq -r '.models["claude-code"].light' "$FIXTURE")"
  cur_light="$(jq -r '.models.cursor.light' "$FIXTURE")"
  alloc_answers
  ans="$ALLOC_PATH"
  answers_case2 "$ans"
  alloc_root
  root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  grep -qxF "model: $cc_light" "$root/.claude/agents/terminal.md" || return 1
  grep -qxF "model: $cur_light" "$root/.cursor/agents/terminal.md" || return 1
}

# Case 3 — frontier_alt_family == frontier without flag → warn 1; with flag → 0
case_3() {
  local ans root w line
  line='emit: warning: models.claude-code.frontier_alt_family equals frontier; set arbiter_same_family: true to accept a same-family arbiter'

  alloc_answers
  ans="$ALLOC_PATH"
  emit_cc_base "$ans"
  jq '
    .models["claude-code"].frontier_alt_family = .models["claude-code"].frontier |
    del(.models["claude-code"].arbiter_same_family)
  ' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root
  root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  w="$(warnings_from_stdout_file "$EMIT_STDOUT")"
  [[ "$EMIT_RC" -eq 0 && "$w" == 1 ]] || return 1
  assert_warn_stderr_only "$EMIT_STDERR" "$EMIT_STDOUT" "$line" || return 1

  jq '.models["claude-code"].arbiter_same_family = true' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root
  root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  w="$(warnings_from_stdout_file "$EMIT_STDOUT")"
  [[ "$EMIT_RC" -eq 0 && "$w" == 0 ]] || return 1
  ! grep -qF 'emit: warning:' "$EMIT_STDERR"
}

# Case 4 — alt_family arbiter warning; three equal + flag → no warn
case_4() {
  local ans root w line
  line='emit: warning: models.claude-code.frontier_alt_family equals alt_family; the rung-5 arbiter must not reuse the fix-cycle-2 model'

  alloc_answers
  ans="$ALLOC_PATH"
  emit_cc_base "$ans"
  jq '
    .models["claude-code"].frontier = "claude-opus-5-5" |
    .models["claude-code"].alt_family = "claude-sonnet-5-5" |
    .models["claude-code"].frontier_alt_family = "claude-sonnet-5-5" |
    .models["claude-code"].arbiter_same_family = true
  ' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root
  root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  w="$(warnings_from_stdout_file "$EMIT_STDOUT")"
  [[ "$EMIT_RC" -eq 0 && "$w" == 1 ]] || return 1
  assert_warn_stderr_only "$EMIT_STDERR" "$EMIT_STDOUT" "$line" || return 1

  jq '
    .models["claude-code"].frontier_alt_family = .models["claude-code"].frontier |
    .models["claude-code"].alt_family = .models["claude-code"].frontier |
    .models["claude-code"].arbiter_same_family = true
  ' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root
  root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  w="$(warnings_from_stdout_file "$EMIT_STDOUT")"
  [[ "$EMIT_RC" -eq 0 && "$w" == 0 ]] || return 1
  ! grep -qF 'emit: warning:' "$EMIT_STDERR"
}

# Case 5 — loop_chain denylist
case_5() {
  local ans root entry line
  for entry in best fable claude-fable-2026; do
    alloc_answers
    ans="$ALLOC_PATH"
    emit_cc_base "$ans"
    jq --arg e "$entry" '.models["claude-code"].loop_chain = $e' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
    line="emit: models.claude-code.loop_chain entry '${entry}' can bill usage credits in headless runs"
    alloc_root
    root="$ALLOC_PATH"
    capture_emit_sh "$root" --answers "$ans"
    [[ "$EMIT_RC" -eq 3 ]] || return 1
    assert_problem_stderr_only "$EMIT_STDERR" "$EMIT_STDOUT" "$line" || return 1
  done
  alloc_answers
  ans="$ALLOC_PATH"
  emit_cc_base "$ans"
  jq '.models["claude-code"].loop_chain = "x,fable"' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  line="emit: models.claude-code.loop_chain entry 'fable' can bill usage credits in headless runs"
  alloc_root
  root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 3 ]] || return 1
  assert_problem_stderr_only "$EMIT_STDERR" "$EMIT_STDOUT" "$line" || return 1
  alloc_answers
  ans="$ALLOC_PATH"
  emit_cc_base "$ans"
  alloc_root
  root="$ALLOC_PATH"
  run_emit_sh "$root" --answers "$ans" >/dev/null 2>&1
}

# Case 6 — type validation exit 3
case_6() {
  local ans root line
  alloc_answers
  ans="$ALLOC_PATH"
  emit_cc_base "$ans"
  jq '.models["claude-code"].arbiter_same_family = "yes"' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root
  root="$ALLOC_PATH"
  line='emit: models.claude-code.arbiter_same_family must be a boolean'
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 3 ]] || return 1
  assert_problem_stderr_only "$EMIT_STDERR" "$EMIT_STDOUT" "$line" || return 1

  alloc_answers
  ans="$ALLOC_PATH"
  emit_cc_base "$ans"
  jq '.models["claude-code"].fast = 42' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root
  root="$ALLOC_PATH"
  line='emit: models.claude-code.fast must be a string'
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 3 ]] || return 1
  assert_problem_stderr_only "$EMIT_STDERR" "$EMIT_STDOUT" "$line" || return 1
}

# Case 7 — v0.28-style upgrade manifest
case_7() {
  local ans root cc_light w line mf
  cc_light="$(jq -r '.models["claude-code"].light' "$FIXTURE")"
  line='emit: warning: models.claude-code.frontier_alt_family equals alt_family; the rung-5 arbiter must not reuse the fix-cycle-2 model'

  alloc_answers
  ans="$ALLOC_PATH"
  emit_v028_answers "$ans"
  alloc_root
  root="$ALLOC_PATH"
  run_emit_sh "$root" --answers "$ans" >/dev/null 2>&1 || return 1
  mf="$root/orchestration-kit.manifest.json"
  jq '.kitVersion = "0.28.0"' "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"

  capture_emit_sh "$root" --upgrade
  w="$(warnings_from_stdout_file "$EMIT_STDOUT")"
  [[ "$EMIT_RC" -eq 0 && "$w" == 1 ]] || return 1
  assert_warn_stderr_only "$EMIT_STDERR" "$EMIT_STDOUT" "$line" || return 1
  grep -qxF "model: $cc_light" "$root/.claude/agents/terminal.md" || return 1

  jq '.models["claude-code"].loop_chain = "fable"' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  jq --slurpfile a "$ans" '.answers = $a[0]' "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
  line="emit: models.claude-code.loop_chain entry 'fable' can bill usage credits in headless runs"
  capture_emit_sh "$root" --upgrade
  [[ "$EMIT_RC" -eq 3 ]] || return 1
  assert_problem_stderr_only "$EMIT_STDERR" "$EMIT_STDOUT" "$line" || return 1
}

# Case 9 — bracket model unquoted in Cursor agents
case_9() {
  local ans root model_line
  alloc_answers
  ans="$ALLOC_PATH"
  jq '
    .harnesses = ["cursor"] |
    .primary = "cursor" |
    del(.models["claude-code"]) |
    .models.cursor = {
      "frontier": "claude-opus-5-5-high[effort=high]",
      "light": "composer-2.5-fast",
      "alt_family": "claude-sonnet-5-5-xhigh",
      "frontier_alt_family": "claude-opus-5-5-high[effort=high]",
      "arbiter_same_family": true,
      "loop_chain": "composer-2.5-fast"
    }
  ' "$FIXTURE" > "$ans"
  alloc_root
  root="$ALLOC_PATH"
  run_emit_sh "$root" --answers "$ans" >/dev/null 2>&1 || return 1
  model_line="$(frontmatter_field "$root/.cursor/agents/evaluator.md" model)"
  [[ "$model_line" == 'claude-opus-5-5-high[effort=high]' ]] || return 1
  ! grep -q '^model: "' "$root/.cursor/agents/evaluator.md"
}

logspawn_run_case10() { # <label> <runner...>
  local label="$1"
  shift
  local runner=("$@")
  local fx log out err rc want_err

  # match (gpt vs o3)
  alloc_root
  fx="$ALLOC_PATH"
  mkdir -p "$fx/_goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_goals/demo/spawns/31-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_goals/demo/spawns/31-report.md"
  log="$fx/_goals/demo/orchestration-log.md"
  (
    cd "$fx" || exit 1
    "${runner[@]}" spawn --goal demo --agent e --phase P --model-requested gpt-4.1-mini \
         --context _goals/demo/spawns/31-context.md >/dev/null
    out="$("${runner[@]}" outcome --goal demo --spawn 31 --report _goals/demo/spawns/31-report.md \
          --verdict PASS --model-reported o3 2>/dev/null)"; rc=$?
    [[ $rc -eq 0 && "$out" == *'model_check: match'* ]] || exit 1
    grep -qF 'model_check: match' "$log" || exit 1
  ) || return 1

  # MISMATCH exact stderr + log OUTCOME line
  alloc_root
  fx="$ALLOC_PATH"
  mkdir -p "$fx/_goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_goals/demo/spawns/32-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_goals/demo/spawns/32-report.md"
  log="$fx/_goals/demo/orchestration-log.md"
  want_err='log-spawn: MODEL-FAMILY-MISMATCH requested=claude-sonnet-5-5 reported=gpt-4.1'
  (
    cd "$fx" || exit 1
    "${runner[@]}" spawn --goal demo --agent e --phase P --model-requested claude-sonnet-5-5 \
         --context _goals/demo/spawns/32-context.md >/dev/null
    err="$("${runner[@]}" outcome --goal demo --spawn 32 --report _goals/demo/spawns/32-report.md \
          --verdict PASS --model-reported gpt-4.1 2>&1 >/dev/null)"; rc=$?
    [[ $rc -eq 0 && "$err" == *"$want_err"* ]] || exit 1
    grep -qF 'model_check: MISMATCH' "$log" || exit 1
    grep -qF "$want_err" <<<"$err" || exit 1
  ) || return 1

  # unverified (unknown reported)
  alloc_root
  fx="$ALLOC_PATH"
  mkdir -p "$fx/_goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_goals/demo/spawns/33-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_goals/demo/spawns/33-report.md"
  log="$fx/_goals/demo/orchestration-log.md"
  (
    cd "$fx" || exit 1
    "${runner[@]}" spawn --goal demo --agent e --phase P --model-requested gpt-4.1-mini \
         --context _goals/demo/spawns/33-context.md >/dev/null
    out="$("${runner[@]}" outcome --goal demo --spawn 33 --report _goals/demo/spawns/33-report.md \
          --verdict PASS --model-reported unknown 2>/dev/null)"; rc=$?
    [[ $rc -eq 0 && "$out" == *'model_check: unverified'* ]] || exit 1
    grep -qF 'model_check: unverified' "$log" || exit 1
  ) || return 1

  # blank requested
  alloc_root
  fx="$ALLOC_PATH"
  mkdir -p "$fx/_goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_goals/demo/spawns/34-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_goals/demo/spawns/34-report.md"
  log="$fx/_goals/demo/orchestration-log.md"
  (
    cd "$fx" || exit 1
    "${runner[@]}" spawn --goal demo --agent e --phase P --model-requested " " \
         --context _goals/demo/spawns/34-context.md >/dev/null
    out="$("${runner[@]}" outcome --goal demo --spawn 34 --report _goals/demo/spawns/34-report.md \
          --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
    [[ $rc -eq 0 && "$out" == *'model_check: unverified'* ]] || exit 1
    grep -qF 'model_check: unverified' "$log" || exit 1
  ) || return 1
}

# Case 10 — log-spawn model_check (canonical twins)
case_10_logspawn_bash() {
  logspawn_run_case10 bash bash "$LOG_SPAWN_SH"
}

# Case 11 — canonical agent templates (frontmatter only)
case_11() {
  local fm
  fm="$(frontmatter_block "$TEMPLATES/agents/terminal.md")"
  grep -qF 'model: {{MODEL_FAST}}' <<<"$fm" || return 1
  grep -qF 'effort: low' <<<"$fm" || return 1
  fm="$(frontmatter_block "$TEMPLATES/agents/diagnostician.md")"
  grep -qF 'effort: xhigh' <<<"$fm" || return 1
}

# Case 12 — structural text guards
case_12() {
  local step3
  step3="$(skill_step3_section)"
  grep -qiE '\| *`fast`.*terminal' "$TEMPLATES/models.map.md" || return 1
  grep -qF '{{CLAUDE_MODEL_FAST}}' "$TEMPLATES/models.map.md" || return 1
  grep -qiF 'same-family arbiter' "$TEMPLATES/models.map.md" || return 1
  grep -qiF 'fast → light' "$TEMPLATES/models.map.md" || return 1
  grep -qF 'agent models' <<<"$step3" || return 1
  grep -qF 'arbiter_same_family' <<<"$step3" || return 1
  grep -qF 'fable' <<<"$step3" || return 1
  grep -qF 'unquoted' "$EMITTER_CURSOR" || return 1
  grep -qF 'Anthropic models only' "$EMITTER_CLAUDE" || return 1
  grep -qF 'model_check' "$TEMPLATES/ORCHESTRATION.md" || return 1
  grep -qF 'model_check' "$TEMPLATES/skills/feature/SKILL.template.md" || return 1
  grep -qF '`evaluator`' "$TEMPLATES/skills/feature/SKILL.template.md" || return 1
  grep -qF '`qa-evaluator`' "$TEMPLATES/skills/feature/SKILL.template.md" || return 1
  grep -qF '`diagnostician`' "$TEMPLATES/skills/feature/SKILL.template.md" || return 1
  grep -qF 're-spawn once on `MISMATCH`' "$TEMPLATES/skills/feature/SKILL.template.md" || return 1
}

# Case 13 — dogfood stale pins absent
case_13() {
  local hits=""
  hits="$(grep -rn 'cursor-grok-4.6-xhigh\|gpt-5.6-sol-medium' \
    "$REPO_ROOT/.claude" "$REPO_ROOT/.cursor" \
    "$REPO_ROOT/orchestration-kit.manifest.json" "$FIXTURE" 2>/dev/null || true)"
  [[ -z "$hits" ]]
}

case_8_bash() {
  case_1 && case_2 && case_3 && case_4 && case_5 && case_6 && case_7
}

# ---------------------------------------------------------------------------
# Run cases 1–13
# ---------------------------------------------------------------------------
if [[ -n "${MODEL_CURRENCY_ONLY:-}" ]]; then
  case "${MODEL_CURRENCY_ONLY}" in
    11) case_11; exit $? ;;
    5)  case_5; exit $? ;;
    *)  echo "unknown MODEL_CURRENCY_ONLY=${MODEL_CURRENCY_ONLY}" >&2; exit 2 ;;
  esac
fi

CASE8_LABEL="case 8 bash-only emit.sh bundle (cases 1–7 regression gate)"

blk_case_1() {
  if case_1; then report PASS "case 1 fast tier → terminal model on claude/cursor/copilot/codex"
  else report FAIL "case 1 fast tier → terminal model on claude/cursor/copilot/codex"; fi
}
blk_case_2() {
  if case_2; then report PASS "case 2 no fast → terminal uses light ID"
  else report FAIL "case 2 no fast → terminal uses light ID"; fi
}
blk_case_3() {
  if case_3; then report PASS "case 3 frontier_alt_family equals frontier warning + flag silence"
  else report FAIL "case 3 frontier_alt_family equals frontier warning + flag silence"; fi
}
blk_case_4() {
  if case_4; then report PASS "case 4 alt_family arbiter warning; three equal + flag silent"
  else report FAIL "case 4 alt_family arbiter warning; three equal + flag silent"; fi
}
blk_case_5() {
  if case_5; then report PASS "case 5 loop_chain denylist (best/fable/claude-fable/x,fable) + clean chain"
  else report FAIL "case 5 loop_chain denylist (best/fable/claude-fable/x,fable) + clean chain"; fi
}
blk_case_6() {
  if case_6; then report PASS "case 6 arbiter_same_family boolean + fast string validation"
  else report FAIL "case 6 arbiter_same_family boolean + fast string validation"; fi
}
blk_case_7() {
  if case_7; then report PASS "case 7 v0.28 upgrade manifest warn + fable exit 3 + terminal on light"
  else report FAIL "case 7 v0.28 upgrade manifest warn + fable exit 3 + terminal on light"; fi
}
blk_case_8() {
  if case_8_bash; then report PASS "$CASE8_LABEL"
  else report FAIL "$CASE8_LABEL"; fi
}
blk_case_9() {
  if case_9; then report PASS "case 9 bracket-param Cursor model emitted unquoted"
  else report FAIL "case 9 bracket-param Cursor model emitted unquoted"; fi
}
blk_case_10_bash() {
  if case_10_logspawn_bash; then report PASS "case 10 log-spawn.sh model_check (match, MISMATCH, unverified x2)"
  else report FAIL "case 10 log-spawn.sh model_check (match, MISMATCH, unverified x2)"; fi
}
blk_case_11() {
  if case_11; then report PASS "case 11 terminal {{MODEL_FAST}}/effort low; diagnostician xhigh (frontmatter)"
  else report FAIL "case 11 terminal {{MODEL_FAST}}/effort low; diagnostician xhigh (frontmatter)"; fi
}
blk_case_12() {
  if case_12; then report PASS "case 12 models.map + SKILL Step 3 + emitters + model_check guidance"
  else report FAIL "case 12 models.map + SKILL Step 3 + emitters + model_check guidance"; fi
}
blk_case_13() {
  if case_13; then report PASS "case 13 dogfood: no cursor-grok / gpt-5.6-sol-medium pins"
  else report FAIL "case 13 dogfood: no cursor-grok / gpt-5.6-sol-medium pins"; fi
}

PAR_COUNTERS="pass fail skip"
PAR_REPORT_FAIL="report"

emit_cache_init
par_init
par_block blk_case_1
par_block blk_case_2
par_block blk_case_3
par_block blk_case_4
par_block blk_case_5
par_block blk_case_6
par_block blk_case_7
par_block blk_case_8
par_block blk_case_9
par_block blk_case_10_bash
par_block blk_case_11
par_block blk_case_12
par_block blk_case_13
par_finish
emit_cache_verify

# ---------------------------------------------------------------------------
# Mutation checks (AC2) — temp copies only
# ---------------------------------------------------------------------------
if [[ -n "${MODEL_CURRENCY_NESTED:-}" ]]; then
  report SKIP "mutation AC2 self-check" "nested run (MODEL_CURRENCY_NESTED set) — recursion guard"
elif [[ "$EMIT_SH" != "$REPO_ROOT/skills/agent-kit/bin/emit.sh" ]]; then
  report SKIP "mutation AC2 self-check" "EMIT_SH overridden — would not mutate the live emitter"
else
  alloc_root
  mut_root="$ALLOC_PATH"
  cp -a "$REPO_ROOT/tests" "$REPO_ROOT/skills" "$mut_root/"
  sed -i 's/{{MODEL_FAST}}/{{MODEL_LIGHT}}/' "$mut_root/skills/agent-kit/templates/agents/terminal.md"
  mut_rc=0
  MODEL_CURRENCY_NESTED=1 AGENT_KIT_EMIT_CACHE=off bash "$mut_root/tests/agent-kit/templates/model-currency.sh" >/dev/null 2>&1 || mut_rc=$?
  if [[ "$mut_rc" -eq 1 ]]; then
    report PASS "mutation AC2: terminal template MODEL_LIGHT revert fails full script (exit 1)"
  else
    report FAIL "mutation AC2: terminal template MODEL_LIGHT revert must exit exactly 1" "rc=$mut_rc"
  fi

  alloc_path mut-emit
  mut_emit="$ALLOC_PATH"
  cp "$EMIT_SH" "$mut_emit"
  sed -i 's/LOOP_CHAIN_USAGE_CREDIT_DENYLIST=(best fable/LOOP_CHAIN_USAGE_CREDIT_DENYLIST=(best/' "$mut_emit"
  mut5_rc=0
  MODEL_CURRENCY_NESTED=1 AGENT_KIT_EMIT_CACHE=off EMIT_SH="$mut_emit" MODEL_CURRENCY_ONLY=5 bash "$HERE/model-currency.sh" >/dev/null 2>&1 || mut5_rc=$?
  if [[ "$mut5_rc" -eq 1 ]]; then
    report PASS "mutation AC2: fable denylist removal fails case 5 (exit 1)"
  else
    report FAIL "mutation AC2: fable denylist removal must exit exactly 1" "rc=$mut5_rc"
  fi
fi

echo
echo "=== model-currency summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
