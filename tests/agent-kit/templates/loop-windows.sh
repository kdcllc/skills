#!/usr/bin/env bash
# Windows Git Bash integration checks for _loop/loop.sh (cmd shim resolution, native child kill).
# SKIPs cleanly on non-Windows hosts. Discovered by tests/agent-kit/run-all.sh.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/loopwin.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"

# shellcheck source=../lib/fixture-root.sh
source "$HERE/../lib/fixture-root.sh"

CANON_LOOP="$REPO_ROOT/skills/agent-kit/templates/loop/loop.sh"
CANON_BREAKER="$REPO_ROOT/skills/agent-kit/templates/loop/breaker.sh"
CANON_MEMORY="$REPO_ROOT/skills/agent-kit/templates/tools/memory.sh"

SUITE_START=$SECONDS
pass=0
fail=0
skip=0

trap 'rm -rf "$FIXTURE_TMPDIR"' EXIT

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); echo "PASS: $2" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $2${3:+ -- $3}" ;;
    INFO) echo "INFO: $2" ;;
    *)
      fail=$((fail + 1))
      echo "FAIL: $2${3:+ -- $3}" >&2
      ;;
  esac
}

finish_suite() {
  local elapsed=$((SECONDS - SUITE_START))
  echo
  echo "=== loop-windows summary ==="
  echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
  echo "runtime: ${elapsed}s"
  if ((fail)); then
    echo "RESULT: $fail case(s) FAILED"
    return 1
  fi
  echo "RESULT: all cases passed"
  return 0
}

_lw_is_windows() {
  case "$(uname -s 2>/dev/null)" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

if ! _lw_is_windows; then
  report SKIP "loop-windows suite" "not Windows Git Bash (uname=$(uname -s 2>/dev/null || echo unknown))"
  finish_suite
  exit 0
fi

_lw_write_loop() {
  local dest="$1"
  mkdir -p "$dest/_loop"
  sed -e 's/{{PROJECT_NAME}}/sandbox-project/g' \
      -e 's/{{LOOP_MODEL_CHAIN}}/sonnet/g' \
      -e 's/{{LOOP_WORKTREE_DEFAULT}}/0/g' \
      -e 's/{{IDE_DIR}}/.claude/g' \
      "$CANON_LOOP" > "$dest/_loop/loop.sh"
  chmod +x "$dest/_loop/loop.sh"
  sed -e 's/{{PROJECT_NAME}}/sandbox-project/g' \
      "$CANON_BREAKER" > "$dest/_loop/breaker.sh"
  chmod +x "$dest/_loop/breaker.sh"
  printf 'Line one of prompt for %%%%STORY_ID%%%%\nLine two: outbox %%%%OUTBOX_DIR%%%%\nKNOWN_LAST_LINE_FOR_WIN_TEST\n' \
    > "$dest/_loop/PROMPT.md"
}

_lw_make_sandbox() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest/_loop" "$dest/_kit"
  _lw_write_loop "$dest"
  cp "$CANON_MEMORY" "$dest/_kit/memory.sh"
  chmod +x "$dest/_kit/memory.sh"
  assert_fixture_root "$dest" || return 1
  (
    cd "$dest"
    git init -q
    git config user.email test@example.com
    git config user.name "loop-windows"
    mkdir -p _memory/loop .claude
    cat > _memory/loop/backlog.md <<'BL'
# backlog

## STORY-101: windows fixture

- priority: 1
- passes: false
- attempts: 0
- blocked: false
BL
    printf 'k\n' > .claude/.keep
    : > .gitignore
    git add -A
    git commit -qm init
  )
}

_lw_ping_pids() {
  local err_file="$1"
  : >"$err_file"
  tasklist //FI "IMAGENAME eq PING.EXE" //FO CSV //NH 2>"$err_file"
}

