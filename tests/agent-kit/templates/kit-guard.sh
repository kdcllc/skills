#!/usr/bin/env bash
# Behavioral suite: flags.kit_guard end-to-end (kit-guard tool, emit hooks, warnings,
# --check, rendered gate text, validation). Scratch roots only; no network.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akkguard.XXXXXX")" || exit 1
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

guard_for_root() { # root → path to guard under test
  local root="$1"
  if [[ -f "$root/_kit/kit-guard.sh" ]]; then
    printf '%s\n' "$root/_kit/kit-guard.sh"
  else
    printf '%s\n' "$KIT/templates/tools/kit-guard.sh"
  fi
}

run_guard_check() { # root [extra env] → GUARD_RC, GUARD_OUT (combined)
  local root="$1" guard
  shift
  guard="$(guard_for_root "$root")"
  alloc_path gout
  GUARD_OUT="$ALLOC_PATH"
  env "$@" bash "$guard" check --root "$root" >"$GUARD_OUT" 2>&1
  GUARD_RC=$?
}

run_guard_hook() { # harness root json [env flags] → HOOK_RC HOOK_OUT HOOK_ERR
  local harness="$1" root="$2" json="$3" guard
  shift 3
  guard="$(guard_for_root "$root")"
  alloc_path hout herr
  HOOK_OUT="$ALLOC_PATH"
  HOOK_ERR="${ALLOC_PATH}.err"
  env -u CURSOR_PROJECT_DIR "$@" bash "$guard" hook "$harness" --root "$root" >"$HOOK_OUT" 2>"$HOOK_ERR" <<<"$json"
  HOOK_RC=$?
}

content_has() { # file substring
  local f="$1" block="$2" content
  content="$(cat "$f")" || return 1
  [[ "$content" == *"$block"* ]]
}

sha256_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    shasum -a 256 "$f" | awk '{print $1}'
  fi
}

manifest_has_file() { # root relpath
  local root="$1" rel="$2"
  jq -e --arg p "$rel" '.files | has($p)' "$root/orchestration-kit.manifest.json" >/dev/null
}

orch_section_text() { # file ### heading
  local f="$1" heading="$2"
  awk -v h="$heading" '
    $0 ~ ("^" h "$") { in_s=1; next }
    in_s && ($0 ~ /^### / || $0 ~ /^---$/ || $0 ~ /^## /) { exit }
    in_s { print }
  ' "$f"
}

section_has_block() { # file heading block
  local f="$1" heading="$2" block="$3" sec
  sec="$(orch_section_text "$f" "$heading")"
  [[ "$sec" == *"$block"* ]]
}

no_hook_or_kit_guard_under() { # root subdir
  local root="$1" sub="$2" hits
  [[ -d "$root/$sub" ]] || return 0
  hits="$(find "$root/$sub" \( -name '*hook*' -o -name '*kit-guard*' \) 2>/dev/null | head -1 || true)"
  [[ -z "$hits" ]]
}

parse_warnings_w() {
  local line w
  line="$(grep -E '^emit: written ' "$1" 2>/dev/null | tail -1)" || true
  w="$(printf '%s' "$line" | sed -n 's/.*· warnings \([0-9][0-9]*\) ·.*/\1/p')"
  [[ -n "$w" ]] || w=""
  printf '%s' "$w"
}

read -r -d '' SETTINGS_JSON_KG <<'EOF' || true
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "3"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/_kit/kit-guard.sh\" hook claude"
          }
        ]
      }
    ]
  }
}
EOF

read -r -d '' CURSOR_HOOKS_JSON_KG <<'EOF' || true
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "command": "bash _kit/kit-guard.sh hook cursor",
        "matcher": "Write|Delete"
      }
    ]
  }
}
EOF

read -r -d '' SETTINGS_JSON_MIN <<'EOF' || true
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "3"
  }
}
EOF

read -r -d '' WARN_SETTINGS_NO_HOOK <<'EOF' || true
warning: .claude/settings.json exists without the kit-guard hook — left untouched; merge into it: {"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/_kit/kit-guard.sh\" hook claude"}]}]}}
EOF

