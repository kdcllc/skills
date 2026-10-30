#!/usr/bin/env bash
# Behavioral suite: flags.hook_telemetry end to end — emit output (hook-log tool, hook configs, warnings,
# manifest, validation), rendered ORCHESTRATION and _memory/README.md text, the emitted hook command
# strings, and the emitted tool run from an emitted root — plus mutation proofs that each check bites.
# Scratch roots only; no network; no git history. Answers files are the emit-golden case answers with
# the flag inserted.
#
# Structure follows kit-guard.sh: PASS:/FAIL:/SKIP: lines, a summary, RESULT. Each check records why it
# failed (the `no` helper) so a mutation proof can require that the check fails for the intended reason.
# Mutation proofs copy skills/agent-kit to a temp dir, change one file, assert (cmp) that the file
# really changed, and run the case's check against that copy through --kit.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03
unset CURSOR_PROJECT_DIR CLAUDE_PROJECT_DIR AGENT_KIT_HOOK_LOG AGENT_KIT_HOOK_LOG_MAX_BYTES HOOK_LOG_NOW
# Bash 5.2 expands `&` in a ${var//pat/repl} replacement unless this is off; the mutators need literals.
shopt -u patsub_replacement 2>/dev/null || true

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akhooktel.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"
# shellcheck source=../lib/kit-version.sh
. "$HERE/../lib/kit-version.sh"
. "$HERE/../lib/emit-cache.sh"
. "$HERE/../lib/parallel.sh"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"
ORIG_KIT="$KIT"
GOLDEN_CASES="$REPO_ROOT/tests/agent-kit/fixtures/emit-golden/cases"
BASE_ALL="$GOLDEN_CASES/harness-all-four/answers.json"
BASE_CLAUDE="$GOLDEN_CASES/harness-claude-code/answers.json"
BASE_CURSOR="$GOLDEN_CASES/harness-cursor/answers.json"

TMP_BASE="$FIXTURE_TMPDIR"
pass=0
fail=0
skip=0
WHY_FILE=""

if command -v jq >/dev/null 2>&1; then HAVE_JQ=1; else HAVE_JQ=0; fi

_suite_cleanup() {
  chmod -R u+rwx "$TMP_BASE" 2>/dev/null
  rm -rf "$TMP_BASE"
  par_cleanup
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

par_fail() {
  report FAIL "$1"
}

for _need in "$BASE_ALL" "$BASE_CLAUDE" "$BASE_CURSOR"; do
  if [[ ! -f "$_need" ]]; then
    echo "FAIL: fixture missing: $_need" >&2
    exit 1
  fi
done

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

# --- failure bookkeeping ---------------------------------------------------------------------

no() { # no <label> — record why a check failed (when a caller reads WHY_FILE); always returns 1
  if [[ -n "$WHY_FILE" ]]; then printf '%s' "$1" > "$WHY_FILE"; fi
  return 1
}

ck() { # ck <label> cmd... — run cmd; on failure record the label and return 1
  local label="$1"
  shift
  if "$@"; then return 0; fi
  no "$label"
}

not() { ! "$@"; }

# --- small file helpers ----------------------------------------------------------------------

sha256_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  else
    shasum -a 256 "$f" | awk '{print $1}'
  fi
}

eq_text() { # file text — the file holds exactly <text> plus one trailing newline
  cmp -s <(printf '%s\n' "$2") "$1"
}

count_line() { # file exact-line → how many lines equal it
  local n
  n="$(grep -cxF -- "$2" "$1" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

count_text() { # file fixed-substring → how many lines contain it
  local n
  n="$(grep -cF -- "$2" "$1" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

has_markers() { # file → 0 when an IF/ENDIF marker for the flag survived rendering
  grep -qE '(END)?IF hook_telemetry' "$1"
}

nlines() { # file → line count (0 when missing)
  if [[ -f "$1" ]]; then wc -l < "$1" | tr -d ' '; else echo 0; fi
}

no_hook_log_under() { # root subdir → 0 when no *hook-log* file exists under it
  local root="$1" sub="$2" hits
  [[ -d "$root/$sub" ]] || return 0
  hits="$(find "$root/$sub" -name '*hook-log*' 2>/dev/null | head -1 || true)"
  [[ -z "$hits" ]]
}

manifest_has_file() { # root relpath
  jq -e --arg p "$2" '.files | has($p)' "$1/orchestration-kit.manifest.json" >/dev/null
}

# --- answers ---------------------------------------------------------------------------------

make_answers() { # out base ht kg [research loop] — ht/kg: absent | true | false | a JSON literal
  local out="$1" base="$2" ht="$3" kg="$4" r="${5:-}" l="${6:-}"
  jq --arg ht "$ht" --arg kg "$kg" --arg r "$r" --arg l "$l" '
    def setflag($name; $v):
      if $v == "absent" then del(.flags[$name])
      elif $v == "true" then .flags[$name] = true
      elif $v == "false" then .flags[$name] = false
      else .flags[$name] = ($v | fromjson) end;
    setflag("hook_telemetry"; $ht) | setflag("kit_guard"; $kg) |
    (if $r != "" then .flags.research = ($r == "1") else . end) |
    (if $l != "" then .flags.loop = ($l == "1") else . end)
  ' "$base" > "$out"
}

fresh_emit() { # base ht kg [research loop] → FE_ROOT FE_ERR (a cached emit copied into a new root)
  local ans
  alloc_path ans
  ans="$ALLOC_PATH"
  make_answers "$ans" "$@" || { no 'answers file'; return 1; }
  alloc_path feerr
  FE_ERR="$ALLOC_PATH"
  alloc_root
  FE_ROOT="$ALLOC_PATH"
  if ! emit_cache_copy "$FE_ROOT" "$ans"; then
    no 'emit'
    return 1
  fi
  cp "$EMIT_CACHE_ERR" "$FE_ERR" 2>/dev/null || : > "$FE_ERR"
  return 0
}

answers_file() { # base ht kg [research loop] → ALLOC_PATH is a new answers file
  local out
  alloc_path ans
  out="$ALLOC_PATH"
  make_answers "$out" "$@" || return 1
  ALLOC_PATH="$out"
}

# --- expected bytes (written out, not derived from the emitter) -------------------------------

read -r -d '' EXP_SETTINGS_MIN <<'EOF' || true
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "3"
  }
}
EOF

read -r -d '' EXP_SETTINGS_KG <<'EOF' || true
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

read -r -d '' EXP_CURSOR_KG <<'EOF' || true
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

read -r -d '' EXP_SETTINGS_HOOKS <<'EOF' || true
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "3"
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "test -f \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" && bash \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" hook claude || true"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "test -f \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" && bash \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" hook claude || true"
          }
        ]
      }
    ]
  }
}
EOF

