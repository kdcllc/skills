#!/usr/bin/env bash
# Guard: byte-compare golden corpus for skills/agent-kit/bin/emit.sh (pre-change oracle).
#
# These goldens are a change detector: any intended template, emitter, or kit-version
# change requires `bash tests/agent-kit/templates/emit-golden.sh --update` plus a
# reviewed diff. Do not update reflexively.
#
# Runs every case in a mktemp root; compares file list and bytes. Exit 0 only when
# all cases PASS. Override EMIT_SH to point at a different emitter.
#
# Usage: bash tests/agent-kit/templates/emit-golden.sh [--update]
set -u

printf 'bash: %s\n' "$BASH_VERSION"

export LC_ALL=C
export EMIT_DATE=2026-09-03

UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    *) echo "usage: $0 [--update]" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/emitgolden.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"

. "$HERE/../lib/parallel.sh"

EMIT_SH="${EMIT_SH:-$REPO_ROOT/skills/agent-kit/bin/emit.sh}"
case "$EMIT_SH" in /*) ;; *) EMIT_SH="$REPO_ROOT/$EMIT_SH" ;; esac
KIT="$REPO_ROOT/skills/agent-kit"
FIXTURE_ROOT="${EMIT_GOLDEN_ROOT:-$REPO_ROOT/tests/agent-kit/fixtures/emit-golden}"
case "$FIXTURE_ROOT" in /*) ;; *) FIXTURE_ROOT="$REPO_ROOT/$FIXTURE_ROOT" ;; esac

PATH_FARM_DIRS=()
PATH_NO_PWSH=""
pass=0
fail=0
FAILED_CASES=""

cleanup_farms() {
  local d
  for d in "${PATH_FARM_DIRS[@]+"${PATH_FARM_DIRS[@]}"}"; do
    rm -rf "$d"
  done
}

# Replace PATH entries that contain pwsh with symlink dirs of their other executables.
# Mutates PATH_FARM_DIRS in this shell (not a subshell).
build_path_no_pwsh() {
  local rest old="$PATH" result="" entry farm f base
  PATH_FARM_DIRS=()
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
    if [ -x "$entry/pwsh" ] || [ -f "$entry/pwsh" ]; then
      farm="$(mktemp -d "$FIXTURE_TMPDIR/pwf.XXXXXX")" || exit 1
      assert_fixture_root "$farm" || exit 1
      PATH_FARM_DIRS+=("$farm")
      for f in "$entry"/*; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        [ "$base" = "pwsh" ] && continue
        ln -s "$f" "$farm/$base" 2>/dev/null || cp -f "$f" "$farm/$base"
      done
      result="${result:+$result:}$farm"
    else
      result="${result:+$result:}$entry"
    fi
  done
  PATH_NO_PWSH="$result"
}

init_path_no_pwsh() {
  [ -n "$PATH_NO_PWSH" ] && return 0
  build_path_no_pwsh
}

run_emit_capture() { # root file_stdout file_stderr file_rc extra-args...
  local root="$1" f_out="$2" f_err="$3" f_rc="$4"
  shift 4
  local rc
  assert_fixture_root "$root" || exit 1
  init_path_no_pwsh
  PATH="$PATH_NO_PWSH" "$BASH" "$EMIT_SH" --root "$root" --kit "$KIT" "$@" \
    >"$f_out" 2>"$f_err"
  rc=$?
  printf '%s' "$rc" > "$f_rc"
}

golden_rel_paths() { # case_dir
  local case_dir="$1" f rel
  find "$case_dir" -type f -name '*.golden' \
    ! -name 'emit.stdout.golden' \
    ! -name 'emit.stderr.golden' \
    ! -name 'emit.exit-code.golden' \
    ! -name 'emit.exec-bits.golden' 2>/dev/null \
    | while IFS= read -r f; do
      rel="${f#"$case_dir"/}"
      rel="${rel%.golden}"
      printf '%s\n' "$rel"
    done | LC_ALL=C sort -u
}

restore_priors() { # case_dir root
  local case_dir="$1" root="$2" f rel dest
  find "$case_dir" -type f -name '*.prior' 2>/dev/null | while IFS= read -r f; do
    rel="${f#"$case_dir"/}"
    rel="${rel%.prior}"
    dest="$root/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -f "$f" "$dest"
  done
}

write_golden_file() { # case_dir rel_path root_file
  local case_dir="$1" rel="$2" src="$3" dest
  dest="$case_dir/${rel}.golden"
  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest"
}

capture_tree_goldens() { # case_dir root
  local case_dir="$1" root="$2" f rel
  find "$root" -type f 2>/dev/null | while IFS= read -r f; do
    rel="${f#"$root"/}"
    write_golden_file "$case_dir" "$rel" "$f"
  done
}

write_exec_bits_list() { # root out_file
  local root="$1" out="$2" f rel
  find "$root" -type f 2>/dev/null | while IFS= read -r f; do
    [ -x "$f" ] || continue
    rel="${f#"$root"/}"
    printf '%s\n' "$rel"
  done | LC_ALL=C sort > "$out"
}

write_exec_bits_golden() { # case_dir root
  write_exec_bits_list "$2" "$1/emit.exec-bits.golden"
}

write_meta_goldens() { # case_dir f_out f_err f_rc
  local case_dir="$1" f_out="$2" f_err="$3" f_rc="$4"
  cp -f "$f_out" "$case_dir/emit.stdout.golden"
  cp -f "$f_err" "$case_dir/emit.stderr.golden"
  cp -f "$f_rc" "$case_dir/emit.exit-code.golden"
}

compare_case() { # name case_dir root f_out f_err f_rc
  local name="$1" case_dir="$2" root="$3" f_out="$4" f_err="$5" f_rc="$6"
  local want got rel first_diff meta exec_tmp

  for meta in emit.stdout.golden emit.stderr.golden emit.exit-code.golden emit.exec-bits.golden; do
    if [ ! -f "$case_dir/$meta" ]; then
      report_fail "$name" "missing $meta"
      return 1
    fi
  done

  if ! cmp -s "$f_out" "$case_dir/emit.stdout.golden"; then
    report_fail "$name" "emit.stdout"
    return 1
  fi
  if ! cmp -s "$f_err" "$case_dir/emit.stderr.golden"; then
    report_fail "$name" "emit.stderr"
    return 1
  fi
  if ! cmp -s "$f_rc" "$case_dir/emit.exit-code.golden"; then
    report_fail "$name" "emit.exit-code"
    return 1
  fi

  got="$(find "$root" -type f 2>/dev/null | sed "s|^$root/||" | LC_ALL=C sort -u)"
  want="$(golden_rel_paths "$case_dir")"
  if [ "$got" != "$want" ]; then
    first_diff="$(comm -3 <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -n 1)"
    report_fail "$name" "${first_diff:-file-list}"
    return 1
  fi

  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    if ! cmp -s "$case_dir/${rel}.golden" "$root/$rel"; then
      report_fail "$name" "$rel"
      return 1
    fi
  done <<EOF
$want
EOF

  exec_tmp="$(mktemp)"
  write_exec_bits_list "$root" "$exec_tmp"
  if ! cmp -s "$exec_tmp" "$case_dir/emit.exec-bits.golden"; then
    rm -f "$exec_tmp"
    report_fail "$name" "emit.exec-bits"
    return 1
  fi
  rm -f "$exec_tmp"

  report_pass "$name"
  return 0
}

report_pass() {
  pass=$((pass + 1))
  echo "PASS: $1"
}

report_fail() {
  fail=$((fail + 1))
  FAILED_CASES="${FAILED_CASES:+$FAILED_CASES }$1"
  echo "FAIL: $1 -- $2" >&2
}

report_fail_par() {
  if [ $# -ge 2 ]; then
    report_fail "$1" "$2"
  else
    report_fail "$1" "parallel"
  fi
}

clear_case_goldens() { # case_dir
  local case_dir="$1"
  find "$case_dir" -type f -name '*.golden' -delete 2>/dev/null || true
}

require_static_inputs() { # case_name case_dir
  local name="$1" case_dir="$2"
  case "$name" in
    error-answers-missing)
      return 0
      ;;
    upgrade-retain|error-manifest-corrupt|error-manifest-no-answers|error-upgrade-blocked)
      if [ "$(find "$case_dir" -type f -name '*.prior' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]; then
        echo "emit-golden: missing .prior files for case $name" >&2
        return 1
      fi
      ;;
    *)
      if [ ! -f "$case_dir/answers.json" ]; then
        echo "emit-golden: missing answers.json for case $name" >&2
        return 1
      fi
      ;;
  esac
  return 0
}

run_case_emit() { # name root fo fe fr
  local name="$1" root="$2" fo="$3" fe="$4" fr="$5"
  local case_dir="$FIXTURE_ROOT/cases/$name" answers

  case "$name" in
    self|harness-claude-code|harness-cursor|harness-copilot|harness-codex|harness-all-four|string-stress|string-stress-scalars)
      answers="$case_dir/answers.json"
      run_emit_capture "$root" "$fo" "$fe" "$fr" --answers "$answers"
      ;;
    upgrade-retain)
      restore_priors "$case_dir" "$root"
      run_emit_capture "$root" "$fo" "$fe" "$fr" --upgrade
      ;;
    error-answers-missing)
      run_emit_capture "$root" "$fo" "$fe" "$fr" --answers "$case_dir/does-not-exist.json"
      ;;
    error-answers-invalid-json|error-models-fast-type)
      run_emit_capture "$root" "$fo" "$fe" "$fr" --answers "$case_dir/answers.json"
      ;;
    error-manifest-corrupt|error-manifest-no-answers|error-upgrade-blocked)
      restore_priors "$case_dir" "$root"
      run_emit_capture "$root" "$fo" "$fe" "$fr" --upgrade
      ;;
    *)
      echo "emit-golden: unknown case $name" >&2
      return 2
      ;;
  esac
}

run_case() { # name
  local name="$1"
  local case_dir="$FIXTURE_ROOT/cases/$name"
  local root fo fe fr

  if [ ! -d "$case_dir" ]; then
    report_fail "$name" "missing case directory"
    return 1
  fi

  root="$(mktemp -d "$FIXTURE_TMPDIR/case.XXXXXX")" || exit 1
  assert_fixture_root "$root" || exit 1
  fo="$(mktemp)"; fe="$(mktemp)"; fr="$(mktemp)"
  run_case_emit "$name" "$root" "$fo" "$fe" "$fr" || {
    report_fail "$name" "emit invocation failed"
    rm -f "$fo" "$fe" "$fr"
    rm -rf "$root"
    return 1
  }

  if [ "$UPDATE" -eq 1 ]; then
    write_meta_goldens "$case_dir" "$fo" "$fe" "$fr"
    capture_tree_goldens "$case_dir" "$root"
    write_exec_bits_golden "$case_dir" "$root"
  else
    compare_case "$name" "$case_dir" "$root" "$fo" "$fe" "$fr" || true
  fi
  rm -f "$fo" "$fe" "$fr"
  rm -rf "$root"
}

CASES=(
  self
  harness-claude-code
  harness-cursor
  harness-copilot
  harness-codex
  harness-all-four
  string-stress
  string-stress-scalars
  upgrade-retain
  error-answers-missing
  error-answers-invalid-json
  error-models-fast-type
  error-manifest-corrupt
  error-manifest-no-answers
  error-upgrade-blocked
)

_suite_cleanup() {
  cleanup_farms
  par_cleanup
  rm -rf "$FIXTURE_TMPDIR"
}
trap _suite_cleanup EXIT

if [ ! -f "$FIXTURE_ROOT/CAPTURED_WITH.txt" ]; then
  echo "emit-golden: missing CAPTURED_WITH.txt" >&2
  exit 1
fi

if [ "$UPDATE" -eq 1 ]; then
  # Validate every case's static inputs first, so a bad corpus never leaves
  # half-cleared goldens behind.
  inputs_ok=1
  for c in "${CASES[@]}"; do
    require_static_inputs "$c" "$FIXTURE_ROOT/cases/$c" || inputs_ok=0
  done
  if [ "$inputs_ok" -ne 1 ]; then
    echo "emit-golden: --update aborted: static inputs missing; no goldens changed" >&2
    exit 1
  fi
  for c in "${CASES[@]}"; do
    clear_case_goldens "$FIXTURE_ROOT/cases/$c"
    run_case "$c"
  done
  if [ "$fail" -gt 0 ]; then
    echo "emit-golden: --update FAILED for $fail case(s): $FAILED_CASES" >&2
    exit 1
  fi
  echo "emit-golden: --update complete"
  exit 0
fi

if [ ! -f "$FIXTURE_ROOT/cases/self/emit.exit-code.golden" ]; then
  echo "emit-golden: goldens missing — run with --update first" >&2
  exit 1
fi

init_path_no_pwsh

if ( assert_fixture_root "$REPO_ROOT" 2>/dev/null ); then
  report_fail "fixture-root guard rejects repository root"
else
  report_pass "fixture-root guard rejects repository root"
fi
if ( assert_fixture_root "" 2>/dev/null ); then
  report_fail "fixture-root guard rejects empty root"
else
  report_pass "fixture-root guard rejects empty root"
fi
# Helper-level negative that can fail: EMIT_SH is an `exit 0` stub that drops a marker, so an
# unguarded run_emit_capture would succeed and leave the marker. The control run proves the stub is live.
_golden_probe_out="$(mktemp "$FIXTURE_TMPDIR/probe-out.XXXXXX")"
_golden_probe_err="$(mktemp "$FIXTURE_TMPDIR/probe-err.XXXXXX")"
_golden_probe_rc="$(mktemp "$FIXTURE_TMPDIR/probe-rc.XXXXXX")"
_golden_stub="$FIXTURE_TMPDIR/emit-stub.sh"
_golden_marker="$FIXTURE_TMPDIR/emit-stub-ran"
printf '%s\n' ': > "$EMIT_STUB_MARKER"' 'exit 0' > "$_golden_stub"
rm -f "$_golden_marker"
_golden_ctrl_root="$(mktemp -d "$FIXTURE_TMPDIR/probe-root.XXXXXX")" || exit 1
assert_fixture_root "$_golden_ctrl_root" || exit 1
_golden_ctrl_rc=0
( EMIT_STUB_MARKER="$_golden_marker" EMIT_SH="$_golden_stub" run_emit_capture "$_golden_ctrl_root" "$_golden_probe_out" "$_golden_probe_err" "$_golden_probe_rc" 2>/dev/null ) || _golden_ctrl_rc=$?
_golden_ctrl_ran=0
[ -e "$_golden_marker" ] && _golden_ctrl_ran=1
rm -f "$_golden_marker"
_golden_empty_rc=0
( EMIT_STUB_MARKER="$_golden_marker" EMIT_SH="$_golden_stub" run_emit_capture "" "$_golden_probe_out" "$_golden_probe_err" "$_golden_probe_rc" 2>/dev/null ) || _golden_empty_rc=$?
if [ "$_golden_ctrl_rc" -eq 0 ] && [ "$_golden_ctrl_ran" -eq 1 ] \
  && [ "$_golden_empty_rc" -ne 0 ] && [ ! -e "$_golden_marker" ]; then
  report_pass "run_emit_capture refuses empty root before emit"
else
  report_fail "run_emit_capture refuses empty root before emit" "control_rc=$_golden_ctrl_rc control_ran=$_golden_ctrl_ran empty_rc=$_golden_empty_rc marker=$([ -e "$_golden_marker" ] && echo present || echo absent)"
fi
rm -rf "$_golden_probe_out" "$_golden_probe_err" "$_golden_probe_rc" "$_golden_ctrl_root" "$_golden_stub"

PAR_COUNTERS="pass fail"
PAR_LISTS="FAILED_CASES"
PAR_REPORT_FAIL="report_fail_par"

blk_run_case() {
  run_case "$1"
}

par_init
for c in "${CASES[@]}"; do
  par_block blk_run_case "$c"
done
par_finish

echo
echo "PASS: $pass   FAIL: $fail"
if [ "$fail" -eq 0 ]; then
  echo "RESULT: all golden cases passed"
  exit 0
fi
echo "RESULT: $fail golden case(s) FAILED"
exit 1