read -r -d '' WARN_CURSOR_NO_HOOK <<'EOF' || true
warning: .cursor/hooks.json exists without the kit-guard hook — left untouched; add to its "hooks" object: "preToolUse":[{"command":"bash _kit/kit-guard.sh hook cursor","matcher":"Write|Delete"}]
EOF

read -r -d '' WARN_SETTINGS_OFF <<'EOF' || true
warning: .claude/settings.json still references _kit/kit-guard.sh but flags.kit_guard is off — remove that hook entry
EOF

read -r -d '' WARN_CURSOR_OFF <<'EOF' || true
warning: .cursor/hooks.json still references _kit/kit-guard.sh but flags.kit_guard is off — remove that hook entry
EOF

read -r -d '' WARN_COPILOT_PARTIAL <<'EOF' || true
warning: flags.kit_guard is partial on copilot: no edit-blocking hook; run emit.sh --check in CI (_kit/ is gitignored)
EOF

read -r -d '' WARN_CODEX_PARTIAL <<'EOF' || true
warning: flags.kit_guard is partial on codex: no edit-blocking hook; run emit.sh --check in CI (_kit/ is gitignored)
EOF

read -r -d '' RESTORE_LINE <<'EOF' || true
kit-guard: restore tracked files from git; delete a modified _kit/ file and re-run emit.sh --upgrade; never edit kit-owned files
EOF

read -r -d '' ORCH_KG_ITEM4 <<'EOF' || true
4. **Kit-owned files are read-only.** Every path under `files` in
   `orchestration-kit.manifest.json` belongs to the kit, except the user-owned harness
   configs (the Claude Code settings file, `.codex/config.toml`, `.cursor/hooks.json`).
   Change kit behavior through the answers file and `emit.sh --answers <file> --upgrade`
   — never by editing those files. After every subagent returns, run
   `_kit/kit-guard.sh check` inline (one-line output when clean); exit 4 stops the goal:
   restore tracked files from git, delete a modified `_kit/` file and re-run
   `emit.sh --upgrade`, log a note, then continue. `_kit/` is gitignored, so on a fresh
   clone the script is missing until `emit.sh --upgrade` runs — run it first and log a
   note. The edit-blocking hooks (Claude Code `PreToolUse`, Cursor `preToolUse`) stop
   most agent edits up front; the check also catches shell edits and harnesses without
   hooks.
EOF

read -r -d '' FILE_LOC_LINE <<'EOF' || true
_kit/{kit-guard.sh,kit-guard.cmd}  # Single-copy tools: kit-file guard (check / hook) + Windows launcher
EOF

read -r -d '' WRITER_KG_BULLET <<'EOF' || true
- Never create, modify or delete a kit-owned file — any path under `files` in
  `orchestration-kit.manifest.json` (agents, skills, `ORCHESTRATION.md`, `_kit/`, `_loop/`)
  except the user-owned harness configs (the Claude Code settings file,
  `.codex/config.toml`, `.cursor/hooks.json`). If the task seems to need one, stop and
  report it. Never work around a kit-guard denial.
EOF

read -r -d '' EVAL_KG_BULLET <<'EOF' || true
- Any change to a kit-owned file (`_kit/kit-guard.sh check` exits 4) — NEEDS FIXES:
  restore tracked files from git, delete a modified `_kit/` file and re-run
  `emit.sh --upgrade`; never `--force`.
EOF

read -r -d '' FEATURE_KG_GATE <<'EOF' || true
**Kit-file gate**: run `_kit/kit-guard.sh check` inline after every spawn and in Quality
Checks; exit 4 ⇒ restore tracked files from git, delete a modified `_kit/` file and re-run
`emit.sh --upgrade`, log a note; never `--force`.
EOF

read -r -d '' FEATURE_PROGRESS_OFF <<'EOF' || true
Update ORCHESTRATION.md Orchestration Progress after each step.
EOF

# Assemble expected progress.md paths at runtime (AC5 forbidden substring guard).
_MEM_WORK_SEGMENT='work'
FEATURE_PROGRESS_KG="Update \`_memory/${_MEM_WORK_SEGMENT}/goals/[goal]/progress.md\` (Orchestration Progress) after each step — ORCHESTRATION.md is kit-owned."
ORCH_PROGRESS_NOTE="With the kit-file guard on, keep this block in \`_memory/${_MEM_WORK_SEGMENT}/goals/[goal]/progress.md\` —
never in this file, which is kit-owned."

