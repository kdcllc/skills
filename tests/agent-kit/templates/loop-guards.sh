#!/usr/bin/env bash
# Behavioral tests for loop driver guards (ledger, timeout, budgets, tamper, lint).
# Stub CLIs only; sandboxes under mktemp. Discovered by tests/agent-kit/run-all.sh.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/loopguards.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
source "$HERE/../lib/fixture-root.sh"

DRIVER_SRC="${LOOP_GUARDS_DRIVER:-$REPO_ROOT/_loop/loop.sh}"
BREAKER_SRC="$REPO_ROOT/_loop/breaker.sh"
PROMPT_SRC="$REPO_ROOT/_loop/PROMPT.md"
TEMPLATE_LOOP_PS1="$REPO_ROOT/skills/agent-kit/templates/loop/loop.ps1"
TEMPLATE_BREAKER_PS1="$REPO_ROOT/skills/agent-kit/templates/loop/breaker.ps1"
EMIT_SH="$REPO_ROOT/skills/agent-kit/bin/emit.sh"
SELF_ANSWERS="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"
KIT="$REPO_ROOT/skills/agent-kit"

SUITE_START=$SECONDS
export LG_STUB_PIDFILE="$FIXTURE_TMPDIR/stub.pids"
pass=0
fail=0
skip=0

trap '_lg_cleanup' EXIT

_lg_cleanup() {
  [[ -f "$LG_STUB_PIDFILE" ]] && while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$LG_STUB_PIDFILE"
  rm -rf "$FIXTURE_TMPDIR"
}

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); echo "PASS: $2" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $2${3:+ -- $3}" ;;
    *)
      fail=$((fail + 1))
      echo "FAIL: $2${3:+ -- $3}" >&2
      ;;
  esac
}

finish_suite() {
  local elapsed=$((SECONDS - SUITE_START))
  echo
  echo "=== loop-guards summary ==="
  echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
  echo "runtime: ${elapsed}s"
  if ((fail)); then
    echo "RESULT: $fail case(s) FAILED"
    return 1
  fi
  echo "RESULT: all cases passed"
  return 0
}

sandbox_git() {
  assert_fixture_root "$1" || return 1
  git -C "$1" "${@:2}"
}

_lg_require_tools() {
  LG_HAVE_JQ=0
  LG_HAVE_TIMEOUT=0
  LG_TIMEOUT_BIN=""
  command -v jq >/dev/null 2>&1 && LG_HAVE_JQ=1
  if command -v timeout >/dev/null 2>&1; then
    LG_HAVE_TIMEOUT=1
    LG_TIMEOUT_BIN="$(command -v timeout)"
  elif command -v gtimeout >/dev/null 2>&1; then
    LG_HAVE_TIMEOUT=1
    LG_TIMEOUT_BIN="$(command -v gtimeout)"
  fi
}

_lg_copy_driver() {
  local dest="$1"
  mkdir -p "$dest/_loop"
  cp "$DRIVER_SRC" "$dest/_loop/loop.sh"
  cp "$BREAKER_SRC" "$dest/_loop/breaker.sh"
  cp "$PROMPT_SRC" "$dest/_loop/PROMPT.md"
  chmod +x "$dest/_loop/loop.sh" "$dest/_loop/breaker.sh"
}

_lg_story_ac() {
  local n="$1" prio="$2" writes="${3:-src/foo.txt}"
  printf '\n## STORY-1%02d: fixture story %d\n\n' "$n" "$n"
  printf '**Acceptance criteria**\n- [ ] done\n\n'
  printf -- '- priority: %s\n- passes: false\n- attempts: 0\n- blocked: false\n' "$prio"
  printf -- '- writes: %s\n' "$writes"
}

lg_make_sandbox() { # dest ide track_loop track_ide [n_stories]
  local dest="$1" ide="$2" track_loop="$3" track_ide="$4" n="${5:-1}" i
  rm -rf "$dest"
  mkdir -p "$dest"
  assert_fixture_root "$dest" || return 1
  _lg_copy_driver "$dest"
  (
    cd "$dest"
    git init -q
    git config user.email test@example.com
    git config user.name "loop-guards"
    mkdir -p _memory/loop "$ide"
    {
      printf '# backlog\n'
      i=1
      while (( i <= n )); do
        _lg_story_ac "$i" "$i" "src/story${i}.txt"
        i=$((i + 1))
      done
    } > _memory/loop/backlog.md
    printf 'placeholder\n' > "$ide/.keep"
    touch orchestration-kit.manifest.json .gitattributes
    : > .gitignore
    if [[ "$track_loop" != "1" ]]; then printf '_memory/loop/\n' >> .gitignore; fi
    if [[ "$track_ide" != "1" ]]; then printf '%s/\n' "$ide" >> .gitignore; fi
    git add -A
    git commit -qm init
  )
}

_lg_write_stub() {
  local path="$1"
  assert_fixture_root "$(dirname "$path")" || return 1
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
set -u
trap 'exit 130' INT
if [[ -n "${LG_STUB_ARGV:-}" ]]; then
  printf '%s\n' "$*" >> "$LG_STUB_ARGV"
fi
emit_json() {
  local story="${1:-STORY-101}" verdict="${2:-passed}" tin="${3:-100}" tout="${4:-50}" cost="${5:-0.01}"
  printf '{"type":"result","result":"ITERATION: %s %s (attempt 1/3)","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"total_cost_usd":%s}\n' \
    "$story" "$verdict" "$tin" "$tout" "$cost"
}
pick_story() {
  local body="${@: -1}" s
  s="$(grep -oE 'STORY-[0-9]+' <<< "$body" | head -1)"
  printf '%s' "${s:-${LG_STUB_STORY:-STORY-101}}"
}
case "$LG_STUB_MODE" in
  pass)
    echo x > progress.txt
    git add progress.txt 2>/dev/null || true
    git commit -qm progress 2>/dev/null || true
    eval "${LG_STUB_BODY:-}" || { echo "stub body failed" >&2; exit 3; }
    emit_json "$(pick_story "$@")" "${LG_STUB_VERDICT:-passed}" "${LG_STUB_TIN:-100}" "${LG_STUB_TOUT:-50}" "${LG_STUB_COST:-0.01}"
    exit 0 ;;
  fail)
    echo x > progress.txt && git add progress.txt && git commit -qm progress
    emit_json "$(pick_story "$@")" failed "${LG_STUB_TIN:-100}" "${LG_STUB_TOUT:-50}" "${LG_STUB_COST:-0.01}"
    exit 0 ;;
  sleep)
    sleep "${LG_STUB_SLEEP:-20}" & printf '%s\n' "$!" >> "${LG_STUB_PIDFILE:-/dev/null}"; wait "$!"
    exit 130 ;;
  cb0)
    echo tamper >> _loop/PROMPT.md
    git add _loop/PROMPT.md && git commit -qm cb0
    emit_json STORY-101 passed
    exit 0 ;;
  exit1)
    echo x > progress.txt && git add progress.txt && git commit -qm p
    emit_json STORY-101 failed
    exit 1 ;;
  no_usage)
    echo x > progress.txt && git add progress.txt && git commit -qm p
    echo "ITERATION: $(pick_story "$@") passed (attempt 1/3)"
    exit 0 ;;
  rate1)
    sleep "${LG_STUB_SLEEP:-3}"
    echo 'rate limit exceeded'
    emit_json STORY-101 failed
    exit 1 ;;
  ffonly)
    echo slot > slot-progress.txt
    git add slot-progress.txt && git commit -qm "slot-side commit (never integrated)"
    echo "conflict from main" > "${LG_MAIN_REPO}/slot-progress.txt"
    git -C "${LG_MAIN_REPO}" add slot-progress.txt
    git -C "${LG_MAIN_REPO}" commit -qm "external main-tree commit (concurrent, conflicting)"
    emit_json STORY-101 passed
    exit 0 ;;
  *)
    echo "unknown stub mode ${LG_STUB_MODE}" >&2
    exit 2 ;;