_lw_ping_pid_list() {
  local err_file="$1" raw rc
  raw="$(_lw_ping_pids "$err_file")"
  rc=$?
  if [[ "$rc" -ne 0 ]] || grep -qvE '^(INFO: |[[:space:]]*$)' "$err_file"; then
    return 1
  fi
  awk -F',' '{gsub(/"/,"",$2); if ($2 ~ /^[0-9]+$/) print $2}' <<< "$raw"
}

_lw_kill_pids() {
  local pid
  for pid in "$@"; do
    [[ -n "$pid" ]] && taskkill //F //PID "$pid" >/dev/null 2>&1 || true
  done
}

# --- Case 1 (informational): bare LOOP_CLI vs .cmd shim on PATH ---
case_1_bare_cmd_shim() {
  local dir="$FIXTURE_TMPDIR/c1" shimdir="$FIXTURE_TMPDIR/c1-shim" log out err rc
  _lw_make_sandbox "$dir" || { report FAIL "case 1: sandbox"; return; }
  mkdir -p "$shimdir"
  cat > "$shimdir/winshim.cmd" <<'CMD'
@echo off
setlocal
echo invoked>> "%~dp0marker.txt"
echo ITERATION: STORY-101 passed
exit /b 0
CMD
  log="$FIXTURE_TMPDIR/c1.log"
  out="$FIXTURE_TMPDIR/c1.out"
  err="$FIXTURE_TMPDIR/c1.err"
  (
    cd "$dir"
    export PATH="$shimdir:$PATH"
    env -u LOOP_SLOTS -u LOOP_WORKTREE LOOP_CLI=winshim bash ./_loop/loop.sh 1
  ) >"$out" 2>"$err"
  rc=$?
  cat "$out" "$err" >"$log"
  if [[ -f "$shimdir/marker.txt" ]]; then
    report INFO "bare .cmd shim resolved"
  else
    report INFO "bare .cmd shim not resolved; use the .cmd suffix in LOOP_CLI"
  fi
  : "$rc" "$log"
}

# --- Case 2: suffixed .cmd shim must run; record multi-line prompt tail ---
case_2_suffixed_cmd_shim() {
  local dir="$FIXTURE_TMPDIR/c2" shimdir="$FIXTURE_TMPDIR/c2-shim" log out err rc marker
  _lw_make_sandbox "$dir" || { report FAIL "case 2: sandbox"; return; }
  mkdir -p "$shimdir"
  cat > "$shimdir/winshim.cmd" <<'CMD'
@echo off
setlocal EnableDelayedExpansion
set "ARGS=%*"
echo !ARGS!>> "%~dp0/argv.txt"
echo !ARGS! | findstr /C:"KNOWN_LAST_LINE_FOR_WIN_TEST" >nul && echo lastline=ok>> "%~dp0/argv.txt" || echo lastline=truncated>> "%~dp0/argv.txt"
echo ITERATION: STORY-101 passed
exit /b 0
CMD
  log="$FIXTURE_TMPDIR/c2.log"
  out="$FIXTURE_TMPDIR/c2.out"
  err="$FIXTURE_TMPDIR/c2.err"
  (
    cd "$dir"
    export PATH="$shimdir:$PATH"
    env -u LOOP_SLOTS -u LOOP_WORKTREE LOOP_CLI=winshim.cmd bash ./_loop/loop.sh 1
  ) >"$out" 2>"$err"
  rc=$?
  cat "$out" "$err" >"$log"
  marker="$shimdir/argv.txt"
  if [[ ! -f "$marker" ]]; then
    report FAIL "case 2: suffixed .cmd shim" "shim never ran (rc=$rc)"
    return
  fi
  if grep -q 'lastline=ok' "$marker" 2>/dev/null; then
    report INFO "multi-line prompt intact"
  else
    report INFO "multi-line prompt truncated by .cmd shim"
  fi
  grep -qF 'ITERATION: STORY-101 passed' "$log" && report PASS "case 2: suffixed .cmd shim runs under loop.sh" \
    || report FAIL "case 2: suffixed .cmd shim" "missing ITERATION line rc=$rc"
}