WRITER_AGENTS=(implementer test-writer evidence-collector)

answers_both() { # outfile research loop kg_mode
  local out="$1" research="$2" loop="$3" mode="$4" rj lj
  [[ "$research" == 1 ]] && rj=true || rj=false
  [[ "$loop" == 1 ]] && lj=true || lj=false
  jq --argjson r "$rj" --argjson l "$lj" '
    .flags.research = $r |
    .flags.loop = $l
  ' "$FIXTURE" > "${out}.tmp"
  case "$mode" in
    absent) jq 'del(.flags.kit_guard)' "${out}.tmp" > "$out" ;;
    false)  jq '.flags.kit_guard = false' "${out}.tmp" > "$out" ;;
    true)   jq '.flags.kit_guard = true' "${out}.tmp" > "$out" ;;
    *) return 1 ;;
  esac
  rm -f "${out}.tmp"
}

answers_copilot_kg() {
  local out="$1"
  jq '
    .harnesses = ["copilot"] |
    .primary = "copilot" |
    del(.models["claude-code"]) |
    del(.models.cursor) |
    .models.copilot = {
      "frontier": "cop-front", "light": "cop-light", "fast": "cop-fast",
      "alt_family": "cop-alt", "frontier_alt_family": "cop-front",
      "arbiter_same_family": true, "loop_chain": "cop-light"
    } |
    .flags.kit_guard = true
  ' "$FIXTURE" > "$out"
}

answers_codex_kg() {
  local out="$1"
  jq '
    .harnesses = ["codex"] |
    .primary = "codex" |
    del(.models["claude-code"]) |
    del(.models.cursor) |
    .models.codex = {
      "frontier": "cod-front", "light": "cod-light", "fast": "cod-fast",
      "alt_family": "cod-alt", "frontier_alt_family": "cod-front",
      "loop_chain": "cod-light", "arbiter_same_family": true
    } |
    .flags.kit_guard = true
  ' "$FIXTURE" > "$out"
}

check_guard_modes() {
  local ans root root_cod guard ans_cod
  alloc_path ansfile
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  guard="$(guard_for_root "$root")"

  run_guard_check "$root"
  [[ "$GUARD_RC" -eq 0 ]] || return 1
  grep -qE 'kit-guard: ok \([0-9]+ kit files\)' "$GUARD_OUT" || return 1

  printf '# touch\n' >> "$root/.claude/agents/implementer.md"
  run_guard_check "$root"
  [[ "$GUARD_RC" -eq 4 ]] || return 1
  grep -qF 'kit-guard: modified .claude/agents/implementer.md' "$GUARD_OUT" || return 1
  content_has "$GUARD_OUT" "$RESTORE_LINE" || return 1

  emit_cache_copy "$root" "$ans" || return 1
  rm -f "$root/_kit/memory.sh"
  run_guard_check "$root"
  [[ "$GUARD_RC" -eq 4 ]] || return 1
  grep -qF 'kit-guard: missing _kit/memory.sh' "$GUARD_OUT" || return 1

  emit_cache_copy "$root" "$ans" || return 1
  manifest_has_file "$root" ".claude/settings.json" || return 1
  manifest_has_file "$root" ".cursor/hooks.json" || return 1
  printf ' \n' >> "$root/.claude/settings.json"
  printf ' \n' >> "$root/.cursor/hooks.json"
  run_guard_check "$root"
  [[ "$GUARD_RC" -eq 0 ]] || return 1
  grep -qE 'kit-guard: ok \([0-9]+ kit files\)' "$GUARD_OUT" || return 1

  alloc_path ans-codex
  answers_codex_kg "$ALLOC_PATH" || return 1
  ans_cod="$ALLOC_PATH"
  alloc_root
  root_cod="$ALLOC_PATH"
  capture_emit_sh "$root_cod" --answers "$ans_cod"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  manifest_has_file "$root_cod" ".codex/config.toml" || return 1
  [[ -f "$root_cod/.codex/config.toml" ]] || return 1
  printf '# exclusion-probe\n' >> "$root_cod/.codex/config.toml"
  run_guard_check "$root_cod"
  [[ "$GUARD_RC" -eq 0 ]] || return 1
  grep -qE 'kit-guard: ok \([0-9]+ kit files\)' "$GUARD_OUT" || return 1

  rm -f "$root/orchestration-kit.manifest.json"
  run_guard_check "$root"
  [[ "$GUARD_RC" -eq 2 ]] || return 1

  emit_cache_copy "$root" "$ans" || return 1
  printf '# touch\n' >> "$root/.claude/agents/implementer.md"
  run_guard_check "$root" AGENT_KIT_GUARD=0
  [[ "$GUARD_RC" -eq 4 ]] || return 1

  emit_cache_copy "$root" "$ans" || return 1
  rm -rf "$root/_kit"
  run_guard_check "$root"
  [[ "$GUARD_RC" -eq 0 ]] || return 1
  grep -qF 'kit-guard: note: _kit/ absent' "$GUARD_OUT" || return 1

  emit_cache_copy "$root" "$ans" || return 1
  rm -f "$root/_kit/memory.sh"
  run_guard_check "$root"
  [[ "$GUARD_RC" -eq 4 ]] || return 1
  grep -qF 'kit-guard: missing _kit/memory.sh' "$GUARD_OUT" || return 1

  return 0
}

