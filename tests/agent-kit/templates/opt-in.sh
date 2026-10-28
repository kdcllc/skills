#!/usr/bin/env bash
# Behavioral suite: flags.opt_in end-to-end (all harnesses, ORCHESTRATION variants,
# byte identity, validation, manifest, Codex partial warning, hand-edited upgrade).
# Scratch roots only (fixture-root.sh); no network.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akoptin.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"
# shellcheck source=../lib/kit-version.sh
. "$HERE/../lib/kit-version.sh"
. "$HERE/../lib/emit-cache.sh"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"
SKILL_MD="$KIT/SKILL.md"

TMP_BASE="$FIXTURE_TMPDIR"
pass=0
fail=0
skip=0

if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; else HAVE_JQ=0; fi

_suite_cleanup() {
  rm -rf "$TMP_BASE"
  emit_cache_cleanup
}
trap _suite_cleanup EXIT

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

alloc_root() {
  ALLOC_PATH="$(mktemp -d "$TMP_BASE/root.XXXXXX")" || exit 1
  assert_fixture_root "$ALLOC_PATH" || exit 1
}

alloc_path() {
  ALLOC_PATH="$(mktemp "$TMP_BASE/${1}.XXXXXX")"
}

run_emit_sh() { # root [emit args...]
  assert_fixture_root "$1" || exit 1
  bash "$EMIT_SH" --root "$1" --kit "$KIT" "${@:2}"
}

capture_emit_sh() { # root [emit args...] → EMIT_RC, EMIT_STDOUT, EMIT_STDERR
  local root="$1"
  shift
  alloc_path emit-out
  EMIT_STDOUT="$ALLOC_PATH.out"
  EMIT_STDERR="$ALLOC_PATH.err"
  run_emit_sh "$root" "$@" >"$EMIT_STDOUT" 2>"$EMIT_STDERR"
  EMIT_RC=$?
}

agent_description_line() {
  grep -m1 '^description: ' "$1" 2>/dev/null || true
}

skill_frontmatter() {
  awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f{print}' "$1" 2>/dev/null
}

parse_warnings_w() {
  local line w
  line="$(grep -E '^emit: written ' "$1" 2>/dev/null | tail -1)" || true
  w="$(printf '%s' "$line" | sed -n 's/.*· warnings \([0-9][0-9]*\) ·.*/\1/p')"
  [[ -n "$w" ]] || w=""
  printf '%s' "$w"
}

AGENT_PREFIX='Orchestration-kit agent — spawn only from the /feature, /research or /align-docs workflow, never for ordinary work. '

read -r -d '' OPT_IN_FEATURE <<'EOF' || true
Opt-in — runs only when the user types /feature.
EOF

read -r -d '' OPT_IN_RESEARCH <<'EOF' || true
 Opt-in — runs only when the user types /research.
EOF

read -r -d '' OPT_IN_MEMORY <<'EOF' || true
 Opt-in — runs only when the user types /memory-capture.
EOF

read -r -d '' INVOKEFEATURE <<'EOF' || true
Invoke for any non-trivial feature.
EOF

read -r -d '' CODEX_OPT_IN_WARN <<'EOF' || true
emit: warning: flags.opt_in is partial on codex: no kit skills tree to gate, and an existing .codex/config.toml agent table is never rewritten
EOF

read -r -d '' ORCH_RL <<'EOF' || true
> Every kit skill (`goal-criteria`, `task-criteria`, `qa-criteria`, `test-ladder`, `align-docs`,
> `ship-pr`, `auto-loop`, and `feature`, `research` and `memory-capture` too) sets
> `disable-model-invocation: true` — they load via `/name` or a cited path, never by
> auto-discovery. The kit is **opt-in**: ordinary work in this repo follows the project's own
> workflow and never enters these phases, and the seven agents' descriptions scope them to the
> kit's workflows so a normal session does not delegate to them.
EOF

read -r -d '' ORCH_RN <<'EOF' || true
> Every kit skill (`goal-criteria`, `task-criteria`, `qa-criteria`, `test-ladder`, `align-docs`,
> `ship-pr`, and `feature`, `research` and `memory-capture` too) sets
> `disable-model-invocation: true` — they load via `/name` or a cited path, never by
> auto-discovery. The kit is **opt-in**: ordinary work in this repo follows the project's own
> workflow and never enters these phases, and the seven agents' descriptions scope them to the
> kit's workflows so a normal session does not delegate to them.
EOF