esac
STUB
  chmod +x "$path"
}

_lg_run_loop() { # dest max_iter env...
  local dest="$1" max_iter="$2"
  shift 2
  lg_out="$(mktemp)"
  lg_err="$(mktemp)"
  ( cd "$dest" && env "$@" bash ./_loop/loop.sh "$max_iter" ) >"$lg_out" 2>"$lg_err"
  lg_rc=$?
}

LEDGER_KEYS=(schema run_id ts_start ts_end slot story attempt format model exit_status outcome rate_limited
  "gen_ai.usage.input_tokens" "gen_ai.usage.output_tokens" cache_read_tokens cache_write_tokens
  cost_usd cost_source diff_files diff_lines tamper tamper_reasons)

_lg_checksum_tree() {
  find "$1" -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}'
}

_lg_timeout_log_shim() {
  local log="$1" real="$2"
  mkdir -p "$(dirname "$log")"
  cat > "$log.sh" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$log"
exec "$real" "\$@"
SH
  chmod +x "$log.sh"
  printf '%s' "$log.sh"
}

_lg_timeout_passthrough_shim() {
  local log="$1" shim="$2"
  cat > "$shim" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$log"
while (( \$# )); do
  case "\$1" in
    -s|-k) shift 2 ;;
    [0-9]*) shift ;;
    *) break ;;
  esac
done
exec "\$@"
SH
  chmod +x "$shim"
}

_lg_run_lint() {
  local dest="$1" bl="${2:-_memory/loop/backlog.md}"
  lg_out="$(mktemp)"
  lg_err="$(mktemp)"
  ( cd "$dest" && bash ./_loop/loop.sh --lint "$bl" ) >"$lg_out" 2>"$lg_err"
  lg_rc=$?
}

_lg_assert_setup_fail() {
  local label="$1" expect="$2"
  shift 2
  local dir="$FIXTURE_TMPDIR/sf-$RANDOM" argv="$FIXTURE_TMPDIR/sf-argv-$RANDOM"
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 6: invalid knobs" "sandbox setup"; return 1; }
  _lg_write_stub "$dir/_loop/stub.sh"
  : > "$argv"
  _lg_run_loop "$dir" 1 LG_STUB_ARGV="$argv" LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh" "$@"
  [[ "$lg_rc" -eq 5 ]] || { report FAIL "case 6: invalid knobs" "$label rc=$lg_rc"; return 1; }
  [[ ! -s "$argv" ]] || { report FAIL "case 6: invalid knobs" "$label argv"; return 1; }
  grep -qF "!!! $expect" "$lg_err" || { report FAIL "case 6: invalid knobs" "$label msg"; return 1; }
  grep -cF '!!!' "$lg_err" | grep -qxF 1 || { report FAIL "case 6: invalid knobs" "$label bang count"; return 1; }
  return 0
}

_lg_tamper_run() {
  local dest="$1" body="$2" mode="${3:-warn}" wt="${4:-0}"
  local -a extra=()
  (( wt )) && extra+=(LOOP_WORKTREE=1)
  _lg_run_loop "$dest" 1 LOOP_USAGE_FORMAT=claude LOOP_TAMPER_CHECK="$mode" \
    LG_STUB_MODE=pass LG_STUB_BODY="$body" LOOP_CLI="$dest/_loop/stub.sh" \
    ${extra[@]+"${extra[@]}"}
}

_lg_tamper_seed() {
  local dir="$1"
  mkdir -p "$dir/tests" "$dir/a" "$dir/lib"
  printf 'def test_x():\n    assert 1\n' > "$dir/tests/test_a.py"
  printf 'def test_z():\n    assert 1\n' > "$dir/tests/test_z.py"
  printf 'x\n' > "$dir/a/x.js"
  printf 'it("x", function(){ it.skip("s"); });\n' > "$dir/tests/test_skip.js"
  git -C "$dir" add tests a && git -C "$dir" commit -qm seed-tests || return 1
}

_lg_expect_tamper_warn() {
  local dir="$1" reason_pat="$2"
  grep -qF '!!! tamper (warn)' "$lg_err" || return 1
  jq -e --arg p "$reason_pat" '.tamper=="warn" and (.tamper_reasons|test($p))' \
    <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null || return 1
}

_lg_write_lint_backlog() {
  local path="$1"
  assert_fixture_root "$(dirname "$path")" || return 1
  cat > "$path"
}

_lg_lint_expect() {
  local dest="$1" bl_rel="$2" want_rc="$3" pat="${4:-}"
  _lg_run_lint "$dest" "$bl_rel"
  [[ "$lg_rc" -eq "$want_rc" ]] || return 1
  local kind=error
  (( want_rc == 0 )) && kind=warn
  [[ -z "$pat" ]] || grep -E "^lint: $kind [^ ]+ : " "$lg_out" | grep -qF "$pat" || return 1
  return 0
}

_lg_ps1_knobs_only_in_comments() {
  local f="$1"
  awk '/^[[:space:]]*#/ {next} /^\s*#/ {next} {print}' "$f" \
    | grep -qE 'LOOP_LEDGER|LOOP_ITER_TIMEOUT|LOOP_TAMPER_CHECK' && return 1
  return 0
}

[[ -f "$DRIVER_SRC" && -f "$BREAKER_SRC" && -f "$PROMPT_SRC" ]] || {
  report FAIL "precheck: driver" "missing $DRIVER_SRC (run scripts/agent-kit/self-install.sh)"
  finish_suite
  exit 1
}

_lg_require_tools