check_hook_claude() {
  local ans root guard kit_path json
  alloc_path ansfile
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  guard="$(guard_for_root "$root")"
  kit_path="$root/.claude/agents/implementer.md"

  json="$(printf '{"file_path":"%s"}' "$kit_path")"
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 2 ]] || return 1
  grep -qF 'kit-guard: .claude/agents/implementer.md' "$HOOK_ERR" || return 1

  json="$(printf '{"file_path":".claude/agents/implementer.md","cwd":"%s"}' "$root")"
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 2 ]] || return 1

  json='{"file_path":"README.md","cwd":"'"$root"'"}'
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 0 ]] || return 1
  [[ ! -s "$HOOK_OUT" ]] || return 1
  [[ ! -s "$HOOK_ERR" ]] || return 1

  json='{"file_path":"/etc/passwd"}'
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 0 ]] || return 1

  json='{"notebook_path":".claude/skills/feature/SKILL.md","cwd":"'"$root"'"}'
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 2 ]] || return 1

  json='{"file_path":".claude/agents/implementer.md","cwd":"'"$root"'"}'
  run_guard_hook claude "$root" "$json" AGENT_KIT_GUARD=0
  [[ "$HOOK_RC" -eq 0 ]] || return 1

  run_guard_hook claude "$root" 'not json at all'
  [[ "$HOOK_RC" -eq 0 ]] || return 1

  json='{"file_path":".claude\/agents\/implementer.md","cwd":"'"$root"'"}'
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 2 ]] || return 1

  json='{"file_path":"README.md","cwd":"'"$root"'\\\\tmp"}'
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 0 ]] || return 1

  json='{"note":"decoy \"file_path\":\"README.md\"","file_path":".claude/agents/implementer.md","cwd":"'"$root"'"}'
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 2 ]] || return 1

  return 0
}

check_hook_cursor() {
  local ans root json keys key
  alloc_path ansfile
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1

  for key in path file_path target_file; do
    json='{"'"$key"'":".claude/agents/implementer.md","cwd":"'"$root"'"}'
    run_guard_hook cursor "$root" "$json"
    [[ "$HOOK_RC" -eq 2 ]] || return 1
    jq -e '.permission=="deny" and (.agent_message|length>0)' "$HOOK_OUT" >/dev/null || return 1
  done

  json='{"path":"README.md","cwd":"'"$root"'"}'
  run_guard_hook cursor "$root" "$json"
  [[ "$HOOK_RC" -eq 0 ]] || return 1
  cmp -s <(printf '%s\n' '{"permission":"allow"}') "$HOOK_OUT" || return 1

  run_guard_hook cursor "$root" '{broken'
  [[ "$HOOK_RC" -eq 0 ]] || return 1
  cmp -s <(printf '%s\n' '{"permission":"allow"}') "$HOOK_OUT" || return 1

  return 0
}

check_usage() {
  local guard="$KIT/templates/tools/kit-guard.sh" rc
  rc=0
  bash "$guard" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || return 1
  rc=0
  bash "$guard" hook >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || return 1
  rc=0
  bash "$guard" hook bogus >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || return 1
  return 0
}

