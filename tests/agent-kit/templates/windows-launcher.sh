#!/usr/bin/env bash
# Guard: Windows `.cmd` launchers (runtime-bash-single-source Task 06).
#
# Static checks run everywhere. Behavior checks run only under Git Bash on Windows
# (MINGW*|MSYS*|CYGWIN*); otherwise they SKIP with a reason.
#
# Environment:
#   LAUNCHER_CMD   Path to the canonical launcher under test (default: template).
#   EMIT_CMD       Path to bin/emit.cmd (default: skills/agent-kit/bin/emit.cmd).
#   EMIT_SH        Emitter for dogfood fixture emits (default: bin/emit.sh).
#
# Mutation (AC4): copy the launcher, swap candidates 3/4 or strip CR, then:
#   LAUNCHER_CMD=/path/to/mutated.cmd bash tests/agent-kit/templates/windows-launcher.sh
# Static checks must FAIL.
#
# Exit 0 when no FAIL; 1 otherwise.
set -u

printf 'bash: %s\n' "$BASH_VERSION"

export LC_ALL=C
export EMIT_DATE=2026-09-03

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

. "$HERE/../lib/emit-cache.sh"

TEMPLATE="$REPO_ROOT/skills/agent-kit/templates/tools/bash-launcher.cmd"
LAUNCHER_CMD="${LAUNCHER_CMD:-$TEMPLATE}"
EMIT_CMD="${EMIT_CMD:-$REPO_ROOT/skills/agent-kit/bin/emit.cmd}"
EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
KIT="$REPO_ROOT/skills/agent-kit"
REF_DOC="$REPO_ROOT/skills/agent-kit/reference/windows-launcher.md"
FIXTURE="$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json"

pass=0
fail=0
skip=0
RUN_TMP=""
PATH_FARM_DIRS=""

report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name${detail:+ -- $detail}" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

_suite_cleanup() {
  local d
  for d in ${PATH_FARM_DIRS}; do
    [ -z "$d" ] && continue
    rm -rf "$d"
  done
  emit_cache_cleanup
  [ -n "$RUN_TMP" ] && rm -rf "$RUN_TMP"
}
trap _suite_cleanup EXIT

RUN_TMP="$(mktemp -d 2>/dev/null || mktemp -d -t wl-run)"

file_every_line_cr() { # path — every line CRLF (portable roundtrip; no GNU-only sed)
  local f="$1" u norm line
  [ -f "$f" ] || return 1
  grep -q $'\r' "$f" 2>/dev/null || return 1
  u="$(mktemp "$RUN_TMP/crlf.XXXXXX")"
  tr -d '\r' <"$f" >"$u"
  norm="$(mktemp "$RUN_TMP/crlfn.XXXXXX")"
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\r\n' "$line"
  done <"$u" >"$norm"
  cmp -s "$norm" "$f"
  local rc=$?
  rm -f "$u" "$norm"
  return "$rc"
}