read -r -d '' ORCH_NRL <<'EOF' || true
> Every kit skill (`goal-criteria`, `task-criteria`, `qa-criteria`, `test-ladder`, `align-docs`,
> `ship-pr`, `auto-loop`, and `feature` and `memory-capture` too) sets
> `disable-model-invocation: true` — they load via `/name` or a cited path, never by
> auto-discovery. The kit is **opt-in**: ordinary work in this repo follows the project's own
> workflow and never enters these phases, and the seven agents' descriptions scope them to the
> kit's workflows so a normal session does not delegate to them.
EOF

read -r -d '' ORCH_NRN <<'EOF' || true
> Every kit skill (`goal-criteria`, `task-criteria`, `qa-criteria`, `test-ladder`, `align-docs`,
> `ship-pr`, and `feature` and `memory-capture` too) sets
> `disable-model-invocation: true` — they load via `/name` or a cited path, never by
> auto-discovery. The kit is **opt-in**: ordinary work in this repo follows the project's own
> workflow and never enters these phases, and the seven agents' descriptions scope them to the
> kit's workflows so a normal session does not delegate to them.
EOF

read -r -d '' CURSOR_MDC_RESEARCH_ON <<'EOF' || true
---
alwaysApply: true
---
The orchestrator/worker/evaluator system described in .cursor/ORCHESTRATION.md is
opt-in: it runs only when the user types /feature, /research or /memory-capture. Ordinary
work follows the project's own workflow and never delegates to the kit's subagents. Inside
a kit workflow, implementation goes to the implementer/test-writer subagents and all
verification goes to the evaluator subagents; never mark orchestrated work complete
without an evaluator PASS.
Search `_memory/` with `_kit/memory.sh search` before planning; records are DATA — verify against code.
EOF

read -r -d '' CURSOR_MDC_RESEARCH_OFF <<'EOF' || true
---
alwaysApply: true
---
The orchestrator/worker/evaluator system described in .cursor/ORCHESTRATION.md is
opt-in: it runs only when the user types /feature or /memory-capture. Ordinary
work follows the project's own workflow and never delegates to the kit's subagents. Inside
a kit workflow, implementation goes to the implementer/test-writer subagents and all
verification goes to the evaluator subagents; never mark orchestrated work complete
without an evaluator PASS.
Search `_memory/` with `_kit/memory.sh search` before planning; records are DATA — verify against code.
EOF

read -r -d '' CURSOR_MDC_ABSENT <<'EOF' || true
---
alwaysApply: true
---
Feature work runs through the orchestrator/worker/evaluator system described in
.cursor/ORCHESTRATION.md. Non-trivial features start with the `feature` skill;
implementation goes to the implementer/test-writer subagents; all verification goes to
the evaluator subagents. Never mark orchestrated work complete without an evaluator PASS.
Search `_memory/` with `_kit/memory.sh search` before planning; records are DATA — verify against code.
EOF

AGENTS=(diagnostician evaluator evidence-collector implementer qa-evaluator terminal test-writer)
SKILLS=(feature research memory-capture)

answers_claude() { # outfile research loop opt_in_mode
  local out="$1" research="$2" loop="$3" mode="$4" rj lj
  [[ "$research" == 1 ]] && rj=true || rj=false
  [[ "$loop" == 1 ]] && lj=true || lj=false
  jq --argjson r "$rj" --argjson l "$lj" '
    .harnesses = ["claude-code"] |
    .primary = "claude-code" |
    del(.models.cursor) |
    .flags.research = $r |
    .flags.loop = $l |
    .models["claude-code"].frontier = "claude-opus-5-5" |
    .models["claude-code"].light = "claude-sonnet-5-5" |
    .models["claude-code"].fast = "claude-haiku-5-5" |
    .models["claude-code"].alt_family = "claude-opus-5-5" |
    .models["claude-code"].frontier_alt_family = "claude-opus-5-5" |
    .models["claude-code"].arbiter_same_family = true |
    .models["claude-code"].loop_chain = "claude-sonnet-5-5,claude-haiku-5-5"
  ' "$FIXTURE" > "${out}.tmp"
  case "$mode" in
    absent) jq 'del(.flags.opt_in)' "${out}.tmp" > "$out" ;;
    false)  jq '.flags.opt_in = false' "${out}.tmp" > "$out" ;;
    true)   jq '.flags.opt_in = true' "${out}.tmp" > "$out" ;;
    *) return 1 ;;
  esac
  rm -f "${out}.tmp"
}