check_emit_on() {
  local ans root cmd rc out err
  alloc_path ansfile
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1

  [[ -f "$root/_kit/kit-guard.sh" ]] || return 1
  [[ -f "$root/_kit/kit-guard.cmd" ]] || return 1
  cmp -s "$root/_kit/kit-guard.cmd" "$root/_kit/memory.cmd" || return 1
  cmp -s <(printf '%s\n' "$SETTINGS_JSON_KG") "$root/.claude/settings.json" || return 1
  cmp -s <(printf '%s\n' "$CURSOR_HOOKS_JSON_KG") "$root/.cursor/hooks.json" || return 1

  cmd="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$root/.claude/settings.json")"
  rc=0
  CLAUDE_PROJECT_DIR="$root" bash -c "$cmd" <<<"{\"file_path\":\".claude/agents/implementer.md\",\"cwd\":\"$root\"}" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || return 1

  before_s="$(sha256_file "$root/.claude/settings.json")"
  before_h="$(sha256_file "$root/.cursor/hooks.json")"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  grep -qF 'written 0' "$EMIT_STDOUT" || return 1
  after_s="$(sha256_file "$root/.claude/settings.json")"
  after_h="$(sha256_file "$root/.cursor/hooks.json")"
  [[ "$before_s" == "$after_s" ]] || return 1
  [[ "$before_h" == "$after_h" ]] || return 1
  return 0
}

check_existing_configs() {
  local ans root w_on w_off
  alloc_path ansfile
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans="$ALLOC_PATH"

  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/.claude" "$root/.cursor"
  printf '%s\n' "$SETTINGS_JSON_MIN" > "$root/.claude/settings.json"
  printf '%s\n' '{"version":1,"hooks":{}}' > "$root/.cursor/hooks.json"
  before_s="$(sha256sum "$root/.claude/settings.json" | awk '{print $1}')"
  before_h="$(sha256sum "$root/.cursor/hooks.json" | awk '{print $1}')"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  after_s="$(sha256sum "$root/.claude/settings.json" | awk '{print $1}')"
  after_h="$(sha256sum "$root/.cursor/hooks.json" | awk '{print $1}')"
  [[ "$before_s" == "$after_s" ]] || return 1
  [[ "$before_h" == "$after_h" ]] || return 1
  grep -qxF "emit: $WARN_SETTINGS_NO_HOOK" "$EMIT_STDERR" || return 1
  [[ "$(grep -cxF "emit: $WARN_SETTINGS_NO_HOOK" "$EMIT_STDERR" || true)" -eq 1 ]] || return 1
  grep -qxF "emit: $WARN_CURSOR_NO_HOOK" "$EMIT_STDERR" || return 1
  [[ "$(grep -cxF "emit: $WARN_CURSOR_NO_HOOK" "$EMIT_STDERR" || true)" -eq 1 ]] || return 1

  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/.claude"
  printf '%s\n' "$SETTINGS_JSON_KG" > "$root/.claude/settings.json"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  grep -qF 'kit-guard hook' "$EMIT_STDERR" && return 1
  return 0
}

check_partial_harnesses() {
  local ans root
  alloc_path ans-cop
  answers_copilot_kg "$ALLOC_PATH" || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  grep -qxF "emit: $WARN_COPILOT_PARTIAL" "$EMIT_STDERR" || return 1
  [[ "$(grep -cxF "emit: $WARN_COPILOT_PARTIAL" "$EMIT_STDERR" || true)" -eq 1 ]] || return 1
  no_hook_or_kit_guard_under "$root" ".github" || return 1

  alloc_path ans-cod
  answers_codex_kg "$ALLOC_PATH" || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  grep -qxF "emit: $WARN_CODEX_PARTIAL" "$EMIT_STDERR" || return 1
  [[ "$(grep -cxF "emit: $WARN_CODEX_PARTIAL" "$EMIT_STDERR" || true)" -eq 1 ]] || return 1
  no_hook_or_kit_guard_under "$root" ".codex" || return 1
  return 0
}