read -r -d '' EXP_CURSOR_HOOKS <<'EOF' || true
{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": "bash _kit/hook-log.sh hook cursor",
        "loop_limit": 1
      }
    ],
    "subagentStop": [
      {
        "command": "bash _kit/hook-log.sh hook cursor",
        "loop_limit": 1
      }
    ]
  }
}
EOF

read -r -d '' EXP_SETTINGS_BOTH <<'EOF' || true
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
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "test -f \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" && bash \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" hook claude || true"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "test -f \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" && bash \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" hook claude || true"
          }
        ]
      }
    ]
  }
}
EOF

read -r -d '' EXP_CURSOR_BOTH <<'EOF' || true
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "command": "bash _kit/kit-guard.sh hook cursor",
        "matcher": "Write|Delete"
      }
    ],
    "stop": [
      {
        "command": "bash _kit/hook-log.sh hook cursor",
        "loop_limit": 1
      }
    ],
    "subagentStop": [
      {
        "command": "bash _kit/hook-log.sh hook cursor",
        "loop_limit": 1
      }
    ]
  }
}
EOF

# stderr of a flag-on emit with all four harnesses: the two partial-support warnings, emit's sorted order.
read -r -d '' EXP_STDERR_HT <<'EOF' || true
emit: warning: flags.hook_telemetry is partial on codex: no telemetry hook
emit: warning: flags.hook_telemetry is partial on copilot: no telemetry hook
EOF

read -r -d '' EXP_STDERR_BOTH <<'EOF' || true
emit: warning: flags.hook_telemetry is partial on codex: no telemetry hook
emit: warning: flags.hook_telemetry is partial on copilot: no telemetry hook
emit: warning: flags.kit_guard is partial on codex: no edit-blocking hook; run emit.sh --check in CI (_kit/ is gitignored)
emit: warning: flags.kit_guard is partial on copilot: no edit-blocking hook; run emit.sh --check in CI (_kit/ is gitignored)
EOF

read -r -d '' WARN_SETTINGS_MERGE <<'EOF' || true
warning: .claude/settings.json exists without the hook-telemetry hooks — left untouched; merge into it: {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"test -f \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" && bash \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" hook claude || true"}]}],"SubagentStop":[{"hooks":[{"type":"command","command":"test -f \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" && bash \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" hook claude || true"}]}]}}
EOF

read -r -d '' WARN_CURSOR_MERGE <<'EOF' || true
warning: .cursor/hooks.json exists without the hook-telemetry hooks — left untouched; add to its "hooks" object: "stop":[{"command":"bash _kit/hook-log.sh hook cursor","loop_limit":1}],"subagentStop":[{"command":"bash _kit/hook-log.sh hook cursor","loop_limit":1}]
EOF

read -r -d '' WARN_SETTINGS_REMOVE <<'EOF' || true
warning: .claude/settings.json still references _kit/hook-log.sh but flags.hook_telemetry is off — remove those hook entries
EOF

read -r -d '' WARN_CURSOR_REMOVE <<'EOF' || true
warning: .cursor/hooks.json still references _kit/hook-log.sh but flags.hook_telemetry is off — remove those hook entries
EOF

read -r -d '' WARN_KG_SETTINGS_MERGE <<'EOF' || true
warning: .claude/settings.json exists without the kit-guard hook — left untouched; merge into it: {"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/_kit/kit-guard.sh\" hook claude"}]}]}}
EOF

SPAWN_DEPTH_MSG='emit: .claude/settings.json present without CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH — left untouched'

# Rendered text.
TREE_LINE='_kit/{hook-log.sh,hook-log.cmd}  # Single-copy tools: stop/subagent-stop hook telemetry (hook / summary) + Windows launcher'
NOTE_LINE='With hook telemetry on, the Claude Code and Cursor stop hooks append one metadata line per'
NOTE_SUMMARY='`_kit/hook-log.sh summary` prints the counts and the error and aborted runs (Windows outside'
README_LINE='    hooks/               # events.jsonl (+ events.1.jsonl): stop/subagent-stop hook telemetry'
ORCH_FILES='.claude/ORCHESTRATION.md .cursor/ORCHESTRATION.md ORCHESTRATION.md'

# Hook payloads.
P_CLAUDE_STOP='{"session_id":"sess-e2e","prompt_id":"prm-e2e","hook_event_name":"Stop","stop_hook_active":false}'
P_CLAUDE_SUB='{"session_id":"sess-e2e","prompt_id":"prm-e2e","hook_event_name":"SubagentStop","agent_id":"ag-e2e","agent_type":"implementer"}'
P_CURSOR_SUB='{"conversation_id":"conv-e2e","generation_id":"gen-e2e","model":"test-model","hook_event_name":"subagentStop","cursor_version":"1.0.0","workspace_roots":["/w"],"user_email":"MAIL-MARKER-7f3a@example.invalid","transcript_path":"/t/c.jsonl","subagent_type":"explore","status":"completed","task":"TASK-MARKER-7f3a","description":"desc","summary":"sum","duration_ms":1234,"message_count":5,"tool_call_count":7,"loop_count":0,"modified_files":["a.txt","b.txt"]}'

# ===========================================================================
# Case 1 — flag on, all four harnesses
# ===========================================================================

c1_tool_files() {
  local r
  fresh_emit "$BASE_ALL" true absent || return 1
  r="$FE_ROOT"
  ck 'hook-log.sh present' test -f "$r/_kit/hook-log.sh" || return 1
  ck 'hook-log.sh executable' test -x "$r/_kit/hook-log.sh" || return 1
  ck 'hook-log.sh bytes' cmp -s "$ORIG_KIT/templates/tools/hook-log.sh" "$r/_kit/hook-log.sh" || return 1
  ck 'hook-log.cmd present' test -f "$r/_kit/hook-log.cmd" || return 1
  ck 'hook-log.cmd bytes' cmp -s "$ORIG_KIT/templates/tools/bash-launcher.cmd" "$r/_kit/hook-log.cmd" || return 1
  ck 'kit-guard files absent' not test -e "$r/_kit/kit-guard.sh" || return 1
  ck 'no hook-log files for copilot' no_hook_log_under "$r" .github || return 1
  ck 'no hook-log files for codex' no_hook_log_under "$r" .codex || return 1
  return 0
}

c1_configs() {
  local r
  fresh_emit "$BASE_ALL" true absent || return 1
  r="$FE_ROOT"
  ck 'claude config bytes' eq_text "$r/.claude/settings.json" "$EXP_SETTINGS_HOOKS" || return 1
  ck 'cursor config bytes' eq_text "$r/.cursor/hooks.json" "$EXP_CURSOR_HOOKS" || return 1
  return 0
}

c1_stderr() {
  fresh_emit "$BASE_ALL" true absent || return 1
  ck 'stderr exact' eq_text "$FE_ERR" "$EXP_STDERR_HT" || return 1
  return 0
}