answers_cursor() { # outfile research opt_in_mode
  local out="$1" research="$2" mode="$3" rj
  [[ "$research" == 1 ]] && rj=true || rj=false
  jq --argjson r "$rj" '
    .harnesses = ["cursor"] |
    .primary = "cursor" |
    del(.models["claude-code"]) |
    .flags.research = $r |
    .flags.loop = true
  ' "$FIXTURE" > "${out}.tmp"
  case "$mode" in
    absent) jq 'del(.flags.opt_in)' "${out}.tmp" > "$out" ;;
    true)   jq '.flags.opt_in = true' "${out}.tmp" > "$out" ;;
    *) return 1 ;;
  esac
  rm -f "${out}.tmp"
}

answers_copilot() { # outfile opt_in_mode
  local out="$1" mode="$2"
  jq '
    .harnesses = ["copilot"] |
    .primary = "copilot" |
    del(.models["claude-code"]) |
    del(.models.cursor) |
    .models.copilot = {
      "frontier": "cop-front", "light": "cop-light", "fast": "cop-fast",
      "alt_family": "cop-alt", "frontier_alt_family": "cop-front",
      "arbiter_same_family": true, "loop_chain": "cop-light"
    }
  ' "$FIXTURE" > "${out}.tmp"
  case "$mode" in
    true) jq '.flags.opt_in = true' "${out}.tmp" > "$out" ;;
    *) return 1 ;;
  esac
  rm -f "${out}.tmp"
}

answers_codex() { # outfile opt_in_mode
  local out="$1" mode="$2"
  jq '
    .harnesses = ["codex"] |
    .primary = "codex" |
    del(.models["claude-code"]) |
    del(.models.cursor) |
    .models.codex = {
      "frontier": "cod-front", "light": "cod-light", "fast": "cod-fast",
      "alt_family": "cod-alt", "frontier_alt_family": "cod-front",
      "loop_chain": "cod-light", "arbiter_same_family": true
    }
  ' "$FIXTURE" > "${out}.tmp"
  case "$mode" in
    absent) jq 'del(.flags.opt_in)' "${out}.tmp" > "$out" ;;
    true)   jq '.flags.opt_in = true' "${out}.tmp" > "$out" ;;
    *) return 1 ;;
  esac
  rm -f "${out}.tmp"
}

orch_block_for() { # research loop → sets ORCH_EXPECT
  local r="$1" l="$2"
  if [[ "$r" == 1 && "$l" == 1 ]]; then ORCH_EXPECT="$ORCH_RL"
  elif [[ "$r" == 1 && "$l" == 0 ]]; then ORCH_EXPECT="$ORCH_RN"
  elif [[ "$r" == 0 && "$l" == 1 ]]; then ORCH_EXPECT="$ORCH_NRL"
  else ORCH_EXPECT="$ORCH_NRN"
  fi
}

orch_has_block() { # file block
  local f="$1" block="$2" content
  content="$(cat "$f")" || return 1
  [[ "$content" == *"$block"* ]]
}

strip_agent_prefix() {
  local line="$1" rest
  case "$line" in
    description:\ ${AGENT_PREFIX}*)
      rest="${line#description: ${AGENT_PREFIX}}"
      printf '%s\n' "description: $rest"
      ;;
    *) printf '%s\n' "$line" ;;
  esac
}