check_emit_check_flag() {
  local ans root rc
  alloc_path ansfile
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1

  rc=0
  bash "$EMIT_SH" --check --root "$root" --kit "$KIT" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || return 1

  printf '# x\n' >> "$root/.claude/agents/implementer.md"
  rc=0
  bash "$EMIT_SH" --check --root "$root" --kit "$KIT" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 4 ]] || return 1

  rm -f "$root/orchestration-kit.manifest.json"
  rc=0
  bash "$EMIT_SH" --check --root "$root" --kit "$KIT" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || return 1

  rc=0
  bash "$EMIT_SH" --check --root "$root" --kit "$KIT" --upgrade >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || return 1
  return 0
}

check_flag_off() {
  local ans_a ans_f root_a root_f
  alloc_path ans-a
  answers_both "$ALLOC_PATH" 1 1 absent || return 1
  ans_a="$ALLOC_PATH"
  alloc_path ans-f
  answers_both "$ALLOC_PATH" 1 1 false || return 1
  ans_f="$ALLOC_PATH"
  alloc_root; root_a="$ALLOC_PATH"
  emit_cache_copy "$root_a" "$ans_a" || return 1
  alloc_root; root_f="$ALLOC_PATH"
  emit_cache_copy "$root_f" "$ans_f" || return 1

  diff -qr --exclude=orchestration-kit.manifest.json "$root_a" "$root_f" >/dev/null 2>&1 || return 1
  jq -e -S 'del(.options.kit_guard, .answers.flags.kit_guard, .installedAt)' \
    "$root_a/orchestration-kit.manifest.json" > "$root_a/mf.norm" || return 1
  jq -e -S 'del(.options.kit_guard, .answers.flags.kit_guard, .installedAt)' \
    "$root_f/orchestration-kit.manifest.json" > "$root_f/mf.norm" || return 1
  cmp -s "$root_a/mf.norm" "$root_f/mf.norm" || return 1
  [[ ! -f "$root_a/_kit/kit-guard.sh" ]] || return 1
  [[ ! -f "$root_f/_kit/kit-guard.sh" ]] || return 1
  [[ ! -f "$root_a/_kit/kit-guard.cmd" ]] || return 1
  [[ ! -f "$root_f/_kit/kit-guard.cmd" ]] || return 1
  [[ ! -f "$root_a/.cursor/hooks.json" ]] || return 1
  cmp -s <(printf '%s\n' "$SETTINGS_JSON_MIN") "$root_a/.claude/settings.json" || return 1
  return 0
}

check_validation() {
  local root ans val mode
  for val in '"yes"' 1 null '{}'; do
    for mode in normal dry check; do
      alloc_root; root="$ALLOC_PATH"
      alloc_path ansfile
      answers_both "$ALLOC_PATH" 1 1 absent || return 1
      ans="$ALLOC_PATH"
      jq --argjson v "$val" '.flags.kit_guard = $v' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
      case "$mode" in
        dry)   capture_emit_sh "$root" --answers "$ans" --dry-run ;;
        check) capture_emit_sh "$root" --check-answers --answers "$ans" ;;
        *)     capture_emit_sh "$root" --answers "$ans" ;;
      esac
      [[ "$EMIT_RC" -eq 3 ]] || return 1
      grep -qF 'flags.kit_guard must be a boolean' "$EMIT_STDERR" || return 1
    done
  done

  for mode in true false absent; do
    alloc_path ansfile
    ans="$ALLOC_PATH"
    answers_both "$ans" 1 1 "$mode" || return 1
    alloc_root; root="$ALLOC_PATH"
    emit_cache_copy "$root" "$ans" || return 1
    mf="$root/orchestration-kit.manifest.json"
    case "$mode" in
      true)  jq -e '.options.kit_guard == true' "$mf" >/dev/null || return 1 ;;
      false) jq -e '.options.kit_guard == false' "$mf" >/dev/null || return 1 ;;
      absent) jq -e '(.options | has("kit_guard")) | not' "$mf" >/dev/null || return 1 ;;
    esac
    if jq -e '.options | has("kit_guard")' "$mf" >/dev/null 2>&1; then
      jq -c '.options' "$mf" > "$root/opt.uns"
      jq -cS '.options' "$mf" > "$root/opt.srt"
      cmp -s "$root/opt.uns" "$root/opt.srt" || return 1
    fi
  done
  return 0
}