# ===========================================================================
# Case 1: Ledger
# ===========================================================================
case_1_ledger() {
  (( LG_HAVE_JQ )) || { report SKIP "case 1: ledger" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c1" line rc_off
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 1: ledger" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  local ledger="$dir/_memory/loop/ledger.jsonl"
  if [[ "$lg_rc" -ne 0 || ! -f "$ledger" ]]; then
    report FAIL "case 1: ledger" "pass rc=$lg_rc"
    return
  fi
  line="$(head -1 "$ledger")"
  jq -e . <<< "$line" >/dev/null 2>&1 || { report FAIL "case 1: ledger" "json"; return; }
  jq -e '[keys_unsorted[]] == $ARGS.positional' --args "${LEDGER_KEYS[@]}" <<< "$line" >/dev/null || { report FAIL "case 1: ledger" "keys"; return; }
  [[ "$(wc -l < "$ledger" | tr -d ' ')" -eq 1 ]] && jq -e . "$ledger" >/dev/null || { report FAIL "case 1: ledger" "one valid line per reap"; return; }
  jq -e '.outcome == "passed"' <<< "$line" >/dev/null || { report FAIL "case 1: ledger" "passed"; return; }

  assert_fixture_root "$dir" || { report FAIL "case 1: ledger" "fixture root"; return; }
  sed -i 's/- passes: true/- passes: false/' "$dir/_memory/loop/backlog.md"
  _lg_run_loop "$dir" 1 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=fail LOOP_CLI="$dir/_loop/stub.sh"
  jq -e '.outcome == "failed"' <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null 2>&1 || { report FAIL "case 1: ledger" "failed"; return; }
  [[ "$(wc -l < "$dir/_memory/loop/ledger.jsonl" | tr -d ' ')" -eq 2 ]] && jq -e . "$dir/_memory/loop/ledger.jsonl" >/dev/null || { report FAIL "case 1: ledger" "one line per failed reap"; return; }
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 1: ledger" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_USAGE_FORMAT=claude LOOP_LEDGER=off LG_STUB_MODE=fail LOOP_CLI="$dir/_loop/stub.sh"
  [[ ! -f "$dir/_memory/loop/ledger.jsonl" ]] || { report FAIL "case 1: ledger" "off"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 1: ledger" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  assert_fixture_root "$dir" || { report FAIL "case 1: ledger" "fixture root"; return; }
  mkdir -p "$dir/custom"
  _lg_run_loop "$dir" 1 LOOP_USAGE_FORMAT=claude LOOP_LEDGER="$dir/custom/ledger.jsonl" LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  [[ -f "$dir/custom/ledger.jsonl" ]] || { report FAIL "case 1: ledger" "custom"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 1: ledger" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 0 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  [[ ! -f "$dir/_memory/loop/ledger.jsonl" ]] || { report FAIL "case 1: ledger" "zero"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 1: ledger" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_USAGE_FORMAT=claude LOOP_LEDGER=off LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  rc_off=$lg_rc
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 1: ledger" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_USAGE_FORMAT=claude LOOP_LEDGER=/dev/null/x.jsonl LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  grep -qF '!!! ledger write failed:' "$lg_err" || { report FAIL "case 1: ledger" "warn"; return; }
  grep -cF '!!! ledger write failed:' "$lg_err" | grep -qxF 1 || { report FAIL "case 1: ledger" "warn count"; return; }
  [[ "$rc_off" -eq "$lg_rc" ]] || { report FAIL "case 1: ledger" "rc"; return; }
  report PASS "case 1: ledger"
}

case_2_cb0() {
  (( LG_HAVE_JQ )) || { report SKIP "case 2: CB0" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c2"
  lg_make_sandbox "$dir" ".claude" 1 1 || { report FAIL "case 2: CB0" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_WORKTREE=1 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=cb0 LOOP_CLI="$dir/_loop/stub.sh"
  [[ "$lg_rc" -eq 4 ]] || { report FAIL "case 2: CB0" "rc=$lg_rc"; return; }
  grep -qF '=== loop run summary' "$lg_err" || { report FAIL "case 2: CB0" "summary"; return; }
  jq -e '.outcome=="protected" and (.diff_files|type=="number") and (.diff_files == (.diff_files|floor))' <<< "$(head -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null \
    || { report FAIL "case 2: CB0" "ledger"; return; }
  report PASS "case 2: CB0"
}

case_3_killed() {
  (( LG_HAVE_JQ )) || { report SKIP "case 3: killed" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c3" sleep_stub="$FIXTURE_TMPDIR/c3-sleep.sh"
  lg_make_sandbox "$dir" ".claude" 1 1 2 || { report FAIL "case 3: killed" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub-cb0.sh"
  _lg_write_stub "$sleep_stub"
  assert_fixture_root "$dir" || { report FAIL "case 3: killed" "fixture root"; return; }
  cat > "$dir/_loop/stub-route.sh" <<'DUAL'
#!/usr/bin/env bash
p="${@: -1}"
if grep -qF 'STORY-101' <<< "$p"; then
  LG_STUB_MODE=cb0 exec "$LG_CB0_STUB" "$@"
fi
LG_STUB_MODE=sleep LG_STUB_SLEEP=20 exec "$LG_SLEEP_STUB" "$@"
DUAL
  chmod +x "$dir/_loop/stub-route.sh"
  _lg_run_loop "$dir" 2 LOOP_WORKTREE=1 LOOP_SLOTS=2 LOOP_USAGE_FORMAT=claude \
    LG_CB0_STUB="$dir/_loop/stub-cb0.sh" LG_SLEEP_STUB="$sleep_stub" \
    LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub-route.sh"
  cp "$lg_err" "$FIXTURE_TMPDIR/c3-summary.err"
  [[ "$lg_rc" -eq 4 ]] || { report FAIL "case 3: killed" "rc=$lg_rc"; return; }
  grep -c '"outcome":"killed"' "$dir/_memory/loop/ledger.jsonl" | grep -qxF 1 \
    || { report FAIL "case 3: killed" "ledger count"; return; }
  jq -e 'select(.outcome=="killed") | .exit_status==null' "$dir/_memory/loop/ledger.jsonl" >/dev/null \
    || { report FAIL "case 3: killed" "ledger null"; return; }
  report PASS "case 3: killed"
}

case_4_summary() {
  (( LG_HAVE_JQ )) || { report SKIP "case 4: summary" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c4" sleep_stub="$FIXTURE_TMPDIR/c4-sleep.sh" killed_err
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 4: summary" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  grep -qF 'ledger:' "$lg_err" || { report FAIL "case 4: summary" "ledger line"; return; }
  grep -qF 'STORY-101 reaps=' "$lg_err" || { report FAIL "case 4: summary" "story line"; return; }
  grep -qF '=== loop run summary' "$lg_out" && { report FAIL "case 4: summary" "stdout summary"; return; }
  _lg_run_loop "$dir" 0 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  [[ -z "$(cat "$lg_err")" ]] || { report FAIL "case 4: summary" "zero stderr"; return; }
  lg_make_sandbox "$dir" ".claude" 1 1 2 || { report FAIL "case 4: summary" "killed sandbox"; return; }
  _lg_write_stub "$dir/_loop/stub-cb0.sh"
  _lg_write_stub "$sleep_stub"
  assert_fixture_root "$dir" || { report FAIL "case 4: summary" "fixture root"; return; }
  cat > "$dir/_loop/stub-route.sh" <<'DUAL'
#!/usr/bin/env bash
p="${@: -1}"
if grep -qF 'STORY-101' <<< "$p"; then
  LG_STUB_MODE=cb0 exec "$LG_CB0_STUB" "$@"
fi
LG_STUB_MODE=sleep LG_STUB_SLEEP=20 exec "$LG_SLEEP_STUB" "$@"
DUAL
  chmod +x "$dir/_loop/stub-route.sh"
  killed_err="$(mktemp)"
  ( cd "$dir" && env LOOP_WORKTREE=1 LOOP_SLOTS=2 LOOP_USAGE_FORMAT=claude \
    LG_CB0_STUB="$dir/_loop/stub-cb0.sh" LG_SLEEP_STUB="$sleep_stub" \
    LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub-route.sh" bash ./_loop/loop.sh 2 ) >"$lg_out" 2>"$killed_err"
  grep -qF 'reaps=0 last=killed tokens=0 cost_usd=n/a' "$killed_err" \
    || { report FAIL "case 4: summary" "killed row"; return; }
  report PASS "case 4: summary"
}

case_5_timeout() {
  (( LG_HAVE_JQ )) || { report SKIP "case 5: timeout" "jq"; return; }
  (( LG_HAVE_TIMEOUT )) || { report SKIP "case 5: timeout" "timeout/gtimeout"; return; }
  local dir="$FIXTURE_TMPDIR/c5" shimd="$FIXTURE_TMPDIR/c5-shim" log="$FIXTURE_TMPDIR/c5-log"
  local pasdir="$FIXTURE_TMPDIR/c5-pas" paslog="$FIXTURE_TMPDIR/c5-paslog" passhim="$FIXTURE_TMPDIR/c5-pas-shim"
  mkdir -p "$shimd" && assert_fixture_root "$shimd"
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 5: timeout" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  cp "$(_lg_timeout_log_shim "$log" "$LG_TIMEOUT_BIN")" "$shimd/timeout"
  local t0=$SECONDS
  _lg_run_loop "$dir" 1 PATH="$shimd:$PATH" LOOP_ITER_TIMEOUT=2 LOOP_USAGE_FORMAT=claude \
    LG_STUB_MODE=sleep LG_STUB_SLEEP=300 LOOP_CLI="$dir/_loop/stub.sh"
  (( SECONDS - t0 <= 10 )) || { report FAIL "case 5: timeout" "reap slow"; return; }
  grep -qF 'iteration exceeded LOOP_ITER_TIMEOUT=2s' "$lg_err" || { report FAIL "case 5: timeout" "gnu msg"; return; }
  jq -e '.outcome=="timeout"' <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null \
    || { report FAIL "case 5: timeout" "gnu ledger"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 5: timeout" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  : > "$log"
  cp "$(_lg_timeout_log_shim "$log" "$LG_TIMEOUT_BIN")" "$shimd/timeout"
  _lg_run_loop "$dir" 1 PATH="$shimd:$PATH" LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  [[ -s "$log" ]] && { report FAIL "case 5: timeout" "unset shim log"; return; }

  mkdir -p "$pasdir" && assert_fixture_root "$pasdir"
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 5: timeout" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_timeout_passthrough_shim "$paslog" "$passhim"
  cp "$passhim" "$pasdir/timeout"
  _lg_run_loop "$dir" 1 PATH="$pasdir:$PATH" LOOP_ITER_TIMEOUT=2 LOOP_USAGE_FORMAT=claude \
    LG_STUB_MODE=sleep LG_STUB_SLEEP=3 LOOP_CLI="$dir/_loop/stub.sh"
  jq -e '.outcome=="timeout"' <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null \
    || { report FAIL "case 5: timeout" "passthrough ledger"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 5: timeout" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 PATH="$pasdir:$PATH" LOOP_ITER_TIMEOUT=2 LOOP_USAGE_FORMAT=claude \
    LG_STUB_MODE=exit1 LOOP_CLI="$dir/_loop/stub.sh"
  jq -e '.outcome!="timeout"' <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null \
    || { report FAIL "case 5: timeout" "exit1 not timeout"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 5: timeout" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 PATH="$pasdir:$PATH" LOOP_ITER_TIMEOUT=2 LOOP_USAGE_FORMAT=claude \
    LG_STUB_MODE=rate1 LG_STUB_SLEEP=3 LOOP_CLI="$dir/_loop/stub.sh"
  jq -e '.outcome!="timeout" and .rate_limited==true' <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null \
    || { report FAIL "case 5: timeout" "rate not timeout"; return; }
  report PASS "case 5: timeout"
}

case_6_invalid_knobs() {
  _lg_assert_setup_fail "iter-timeout" "invalid LOOP_ITER_TIMEOUT='abc'" LOOP_ITER_TIMEOUT=abc || return
  _lg_assert_setup_fail "run-budget-usd" "invalid LOOP_RUN_BUDGET_USD='0'" LOOP_RUN_BUDGET_USD=0 || return
  _lg_assert_setup_fail "tamper-maybe" "invalid LOOP_TAMPER_CHECK='maybe'" LOOP_TAMPER_CHECK=maybe || return
  _lg_assert_setup_fail "tamper-fail-wt0" "LOOP_TAMPER_CHECK=fail requires LOOP_WORKTREE=1" \
    LOOP_TAMPER_CHECK=fail LOOP_WORKTREE=0 || return
  local dir="$FIXTURE_TMPDIR/c6" argv="$FIXTURE_TMPDIR/c6-argv" shimd="$FIXTURE_TMPDIR/c6-shim"
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 6: invalid knobs" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  mkdir -p "$shimd" && assert_fixture_root "$shimd"
  printf '#!/bin/sh\nexit 1\n' > "$shimd/timeout" && chmod +x "$shimd/timeout"
  : > "$argv"
  _lg_run_loop "$dir" 1 PATH="$shimd:$PATH" LOOP_ITER_TIMEOUT=2 LG_STUB_ARGV="$argv" LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  [[ "$lg_rc" -eq 5 && ! -s "$argv" ]] || { report FAIL "case 6: invalid knobs" "probe rc=$lg_rc"; return; }
  grep -qF 'does not support -s/-k' "$lg_err" || { report FAIL "case 6: invalid knobs" "timeout probe"; return; }
  grep -cF '!!!' "$lg_err" | grep -qxF 1 || { report FAIL "case 6: invalid knobs" "probe bang"; return; }
  report PASS "case 6: invalid knobs"
}

case_7_run_budget_tokens() {
  (( LG_HAVE_JQ )) || { report SKIP "case 7: run budget tokens" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c7"
  lg_make_sandbox "$dir" ".claude" 0 1 3 || { report FAIL "case 7: run budget tokens" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 3 LOOP_WORKTREE=0 LOOP_SLOTS=1 LOOP_RUN_BUDGET_TOKENS=150 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LG_STUB_TIN=200 LOOP_CLI="$dir/_loop/stub.sh"
  grep -qF '!!! run budget reached' "$lg_err" || { report FAIL "case 7: run budget tokens" "bang msg"; return; }
  grep -qF '=== run budget reached -- exiting ===' "$lg_out" || { report FAIL "case 7: run budget tokens" "banner"; return; }
  [[ "$lg_rc" -eq 1 ]] || { report FAIL "case 7: run budget tokens" "rc"; return; }
  [[ "$(wc -l < "$dir/_memory/loop/ledger.jsonl" | tr -d ' ')" -eq 1 ]] || { report FAIL "case 7: run budget tokens" "dispatches"; return; }
  awk '/^## STORY-102:/{f=1;next} /^## /{f=0} f&&/^- attempts:/{print $3}' "$dir/_memory/loop/backlog.md" | grep -qxF 0 || { report FAIL "case 7: run budget tokens" "attempts"; return; }
  lg_make_sandbox "$dir" ".claude" 0 1 3 || { report FAIL "case 7: run budget tokens" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 3 LOOP_WORKTREE=0 LOOP_SLOTS=1 LOOP_RUN_BUDGET_TOKENS=150 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LG_STUB_TIN=100 LG_STUB_TOUT=50 LOOP_CLI="$dir/_loop/stub.sh"
  [[ "$lg_rc" -eq 1 && "$(wc -l < "$dir/_memory/loop/ledger.jsonl" | tr -d ' ')" -eq 1 ]] || { report FAIL "case 7: run budget tokens" "boundary =="; return; }
  report PASS "case 7: run budget tokens"
}

case_8_run_budget_drained() {
  (( LG_HAVE_JQ )) || { report SKIP "case 8: run budget drained" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c8"
  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 8: run budget drained" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_WORKTREE=0 LOOP_RUN_BUDGET_TOKENS=1 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LG_STUB_TIN=500 LOOP_CLI="$dir/_loop/stub.sh"
  [[ "$lg_rc" -eq 0 ]] || { report FAIL "case 8: run budget drained" "rc=$lg_rc"; return; }
  report PASS "case 8: run budget drained"
}

case_9_run_budget_usd() {
  (( LG_HAVE_JQ )) || { report SKIP "case 9: run budget usd" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c9"
  lg_make_sandbox "$dir" ".claude" 0 1 3 || { report FAIL "case 9: run budget usd" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 3 LOOP_WORKTREE=0 LOOP_SLOTS=1 LOOP_RUN_BUDGET_USD=0.1 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LG_STUB_COST=0.08 LOOP_CLI="$dir/_loop/stub.sh"
  [[ "$lg_rc" -eq 1 ]] || { report FAIL "case 9: run budget usd" "rc"; return; }
  grep -qF '!!! run budget reached' "$lg_err" || { report FAIL "case 9: run budget usd" "msg"; return; }
  [[ "$(wc -l < "$dir/_memory/loop/ledger.jsonl" | tr -d ' ')" -eq 2 ]] || { report FAIL "case 9: run budget usd" "dispatches"; return; }
  awk '/^## STORY-103:/{f=1;next} /^## /{f=0} f&&/^- attempts:/{print $3}' "$dir/_memory/loop/backlog.md" | grep -qxF 0 || { report FAIL "case 9: run budget usd" "attempts"; return; }
  lg_make_sandbox "$dir" ".claude" 0 1 3 || { report FAIL "case 9: run budget usd" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 3 LOOP_WORKTREE=0 LOOP_SLOTS=1 LOOP_RUN_BUDGET_USD=0.1 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LG_STUB_COST=0.05 LOOP_CLI="$dir/_loop/stub.sh"
  [[ "$lg_rc" -eq 1 && "$(wc -l < "$dir/_memory/loop/ledger.jsonl" | tr -d ' ')" -eq 2 ]] || { report FAIL "case 9: run budget usd" "boundary =="; return; }
  report PASS "case 9: run budget usd"
}

case_10_story_budget() {
  (( LG_HAVE_JQ )) || { report SKIP "case 10: story budget" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c10"
  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 10: story budget" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_STORY_BUDGET_TOKENS=50 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=fail LG_STUB_TIN=100 LG_STUB_TOUT=0 LOOP_CLI="$dir/_loop/stub.sh"
  grep -qF 'blocked: true' "$dir/_memory/loop/backlog.md" || { report FAIL "case 10: story budget" "blocked"; return; }
  grep -qF 'story budget reached' "$lg_err" || { report FAIL "case 10: story budget" "stderr"; return; }
  grep -qF -- '- reason: story budget reached' "$dir/_memory/loop/ESCALATIONS.md" || { report FAIL "case 10: story budget" "escalation"; return; }
  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 10: story budget" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 1 LOOP_STORY_BUDGET_TOKENS=50 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=pass LG_STUB_TIN=100 LG_STUB_TOUT=0 LOOP_CLI="$dir/_loop/stub.sh"
  grep -qF 'blocked: false' "$dir/_memory/loop/backlog.md" || { report FAIL "case 10: story budget" "pass blocked"; return; }
  report PASS "case 10: story budget"
}

case_11_fail_open() {
  (( LG_HAVE_JQ )) || { report SKIP "case 11: fail open" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c11"
  lg_make_sandbox "$dir" ".claude" 0 1 2 || { report FAIL "case 11: fail open" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_run_loop "$dir" 2 LOOP_RUN_BUDGET_TOKENS=10 LOOP_USAGE_FORMAT=claude LG_STUB_MODE=no_usage LOOP_CLI="$dir/_loop/stub.sh"
  grep -qF 'reported no usage' "$lg_err" || { report FAIL "case 11: fail open" "note"; return; }
  grep -cF 'reported no usage' "$lg_err" | grep -qxF 1 || { report FAIL "case 11: fail open" "count"; return; }
  [[ "$lg_rc" -eq 0 ]] || { report FAIL "case 11: fail open" "rc"; return; }
  report PASS "case 11: fail open"
}

case_12_claude_budget_flag() {
  (( LG_HAVE_JQ )) || { report SKIP "case 12: claude budget flag" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c12" argv="$FIXTURE_TMPDIR/c12-argv"
  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 12: claude budget flag" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  : > "$argv"
  _lg_run_loop "$dir" 1 LOOP_ITER_BUDGET_USD=0.5 LOOP_USAGE_FORMAT=claude LG_STUB_ARGV="$argv" LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  grep -qF -- '--max-budget-usd' "$argv" || { report FAIL "case 12: claude budget flag" "flag"; return; }
  : > "$argv"
  _lg_run_loop "$dir" 1 LOOP_ITER_BUDGET_USD=0.5 LOOP_USAGE_FORMAT=none LG_STUB_ARGV="$argv" LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  grep -cF 'note: LOOP_ITER_BUDGET_USD ignored' "$lg_err" | grep -qxF 1 || { report FAIL "case 12: claude budget flag" "note"; return; }
  grep -qF 'has no effect' "$lg_err" && { report FAIL "case 12: claude budget flag" "has-no-effect"; return; }
  grep -qF -- '--max-budget-usd' "$argv" && { report FAIL "case 12: claude budget flag" "flag present"; return; }
  report PASS "case 12: claude budget flag"
}

case_13_tamper() {
  (( LG_HAVE_JQ )) || { report SKIP "case 13: tamper signals" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c13"
  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'git rm -f tests/test_a.py && git commit -qm tamper' warn 0
  _lg_expect_tamper_warn "$dir" 'deleted:tests/test_a.py' \
    || { report FAIL "case 13: tamper signals" "delete"; return; }

  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'printf "\n    it.only(x);\n" >> tests/test_a.py && git add tests/test_a.py && git commit -qm only' warn 0
  _lg_expect_tamper_warn "$dir" 'skip-marker:tests/test_a.py' \
    || { report FAIL "case 13: tamper signals" "only"; return; }

  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'printf "\n@Disabled\n" >> tests/test_a.py && git add tests/test_a.py && git commit -qm dis' warn 0
  _lg_expect_tamper_warn "$dir" 'skip-marker:tests/test_a.py' \
    || { report FAIL "case 13: tamper signals" "disabled"; return; }

  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'sed -i "/assert 1/d" tests/test_a.py && git add tests/test_a.py && git commit -qm net' warn 0
  _lg_expect_tamper_warn "$dir" 'assertions-removed:tests/test_a.py:1' \
    || { report FAIL "case 13: tamper signals" "assertions"; return; }

  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'printf "def test_new():\n    assert 2\n" > tests/test_new.py && git add tests/test_new.py && git commit -qm new' warn 0
  [[ "$lg_rc" -ne 3 ]] || { report FAIL "case 13: tamper signals" "new stub rc"; return; }
  grep -qF 'stub body failed' "$lg_err" && { report FAIL "case 13: tamper signals" "new stub body"; return; }
  grep -qF '!!! tamper (warn)' "$lg_err" && { report FAIL "case 13: tamper signals" "new stderr"; return; }
  jq -e '.tamper=="none"' <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null \
    || { report FAIL "case 13: tamper signals" "new ledger"; return; }

  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'git mv tests/test_a.py tests/test_b.py && sed -i "/assert 1/d" tests/test_b.py && git add -A && git commit -qm mv' warn 0
  _lg_expect_tamper_warn "$dir" 'assertions-removed:tests/test_b.py:1' \
    || { report FAIL "case 13: tamper signals" "rename assert"; return; }

  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'git mv tests/test_a.py lib/a.py && git add -A && git commit -qm out' warn 0
  _lg_expect_tamper_warn "$dir" 'deleted:tests/test_a.py' \
    || { report FAIL "case 13: tamper signals" "rename lib"; return; }

  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'git mv a/x.js a/y.js && git rm -f tests/test_z.py && git commit -qm mix' warn 0
  _lg_expect_tamper_warn "$dir" 'deleted:tests/test_z.py' \
    || { report FAIL "case 13: tamper signals" "mixed"; return; }

  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 13: tamper signals" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'git mv tests/test_skip.js tests/test_renamed.js && git commit -qm pure' warn 0
  [[ "$lg_rc" -ne 3 ]] || { report FAIL "case 13: tamper signals" "skip rename stub rc"; return; }
  grep -qF 'stub body failed' "$lg_err" && { report FAIL "case 13: tamper signals" "skip rename stub body"; return; }
  grep -qF '!!! tamper (warn)' "$lg_err" && { report FAIL "case 13: tamper signals" "skip rename stderr"; return; }
  jq -e '.tamper=="none"' <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null \
    || { report FAIL "case 13: tamper signals" "skip rename ledger"; return; }
  report PASS "case 13: tamper signals"
}

case_14_tamper_modes() {
  (( LG_HAVE_JQ )) || { report SKIP "case 14: tamper modes" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c14"
  lg_make_sandbox "$dir" ".claude" 0 1 1 || { report FAIL "case 14: tamper modes" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 14: tamper modes" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'git rm -f tests/test_a.py && git commit -qm tamper' warn 0
  grep -qF 'passes: true' "$dir/_memory/loop/backlog.md" \
    || { report FAIL "case 14: tamper modes" "warn passes"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 14: tamper modes" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 14: tamper modes" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  _lg_tamper_run "$dir" 'git rm -f tests/test_a.py && git commit -qm tamper' fail 1
  [[ "$lg_rc" -eq 1 ]] || { report FAIL "case 14: tamper modes" "fail rc=$lg_rc"; return; }
  grep -qF '=== max iterations (1) reached; backlog not complete ===' "$lg_out" \
    || { report FAIL "case 14: tamper modes" "fail banner"; return; }
  grep -qF 'passes: false' "$dir/_memory/loop/backlog.md" \
    || { report FAIL "case 14: tamper modes" "fail passes"; return; }
  grep -rqF 'reason: tamper' "$dir/.loop-worktrees/" \
    || { report FAIL "case 14: tamper modes" "quarantine"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 14: tamper modes" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 14: tamper modes" "sandbox setup"; return; }
  assert_fixture_root "$dir" || { report FAIL "case 14: tamper modes" "fixture root"; return; }
  cat > "$dir/_loop/stub-cb0del.sh" <<'STUB'
#!/usr/bin/env bash
echo tamper >> _loop/PROMPT.md
git rm -f tests/test_a.py 2>/dev/null || true
git add -A && git commit -qm cb0del
printf '{"type":"result","result":"ITERATION: STORY-101 passed (attempt 1/3)","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"total_cost_usd":0.01}\n'
exit 0
STUB
  chmod +x "$dir/_loop/stub-cb0del.sh"
  _lg_run_loop "$dir" 1 LOOP_WORKTREE=1 LOOP_USAGE_FORMAT=claude LOOP_CLI="$dir/_loop/stub-cb0del.sh"
  [[ "$lg_rc" -eq 4 ]] || { report FAIL "case 14: tamper modes" "cb0del rc=$lg_rc"; return; }

  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 14: tamper modes" "sandbox setup"; return; }
  _lg_tamper_seed "$dir" || { report FAIL "case 14: tamper modes" "sandbox setup"; return; }
  assert_fixture_root "$dir" || { report FAIL "case 14: tamper modes" "fixture root"; return; }
  cat > "$dir/_loop/stub-cb0del.sh" <<'STUB'
#!/usr/bin/env bash
echo tamper >> _loop/PROMPT.md
git rm -f tests/test_a.py 2>/dev/null || true
git add -A && git commit -qm cb0del
printf '{"type":"result","result":"ITERATION: STORY-101 passed (attempt 1/3)","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"total_cost_usd":0.01}\n'
exit 0
STUB
  chmod +x "$dir/_loop/stub-cb0del.sh"
  _lg_run_loop "$dir" 1 LOOP_WORKTREE=1 LOOP_USAGE_FORMAT=claude LOOP_TAMPER_CHECK=fail \
    LOOP_CLI="$dir/_loop/stub-cb0del.sh"
  [[ "$lg_rc" -eq 4 ]] || { report FAIL "case 14: tamper modes" "cb0 fail rc=$lg_rc"; return; }
  jq -e '.outcome=="protected"' <<< "$(tail -1 "$dir/_memory/loop/ledger.jsonl")" >/dev/null \
    || { report FAIL "case 14: tamper modes" "cb0 fail ledger"; return; }
  report PASS "case 14: tamper modes"
}

case_15_lint() {
  local dir="$FIXTURE_TMPDIR/c15" bl="$FIXTURE_TMPDIR/c15-bl-ext.md" cs_before cs_after
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 15: lint" "sandbox setup"; return; }
  cs_before="$(_lg_checksum_tree "$dir")"
  _lg_lint_expect "$dir" _memory/loop/backlog.md 0 || { report FAIL "case 15: lint" "clean"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: src/a.txt

## STORY-101: dup
**Acceptance criteria**
- [ ] y
- priority: 2
- passes: false
- attempts: 0
- blocked: false
- writes: src/b.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'lint: error STORY-101 : duplicate story id' \
    || { report FAIL "case 15: lint" "dup"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- passes: false
- attempts: 0
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'missing required field: priority' \
    || { report FAIL "case 15: lint" "prio"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- attempts: 0
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'missing required field: passes' \
    || { report FAIL "case 15: lint" "passes"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'missing required field: attempts' \
    || { report FAIL "case 15: lint" "attempts"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'missing required field: blocked' \
    || { report FAIL "case 15: lint" "blocked"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 08
- passes: false
- attempts: 0
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'priority must be a decimal integer without leading zeros' \
    || { report FAIL "case 15: lint" "prio08"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 08
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'attempts must be a decimal integer without leading zeros' \
    || { report FAIL "case 15: lint" "att08"; return; }
  grep -qF '((' "$lg_out" && { report FAIL "case 15: lint" "att08 arith"; return; }
  grep -qF '((' "$lg_err" && { report FAIL "case 15: lint" "att08 arith err"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: -1
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 0 || { report FAIL "case 15: lint" "att-1"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: maybe
- attempts: 0
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'passes must be true or false' \
    || { report FAIL "case 15: lint" "passes-val"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- blocked: maybe
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'blocked must be true or false' \
    || { report FAIL "case 15: lint" "blocked-val"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: bad*middle.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 "malformed writes: glob 'bad*middle.txt'" \
    || { report FAIL "case 15: lint" "malformed"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: _loop/PROMPT.md
BL
  _lg_lint_expect "$dir" "$bl" 1 'writes: intersects a protected path' \
    || { report FAIL "case 15: lint" "protected"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'missing **Acceptance criteria** heading' \
    || { report FAIL "case 15: lint" "ac heading"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'no acceptance criteria checklist items' \
    || { report FAIL "case 15: lint" "ac items"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- blocked: false
BL
  _lg_lint_expect "$dir" "$bl" 0 'lint: warn STORY-101 : absent or empty writes' \
    || { report FAIL "case 15: lint" "empty writes"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] 1
- [ ] 2
- [ ] 3
- [ ] 4
- [ ] 5
- [ ] 6
- [ ] 7
- [ ] 8
- [ ] 9
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: src/a.txt
BL
  _lg_lint_expect "$dir" "$bl" 0 'more than 8 acceptance criteria items' \
    || { report FAIL "case 15: lint" "ac8"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: w1.txt,w2.txt,w3.txt,w4.txt,w5.txt,w6.txt,w7.txt,w8.txt,w9.txt,w10.txt,w11.txt,w12.txt,w13.txt
BL
  _lg_lint_expect "$dir" "$bl" 0 'more than 12 writes: globs' \
    || { report FAIL "case 15: lint" "writes12"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: ORCHESTRATION.md
BL
  _lg_lint_expect "$dir" "$bl" 0 'writes: glob covers a hotspot path' \
    || { report FAIL "case 15: lint" "hotspot"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: <title>
**Acceptance criteria**
- [ ] <observable, verifiable outcome>
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: <comma-separated path globs>
BL
  _lg_lint_expect "$dir" "$bl" 0 'template placeholder text remains: <title>' \
    || { report FAIL "case 15: lint" "tpl"; return; }
  grep -qF 'template placeholder text remains: <comma-separated path globs>' "$lg_out" \
    || { report FAIL "case 15: lint" "tpl2"; return; }
  grep -qF 'template placeholder text remains: <observable, verifiable outcome>' "$lg_out" \
    || { report FAIL "case 15: lint" "tpl3"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- passes: false
- attempts: 0
- blocked: false
- writes: src/shared.txt

## STORY-102: b
**Acceptance criteria**
- [ ] y
- priority: 2
- passes: false
- attempts: 0
- blocked: false
- writes: src/shared.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 'missing required field: priority' \
    || { report FAIL "case 15: lint" "no-overlap-missing-prio err"; return; }
  grep -qF 'writes: globs intersect' "$lg_out" && { report FAIL "case 15: lint" "no-overlap spurious"; return; }

  _lg_write_lint_backlog "$bl" <<'BL'
# backlog
## STORY-101: a
**Acceptance criteria**
- [ ] x
- priority: 1
- passes: false
- attempts: 0
- blocked: false
- writes: bad*mid.txt

## STORY-102: b
**Acceptance criteria**
- [ ] y
- priority: 2
- passes: false
- attempts: 0
- blocked: false
- writes: src/shared.txt
BL
  _lg_lint_expect "$dir" "$bl" 1 "malformed writes: glob 'bad*mid.txt'" \
    || { report FAIL "case 15: lint" "malformed overlap err"; return; }
  grep -qF 'writes: globs intersect with eligible story' "$lg_out" \
    || { report FAIL "case 15: lint" "malformed overlap warn"; return; }

  _lg_run_lint "$dir" _memory/loop/no-such.md
  [[ "$lg_rc" -eq 5 ]] || { report FAIL "case 15: lint" "missing rc=$lg_rc"; return; }
  _lg_run_lint "$dir" _memory/loop
  [[ "$lg_rc" -eq 5 ]] || { report FAIL "case 15: lint" "dir rc=$lg_rc"; return; }

  cs_after="$(_lg_checksum_tree "$dir")"
  [[ "$cs_before" == "$cs_after" ]] || { report FAIL "case 15: lint" "checksum"; return; }
  [[ ! -f "$dir/_memory/loop/breaker-state.json" && ! -f "$dir/_memory/loop/ledger.jsonl" ]] \
    || { report FAIL "case 15: lint" "side effects"; return; }

  assert_fixture_root "$dir" || { report FAIL "case 15: lint" "fixture root"; return; }
  sed -i 's/- passes: false/- passes: true/' "$dir/_memory/loop/backlog.md"
  assert_fixture_root "$dir" || { report FAIL "case 15: lint" "fixture root"; return; }
  cat > "$dir/_loop/never.sh" <<'NEV'
#!/usr/bin/env bash
echo "stub should not run" >&2
exit 9
NEV
  chmod +x "$dir/_loop/never.sh"
  lg_out="$(mktemp)"; lg_err="$(mktemp)"
  ( cd "$dir" && LOOP_CLI="$dir/_loop/never.sh" bash ./_loop/loop.sh ) >"$lg_out" 2>"$lg_err"
  lg_rc=$?
  [[ "$lg_rc" -eq 0 ]] || { report FAIL "case 15: lint" "default rc=$lg_rc"; return; }
  grep -qF 'stub should not run' "$lg_err" && { report FAIL "case 15: lint" "dispatched"; return; }
  report PASS "case 15: lint"
}

case_16_emit() {
  local dir="$FIXTURE_TMPDIR/c16" no="$FIXTURE_TMPDIR/c16-no"
  mkdir -p "$dir" && assert_fixture_root "$dir"
  bash "$EMIT_SH" --root "$dir" --kit "$KIT" --answers "$SELF_ANSWERS" >/dev/null 2>&1 \
    || { report FAIL "case 16: emit" "loop emit"; return; }
  grep -Fx '_memory/loop/ledger.jsonl' "$dir/.gitignore" >/dev/null \
    || { report FAIL "case 16: emit" "loop gitignore"; return; }
  mkdir -p "$no" && assert_fixture_root "$no"
  jq '.flags.loop=false' "$SELF_ANSWERS" > "$FIXTURE_TMPDIR/c16-answers.json"
  bash "$EMIT_SH" --root "$no" --kit "$KIT" --answers "$FIXTURE_TMPDIR/c16-answers.json" >/dev/null 2>&1 \
    || { report FAIL "case 16: emit" "no-loop emit"; return; }
  grep -Fx '_memory/loop/ledger.jsonl' "$no/.gitignore" >/dev/null \
    && { report FAIL "case 16: emit" "no-loop has ledger"; return; }
  report PASS "case 16: emit"
}

case_17_frozen_twins() {
  local f
  for f in "$TEMPLATE_LOOP_PS1" "$TEMPLATE_BREAKER_PS1"; do
    head -n 20 "$f" | grep -qi frozen || { report FAIL "case 17: frozen twins" "$f"; return; }
    grep -qF 'any divergence is a bug' "$f" && { report FAIL "case 17: frozen twins" "parity $f"; return; }
    _lg_ps1_knobs_only_in_comments "$f" || { report FAIL "case 17: frozen twins" "knobs $f"; return; }
  done
  report PASS "case 17: frozen twins"
}

case_18_nonff() {
  (( LG_HAVE_JQ )) || { report SKIP "case 18: nonff" "jq"; return; }
  local dir="$FIXTURE_TMPDIR/c18"
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 18: nonff" "sandbox setup"; return; }
  assert_fixture_root "$dir" || { report FAIL "case 18: nonff" "fixture root"; return; }
  sed -i 's|- writes: src/story1.txt|- writes: src/story1.txt, slot-progress.txt|' "$dir/_memory/loop/backlog.md"
  sandbox_git "$dir" commit -qm 'widen writes for nonff' _memory/loop/backlog.md \
    || { report FAIL "case 18: nonff" "fixture root"; return; }
  assert_fixture_root "$dir" || { report FAIL "case 18: nonff" "fixture root"; return; }
  cat > "$dir/_loop/stub-ffonly.sh" <<STUB
#!/usr/bin/env bash
echo "slot progress" > slot-progress.txt
git add slot-progress.txt
git commit -qm "slot-side commit (never integrated)"
echo "conflict from main" > "$dir/slot-progress.txt"
git -C "$dir" add slot-progress.txt
git -C "$dir" commit -qm "external main-tree commit (concurrent, conflicting)"
echo "ITERATION: STORY-101 passed"
exit 0
STUB
  chmod +x "$dir/_loop/stub-ffonly.sh"
  _lg_run_loop "$dir" 1 LOOP_WORKTREE=1 LOOP_USAGE_FORMAT=none LOOP_CLI="$dir/_loop/stub-ffonly.sh"
  [[ "$lg_rc" -eq 5 ]] || { report FAIL "case 18: nonff" "rc=$lg_rc"; return; }
  grep -c '"outcome":"nonff"' "$dir/_memory/loop/ledger.jsonl" 2>/dev/null | grep -qxF 1 \
    || { report FAIL "case 18: nonff" "ledger"; return; }
  grep -qF '=== loop run summary' "$lg_err" || { report FAIL "case 18: nonff" "summary"; return; }
  report PASS "case 18: nonff"
}

case_19_setup_fail_count() {
  local n
  n="$(grep -cE '^\s*exit 5\s*$' "$DRIVER_SRC")"
  [[ "$n" -eq 6 ]] || { report FAIL "case 19: setup-failure helper" "count=$n"; return; }
  _lg_assert_setup_fail "c19-iter" "invalid LOOP_ITER_TIMEOUT='abc'" LOOP_ITER_TIMEOUT=abc || return
  _lg_assert_setup_fail "c19-usd" "invalid LOOP_RUN_BUDGET_USD='0'" LOOP_RUN_BUDGET_USD=0 || return
  _lg_assert_setup_fail "c19-tamper" "invalid LOOP_TAMPER_CHECK='maybe'" LOOP_TAMPER_CHECK=maybe || return
  _lg_assert_setup_fail "c19-failwt" "LOOP_TAMPER_CHECK=fail requires LOOP_WORKTREE=1" \
    LOOP_TAMPER_CHECK=fail LOOP_WORKTREE=0 || return
  local dir="$FIXTURE_TMPDIR/c19" argv="$FIXTURE_TMPDIR/c19-argv" shimd="$FIXTURE_TMPDIR/c19-shim"
  lg_make_sandbox "$dir" ".claude" 1 1 1 || { report FAIL "case 19: setup-failure helper" "sandbox setup"; return; }
  _lg_write_stub "$dir/_loop/stub.sh"
  mkdir -p "$shimd" && assert_fixture_root "$shimd"
  printf '#!/bin/sh\nexit 1\n' > "$shimd/timeout" && chmod +x "$shimd/timeout"
  : > "$argv"
  _lg_run_loop "$dir" 1 PATH="$shimd:$PATH" LOOP_ITER_TIMEOUT=2 LG_STUB_ARGV="$argv" LG_STUB_MODE=pass LOOP_CLI="$dir/_loop/stub.sh"
  [[ "$lg_rc" -eq 5 && ! -s "$argv" ]] || { report FAIL "case 19: setup-failure helper" "probe"; return; }
  grep -cF '!!!' "$lg_err" | grep -qxF 1 || { report FAIL "case 19: setup-failure helper" "probe bang"; return; }
  report PASS "case 19: setup-failure helper"
}

case_1_ledger
case_2_cb0
case_3_killed
case_4_summary
case_5_timeout
case_6_invalid_knobs
case_7_run_budget_tokens
case_8_run_budget_drained
case_9_run_budget_usd
case_10_story_budget
case_11_fail_open
case_12_claude_budget_flag
case_13_tamper
case_14_tamper_modes
case_15_lint
case_16_emit
case_17_frozen_twins
case_18_nonff
case_19_setup_fail_count
finish_suite
exit $?