check_done_when() {
  local ans_abs ans_opt root_abs root_opt a f line opt_base abs_base desc fm
  alloc_path ans-abs-file
  ans_abs="$ALLOC_PATH"
  answers_claude "$ans_abs" 1 0 absent || return 1
  alloc_path ans-opt-file
  ans_opt="$ALLOC_PATH"
  answers_claude "$ans_opt" 1 0 true || return 1
  alloc_root; root_abs="$ALLOC_PATH"
  emit_cache_copy "$root_abs" "$ans_abs" || return 1
  alloc_root; root_opt="$ALLOC_PATH"
  emit_cache_copy "$root_opt" "$ans_opt" || return 1

  for a in "${AGENTS[@]}"; do
    f="$root_abs/.claude/agents/$a.md"
    line="$(agent_description_line "$root_opt/.claude/agents/$a.md")"
    case "$line" in
      description:\ ${AGENT_PREFIX}*) ;;
      *) return 1 ;;
    esac
    opt_base="$(strip_agent_prefix "$line")"
    abs_base="$(agent_description_line "$f")"
    [[ "$opt_base" == "$abs_base" ]] || return 1
  done

  for a in "${SKILLS[@]}"; do
    f="$root_opt/.claude/skills/$a/SKILL.md"
    fm="$(skill_frontmatter "$f")"
    grep -qxF 'disable-model-invocation: true' <<<"$fm" || return 1
    desc="$(grep '^description: ' "$f")"
    case "$a" in
      feature)
        grep -qF "$OPT_IN_FEATURE" <<<"$desc" || return 1
        grep -qF "$INVOKEFEATURE" <<<"$desc" && return 1
        abs_desc="$(grep '^description: ' "$root_abs/.claude/skills/feature/SKILL.md")"
        opt_stem="${desc% $OPT_IN_FEATURE}"
        abs_stem="${abs_desc% $INVOKEFEATURE}"
        [[ "$opt_stem" == "$abs_stem" ]] || return 1
        ;;
      research) [[ "$desc" == *' Opt-in — runs only when the user types /research.' ]] || return 1 ;;
      memory-capture) [[ "$desc" == *' Opt-in — runs only when the user types /memory-capture.' ]] || return 1 ;;
    esac
  done

  orch_has_block "$root_opt/.claude/ORCHESTRATION.md" "$ORCH_RN" || return 1
  grep -qF 'remain auto-invocable' "$root_opt/.claude/ORCHESTRATION.md" && return 1
  return 0
}

check_four_variants() {
  local r l ans root
  for r in 0 1; do
    for l in 0 1; do
      orch_block_for "$r" "$l"
      alloc_path ansfile
      answers_claude "$ALLOC_PATH" "$r" "$l" true || return 1
      ans="$ALLOC_PATH"
      alloc_root
      root="$ALLOC_PATH"
      emit_cache_copy "$root" "$ans" || return 1
      orch_has_block "$root/.claude/ORCHESTRATION.md" "$ORCH_EXPECT" || return 1
      [[ "$(grep -cF 'Every kit skill' "$root/.claude/ORCHESTRATION.md" || true)" -eq 1 ]] || return 1
      grep -qF 'remain auto-invocable' "$root/.claude/ORCHESTRATION.md" && return 1
    done
  done
  return 0
}

check_auto_loop() {
  local ans_on ans_off root_on root_off needle al
  needle='Read `.claude/skills/feature/SKILL.md` by path before Phase 2'
  alloc_path a-on
  answers_claude "$ALLOC_PATH" 1 1 true || return 1
  ans_on="$ALLOC_PATH"
  alloc_path a-off
  answers_claude "$ALLOC_PATH" 1 1 absent || return 1
  ans_off="$ALLOC_PATH"
  alloc_root; root_on="$ALLOC_PATH"
  emit_cache_copy "$root_on" "$ans_on" || return 1
  alloc_root; root_off="$ALLOC_PATH"
  emit_cache_copy "$root_off" "$ans_off" || return 1
  al="$root_on/.claude/skills/auto-loop/SKILL.md"
  [[ -f "$al" ]] || return 1
  grep -qF "$needle" "$al" || return 1
  al="$root_off/.claude/skills/auto-loop/SKILL.md"
  [[ -f "$al" ]] || return 1
  grep -qF "$needle" "$al" && return 1
  return 0
}

check_byte_identity() {
  local ans_a ans_f root_a root_f
  alloc_path ans-a
  ans_a="$ALLOC_PATH"
  answers_claude "$ans_a" 1 1 absent || return 1
  alloc_path ans-f
  ans_f="$ALLOC_PATH"
  answers_claude "$ans_f" 1 1 false || return 1
  alloc_root; root_a="$ALLOC_PATH"
  emit_cache_copy "$root_a" "$ans_a" || return 1
  alloc_root; root_f="$ALLOC_PATH"
  emit_cache_copy "$root_f" "$ans_f" || return 1
  diff -qr --exclude=orchestration-kit.manifest.json "$root_a" "$root_f" >/dev/null 2>&1 || return 1
  jq -e -S 'del(.options.opt_in, .answers.flags.opt_in, .installedAt)' \
    "$root_a/orchestration-kit.manifest.json" > "$root_a/mf.norm"
  jq -e -S 'del(.options.opt_in, .answers.flags.opt_in, .installedAt)' \
    "$root_f/orchestration-kit.manifest.json" > "$root_f/mf.norm"
  cmp -s "$root_a/mf.norm" "$root_f/mf.norm" || return 1
  return 0
}