check_rendered_text() {
  local r l ans root orch f a
  for r in 0 1; do
    for l in 0 1; do
      for mode in true false absent; do
        alloc_path ansfile
        answers_both "$ALLOC_PATH" "$r" "$l" "$mode" || return 1
        ans="$ALLOC_PATH"
        alloc_root; root="$ALLOC_PATH"
        emit_cache_copy "$root" "$ans" || return 1
        orch="$root/.claude/ORCHESTRATION.md"
        case "$mode" in
          true)
            section_has_block "$orch" '### Repository safety' "$ORCH_KG_ITEM4" || return 1
            [[ "$(grep -cF "$FILE_LOC_LINE" "$orch" || true)" -eq 1 ]] || return 1
            content_has "$root/.claude/skills/feature/SKILL.md" "$FEATURE_KG_GATE" || return 1
            for a in "${WRITER_AGENTS[@]}"; do
              content_has "$root/.claude/agents/$a.md" "$WRITER_KG_BULLET" || return 1
            done
            content_has "$root/.claude/agents/evaluator.md" "$EVAL_KG_BULLET" || return 1
            ;;
          *)
            grep -qF 'Kit-owned files are read-only' "$orch" && return 1
            grep -qF "$FILE_LOC_LINE" "$orch" && return 1
            grep -qF "$FEATURE_KG_GATE" "$root/.claude/skills/feature/SKILL.md" && return 1
            for a in "${WRITER_AGENTS[@]}"; do
              grep -qF 'Never work around a kit-guard denial' "$root/.claude/agents/$a.md" && return 1
            done
            grep -qF 'kit-owned file (`_kit/kit-guard.sh check` exits 4)' "$root/.claude/agents/evaluator.md" && return 1
            ;;
        esac
      done
    done
  done

  alloc_path ans-both
  jq '.flags.kit_guard = true | .flags.opt_in = true' "$FIXTURE" > "$ALLOC_PATH" || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  grep -qxF 'disable-model-invocation: true' <<<"$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f{print}' "$root/.claude/skills/feature/SKILL.md")" || return 1
  return 0
}

check_turning_off() {
  local ans_on ans_off root
  alloc_path ans-on
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans_on="$ALLOC_PATH"
  alloc_path ans-off
  answers_both "$ALLOC_PATH" 1 1 false || return 1
  ans_off="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans_on" || return 1
  [[ -f "$root/_kit/kit-guard.sh" ]] || return 1
  capture_emit_sh "$root" --answers "$ans_off" --upgrade
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  [[ ! -f "$root/_kit/kit-guard.sh" ]] || return 1
  [[ ! -f "$root/_kit/kit-guard.cmd" ]] || return 1
  [[ -f "$root/.claude/settings.json" ]] || return 1
  [[ -f "$root/.cursor/hooks.json" ]] || return 1
  grep -qxF "emit: $WARN_SETTINGS_OFF" "$EMIT_STDERR" || return 1
  [[ "$(grep -cxF "emit: $WARN_SETTINGS_OFF" "$EMIT_STDERR" || true)" -eq 1 ]] || return 1
  grep -qxF "emit: $WARN_CURSOR_OFF" "$EMIT_STDERR" || return 1
  [[ "$(grep -cxF "emit: $WARN_CURSOR_OFF" "$EMIT_STDERR" || true)" -eq 1 ]] || return 1
  return 0
}

check_cursor_caller_claude() {
  local ans root json rc
  alloc_path ansfile
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1

  json='{"hook_event_name":"preToolUse","file_path":".claude/agents/implementer.md","cwd":"'"$root"'"}'
  run_guard_hook claude "$root" "$json"
  [[ "$HOOK_RC" -eq 2 ]] || return 1
  jq -e '.permission=="deny"' "$HOOK_OUT" >/dev/null || return 1

  json='{"file_path":".claude/agents/implementer.md","cwd":"'"$root"'"}'
  rc=0
  env CURSOR_PROJECT_DIR="$root" bash "$(guard_for_root "$root")" hook claude --root "$root" >"$HOOK_OUT" 2>"$HOOK_ERR" <<<"$json" || rc=$?
  [[ "$rc" -eq 2 ]] || return 1
  jq -e '.permission=="deny"' "$HOOK_OUT" >/dev/null || return 1

  json='{"file_path":"README.md","cwd":"'"$root"'"}'
  rc=0
  env CURSOR_PROJECT_DIR="$root" bash "$(guard_for_root "$root")" hook claude --root "$root" >"$HOOK_OUT" 2>"$HOOK_ERR" <<<"$json" || rc=$?
  [[ "$rc" -eq 0 ]] || return 1
  cmp -s <(printf '%s\n' '{"permission":"allow"}') "$HOOK_OUT" || return 1
  return 0
}