c1_manifest() {
  local r mf sh_hash
  fresh_emit "$BASE_ALL" true absent || return 1
  r="$FE_ROOT"
  mf="$r/orchestration-kit.manifest.json"
  ck 'options.hook_telemetry' jq -e '.options.hook_telemetry == true' "$mf" >/dev/null || return 1
  ck 'manifest lists hook-log.sh' manifest_has_file "$r" '_kit/hook-log.sh' || return 1
  ck 'manifest lists hook-log.cmd' manifest_has_file "$r" '_kit/hook-log.cmd' || return 1
  sh_hash="$(sha256_file "$r/_kit/hook-log.sh")"
  ck 'manifest sha of hook-log.sh' jq -e --arg h "$sh_hash" '.files["_kit/hook-log.sh"] == $h' "$mf" >/dev/null || return 1
  ck 'manifest kit version' test "$(jq -r '.kitVersion' "$mf")" = "$(kit_version "$ORIG_KIT/SKILL.md")" || return 1
  return 0
}

# ===========================================================================
# Case 2 — both flags
# ===========================================================================

c2_both_configs() {
  local r
  fresh_emit "$BASE_ALL" true true || return 1
  r="$FE_ROOT"
  ck 'claude combined bytes' eq_text "$r/.claude/settings.json" "$EXP_SETTINGS_BOTH" || return 1
  ck 'cursor combined bytes' eq_text "$r/.cursor/hooks.json" "$EXP_CURSOR_BOTH" || return 1
  return 0
}

c2_both_tools() {
  local r
  fresh_emit "$BASE_ALL" true true || return 1
  r="$FE_ROOT"
  ck 'both tools executable' test -x "$r/_kit/kit-guard.sh" -a -x "$r/_kit/hook-log.sh" || return 1
  ck 'both launchers present' test -f "$r/_kit/kit-guard.cmd" -a -f "$r/_kit/hook-log.cmd" || return 1
  ck 'manifest options both true' jq -e '.options.hook_telemetry == true and .options.kit_guard == true' \
    "$r/orchestration-kit.manifest.json" >/dev/null || return 1
  return 0
}

c2_both_stderr() {
  fresh_emit "$BASE_ALL" true true || return 1
  ck 'both stderr exact' eq_text "$FE_ERR" "$EXP_STDERR_BOTH" || return 1
  return 0
}

# ===========================================================================
# Case 3 — flag off (absent and false) and kit-guard only
# ===========================================================================

c3_off() { # absent|false
  local r
  fresh_emit "$BASE_ALL" "$1" absent || return 1
  r="$FE_ROOT"
  ck 'no hook-log files' not test -e "$r/_kit/hook-log.sh" -o -e "$r/_kit/hook-log.cmd" || return 1
  ck 'settings min bytes' eq_text "$r/.claude/settings.json" "$EXP_SETTINGS_MIN" || return 1
  ck 'no cursor hooks file' not test -e "$r/.cursor/hooks.json" || return 1
  ck 'no hook-log text anywhere' not grep -rIqE --exclude=orchestration-kit.manifest.json 'hook-log|work/hooks|hook telemetry|hook_telemetry' "$r" || return 1
  ck 'stderr silent' test ! -s "$FE_ERR" || return 1
  return 0
}

c3_kg_only() { # absent|false (hook_telemetry)
  local r
  fresh_emit "$BASE_ALL" "$1" true || return 1
  r="$FE_ROOT"
  ck 'no hook-log files' not test -e "$r/_kit/hook-log.sh" -o -e "$r/_kit/hook-log.cmd" || return 1
  ck 'kit-guard tool emitted' test -x "$r/_kit/kit-guard.sh" || return 1
  ck 'kit-guard settings bytes' eq_text "$r/.claude/settings.json" "$EXP_SETTINGS_KG" || return 1
  ck 'kit-guard cursor bytes' eq_text "$r/.cursor/hooks.json" "$EXP_CURSOR_KG" || return 1
  return 0
}

c3_off_identity() {
  local ra rf
  fresh_emit "$BASE_ALL" absent absent || return 1
  ra="$FE_ROOT"
  fresh_emit "$BASE_ALL" false absent || return 1
  rf="$FE_ROOT"
  ck 'absent vs false trees' diff -qr --exclude=orchestration-kit.manifest.json "$ra" "$rf" >/dev/null 2>&1 || return 1
  jq -e -S 'del(.options.hook_telemetry, .answers.flags.hook_telemetry, .installedAt)' \
    "$ra/orchestration-kit.manifest.json" > "$ra/mf.norm" || { no 'normalise manifest (absent)'; return 1; }
  jq -e -S 'del(.options.hook_telemetry, .answers.flags.hook_telemetry, .installedAt)' \
    "$rf/orchestration-kit.manifest.json" > "$rf/mf.norm" || { no 'normalise manifest (false)'; return 1; }
  ck 'absent vs false manifests' cmp -s "$ra/mf.norm" "$rf/mf.norm" || return 1
  return 0
}

# ===========================================================================
# Case 4 — existing configs without a reference
# ===========================================================================

c4_existing() { # claude|cursor
  local which="$1" base rel body warn merged ans root sha0 pass_name
  if [[ "$which" == claude ]]; then
    base="$BASE_CLAUDE"; rel='.claude/settings.json'; body="$EXP_SETTINGS_MIN"
    warn="emit: $WARN_SETTINGS_MERGE"; merged="$EXP_SETTINGS_HOOKS"
  else
    base="$BASE_CURSOR"; rel='.cursor/hooks.json'; body='{"version":1,"hooks":{}}'
    warn="emit: $WARN_CURSOR_MERGE"; merged="$EXP_CURSOR_HOOKS"
  fi
  answers_file "$base" true absent || { no 'answers file'; return 1; }
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/$(dirname "$rel")"
  printf '%s\n' "$body" > "$root/$rel"
  sha0="$(sha256_file "$root/$rel")"

  for pass_name in emit upgrade; do
    if [[ "$pass_name" == emit ]]; then
      capture_emit_sh "$root" --answers "$ans"
    else
      capture_emit_sh "$root" --answers "$ans" --upgrade
    fi
    ck "$pass_name rc 0" test "$EMIT_RC" -eq 0 || return 1
    ck "file unchanged after $pass_name" test "$(sha256_file "$root/$rel")" = "$sha0" || return 1
    ck "merge warning once ($pass_name)" test "$(count_line "$EMIT_STDERR" "$warn")" -eq 1 || return 1
    ck "no hook-log reference merged ($pass_name)" not grep -qF '_kit/hook-log.sh' "$root/$rel" || return 1
    ck "tool still emitted ($pass_name)" test -x "$root/_kit/hook-log.sh" || return 1
  done

  # Control: a config that already carries the hooks gets no merge warning.
  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/$(dirname "$rel")"
  printf '%s\n' "$merged" > "$root/$rel"
  capture_emit_sh "$root" --answers "$ans"
  ck 'control rc 0' test "$EMIT_RC" -eq 0 || return 1
  ck 'control: no merge warning when already merged' test "$(count_text "$EMIT_STDERR" 'exists without the hook-telemetry hooks')" -eq 0 || return 1
  return 0
}