check_non_boolean() {
  local root ans val out rc
  for val in '"yes"' 1 null '{}'; do
    for mode in normal dry check; do
      alloc_root; root="$ALLOC_PATH"
      alloc_path ansfile
      answers_claude "$ALLOC_PATH" 1 1 absent || return 1
      ans="$ALLOC_PATH"
      jq --argjson v "$val" '.flags.opt_in = $v' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
      case "$mode" in
        dry)
          capture_emit_sh "$root" --answers "$ans" --dry-run
          ;;
        check)
          capture_emit_sh "$root" --check-answers --answers "$ans"
          ;;
        *)
          capture_emit_sh "$root" --answers "$ans"
          ;;
      esac
      [[ "$EMIT_RC" -eq 3 ]] || return 1
      grep -qF 'flags.opt_in must be a boolean' "$EMIT_STDERR" || return 1
    done
  done
  return 0
}

check_manifest() {
  local ans root mf mode
  for mode in true false absent; do
    alloc_path ansfile
    ans="$ALLOC_PATH"
    answers_claude "$ans" 1 1 "$mode" || return 1
    alloc_root; root="$ALLOC_PATH"
    emit_cache_copy "$root" "$ans" || return 1
    mf="$root/orchestration-kit.manifest.json"
    case "$mode" in
      true)  jq -e '.options.opt_in == true' "$mf" >/dev/null || return 1 ;;
      false) jq -e '.options.opt_in == false' "$mf" >/dev/null || return 1 ;;
      absent) jq -e '(.options | has("opt_in")) | not' "$mf" >/dev/null || return 1 ;;
    esac
    if jq -e '.options | has("opt_in")' "$mf" >/dev/null 2>&1; then
      jq -c '.options' "$mf" > "$root/opt.uns"
      jq -cS '.options' "$mf" > "$root/opt.srt"
      cmp -s "$root/opt.uns" "$root/opt.srt" || return 1
    fi
  done
  return 0
}

check_cursor() {
  local ans ans1 ans2 ans3 root root1 root2 root3 line mdc
  alloc_path cursor-a1
  ans1="$ALLOC_PATH"
  answers_cursor "$ans1" 1 true || return 1
  alloc_path cursor-a2
  ans2="$ALLOC_PATH"
  answers_cursor "$ans2" 0 true || return 1
  alloc_path cursor-a3
  ans3="$ALLOC_PATH"
  answers_cursor "$ans3" 1 absent || return 1
  alloc_root; root1="$ALLOC_PATH"
  emit_cache_copy "$root1" "$ans1" || return 1
  alloc_root; root2="$ALLOC_PATH"
  emit_cache_copy "$root2" "$ans2" || return 1
  alloc_root; root3="$ALLOC_PATH"
  emit_cache_copy "$root3" "$ans3" || return 1
  for a in "${AGENTS[@]}"; do
    line="$(agent_description_line "$root1/.cursor/agents/$a.md")"
    case "$line" in
      description:\ ${AGENT_PREFIX}*) ;;
      *) return 1 ;;
    esac
  done
  for s in "${SKILLS[@]}"; do
    grep -qxF 'disable-model-invocation: true' <<<"$(skill_frontmatter "$root1/.cursor/skills/$s/SKILL.md")" || return 1
  done
  mdc="$root1/.cursor/rules/orchestration.mdc"
  cmp -s <(printf '%s\n' "$CURSOR_MDC_RESEARCH_ON") "$mdc" || return 1
  line="$(sed -n '5p' "$root2/.cursor/rules/orchestration.mdc")"
  [[ "$line" == 'opt-in: it runs only when the user types /feature or /memory-capture. Ordinary' ]] || return 1
  grep -qF 'Non-trivial features start with the `feature` skill' "$root3/.cursor/rules/orchestration.mdc" || return 1
  return 0
}

