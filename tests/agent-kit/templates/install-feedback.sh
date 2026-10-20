#!/usr/bin/env bash
# Behavioral guard for agent-kit install-feedback: pre-existing emit paths, bootstrap
# ids, loop_worktree, memory-table IF guards, path-scoped routing prose, Codex append.
# Scratch roots only (fixture-root.sh); no network.
set -u

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akif.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"

. "$HERE/../lib/emit-cache.sh"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="${EMIT_KIT:-$REPO_ROOT/skills/agent-kit}"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

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

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

EVALUATOR='.claude/agents/evaluator.md'
BLOCKED_NEW="emit: blocked $EVALUATOR (exists; not written by a previous emit)"
WARN_ALT_LIGHT='emit: warning: models.claude-code.alt_family equals light; fix cycle 2 would not rotate models'
ORCH_PHRASE='Path-scoped rule files listed here are not guaranteed to load in subagents'
FEATURE_PHRASE='matching path-scoped rules'
MODEL_MAP_PHRASE='Same-family rotation'

answers_base() { # outfile
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

check_a() {
  local root before ans
  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/.claude/agents"
  printf '# user evaluator\n' > "$root/$EVALUATOR"
  before="$(sha256_file "$root/$EVALUATOR")"
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans" --dry-run
  grep -qxF "blocked $EVALUATOR" "$EMIT_STDOUT" || return 1
  [[ "$EMIT_RC" -eq 4 ]] || return 1
  capture_emit_sh "$root" --answers "$ans"
  grep -qxF "$BLOCKED_NEW" "$EMIT_STDERR" || return 1
  [[ "$EMIT_RC" -eq 4 ]] || return 1
  [[ "$(sha256_file "$root/$EVALUATOR")" == "$before" ]]
}

check_b() {
  local root before after ans
  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/.claude/agents"
  printf '# user evaluator\n' > "$root/$EVALUATOR"
  before="$(sha256_file "$root/$EVALUATOR")"
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans" --force
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  after="$(sha256_file "$root/$EVALUATOR")"
  [[ "$before" != "$after" ]]
}

check_c() {
  local root1 root2 ans
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  alloc_root; root1="$ALLOC_PATH"
  emit_cache_copy "$root1" "$ans" || return 1
  alloc_root; root2="$ALLOC_PATH"
  mkdir -p "$root2/.claude/agents"
  cp "$root1/$EVALUATOR" "$root2/$EVALUATOR"
  capture_emit_sh "$root2" --answers "$ans"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  ! grep -qF 'emit: blocked' "$EMIT_STDERR"
}

check_d() {
  local root target want_line ans
  target='.claude/agents/implementer.md'
  want_line="emit: blocked $target"
  alloc_root; root="$ALLOC_PATH"
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  printf '\nUSER_EDIT\n' >> "$root/$target"
  capture_emit_sh "$root" --upgrade
  [[ "$EMIT_RC" -eq 4 ]] || return 1
  grep -qxF "$want_line" "$EMIT_STDERR" || return 1
  ! grep -qF '(exists; not written' "$EMIT_STDERR"
}

check_e() {
  local root target mf want_line ans
  target='.claude/agents/implementer.md'
  want_line="emit: blocked $target (exists; not written by a previous emit)"
  alloc_root; root="$ALLOC_PATH"
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  mf="$root/orchestration-kit.manifest.json"
  printf '\nLOST_MANIFEST\n' >> "$root/$target"
  jq --arg p "$target" 'del(.files[$p])' "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
  capture_emit_sh "$root" --upgrade
  [[ "$EMIT_RC" -eq 4 ]] || return 1
  grep -qxF "$want_line" "$EMIT_STDERR" || return 1
}

check_f() {
  local root ans
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  jq '.models["claude-code"].alt_family = .models["claude-code"].light' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root; root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  grep -qxF "$WARN_ALT_LIGHT" "$EMIT_STDERR" || return 1
  jq '.models["claude-code"].alt_family = "claude-opus-5-5"' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root; root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  ! grep -qF 'alt_family equals light' "$EMIT_STDERR"
}

check_g() {
  local root ans mf want_line='emit: flags.loop_worktree must be a boolean'
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  jq '.flags.loop_worktree = true' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  mf="$root/orchestration-kit.manifest.json"
  jq -e '.options.loop_worktree == true' "$mf" >/dev/null || return 1
  grep -qF "LOOP_WORKTREE_DEFAULT='1'" "$root/_loop/loop.sh" || return 1
  grep -qF 'WORKTREE="${LOOP_WORKTREE:-$LOOP_WORKTREE_DEFAULT}"' "$root/_loop/loop.sh" || return 1
  grep -qF "\$WorktreeRaw = '1'" "$root/_loop/loop.ps1" || return 1

  jq 'del(.flags.loop_worktree)' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  mf="$root/orchestration-kit.manifest.json"
  jq -e '(.options | has("loop_worktree")) | not' "$mf" >/dev/null || return 1
  grep -qF "LOOP_WORKTREE_DEFAULT='0'" "$root/_loop/loop.sh" || return 1
  grep -qF "\$WorktreeRaw = '0'" "$root/_loop/loop.ps1" || return 1

  jq '.flags.loop_worktree = "yes"' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root; root="$ALLOC_PATH"
  capture_emit_sh "$root" --answers "$ans"
  [[ "$EMIT_RC" -eq 3 ]] || return 1
  grep -qxF "$want_line" "$EMIT_STDERR" || return 1
}

check_h() {
  local root ans orch
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  jq '.flags.research = false | .flags.loop = false' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  orch="$root/.claude/ORCHESTRATION.md"
  grep -qF '| **Research** |' "$orch" && return 1
  grep -qF '| **Loop (manual)** |' "$orch" && return 1
  grep -qF '| **Loop (dispatched)** |' "$orch" && return 1

  jq '.flags.research = true | .flags.loop = true' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  orch="$root/.claude/ORCHESTRATION.md"
  grep -qF '| **Research** |' "$orch" || return 1
  grep -qF '| **Loop (manual)** |' "$orch" || return 1
  grep -qF '| **Loop (dispatched)** |' "$orch" || return 1
}

check_i() {
  local root ans
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  emit_cache_copy "$root" "$ans" || return 1
  grep -qF "$ORCH_PHRASE" "$root/.claude/ORCHESTRATION.md" || return 1
  grep -qF "$FEATURE_PHRASE" "$root/.claude/skills/feature/SKILL.md" || return 1
  grep -qF "$MODEL_MAP_PHRASE" "$root/.claude/skills/agent-kit-models.map.md" || return 1
}

check_j() {
  local ans ans2 root out rc
  alloc_path ansfile
  answers_base "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  jq 'del(.bootstrap["existing-agents"])' "$ans" > "${ans}.tmp" && mv "${ans}.tmp" "$ans"
  alloc_root; root="$ALLOC_PATH"
  out="$(run_emit_sh "$root" --check-answers --answers "$ans" 2>/dev/null)"; rc=$?
  [[ "$rc" -eq 3 ]] || return 1
  grep -qF $'existing-agents\t' <<<"$out" || return 1
  alloc_path ansfile2
  answers_base "$ALLOC_PATH"
  ans2="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  out="$(run_emit_sh "$root" --check-answers --answers "$ans2" 2>/dev/null)"; rc=$?
  [[ "$rc" -eq 0 && -z "$out" ]] || return 1
}

check_k() {
  local root ans prefix cf
  prefix='# user codex config
model = "gpt-test"
'
  alloc_path ansfile
  jq '
    .harnesses = ["codex"] |
    .primary = "codex" |
    del(.models["claude-code"]) |
    del(.models.cursor) |
    .models.codex = {
      "frontier": "cod-front", "light": "cod-light", "fast": "cod-fast-id",
      "alt_family": "cod-alt", "frontier_alt_family": "cod-front", "loop_chain": "cod-light"
    }
  ' "$FIXTURE" > "$ALLOC_PATH"
  ans="$ALLOC_PATH"
  alloc_root; root="$ALLOC_PATH"
  mkdir -p "$root/.codex"
  cf="$root/.codex/config.toml"
  printf '%s' "$prefix" > "$cf"
  capture_emit_sh "$root" --answers "$ans"
  cf="$root/.codex/config.toml"
  [[ "$EMIT_RC" -eq 0 ]] || return 1
  ! grep -qF 'emit: blocked' "$EMIT_STDERR" || return 1
  grep -qF '# orchestration-kit:agents' "$cf" || return 1
  head -c "${#prefix}" "$cf" | diff -q - <(printf '%s' "$prefix") >/dev/null || return 1
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

run_check a check_a 'first install differing evaluator: dry-run blocked, exit 4, stderr new-class, bytes unchanged'
run_check b check_b 'first install differing evaluator: --force exit 0, file replaced'
run_check c check_c 'pre-existing byte-identical kit path: exit 0, not blocked'
run_check d check_d 'upgrade hand-edited manifest path: plain blocked line, exit 4'
run_check e check_e 'upgrade path dropped from manifest with differing bytes: new-class line, exit 4'
run_check f check_f 'alt_family equals light warns; frontier alt_family silent'
run_check g check_g 'flags.loop_worktree manifest, loop drivers, boolean validation'
run_check h check_h 'research/loop false omits memory rows; true includes all three'
run_check i check_i 'ORCHESTRATION path-scoped sentence, feature rules phrase, model map rotation'
run_check j check_j '--check-answers lists existing-agents when missing, not when ""'
run_check k check_k 'Codex pre-existing config.toml append without block'

emit_cache_verify

echo
echo "=== install-feedback summary ==="
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if ((fail)); then
  echo "RESULT: $fail assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