# ===========================================================================
# Case 5 — stale reference with the flag off
# ===========================================================================

c5_stale() { # claude|cursor
  local which="$1" base rel stale clean warn ht ans root sha0
  if [[ "$which" == claude ]]; then
    base="$BASE_CLAUDE"; rel='.claude/settings.json'; stale="$EXP_SETTINGS_HOOKS"
    clean="$EXP_SETTINGS_MIN"; warn="emit: $WARN_SETTINGS_REMOVE"
  else
    base="$BASE_CURSOR"; rel='.cursor/hooks.json'; stale="$EXP_CURSOR_HOOKS"
    clean='{"version":1,"hooks":{}}'; warn="emit: $WARN_CURSOR_REMOVE"
  fi
  for ht in absent false; do
    answers_file "$base" "$ht" absent || { no 'answers file'; return 1; }
    ans="$ALLOC_PATH"
    alloc_root; root="$ALLOC_PATH"
    mkdir -p "$root/$(dirname "$rel")"
    printf '%s\n' "$stale" > "$root/$rel"
    sha0="$(sha256_file "$root/$rel")"
    capture_emit_sh "$root" --answers "$ans"
    ck "rc 0 ($ht)" test "$EMIT_RC" -eq 0 || return 1
    ck "removal warning once ($ht)" test "$(count_line "$EMIT_STDERR" "$warn")" -eq 1 || return 1
    ck "file untouched ($ht)" test "$(sha256_file "$root/$rel")" = "$sha0" || return 1
    ck "no hook-log tool ($ht)" not test -e "$root/_kit/hook-log.sh" || return 1
  done

  # Control: no stale reference, no removal warning.
  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/$(dirname "$rel")"
  printf '%s\n' "$clean" > "$root/$rel"
  capture_emit_sh "$root" --answers "$ans"
  ck 'control rc 0' test "$EMIT_RC" -eq 0 || return 1
  ck 'control: no removal warning without a reference' test "$(count_text "$EMIT_STDERR" 'is off — remove those hook entries')" -eq 0 || return 1
  return 0
}

# ===========================================================================
# Case 6 — spawn-depth message with an existing settings file
# ===========================================================================

c6_spawn_depth() {
  local ans root sha0
  answers_file "$BASE_CLAUDE" true true || { no 'answers file'; return 1; }
  ans="$ALLOC_PATH"

  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/.claude"
  printf '%s\n' '{"hooks":{}}' > "$root/.claude/settings.json"
  sha0="$(sha256_file "$root/.claude/settings.json")"
  capture_emit_sh "$root" --answers "$ans"
  ck 'rc 0' test "$EMIT_RC" -eq 0 || return 1
  ck 'spawn-depth message once' test "$(count_line "$EMIT_STDERR" "$SPAWN_DEPTH_MSG")" -eq 1 || return 1
  ck 'hook-telemetry merge warning once' test "$(count_line "$EMIT_STDERR" "emit: $WARN_SETTINGS_MERGE")" -eq 1 || return 1
  ck 'kit-guard merge warning once' test "$(count_line "$EMIT_STDERR" "emit: $WARN_KG_SETTINGS_MERGE")" -eq 1 || return 1
  ck 'settings untouched' test "$(sha256_file "$root/.claude/settings.json")" = "$sha0" || return 1

  # Control: with the spawn-depth env present there is no message.
  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/.claude"
  printf '%s\n' '{"env":{"CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH":"3"},"hooks":{}}' > "$root/.claude/settings.json"
  capture_emit_sh "$root" --answers "$ans"
  ck 'control rc 0' test "$EMIT_RC" -eq 0 || return 1
  ck 'control: no spawn-depth message when the env is set' test "$(count_text "$EMIT_STDERR" 'present without CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH')" -eq 0 || return 1
  return 0
}

# ===========================================================================
# Case 7 — validation and manifest persistence
# ===========================================================================

c7_validation() {
  local val mode root ans
  for val in '"yes"' 1 null '{}'; do
    for mode in normal dry check; do
      alloc_root; root="$ALLOC_PATH"
      answers_file "$BASE_CLAUDE" "$val" absent || { no 'answers file'; return 1; }
      ans="$ALLOC_PATH"
      case "$mode" in
        dry)   capture_emit_sh "$root" --answers "$ans" --dry-run ;;
        check) capture_emit_sh "$root" --check-answers --answers "$ans" ;;
        *)     capture_emit_sh "$root" --answers "$ans" ;;
      esac
      ck "validation rc 3 ($val, $mode)" test "$EMIT_RC" -eq 3 || return 1
      ck "validation message ($val, $mode)" grep -qF 'flags.hook_telemetry must be a boolean' "$EMIT_STDERR" || return 1
      ck "nothing emitted on invalid ($val, $mode)" not test -e "$root/_kit" || return 1
    done
  done
  return 0
}

c7_manifest_options() {
  local mode mf
  for mode in true false absent; do
    fresh_emit "$BASE_ALL" "$mode" absent || return 1
    mf="$FE_ROOT/orchestration-kit.manifest.json"
    case "$mode" in
      true)   ck 'options true' jq -e '.options.hook_telemetry == true' "$mf" >/dev/null || return 1 ;;
      false)  ck 'options false' jq -e '.options.hook_telemetry == false' "$mf" >/dev/null || return 1 ;;
      absent) ck 'options absent' jq -e '(.options | has("hook_telemetry")) | not' "$mf" >/dev/null || return 1 ;;
    esac
    if jq -e '.options | has("hook_telemetry")' "$mf" >/dev/null 2>&1; then
      jq -c '.options' "$mf" > "$FE_ROOT/opt.uns"
      jq -cS '.options' "$mf" > "$FE_ROOT/opt.srt"
      ck "options keys sorted ($mode)" cmp -s "$FE_ROOT/opt.uns" "$FE_ROOT/opt.srt" || return 1
    fi
  done
  return 0
}

# ===========================================================================
# Case 8 — rendered ORCHESTRATION and _memory/README.md
# ===========================================================================