check_copilot() {
  local ans root line desc
  alloc_path ansfile
  answers_copilot "$ALLOC_PATH" true || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  for a in "${AGENTS[@]}"; do
    line="$(agent_description_line "$root/.github/agents/$a.agent.md")"
    case "$line" in
      description:\ ${AGENT_PREFIX}*) ;;
      *) return 1 ;;
    esac
  done
  desc="$(agent_description_line "$root/.github/agents/feature.agent.md")"
  grep -qF "$OPT_IN_FEATURE" <<<"$desc" || return 1
  grep -qxF 'disable-model-invocation: true' <<<"$(skill_frontmatter "$root/.github/agents/feature.agent.md")" || return 1
  for s in feature research memory-capture; do
    grep -qxF 'disable-model-invocation: true' <<<"$(skill_frontmatter "$root/.github/skills/$s/SKILL.md")" || return 1
  done
  return 0
}

check_codex() {
  local ans_abs ans_opt root_f root_o root_r prefix needle n
  prefix='description = "Orchestration-kit agent — spawn only from the /feature, /research or /align-docs workflow, never for ordinary work.'
  needle='Orchestration-kit agent — spawn only from the /feature, /research or /align-docs workflow, never for ordinary work.'
  alloc_path codex-opt
  ans_opt="$ALLOC_PATH"
  answers_codex "$ans_opt" true || return 1
  alloc_path codex-abs
  ans_abs="$ALLOC_PATH"
  answers_codex "$ans_abs" absent || return 1

  alloc_root; root_f="$ALLOC_PATH"
  capture_emit_sh "$root_f" --answers "$ans_opt"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  n="$(grep -cF "$prefix" "$root_f/.codex/config.toml" || true)"
  [[ "$n" -eq 7 ]] || return 1
  grep -qxF "$CODEX_OPT_IN_WARN" "$EMIT_STDERR" || return 1
  [[ "$(grep -cxF "$CODEX_OPT_IN_WARN" "$EMIT_STDERR" || true)" -eq 1 ]] || return 1
  w_opt="$(parse_warnings_w "$EMIT_STDOUT")"
  [[ -n "$w_opt" ]] || return 1

  alloc_root; root_o="$ALLOC_PATH"
  capture_emit_sh "$root_o" --answers "$ans_abs"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  w_abs="$(parse_warnings_w "$EMIT_STDOUT")"
  [[ -n "$w_abs" ]] || return 1
  [[ $((w_opt - w_abs)) -eq 1 ]] || return 1
  grep -qF "$needle" "$root_o/.codex/config.toml" && return 1
  grep -qF "$CODEX_OPT_IN_WARN" "$EMIT_STDERR" && return 1

  alloc_root; root_r="$ALLOC_PATH"
  emit_cache_copy "$root_r" "$ans_abs" || return 1
  capture_emit_sh "$root_r" --answers "$ans_opt"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  grep -qF "$needle" "$root_r/.codex/config.toml" && return 1
  [[ "$(grep -cxF "$CODEX_OPT_IN_WARN" "$EMIT_STDERR" || true)" -eq 1 ]] || return 1
  return 0
}

copy_handedit_files() { # from_root to_root loop_on
  local from="$1" to="$2" loop_on="$3" a s
  for a in "${AGENTS[@]}"; do
    cp "$from/.claude/agents/$a.md" "$to/.claude/agents/$a.md"
  done
  for s in "${SKILLS[@]}"; do
    cp "$from/.claude/skills/$s/SKILL.md" "$to/.claude/skills/$s/SKILL.md"
  done
  cp "$from/.claude/ORCHESTRATION.md" "$to/.claude/ORCHESTRATION.md"
  if [[ "$loop_on" == 1 ]]; then
    cp "$from/.claude/skills/auto-loop/SKILL.md" "$to/.claude/skills/auto-loop/SKILL.md"
  fi
}