git_blob_every_line_cr() { # git-path
  local gp="$1" tmp rc
  tmp="$(mktemp "$RUN_TMP/gitblob.XXXXXX")"
  git show ":$gp" >"$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  file_every_line_cr "$tmp"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

ref_exit127_message() {
  awk '
    /^```text$/ { inb=1; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$REF_DOC" | sed '/^$/d'
}

launcher_exit127_line() {
  grep -F 'agent-kit: Git Bash not found' "$LAUNCHER_CMD" 2>/dev/null \
    | head -1 \
    | tr -d '\r' \
    | sed 's/^[^e]*echo //; s/^>\&2 echo //'
}

CRLF_WT_DETAIL=""

static_crlf_worktree() {
  CRLF_WT_DETAIL=""
  if ! file_every_line_cr "$LAUNCHER_CMD"; then
    CRLF_WT_DETAIL="LAUNCHER_CMD not all-CRLF lines"
  fi
  if ! file_every_line_cr "$EMIT_CMD"; then
    CRLF_WT_DETAIL="${CRLF_WT_DETAIL:+$CRLF_WT_DETAIL; }EMIT_CMD not all-CRLF lines"
  fi
  [ -z "$CRLF_WT_DETAIL" ]
}

static_crlf_git_blob() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    report SKIP "git blob CRLF on template and emit.cmd" "not a git repository"
    return 0
  fi
  local ok=1 detail=""
  if git_blob_every_line_cr "skills/agent-kit/templates/tools/bash-launcher.cmd"; then
    :
  else
    ok=0
    detail="template blob not all-CRLF lines"
  fi
  if git_blob_every_line_cr "skills/agent-kit/bin/emit.cmd"; then
    :
  else
    ok=0
    detail="${detail:+$detail; }emit.cmd blob not all-CRLF lines"
  fi
  if [ "$ok" -eq 1 ]; then
    report PASS "git blob CRLF on template and emit.cmd"
  else
    report FAIL "git blob CRLF on template and emit.cmd" "$detail"
  fi
}

static_forward_slash_script_path() {
  grep -qF 'set "S=%S:\=/%"' "$LAUNCHER_CMD"
}

static_emit_cmd_identity() {
  cmp -s "$LAUNCHER_CMD" "$EMIT_CMD"
}

static_emitted_cmd_identity() {
  local emit_root=""
  emit_cache_root emit_root "$FIXTURE" || return 1
  cmp -s "$LAUNCHER_CMD" "$emit_root/_kit/memory.cmd" \
    && cmp -s "$LAUNCHER_CMD" "$emit_root/_kit/log-spawn.cmd"
}

static_candidate_order() {
  awk '
    BEGIN {
      n=0
      want[++n]="AGENT_KIT_BASH"
      want[++n]="CLAUDE_CODE_GIT_BASH_PATH"
      want[++n]="git --exec-path"
      want[++n]="ProgramFiles%\\Git\\bin\\bash.exe"
      want[++n]="LOCALAPPDATA%\\Programs\\Git\\bin\\bash.exe"
      for (i=1; i<=n; i++) first[i]=0
    }
    {
      line=$0
      gsub(/\r/, "", line)
      for (i=1; i<=n; i++) {
        if (first[i] == 0 && index(line, want[i])) first[i]=NR
      }
    }
    END {
      for (i=1; i<=n; i++) if (first[i] == 0) exit 1
      for (i=2; i<=n; i++) if (first[i] <= first[i-1]) exit 1
      exit 0
    }
  ' "$LAUNCHER_CMD"
}

static_validity_and_wsl() {
  grep -qF ':TryCandidate' "$LAUNCHER_CMD" \
    && grep -qF 'if not exist' "$LAUNCHER_CMD" \
    && grep -qF 'if exist "%CAND%\"' "$LAUNCHER_CMD" \
    && grep -qF '%%~fI' "$LAUNCHER_CMD" \
    && grep -qF ':IsWslStub' "$LAUNCHER_CMD" \
    && grep -qF 'System32\bash.exe' "$LAUNCHER_CMD" \
    && grep -qF 'WindowsApps\bash.exe' "$LAUNCHER_CMD"
}

static_no_delayed_expansion() {
  ! grep -qi 'EnableDelayedExpansion' "$LAUNCHER_CMD" 2>/dev/null
}

static_exit127_message() {
  local want got
  want="$(ref_exit127_message)"
  got="$(launcher_exit127_line)"
  [ -n "$want" ] && [ "$got" = "$want" ]
}

path_without() { # cmd...
  local entry farm f base cmd hit result="" old="$PATH" rest
  rest="$old"
  while [ -n "$rest" ]; do
    if [ "${rest#*:}" != "$rest" ]; then
      entry="${rest%%:*}"
      rest="${rest#*:}"
    else
      entry="$rest"
      rest=""
    fi
    [ -n "$entry" ] || continue
    hit=0
    for cmd in "$@"; do
      if [ -e "$entry/$cmd" ] || [ -e "$entry/$cmd.exe" ]; then hit=1; fi
    done
    if [ "$hit" -eq 1 ]; then
      farm="$(mktemp -d "$RUN_TMP/pwf.XXXXXX")"
      PATH_FARM_DIRS="${PATH_FARM_DIRS} ${farm}"
      for f in "$entry"/*; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        for cmd in "$@"; do
          [ "$base" = "$cmd" ] && continue 2
          [ "$base" = "$cmd.exe" ] && continue 2
        done
        ln -s "$f" "$farm/$base" 2>/dev/null || cp -f "$f" "$farm/$base"
      done
      result="${result:+$result:}$farm"
    else
      result="${result:+$result:}$entry"
    fi
  done
  printf '%s' "$result"
}

win_is() {
  case "$(uname -s 2>/dev/null)" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

win_real_bash() {
  command -v bash 2>/dev/null || return 1
}

win_path_w() { # unix path → Windows path for cmd
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "${1//\//\\}"
  fi
}

win_path_wp() { # PATH string (unix) → Windows PATH
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -wp "$1"
  else
    printf '%s' "${1//\//\\}"
  fi
}

win_write_bat() { # bat_path line...
  local bat="$1"
  shift
  : >"$bat"
  while [ $# -gt 0 ]; do
    printf '%s\r\n' "$1" >>"$bat"
    shift
  done
}

win_run_bat() { # rc_var stdout_var stderr_var bat_path
  local _rc _out _err _batw
  _out="$(mktemp "$RUN_TMP/bout.XXXXXX")"
  _err="$(mktemp "$RUN_TMP/berr.XXXXXX")"
  _batw="$(win_path_w "$4")"
  MSYS_NO_PATHCONV=1 cmd.exe /c "$_batw" >"$_out" 2>"$_err"
  _rc=$?
  eval "$1=\"\$_rc\""
  eval "$2=\"\$(tr -d '\r' <\"$_out\")\""
  eval "$3=\"\$(tr -d '\r' <\"$_err\")\""
  rm -f "$_out" "$_err"
}

win_fixture_dir() {
  local d="$RUN_TMP/win-fix.$$"
  mkdir -p "$d"
  cp -f "$LAUNCHER_CMD" "$d/stub.cmd"
  cat > "$d/stub.sh" <<'STUB'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  exit3) exit 3 ;;
  exit42) exit 42 ;;
  showargs)
    shift
    printf 'argc:%s args:' "$#"
    for _a; do printf '[%s]' "$_a"; done
    printf '\n'
    exit 0
    ;;
  probe)
    printf 'bash:%s\n' "$BASH"
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$d/stub.sh"
  printf '%s' "$d"
}

win_bash_used() { # probe line from stub
  sed -n 's/^bash://p' <<<"$1" | head -1
}

win_bash_norm() { # strip trailing .exe for comparison
  local p="$1"
  case "$p" in
    *.exe) printf '%s' "${p%.exe}" ;;
    *.EXE) printf '%s' "${p%.EXE}" ;;
    *) printf '%s' "$p" ;;
  esac
}

win_bash_paths_equal() {
  [ "$(win_bash_norm "$1")" = "$(win_bash_norm "$2")" ]
}

# --- static (everywhere) -------------------------------------------------------
emit_cache_init

if static_crlf_worktree; then
  report PASS "working-tree CRLF on template (LAUNCHER_CMD) and emit.cmd"
else
  report FAIL "working-tree CRLF on template (LAUNCHER_CMD) and emit.cmd" "$CRLF_WT_DETAIL"
fi

static_crlf_git_blob

if static_forward_slash_script_path; then
  report PASS "forward-slash script path conversion (S=%S:\\=/)"
else
  report FAIL "forward-slash script path conversion (S=%S:\\=/)"
fi

if static_emit_cmd_identity; then
  report PASS "emit.cmd byte-identical to canonical template"
else
  report FAIL "emit.cmd byte-identical to canonical template"
fi

if static_emitted_cmd_identity; then
  report PASS "emitted _kit/memory.cmd and log-spawn.cmd match template (cached emit)"
else
  report FAIL "emitted _kit/memory.cmd and log-spawn.cmd match template (cached emit)"
fi

if static_candidate_order; then
  report PASS "candidate order 1-5 in launcher source"
else
  report FAIL "candidate order 1-5 in launcher source"
fi

if static_validity_and_wsl; then
  report PASS "validity rule, TryCandidate, and WSL-stub exclusions present"
else
  report FAIL "validity rule, TryCandidate, and WSL-stub exclusions present"
fi

if static_no_delayed_expansion; then
  report PASS "no EnableDelayedExpansion in launcher"
else
  report FAIL "no EnableDelayedExpansion in launcher"
fi

if static_exit127_message; then
  report PASS "exit-127 message matches reference/windows-launcher.md"
else
  report FAIL "exit-127 message matches reference/windows-launcher.md"
fi

# --- behavior (Windows Git Bash only) ------------------------------------------
if ! win_is; then
  report SKIP "Windows behavior: stub exit codes 0/3/42" "not MINGW/MSYS/CYGWIN"
  report SKIP "Windows behavior: argument with spaces" "not MINGW/MSYS/CYGWIN"
  report SKIP "Windows behavior: two words without quotes not merged (negative control)" "not MINGW/MSYS/CYGWIN"
  report SKIP "Windows behavior: AGENT_KIT_BASH missing file skipped" "not MINGW/MSYS/CYGWIN"
  report SKIP "Windows behavior: AGENT_KIT_BASH WSL stub (System32) skipped" "not MINGW/MSYS/CYGWIN"
  report SKIP "Windows behavior: AGENT_KIT_BASH WSL stub (WindowsApps) skipped" "not MINGW/MSYS/CYGWIN"
  report SKIP "Windows behavior: AGENT_KIT_BASH quoted path with spaces" "not MINGW/MSYS/CYGWIN"
  report SKIP "Windows behavior: AGENT_KIT_BASH path with ampersand" "not MINGW/MSYS/CYGWIN"
  report SKIP "Windows behavior: exit 127 when all candidates neutralized" "not MINGW/MSYS/CYGWIN"
else
    if ! win_real_bash >/dev/null; then
      report SKIP "Windows behavior suite" "bash not on PATH"
    elif ! command -v cygpath >/dev/null 2>&1; then
      report SKIP "Windows behavior suite" "cygpath not available"
    else
      real_bash="$(win_real_bash)"
      fix="$(win_fixture_dir)"
      stub_cmd_w="$(win_path_w "$fix/stub.cmd")"
      bat="$RUN_TMP/probe.bat"
      rc=0
      out=""
      err=""

      win_write_bat "$bat" "@echo off" "call \"$stub_cmd_w\" exit3"
      win_run_bat rc out err "$bat"
      if [ "$rc" -eq 3 ]; then
        report PASS "Windows behavior: stub exit code 3 propagated"
      else
        report FAIL "Windows behavior: stub exit code 3 propagated" "rc=$rc err=[$err]"
      fi

      win_write_bat "$bat" "@echo off" "call \"$stub_cmd_w\" exit42"
      win_run_bat rc out err "$bat"
      if [ "$rc" -eq 42 ]; then
        report PASS "Windows behavior: stub exit code 42 propagated"
      else
        report FAIL "Windows behavior: stub exit code 42 propagated" "rc=$rc"
      fi

      win_write_bat "$bat" "@echo off" "call \"$stub_cmd_w\" showargs \"hello world\""
      win_run_bat rc out err "$bat"
      if [ "$rc" -eq 0 ] && [[ "$out" == *'argc:1'* ]] && [[ "$out" == *'[hello world]'* ]]; then
        report PASS "Windows behavior: argument with spaces intact"
      else
        report FAIL "Windows behavior: argument with spaces intact" "out=[$out]"
      fi

      win_write_bat "$bat" "@echo off" "call \"$stub_cmd_w\" showargs hello world"
      win_run_bat rc out err "$bat"
      if [ "$rc" -eq 0 ] && [[ "$out" == *'argc:2'* ]]; then
        report PASS "Windows behavior: two words without quotes not merged (negative control)"
      else
        report FAIL "Windows behavior: two words without quotes not merged (negative control)" "out=[$out]"
      fi

      win_write_bat "$bat" "@echo off" "set \"AGENT_KIT_BASH=C:\\missing\\nope\\bash.exe\"" "call \"$stub_cmd_w\" probe"
      win_run_bat rc out err "$bat"
      got_bash="$(win_bash_used "$out")"
      if [ "$rc" -eq 0 ] && win_bash_paths_equal "$got_bash" "$real_bash"; then
        report PASS "Windows behavior: AGENT_KIT_BASH missing file skipped"
      else
        report FAIL "Windows behavior: AGENT_KIT_BASH missing file skipped" "rc=$rc bash=[$got_bash] want=[$real_bash]"
      fi

      wsl_root="$RUN_TMP/wsl-fake-root"
      mkdir -p "$wsl_root/System32"
      cp -f "$real_bash" "$wsl_root/System32/bash.exe"
      wsl_root_w="$(win_path_w "$wsl_root")"
      win_write_bat "$bat" "@echo off" \
        "set \"SystemRoot=$wsl_root_w\"" \
        "set \"AGENT_KIT_BASH=%SystemRoot%\\System32\\bash.exe\"" \
        "call \"$stub_cmd_w\" probe"
      win_run_bat rc out err "$bat"
      got_bash="$(win_bash_used "$out")"
      if [ "$rc" -eq 0 ] && win_bash_paths_equal "$got_bash" "$real_bash"; then
        report PASS "Windows behavior: AGENT_KIT_BASH WSL stub (System32) skipped"
      else
        report FAIL "Windows behavior: AGENT_KIT_BASH WSL stub (System32) skipped" "rc=$rc bash=[$got_bash]"
      fi

      apps_root="$RUN_TMP/Microsoft/WindowsApps"
      mkdir -p "$apps_root"
      cp -f "$real_bash" "$apps_root/bash.exe"
      apps_bash_w="$(win_path_w "$apps_root/bash.exe")"
      win_write_bat "$bat" "@echo off" \
        "set \"AGENT_KIT_BASH=$apps_bash_w\"" \
        "call \"$stub_cmd_w\" probe"
      win_run_bat rc out err "$bat"
      got_bash="$(win_bash_used "$out")"
      if [ "$rc" -eq 0 ] && win_bash_paths_equal "$got_bash" "$real_bash"; then
        report PASS "Windows behavior: AGENT_KIT_BASH WSL stub (WindowsApps) skipped"
      else
        report FAIL "Windows behavior: AGENT_KIT_BASH WSL stub (WindowsApps) skipped" "rc=$rc bash=[$got_bash]"
      fi

      spaced_root="$RUN_TMP/spaced Git"
      mkdir -p "$spaced_root/bin"
      cp -f "$real_bash" "$spaced_root/bin/bash.exe"
      spaced_bash_w="$(win_path_w "$spaced_root/bin/bash.exe")"
      win_write_bat "$bat" "@echo off" "set \"AGENT_KIT_BASH=$spaced_bash_w\"" "call \"$stub_cmd_w\" probe"
      win_run_bat rc out err "$bat"
      got_bash="$(win_bash_used "$out")"
      if [ "$rc" -eq 0 ] && win_bash_paths_equal "$got_bash" "$spaced_root/bin/bash.exe"; then
        report PASS "Windows behavior: AGENT_KIT_BASH quoted path with spaces"
      else
        report FAIL "Windows behavior: AGENT_KIT_BASH quoted path with spaces" "rc=$rc bash=[$got_bash]"
      fi

      amp_root="$RUN_TMP/foo&bar"
      mkdir -p "$amp_root/bin"
      cp -f "$real_bash" "$amp_root/bin/bash.exe"
      amp_bash_w="$(win_path_w "$amp_root/bin/bash.exe")"
      win_write_bat "$bat" "@echo off" "set \"AGENT_KIT_BASH=$amp_bash_w\"" "call \"$stub_cmd_w\" probe"
      win_run_bat rc out err "$bat"
      got_bash="$(win_bash_used "$out")"
      if [ "$rc" -eq 0 ] && win_bash_paths_equal "$got_bash" "$amp_root/bin/bash.exe"; then
        report PASS "Windows behavior: AGENT_KIT_BASH path with ampersand"
      else
        report FAIL "Windows behavior: AGENT_KIT_BASH path with ampersand" "rc=$rc bash=[$got_bash]"
      fi

      empty_pf="$RUN_TMP/empty-pf"
      empty_la="$RUN_TMP/empty-la"
      mkdir -p "$empty_pf" "$empty_la"
      pf_w="$(win_path_w "$empty_pf")"
      la_w="$(win_path_w "$empty_la")"
      path_no_git="$(path_without git)"
      path_no_git_w="$(win_path_wp "$path_no_git")"
      want_msg="$(ref_exit127_message)"
      win_write_bat "$bat" "@echo off" \
        "set \"AGENT_KIT_BASH=C:\\nope\\bash.exe\"" \
        "set \"CLAUDE_CODE_GIT_BASH_PATH=C:\\nope2\\bash.exe\"" \
        "set \"ProgramFiles=$pf_w\"" \
        "set \"LOCALAPPDATA=$la_w\"" \
        "set \"PATH=$path_no_git_w\"" \
        "call \"$stub_cmd_w\""
      win_run_bat rc out err "$bat"
      err_one="$(printf '%s' "$err" | sed '/^$/d' | head -1)"
      if [ "$rc" -eq 127 ] && [ "$err_one" = "$want_msg" ]; then
        report PASS "Windows behavior: exit 127 when all candidates neutralized"
      else
        report FAIL "Windows behavior: exit 127 when all candidates neutralized" "rc=$rc err=[$err_one]"
      fi

      rm -rf "$fix"
    fi
fi

# --- Linux unit simulations (portable pieces; Windows behavior runs on CI) -----
if ! win_is; then
  sim_fix="$(win_fixture_dir)"
  sim_stub="$sim_fix/stub.sh"
  sim_out="$("$BASH" "$sim_stub" showargs "hello world")"
  if [ "$sim_out" = "argc:1 args:[hello world]" ]; then
    report PASS "linux sim: showargs quoted → argc:1 [hello world]"
  else
    report FAIL "linux sim: showargs quoted → argc:1 [hello world]" "out=[$sim_out]"
  fi
  sim_out="$("$BASH" "$sim_stub" showargs hello world)"
  if [ "$sim_out" = "argc:2 args:[hello][world]" ]; then
    report PASS "linux sim: showargs unquoted → argc:2"
  else
    report FAIL "linux sim: showargs unquoted → argc:2" "out=[$sim_out]"
  fi

  sim_line="bash:/tmp/x/spaced dir/bin/bash.exe"
  sim_got="$(win_bash_used "$sim_line")"
  sim_want="/tmp/x/spaced dir/bin/bash"
  if [ "$sim_got" = "/tmp/x/spaced dir/bin/bash.exe" ] && win_bash_paths_equal "$sim_got" "$sim_want"; then
    report PASS "linux sim: win_bash_used spaced path + .exe normalize"
  else
    report FAIL "linux sim: win_bash_used spaced path + .exe normalize" "got=[$sim_got]"
  fi

  sim_bin="$RUN_TMP/sim-bin"
  mkdir -p "$sim_bin"
  printf '#!/bin/sh\n' >"$sim_bin/git.exe"
  printf '#!/bin/sh\n' >"$sim_bin/jq.exe"
  printf '#!/bin/sh\n' >"$sim_bin/sha256sum.exe"
  printf '#!/bin/sh\n' >"$sim_bin/awk"
  chmod +x "$sim_bin"/*
  sim_path="${sim_bin}:/usr/bin:/bin"
  sim_saved_path="$PATH"
  PATH="$sim_path"
  sim_farmed="$(path_without git jq sha256sum)"
  sim_rc=0
  PATH="$sim_farmed" command -v git.exe >/dev/null 2>&1 && sim_rc=1
  PATH="$sim_farmed" command -v jq.exe >/dev/null 2>&1 && sim_rc=1
  PATH="$sim_farmed" command -v sha256sum.exe >/dev/null 2>&1 && sim_rc=1
  PATH="$sim_farmed" command -v awk >/dev/null 2>&1 || sim_rc=1
  PATH="$sim_saved_path"
  if [ "$sim_rc" -eq 0 ]; then
    report PASS "linux sim: path_without hides cmd and cmd.exe"
  else
    report FAIL "linux sim: path_without hides cmd and cmd.exe"
  fi

  rm -rf "$sim_fix"

  if file_every_line_cr "$TEMPLATE"; then
    sim_mut="$(mktemp "$RUN_TMP/simcrlf.XXXXXX")"
    {
      printf '%s\n' "$(head -1 "$TEMPLATE" | tr -d '\r')"
      tail -n +2 "$TEMPLATE"
    } >"$sim_mut"
    if ! file_every_line_cr "$sim_mut"; then
      report PASS "linux sim: CRLF check FAIL on one-LF-line copy"
    else
      report FAIL "linux sim: CRLF check FAIL on one-LF-line copy"
    fi
    rm -f "$sim_mut"
  else
    report FAIL "linux sim: CRLF canonical template"
  fi
fi

echo "SUMMARY: pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