c8_orch_on() {
  local f
  fresh_emit "$BASE_ALL" true absent || return 1
  for f in $ORCH_FILES; do
    ck "orch tree line once ($f)" test "$(count_line "$FE_ROOT/$f" "$TREE_LINE")" -eq 1 || return 1
    ck "orch note present ($f)" grep -qF "$NOTE_SUMMARY" "$FE_ROOT/$f" || return 1
    ck "orch note opening once ($f)" test "$(count_line "$FE_ROOT/$f" "$NOTE_LINE")" -eq 1 || return 1
    ck "orch markers gone ($f)" not has_markers "$FE_ROOT/$f" || return 1
  done
  return 0
}

c8_orch_off() { # absent|false
  local f
  fresh_emit "$BASE_ALL" "$1" absent || return 1
  for f in $ORCH_FILES; do
    ck "orch flag off tree line absent ($f)" test "$(count_text "$FE_ROOT/$f" '_kit/{hook-log.sh,hook-log.cmd}')" -eq 0 || return 1
    ck "orch flag off note absent ($f)" not grep -qF '_kit/hook-log.sh summary' "$FE_ROOT/$f" || return 1
    ck "orch flag off note opening absent ($f)" test "$(count_line "$FE_ROOT/$f" "$NOTE_LINE")" -eq 0 || return 1
    ck "orch flag off markers gone ($f)" not has_markers "$FE_ROOT/$f" || return 1
  done
  return 0
}

c8_variant() { # research loop mode(true|false) — one research × loop variant, claude-code only
  local r="$1" l="$2" mode="$3" f
  fresh_emit "$BASE_CLAUDE" "$mode" absent "$r" "$l" || return 1
  f="$FE_ROOT/.claude/ORCHESTRATION.md"
  ck 'variant markers gone' not has_markers "$f" || return 1
  if [[ "$mode" == true ]]; then
    ck "variant r=$r l=$l tree line once" test "$(count_line "$f" "$TREE_LINE")" -eq 1 || return 1
    ck "variant r=$r l=$l note once" test "$(count_line "$f" "$NOTE_LINE")" -eq 1 || return 1
  else
    ck "variant r=$r l=$l tree line absent" test "$(count_text "$f" '_kit/{hook-log.sh,hook-log.cmd}')" -eq 0 || return 1
    ck "variant r=$r l=$l note absent" test "$(count_line "$f" "$NOTE_LINE")" -eq 0 || return 1
  fi
  return 0
}

c8_orch_variants() {
  local r l mode pid rc=0 pids=""
  for mode in true false; do
    for r in 0 1; do
      for l in 0 1; do
        if [[ "${PAR_JOBS:-1}" -gt 1 ]]; then
          c8_variant "$r" "$l" "$mode" &
          pids="$pids $!"
        else
          c8_variant "$r" "$l" "$mode" || rc=1
        fi
      done
    done
  done
  for pid in $pids; do
    wait "$pid" || rc=1
  done
  [[ "$rc" -eq 0 ]] || { no 'a research x loop variant'; return 1; }
  return 0
}

c8_readme_on() {
  local f
  fresh_emit "$BASE_ALL" true absent || return 1
  f="$FE_ROOT/_memory/README.md"
  ck 'readme file present' test -f "$f" || return 1
  ck 'readme line once' test "$(count_line "$f" "$README_LINE")" -eq 1 || return 1
  ck 'readme markers gone' not has_markers "$f" || return 1
  return 0
}

c8_readme_off() { # absent|false
  local f
  fresh_emit "$BASE_ALL" "$1" absent || return 1
  f="$FE_ROOT/_memory/README.md"
  ck 'readme file present' test -f "$f" || return 1
  ck 'readme flag off line absent' test "$(count_text "$f" 'stop/subagent-stop hook telemetry')" -eq 0 || return 1
  ck 'readme flag off markers gone' not has_markers "$f" || return 1
  return 0
}

# ===========================================================================
# Case 9 — fresh-clone guard on the emitted Claude Code commands
# ===========================================================================

# run_cmd_in <root> <command-string> <payload> → CMD_RC CMD_OUT CMD_ERR (sh -c, CLAUDE_PROJECT_DIR=<root>)
run_cmd_in() {
  local root="$1" cmd="$2" payload="$3"
  alloc_path cmd-out
  CMD_OUT="$ALLOC_PATH.out"
  CMD_ERR="$ALLOC_PATH.err"
  env CLAUDE_PROJECT_DIR="$root" sh -c "$cmd" >"$CMD_OUT" 2>"$CMD_ERR" <<<"$payload"
  CMD_RC=$?
}

c9_fresh_clone_guard() {
  local r cmd_stop cmd_sub empty which cmd payload
  fresh_emit "$BASE_ALL" true absent || return 1
  r="$FE_ROOT"
  cmd_stop="$(jq -r '.hooks.Stop[0].hooks[0].command' "$r/.claude/settings.json")"
  cmd_sub="$(jq -r '.hooks.SubagentStop[0].hooks[0].command' "$r/.claude/settings.json")"
  ck 'extracted Stop command' test -n "$cmd_stop" -a "$cmd_stop" != null || return 1
  ck 'extracted SubagentStop command' test -n "$cmd_sub" -a "$cmd_sub" != null || return 1

  # Root without _kit/hook-log.sh: a fresh clone (no _kit at all) and a kit missing only this tool.
  for which in stop sub; do
    if [[ "$which" == stop ]]; then cmd="$cmd_stop"; payload="$P_CLAUDE_STOP"; else cmd="$cmd_sub"; payload="$P_CLAUDE_SUB"; fi
    alloc_root; empty="$ALLOC_PATH"
    run_cmd_in "$empty" "$cmd" "$payload"
    ck "no-script exit 0 ($which)" test "$CMD_RC" -eq 0 || return 1
    ck "no-script stdout empty ($which)" test ! -s "$CMD_OUT" || return 1
    ck "no-script stderr empty ($which)" test ! -s "$CMD_ERR" || return 1
    ck "no-script writes nothing ($which)" not test -e "$empty/_memory" || return 1

    alloc_root; empty="$ALLOC_PATH"
    cp -Rp "$r/_kit" "$empty/_kit"
    rm -f "$empty/_kit/hook-log.sh"
    run_cmd_in "$empty" "$cmd" "$payload"
    ck "no-script (kit present) exit 0 ($which)" test "$CMD_RC" -eq 0 || return 1
    ck "no-script (kit present) stdout empty ($which)" test ! -s "$CMD_OUT" || return 1
    ck "no-script (kit present) stderr empty ($which)" test ! -s "$CMD_ERR" || return 1
    ck "no-script (kit present) writes nothing ($which)" not test -e "$empty/_memory" || return 1
  done

  # With the script present each command writes exactly one line and prints nothing.
  alloc_root; empty="$ALLOC_PATH"
  cp -Rp "$r/_kit" "$empty/_kit"
  run_cmd_in "$empty" "$cmd_stop" "$P_CLAUDE_STOP"
  ck 'script present: Stop exit 0' test "$CMD_RC" -eq 0 || return 1
  ck 'script present: Stop prints nothing' test ! -s "$CMD_OUT" -a ! -s "$CMD_ERR" || return 1
  ck 'script present writes one line' test "$(nlines "$empty/_memory/work/hooks/events.jsonl")" -eq 1 || return 1
  ck 'script present: Stop line' grep -qF '"harness":"claude","event":"Stop","session":"sess-e2e"' "$empty/_memory/work/hooks/events.jsonl" || return 1
  run_cmd_in "$empty" "$cmd_sub" "$P_CLAUDE_SUB"
  ck 'script present: SubagentStop exit 0' test "$CMD_RC" -eq 0 || return 1
  ck 'script present: SubagentStop prints nothing' test ! -s "$CMD_OUT" -a ! -s "$CMD_ERR" || return 1
  ck 'script present: second line' test "$(nlines "$empty/_memory/work/hooks/events.jsonl")" -eq 2 || return 1
  ck 'script present: SubagentStop line' grep -qF '"event":"SubagentStop","session":"sess-e2e","generation":"prm-e2e","agent_id":"ag-e2e","agent_type":"implementer"' "$empty/_memory/work/hooks/events.jsonl" || return 1
  return 0
}