check_migration_one() { # loop_on
  local loop_on="$1" ans_abs ans_opt root_a root_b mf want_ver
  alloc_path mig-abs
  ans_abs="$ALLOC_PATH"
  answers_claude "$ans_abs" 1 "$loop_on" absent || return 1
  alloc_path mig-opt
  ans_opt="$ALLOC_PATH"
  answers_claude "$ans_opt" 1 "$loop_on" true || return 1
  alloc_root; root_a="$ALLOC_PATH"
  alloc_root; root_b="$ALLOC_PATH"
  emit_cache_copy "$root_a" "$ans_abs" || return 1
  emit_cache_copy "$root_b" "$ans_opt" || return 1
  mf="$root_a/orchestration-kit.manifest.json"
  jq '.kitVersion = "2.1.0"' "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
  copy_handedit_files "$root_b" "$root_a" "$loop_on"
  capture_emit_sh "$root_a" --answers "$ans_opt" --upgrade
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  grep -qiF 'blocked' "$EMIT_STDOUT" && return 1
  grep -qiF 'blocked' "$EMIT_STDERR" && return 1
  for a in "${AGENTS[@]}"; do
    cmp -s "$root_a/.claude/agents/$a.md" "$root_b/.claude/agents/$a.md" || return 1
  done
  for s in "${SKILLS[@]}"; do
    cmp -s "$root_a/.claude/skills/$s/SKILL.md" "$root_b/.claude/skills/$s/SKILL.md" || return 1
  done
  cmp -s "$root_a/.claude/ORCHESTRATION.md" "$root_b/.claude/ORCHESTRATION.md" || return 1
  if [[ "$loop_on" == 1 ]]; then
    cmp -s "$root_a/.claude/skills/auto-loop/SKILL.md" "$root_b/.claude/skills/auto-loop/SKILL.md" || return 1
  fi
  jq -e '.options.opt_in == true' "$root_a/orchestration-kit.manifest.json" >/dev/null || return 1
  want_ver="$(kit_version "$SKILL_MD")"
  [[ -n "$want_ver" ]] || return 1
  jq -e --arg v "$want_ver" '.kitVersion == $v' "$root_a/orchestration-kit.manifest.json" >/dev/null || return 1
  return 0
}

check_migration_negative() {
  local ans_abs ans_opt root_a root_b mf
  alloc_path mig-n-abs
  ans_abs="$ALLOC_PATH"
  answers_claude "$ans_abs" 1 0 absent || return 1
  alloc_path mig-n-opt
  ans_opt="$ALLOC_PATH"
  answers_claude "$ans_opt" 1 0 true || return 1
  alloc_root; root_a="$ALLOC_PATH"
  alloc_root; root_b="$ALLOC_PATH"
  emit_cache_copy "$root_a" "$ans_abs" || return 1
  emit_cache_copy "$root_b" "$ans_opt" || return 1
  mf="$root_a/orchestration-kit.manifest.json"
  jq '.kitVersion = "2.1.0"' "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
  copy_handedit_files "$root_b" "$root_a" 0
  sed -i 's/^> Every kit skill (`goal-criteria`/>& /' "$root_a/.claude/ORCHESTRATION.md"
  capture_emit_sh "$root_a" --answers "$ans_opt" --upgrade
  [[ "$EMIT_RC" -eq 4 ]] || return 1
  grep -qF 'emit: blocked .claude/ORCHESTRATION.md' "$EMIT_STDERR" || return 1
  capture_emit_sh "$root_a" --answers "$ans_opt" --force --upgrade
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  return 0
}

run_check() {
  local letter="$1" fn="$2" title="$3"
  if [[ "$HAVE_JQ" -ne 1 ]]; then
    report SKIP "($letter) $title" "jq not on PATH"
    return
  fi
  if "$fn"; then
    report PASS "($letter) $title"
  else
    report FAIL "($letter) $title"
  fi
}

PAR_REPORT_FAIL="report"
emit_cache_init

run_check a check_done_when 'claude-code opt_in: agents, skills, ORCHESTRATION (research on, loop off)'
run_check b check_four_variants 'four research×loop ORCHESTRATION opt-in blocks'
run_check c check_auto_loop 'auto-loop feature path Read when opt_in'
run_check d check_byte_identity 'byte identity absent vs opt_in false (manifest opt_in only)'
run_check e check_non_boolean 'non-boolean opt_in exit 3 (emit, dry-run, check-answers)'
run_check f check_manifest 'manifest options.opt_in persistence and sorted keys'
run_check g check_cursor 'cursor opt_in agents, skills, orchestration.mdc variants'
run_check h check_copilot 'copilot opt_in agents and skill flags'
run_check i check_codex 'codex partial opt_in warning and description prefix behavior'
check_migration_off() { check_migration_one 0; }
check_migration_on() { check_migration_one 1; }
run_check j check_migration_off 'migration hand-edit upgrade loop off'
run_check k check_migration_on 'migration hand-edit upgrade loop on'
run_check l check_migration_negative 'migration negative control blocked ORCHESTRATION then --force'

emit_cache_verify

echo
echo "=== opt-in summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