check_progress_location() {
  local ans_on ans_off root_on root_off
  alloc_path ans-on
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans_on="$ALLOC_PATH"
  alloc_path ans-off
  answers_both "$ALLOC_PATH" 1 1 absent || return 1
  ans_off="$ALLOC_PATH"
  alloc_root; root_on="$ALLOC_PATH"
  emit_cache_copy "$root_on" "$ans_on" || return 1
  alloc_root; root_off="$ALLOC_PATH"
  emit_cache_copy "$root_off" "$ans_off" || return 1

  content_has "$root_on/.claude/skills/feature/SKILL.md" "$FEATURE_PROGRESS_KG" || return 1
  grep -qF 'Update ORCHESTRATION.md Orchestration Progress' "$root_on/.claude/skills/feature/SKILL.md" && return 1
  section_has_block "$root_on/.claude/ORCHESTRATION.md" '### Workflow State Tracking' "$ORCH_PROGRESS_NOTE" || return 1
  content_has "$root_off/.claude/skills/feature/SKILL.md" "$FEATURE_PROGRESS_OFF" || return 1
  grep -qF 'progress.md' "$root_off/.claude/skills/feature/SKILL.md" && return 1
  return 0
}

check_evaluator_bootstrap() {
  local ans root ev bootstrap_ln kg_ln
  alloc_path ansfile
  answers_both "$ALLOC_PATH" 1 1 true || return 1
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  ev="$root/.claude/agents/evaluator.md"
  grep -qF 'Unresolved' "$ev" || return 1
  grep -qE '<!--[[:space:]]*BOOTSTRAP' "$ev" && return 1
  content_has "$ev" "$EVAL_KG_BULLET" || return 1
  bootstrap_ln="$(grep -nF 'Unresolved' "$ev" | head -1 | cut -d: -f1)"
  kg_ln="$(grep -nF 'kit-owned file (`_kit/kit-guard.sh check` exits 4)' "$ev" | head -1 | cut -d: -f1)"
  [[ -n "$bootstrap_ln" && -n "$kg_ln" && "$bootstrap_ln" -lt "$kg_ln" ]] || return 1
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

emit_cache_init

run_check a check_guard_modes 'kit-guard check modes (clean, modified, missing, exclusions, manifest, _kit absent)'
run_check b check_hook_claude 'hook claude deny/allow, notebook_path, AGENT_KIT_GUARD=0, JSON escapes'
run_check c check_hook_cursor 'hook cursor keys, deny JSON, allow exact bytes'
run_check d check_usage 'usage exit 2 for missing/invalid args'
run_check e check_emit_on 'emit kit_guard on: tool, configs, hook e2e, second emit written 0'
run_check f check_existing_configs 'existing settings/hooks warnings once; pre-merged settings silent'
run_check g check_partial_harnesses 'copilot and codex partial-support warnings'
run_check h check_emit_check_flag 'emit.sh --check mirrors check exit codes'
run_check i check_flag_off 'kit_guard absent vs false byte identity'
run_check j check_validation 'non-boolean kit_guard exit 3; manifest options'
run_check k check_rendered_text 'rendered gate text four research×loop×flag variants'
run_check l check_turning_off 're-emit kit_guard false prunes tools, hook warnings'
run_check m check_cursor_caller_claude 'hook claude Cursor-caller JSON and CURSOR_PROJECT_DIR'
run_check n check_progress_location 'feature progress.md vs ORCHESTRATION.md'
run_check o check_evaluator_bootstrap 'evaluator kit-guard bullet after bootstrap text'

emit_cache_verify

echo
echo "=== kit-guard summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