# ===========================================================================
# Case 10 — the emitted Cursor hook and summary, end to end
# ===========================================================================

c10_emitted_hook_e2e() {
  local r cmd_stop cmd_sub log key want out err rc summary
  fresh_emit "$BASE_ALL" true absent || return 1
  r="$FE_ROOT"
  cmd_sub="$(jq -r '.hooks.subagentStop[0].command' "$r/.cursor/hooks.json")"
  cmd_stop="$(jq -r '.hooks.stop[0].command' "$r/.cursor/hooks.json")"
  ck 'cursor command text' test "$cmd_sub" = 'bash _kit/hook-log.sh hook cursor' -a "$cmd_stop" = 'bash _kit/hook-log.sh hook cursor' || return 1

  log="$r/_memory/work/hooks/events.jsonl"
  alloc_path e2e
  out="$ALLOC_PATH.out"
  err="$ALLOC_PATH.err"
  rc=0
  (cd "$r" && printf '%s' "$P_CURSOR_SUB" | env HOOK_LOG_NOW=2026-10-29T12:00:00Z sh -c "$cmd_sub") >"$out" 2>"$err" || rc=$?
  ck 'cursor exit 0' test "$rc" -eq 0 || return 1
  ck 'cursor stdout {}' eq_text "$out" '{}' || return 1
  ck 'cursor stderr empty' test ! -s "$err" || return 1
  ck 'one log line' test "$(nlines "$log")" -eq 1 || return 1

  key="$(printf '%s' "$P_CURSOR_SUB" | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | cut -c1-16)"
  want='{"ts":"2026-10-29T12:00:00Z","harness":"cursor","event":"subagentStop","session":"conv-e2e","generation":"gen-e2e","agent_id":null,"agent_type":"explore","status":"completed","duration_ms":1234,"message_count":5,"tool_call_count":7,"loop_count":0,"model":"test-model","modified_files":2,"key":"'"$key"'"}'
  ck 'log line bytes' eq_text "$log" "$want" || return 1
  ck 'metadata only (task)' not grep -qF 'TASK-MARKER-7f3a' "$log" || return 1
  ck 'metadata only (email)' not grep -qF 'MAIL-MARKER-7f3a' "$log" || return 1

  summary="$(cd "$r" && bash _kit/hook-log.sh summary)"
  ck 'summary 1 events' grep -qF '1 events' <<<"$summary" || return 1
  ck 'summary by event' grep -qxF '  1 subagentStop' <<<"$summary" || return 1
  ck 'summary by status' grep -qxF '  1 completed' <<<"$summary" || return 1

  # The same payload again is not appended twice, and the summary still reports one event.
  (cd "$r" && printf '%s' "$P_CURSOR_SUB" | sh -c "$cmd_sub") >"$out" 2>"$err" || true
  ck 'duplicate not appended' test "$(nlines "$log")" -eq 1 || return 1
  summary="$(cd "$r" && bash _kit/hook-log.sh summary)"
  ck 'summary still 1 events' grep -qF '1 events' <<<"$summary" || return 1
  return 0
}

# ===========================================================================
# Mutators (operate on a copy of the kit) and the mutation-proof runner
# ===========================================================================