# --- Case 3 (informational outcome): does a native PING.EXE child outlive the iteration timeout? Harness errors FAIL. ---
case_3_native_child_kill() {
  local dir="$FIXTURE_TMPDIR/c3" marker log out err rc tl_err tl_out ping_winpid
  local before=() after=() new_pids=() pid seen b still_alive=0
  _lw_make_sandbox "$dir" || { report FAIL "case 3: sandbox"; return; }
  marker="$dir/_loop/ping-pid.marker"
  cat > "$dir/_loop/ping-stub.sh" <<STUB
#!/usr/bin/env bash
ping -n 120 127.0.0.1 >/dev/null 2>&1 &
winpid=\$(cat /proc/\$!/winpid 2>/dev/null || true)
printf '%s\n' "\$winpid" > '$marker'
wait
exit 0
STUB
  chmod +x "$dir/_loop/ping-stub.sh"
  tl_err="$FIXTURE_TMPDIR/c3-tasklist.err"
  # Capture in a variable: the status of a process substitution is never visible to mapfile.
  if ! tl_out="$(_lw_ping_pid_list "$tl_err")"; then
    report FAIL "case 3: tasklist" "tasklist error: $(tr '\n' ' ' <"$tl_err")"
    return
  fi
  # Load only a non-empty list so no empty element lands in "before".
  if [[ -n "$tl_out" ]]; then
    mapfile -t before <<< "$tl_out"
  fi
  log="$FIXTURE_TMPDIR/c3.log"
  out="$FIXTURE_TMPDIR/c3.out"
  err="$FIXTURE_TMPDIR/c3.err"
  (
    cd "$dir"
    env -u LOOP_SLOTS -u LOOP_WORKTREE LOOP_ITER_TIMEOUT=5 \
      LOOP_CLI="$dir/_loop/ping-stub.sh" bash ./_loop/loop.sh 1
  ) >"$out" 2>"$err"
  rc=$?
  cat "$out" "$err" >"$log"
  ping_winpid="$(tr -d '\r\n' <"$marker" 2>/dev/null || true)"
  # Snapshot first, on every path: the "ping never started" branch must still end any PING.EXE
  # that did start (its PID may simply not have been captured).
  tl_err="$FIXTURE_TMPDIR/c3-tasklist-after.err"
  if ! tl_out="$(_lw_ping_pid_list "$tl_err")"; then
    report FAIL "case 3: tasklist after run" "tasklist error: $(tr '\n' ' ' <"$tl_err")"
    [[ -n "$ping_winpid" ]] && _lw_kill_pids "$ping_winpid"
    return
  fi
  if [[ -n "$tl_out" ]]; then
    mapfile -t after <<< "$tl_out"
  fi
  for pid in "${after[@]}"; do
    seen=0
    for b in "${before[@]}"; do
      [[ "$pid" == "$b" ]] && seen=1
    done
    (( seen == 0 )) && new_pids+=("$pid")
  done
  if [[ -z "$ping_winpid" ]]; then
    report FAIL "case 3: ping never started" "empty ping-pid marker (rc=$rc) new=(${new_pids[*]})"
    _lw_kill_pids "${new_pids[@]}"
    return
  fi
  for pid in "${after[@]}"; do
    [[ "$pid" == "$ping_winpid" ]] && still_alive=1
  done
  if [[ "$still_alive" -eq 0 && ${#new_pids[@]} -eq 0 ]]; then
    report PASS "case 3: recorded PING.EXE PID $ping_winpid gone after iteration timeout (rc=$rc)"
  else
    report INFO "case 3: native child survived slot kill (known limitation) -- winpid=$ping_winpid new=(${new_pids[*]})"
  fi
  _lw_kill_pids "${new_pids[@]}"
  [[ "$still_alive" -eq 1 ]] && _lw_kill_pids "$ping_winpid"
}

case_1_bare_cmd_shim
case_2_suffixed_cmd_shim
case_3_native_child_kill

finish_suite