m_sub() { # m_sub <file> <from> <to> — replace every literal occurrence
  local f="$1" from="$2" to="$3" c r
  c="$(cat "$f"; printf x)"; c="${c%x}"
  r=${c//"$from"/$to}
  printf '%s' "$r" > "$f"
}

# m_block <file> <keyword> <drop|unwrap> — act on every `IF hook_telemetry` block whose body holds <keyword>:
# drop removes the block with its markers; unwrap keeps the body and removes only the markers.
m_block() {
  local f="$1" kw="$2" mode="$3"
  awk -v kw="$kw" -v mode="$mode" '
    $0 == "<!-- IF hook_telemetry -->" { inb = 1; open = $0; body = ""; next }
    inb && $0 == "<!-- ENDIF hook_telemetry -->" {
      inb = 0
      if (index(body, kw) > 0) {
        if (mode == "unwrap") printf "%s", body
      } else {
        printf "%s\n%s%s\n", open, body, $0
      }
      next
    }
    inb { body = body $0 "\n"; next }
    { print }
  ' "$f" > "$f.new" && mv "$f.new" "$f"
}

# mutation_proof <name> <check_spec> <want-label> <file-relative-to-kit> <mutator> [mutator args…]
# <check_spec> is a check function and its arguments, as one word-split string ("c3_off absent").
# Copies the kit, applies the mutator to one file, requires that the file changed (and still parses when
# it is a script), runs the case's check against the copy, and requires it to fail on <want-label>.
mutation_proof() {
  local name="$1" check_spec="$2" want="$3" rel="$4" mut="$5" d mkit why got
  shift 5
  if [[ "$HAVE_JQ" -ne 1 ]]; then
    report SKIP "mutation-proof $name" "jq not on PATH"
    return
  fi
  d="$(mktemp -d "$TMP_BASE/mut.XXXXXX")" || { report FAIL "mutation-proof $name" "mktemp failed"; return; }
  assert_fixture_root "$d" || { report FAIL "mutation-proof $name" "bad fixture root"; return; }
  mkit="$d/kit"
  mkdir -p "$d/cache"
  if ! cp -Rp "$ORIG_KIT" "$mkit"; then
    report FAIL "mutation-proof $name" "copy failed"
    rm -rf "$d"
    return
  fi
  "$mut" "$mkit/$rel" "$@"
  if cmp -s "$ORIG_KIT/$rel" "$mkit/$rel"; then
    report FAIL "mutation-proof $name" "the mutation changed nothing"
  elif [[ "$rel" == *.sh ]] && ! bash -n "$mkit/$rel" 2>/dev/null; then
    report FAIL "mutation-proof $name" "the mutant does not parse"
  else
    why="$d/why"
    : > "$why"
    # shellcheck disable=SC2086 # the spec is deliberately word-split into function + arguments
    if ( KIT="$mkit"; EMIT_SH="$mkit/bin/emit.sh"; export AGENT_KIT_EMIT_CACHE="$d/cache"; WHY_FILE="$why"; $check_spec ) >/dev/null 2>&1; then
      report FAIL "mutation-proof $name" "check still passed on the mutated copy"
    else
      got="$(cat "$why")"
      if [[ "$got" == *"$want"* ]]; then
        report PASS "mutation-proof $name" "check failed on: $got"
      else
        report FAIL "mutation-proof $name" "check failed for another reason: [$got] (wanted [$want])"
      fi
    fi
  fi
  rm -rf "$d"
}

# ===========================================================================
# Runner
# ===========================================================================

run_check() { # run_check <id> <fn> <title> [fn args…]
  local id="$1" fn="$2" title="$3"
  shift 3
  if [[ "$HAVE_JQ" -ne 1 ]]; then
    report SKIP "($id) $title" "jq not on PATH"
    return
  fi
  alloc_path why
  WHY_FILE="$ALLOC_PATH"
  : > "$WHY_FILE"
  if "$fn" "$@"; then
    report PASS "($id) $title"
  else
    report FAIL "($id) $title" "failed on: $(cat "$WHY_FILE")"
  fi
}

PAR_COUNTERS="pass fail skip"
PAR_REPORT_FAIL=par_fail

emit_cache_init
par_init

EMIT_REL='bin/emit.sh'
ORCH_REL='templates/ORCHESTRATION.md'
README_REL='templates/memory/README.md'
TOOL_REL='templates/tools/hook-log.sh'

# Case 1 — flag on, all four harnesses
par_block run_check 1a c1_tool_files 'flag on, four harnesses: _kit/hook-log.sh executable and byte-equal, hook-log.cmd equals the launcher, no kit-guard files'
par_block run_check 1b c1_configs 'flag on, four harnesses: .claude/settings.json and .cursor/hooks.json exact bytes'
par_block run_check 1c c1_stderr 'flag on, four harnesses: stderr is exactly the two partial warnings'
par_block run_check 1d c1_manifest 'flag on, four harnesses: manifest options.hook_telemetry true, both _kit/hook-log.* files listed with their hashes'

# Case 2 — both flags
par_block run_check 2a c2_both_configs 'kit_guard + hook_telemetry: both configs equal their exact combined bytes'
par_block run_check 2b c2_both_tools 'kit_guard + hook_telemetry: both tools and launchers emitted, both options true'
par_block run_check 2c c2_both_stderr 'kit_guard + hook_telemetry: stderr is the four partial warnings'

# Case 3 — flag off and kit-guard only
par_block run_check 3a c3_off 'flag absent: no hook-log files or text, settings equals the minimal bytes, no cursor hooks, silent stderr' absent
par_block run_check 3b c3_off 'flag false: no hook-log files or text, settings equals the minimal bytes, no cursor hooks, silent stderr' false
par_block run_check 3c c3_kg_only 'kit-guard only (flag absent): configs equal the kit-guard bytes, no hook-log files' absent
par_block run_check 3d c3_kg_only 'kit-guard only (flag false): configs equal the kit-guard bytes, no hook-log files' false
par_block run_check 3e c3_off_identity 'flag absent vs false: identical trees and manifests apart from the option'

# Cases 4-6 — existing and stale configs, spawn-depth message
par_block run_check 4a c4_existing 'existing .claude/settings.json: untouched by emit and --upgrade, merge warning exactly once with the exact text' claude
par_block run_check 4b c4_existing 'existing .cursor/hooks.json: untouched by emit and --upgrade, merge warning exactly once with the exact text' cursor
par_block run_check 5a c5_stale 'stale _kit/hook-log.sh reference in .claude/settings.json, flag off: removal warning exactly once' claude
par_block run_check 5b c5_stale 'stale _kit/hook-log.sh reference in .cursor/hooks.json, flag off: removal warning exactly once' cursor
par_block run_check 6 c6_spawn_depth 'existing settings without the spawn-depth env, both flags on: spawn-depth message exactly once'

# Case 7 — validation and manifest options
par_block run_check 7a c7_validation 'non-boolean hook_telemetry exits 3 with the message (emit, --dry-run, --check-answers)'
par_block run_check 7b c7_manifest_options 'manifest options.hook_telemetry persisted for true and false, omitted when absent, keys sorted'

# Case 8 — rendered text
par_block run_check 8a c8_orch_on 'ORCHESTRATION, flag on: tree line once, summary note present, no IF marker left'
par_block run_check 8b c8_orch_off 'ORCHESTRATION, flag absent: neither tree line nor note, no IF marker left' absent
par_block run_check 8c c8_orch_off 'ORCHESTRATION, flag false: neither tree line nor note, no IF marker left' false
par_block run_check 8d c8_orch_variants 'ORCHESTRATION across the four research x loop variants, flag on and off'
par_block run_check 8e c8_readme_on '_memory/README.md, flag on: hooks/ line once, no IF marker left'
par_block run_check 8f c8_readme_off '_memory/README.md, flag absent: no hooks/ line, no IF marker left' absent
par_block run_check 8g c8_readme_off '_memory/README.md, flag false: no hooks/ line, no IF marker left' false

# Cases 9-10 — emitted hook behavior
par_block run_check 9 c9_fresh_clone_guard 'emitted Claude Code Stop/SubagentStop commands: silent no-op without _kit/hook-log.sh, one line with it'
par_block run_check 10 c10_emitted_hook_e2e 'emitted Cursor hook command prints {} and logs one exact line; emitted summary reports 1 events'

# Mutation proofs (each on a copy of the kit; the file must change; the check must fail for the stated reason)
par_block mutation_proof '(1a) drop hook_telemetry from known_flag' c1_tool_files 'emit' "$EMIT_REL" m_sub 'kit_guard|hook_telemetry|\' 'kit_guard|\'
par_block mutation_proof '(1a) never emit _kit/hook-log.sh' c1_tool_files 'hook-log.sh present' "$EMIT_REL" m_sub 'put_emit "_kit/hook-log.sh" "$content"' ': "_kit/hook-log.sh" "$content"'
par_block mutation_proof '(1a) never emit _kit/hook-log.cmd' c1_tool_files 'hook-log.cmd present' "$EMIT_REL" m_sub 'map_set EMIT "_kit/hook-log.cmd" "$content"' ': "_kit/hook-log.cmd" "$content"'
par_block mutation_proof '(1b) remove the Stop entry' c1_configs 'claude config bytes' "$EMIT_REL" m_sub '    "Stop": [' '    "StopX": ['
par_block mutation_proof '(1b) cursor entries without loop_limit' c1_configs 'cursor config bytes' "$EMIT_REL" m_sub '        "loop_limit": 1' '        "loop_limitX": 1'
par_block mutation_proof '(1c) drop the codex partial warning' c1_stderr 'stderr exact' "$EMIT_REL" m_sub 'record_warn_line "warning: flags.hook_telemetry is partial on codex: no telemetry hook"' ': "warning: flags.hook_telemetry is partial on codex: no telemetry hook"'
par_block mutation_proof '(1d) persist the option under the wrong key' c1_manifest 'options.hook_telemetry' "$EMIT_REL" m_sub '"${J_US}options${J_US}hook_telemetry"' '"${J_US}options${J_US}hook_telemetryX"'
par_block mutation_proof '(2a) combined claude config loses the kit-guard entry' c2_both_configs 'claude combined bytes' "$EMIT_REL" m_sub '$(settings_hooks_claude_pretooluse),' ''
par_block mutation_proof '(2a) combined cursor config loses the kit-guard entry' c2_both_configs 'cursor combined bytes' "$EMIT_REL" m_sub '$(cursor_hooks_pretooluse),' ''
par_block mutation_proof '(3a) flag off still writes the hook config' 'c3_off absent' 'settings min bytes' "$EMIT_REL" m_sub 'put_emit ".claude/settings.json" "$(settings_json_min)"' 'put_emit ".claude/settings.json" "$(settings_json_hooks)"'
par_block mutation_proof '(3a) flag off still emits the tool' 'c3_off absent' 'no hook-log files' "$EMIT_REL" m_sub $'if flag_is hook_telemetry; then\n    if [ -f "$TPL/tools/hook-log.sh" ]; then' $'if true; then\n    if [ -f "$TPL/tools/hook-log.sh" ]; then'
par_block mutation_proof '(3b) flag false: the _memory/README.md block leaks into the render' 'c3_off false' 'no hook-log text anywhere' "$README_REL" m_block 'hooks/' unwrap
par_block mutation_proof '(3c) kit-guard-only cursor config gains the stop hooks' 'c3_kg_only absent' 'kit-guard cursor bytes' "$EMIT_REL" m_sub 'put_emit ".cursor/hooks.json" "$(cursor_hooks_json_kit_guard)"' 'put_emit ".cursor/hooks.json" "$(cursor_hooks_json_hooks)"'
par_block mutation_proof '(4a) drop the claude merge warning' 'c4_existing claude' 'merge warning once' "$EMIT_REL" m_sub "record_warn_line 'warning: .claude/settings.json exists without the hook-telemetry hooks" ": 'warning: .claude/settings.json exists without the hook-telemetry hooks"
par_block mutation_proof '(4b) drop the cursor merge warning' 'c4_existing cursor' 'merge warning once' "$EMIT_REL" m_sub "record_warn_line 'warning: .cursor/hooks.json exists without the hook-telemetry hooks" ": 'warning: .cursor/hooks.json exists without the hook-telemetry hooks"
par_block mutation_proof '(5a) drop the claude removal warning' 'c5_stale claude' 'removal warning once' "$EMIT_REL" m_sub 'record_warn_line "warning: .claude/settings.json still references _kit/hook-log.sh' ': "warning: .claude/settings.json still references _kit/hook-log.sh'
par_block mutation_proof '(5b) drop the cursor removal warning' 'c5_stale cursor' 'removal warning once' "$EMIT_REL" m_sub 'record_warn_line "warning: .cursor/hooks.json still references _kit/hook-log.sh' ': "warning: .cursor/hooks.json still references _kit/hook-log.sh'
par_block mutation_proof '(6) drop the spawn-depth message' c6_spawn_depth 'spawn-depth message once' "$EMIT_REL" m_sub "printf 'emit: .claude/settings.json present without" ": 'emit: .claude/settings.json present without"
par_block mutation_proof '(6) print the spawn-depth message twice' c6_spawn_depth 'spawn-depth message once' "$EMIT_REL" m_sub "printf 'emit: .claude/settings.json present without" "printf 'emit: .claude/settings.json present without CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH — left untouched\n' >&2; printf 'emit: .claude/settings.json present without"
par_block mutation_proof '(7a) accept a non-boolean hook_telemetry' c7_validation 'validation rc 3' "$EMIT_REL" m_sub 'add_problem "flags.hook_telemetry must be a boolean"' ': "flags.hook_telemetry must be a boolean"'
par_block mutation_proof '(8a) drop the ORCHESTRATION note block' c8_orch_on 'orch note present' "$ORCH_REL" m_block 'With hook telemetry on' drop
par_block mutation_proof '(8b) ORCHESTRATION note rendered unconditionally' 'c8_orch_off absent' 'note absent' "$ORCH_REL" m_block 'With hook telemetry on' unwrap
par_block mutation_proof '(8c) ORCHESTRATION tree line rendered unconditionally' 'c8_orch_off absent' 'tree line absent' "$ORCH_REL" m_block 'Single-copy tools: stop/subagent-stop' unwrap
par_block mutation_proof '(8e) drop the _memory/README.md block' c8_readme_on 'readme line once' "$README_REL" m_block 'hooks/' drop
par_block mutation_proof '(8f) _memory/README.md block rendered unconditionally' 'c8_readme_off absent' 'readme flag off line absent' "$README_REL" m_block 'hooks/' unwrap
par_block mutation_proof '(9) drop the test -f guard from the Claude Code command' c9_fresh_clone_guard 'no-script stderr empty' "$EMIT_REL" m_sub 'test -f \"$CLAUDE_PROJECT_DIR/_kit/hook-log.sh\" && ' ''
par_block mutation_proof '(9) drop the || true from the Claude Code command' c9_fresh_clone_guard 'no-script exit 0' "$EMIT_REL" m_sub 'hook claude || true' 'hook claude'
par_block mutation_proof '(10) emitted cursor hook prints nothing' c10_emitted_hook_e2e 'cursor stdout {}' "$TOOL_REL" m_sub "= 'cursor' ]; then" "= 'cursorX' ]; then"
par_block mutation_proof '(10) emitted tool logs to another directory' c10_emitted_hook_e2e 'one log line' "$TOOL_REL" m_sub "LOG_SUBDIR='_memory/work/hooks'" "LOG_SUBDIR='_memory/work/hooksX'"
par_block mutation_proof '(10) emitted summary changes its count line' c10_emitted_hook_e2e 'summary 1 events' "$TOOL_REL" m_sub 'hook-log: %d events (%s)' 'hook-log: %d evts (%s)'
par_finish

emit_cache_verify

echo
echo "=== hook-telemetry summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
