#!/usr/bin/env bash
# Self-test for tests/agent-kit/lib/{parallel,emit-cache}.sh (Bash 3.2).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/selftest-base.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=fixture-root.sh
. "$HERE/fixture-root.sh"

echo "bash: $BASH_VERSION"

. "$HERE/parallel.sh"

pass=0
fail=0
skip=0
FAILED_CASES=""

report() {
  local status="$1"
  local name="$2"
  shift 2
  local detail="${1:-}"
  case "$status" in
    PASS)
      pass=$((pass + 1))
      if [ -n "$detail" ]; then
        echo "PASS: $name -- $detail"
      else
        echo "PASS: $name"
      fi
      ;;
    FAIL)
      fail=$((fail + 1))
      FAILED_CASES="${FAILED_CASES} ${name}"
      if [ -n "$detail" ]; then
        echo "FAIL: $name -- $detail"
      else
        echo "FAIL: $name"
      fi
      ;;
    SKIP)
      skip=$((skip + 1))
      echo "SKIP: $name"
      ;;
  esac
}

report_fail_par() {
  report FAIL "$1"
}

VERIFY_CAPTURE_FILE=""
report_fail_verify_capture() {
  fail=$((fail + 1))
  echo "FAIL: $1" >>"${VERIFY_CAPTURE_FILE}"
}

WATCHDOG_PID=""
_run_with_watchdog() {
  local limit="$1"
  shift
  local start rc=0
  start=$SECONDS
  "$@" &
  WATCHDOG_PID=$!
  while kill -0 "$WATCHDOG_PID" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$limit" ]; then
      kill "$WATCHDOG_PID" 2>/dev/null || true
      sleep 1
      kill -9 "$WATCHDOG_PID" 2>/dev/null || true
      wait "$WATCHDOG_PID" 2>/dev/null || true
      return 124
    fi
    sleep 0.1
  done
  wait "$WATCHDOG_PID" 2>/dev/null || rc=$?
  return "$rc"
}

_bash4_scan() {
  local f="$1"
  local pat
  for pat in \
    'declare -A' \
    'mapfile' \
    'readarray' \
    'local -n' \
    'declare -g' \
    'wait -n'
  do
    if grep -qF "$pat" "$f" 2>/dev/null; then
      report FAIL "bash32-scan $f contains forbidden: $pat"
      return 1
    fi
  done
  if grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)' "$f" 2>/dev/null; then
    report FAIL "bash32-scan $f contains Bash-4 parameter expansion"
    return 1
  fi
  if grep -qE '\[-1\]' "$f" 2>/dev/null; then
    report FAIL "bash32-scan $f contains forbidden: [-1]"
    return 1
  fi
  report PASS "bash32-scan $f"
}

_bash4_scan "$HERE/parallel.sh"
_bash4_scan "$HERE/emit-cache.sh"
_bash4_scan "$REPO_ROOT/tests/agent-kit/run-all.sh"

STUB_DIR="$(mktemp -d "$FIXTURE_TMPDIR/stub.XXXXXX")" || exit 1
assert_fixture_root "$STUB_DIR" || exit 1
SELFTEST_RM="$FIXTURE_TMPDIR"
_selftest_exit_cleanup() {
  emit_cache_cleanup 2>/dev/null || true
  par_cleanup 2>/dev/null || true
  rm -rf $SELFTEST_RM 2>/dev/null
}
trap _selftest_exit_cleanup EXIT
STUB_EMIT="$STUB_DIR/stub-emit.sh"
cat >"$STUB_EMIT" <<'STUB'
#!/usr/bin/env bash
set -u
root=""
kit=""
answers=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --kit) kit="$2"; shift 2 ;;
    --answers) answers="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$root" ] || exit 2
[ -f "$answers" ] || exit 2
if grep -q '^rc=9' "$answers" 2>/dev/null; then
  echo "stub fail" >&2
  exit 9
fi
mkdir -p "$root/out"
if [ -d "$kit" ]; then
  find "$kit" -type f 2>/dev/null | head -n 1 | while IFS= read -r f; do
    [ -z "$f" ] && continue
    b="$(basename "$f")"
    cp "$f" "$root/out/$b" 2>/dev/null || true
  done
fi
if [ -n "${EMIT_STUB_COUNT:-}" ]; then
  n=0
  [ -f "$EMIT_STUB_COUNT" ] && n="$(cat "$EMIT_STUB_COUNT" 2>/dev/null || echo 0)"
  n=$((n + 1))
  echo "$n" >"$EMIT_STUB_COUNT"
fi
echo "ok" >"$root/stamp"
exit 0
STUB
chmod +x "$STUB_EMIT"

STUB_SLOW="$STUB_DIR/stub-emit-slow.sh"
cat >"$STUB_SLOW" <<'STUB'
#!/usr/bin/env bash
sleep 3
exec "$(dirname "$0")/stub-emit.sh" "$@"
STUB
chmod +x "$STUB_SLOW"

KIT_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t selftest-kit)"
SELFTEST_RM="$SELFTEST_RM $KIT_DIR"
echo 'v1' >"$KIT_DIR/sample.txt"
ANSWERS_OK="$(mktemp 2>/dev/null || mktemp -t ans)"
SELFTEST_RM="$SELFTEST_RM $ANSWERS_OK"
echo 'ok' >"$ANSWERS_OK"
ANSWERS_BAD="$(mktemp 2>/dev/null || mktemp -t ansb)"
SELFTEST_RM="$SELFTEST_RM $ANSWERS_BAD"
echo 'rc=9' >"$ANSWERS_BAD"

PAR_COUNTERS="pass fail skip"
PAR_LISTS="FAILED_CASES"
PAR_REPORT_FAIL="report_fail_par"

block_pass_detail() {
  report PASS "block-pass" "detail-${1:-x}"
}

block_skip() {
  report SKIP "block-skip"
}

block_fail_list() {
  report FAIL "block-fail" "because"
}

block_fail_nospace() {
  local tag="$1"
  fail=$((fail + 1))
  FAILED_CASES="${FAILED_CASES:+$FAILED_CASES }${tag}"
  echo "FAIL: ${tag}" >>"${PAR_BLOCK_LOG:-/dev/null}"
}

block_exit3() {
  exit 3
}

block_unbound() {
  echo "${SELFTEST_UNBOUND_VAR}"
}

block_exit1() {
  exit 1
}

block_slow() {
  sleep 2
  report PASS "block-slow" "done"
}

block_fast() {
  report PASS "block-fast" "done"
}

_par_demo_isolated() {
  local jobs="$1"
  local out="$STUB_DIR/par-demo-${jobs}.log"
  : >"$out"
  (
    local pass=0 fail=0 skip=0 FAILED_CASES=""
    AGENT_KIT_CASE_JOBS="$jobs"
    PAR_REPORT_FAIL="report_fail_capture"
    report_fail_capture() {
      fail=$((fail + 1))
      echo "FAIL: $1" >>"$out"
    }
    par_init
    par_block block_pass_detail one
    par_block block_skip
    par_block block_fail_list
    par_block block_fail_list
    par_finish >>"$out"
    par_cleanup
    echo "$pass" >"$STUB_DIR/par-demo-${jobs}.pass"
    echo "$fail" >"$STUB_DIR/par-demo-${jobs}.fail"
    echo "$skip" >"$STUB_DIR/par-demo-${jobs}.skip"
    echo "$FAILED_CASES" >"$STUB_DIR/par-demo-${jobs}.list"
  ) >>"$out" 2>&1
  PAR_DEMO_PASS="$(cat "$STUB_DIR/par-demo-${jobs}.pass")"
  PAR_DEMO_FAIL="$(cat "$STUB_DIR/par-demo-${jobs}.fail")"
  PAR_DEMO_SKIP="$(cat "$STUB_DIR/par-demo-${jobs}.skip")"
  PAR_DEMO_LIST="$(cat "$STUB_DIR/par-demo-${jobs}.list")"
  PAR_DEMO_OUT="$out"
}

_par_demo_isolated 1
PAR_J1_PASS="$PAR_DEMO_PASS"
PAR_J1_FAIL="$PAR_DEMO_FAIL"
PAR_J1_SKIP="$PAR_DEMO_SKIP"
PAR_J1_LIST="$PAR_DEMO_LIST"
PAR_SNAP_J1="$(cat "$PAR_DEMO_OUT")"
_par_demo_isolated 4
PAR_J4_PASS="$PAR_DEMO_PASS"
PAR_J4_FAIL="$PAR_DEMO_FAIL"
PAR_J4_SKIP="$PAR_DEMO_SKIP"
PAR_J4_LIST="$PAR_DEMO_LIST"
PAR_SNAP_J4="$(cat "$PAR_DEMO_OUT")"

if [ "$PAR_SNAP_J1" = "$PAR_SNAP_J4" ]; then
  report PASS "par jobs=1 vs 4 identical block output"
else
  report FAIL "par jobs=1 vs 4" "output differed"
fi
if [ "$PAR_J1_PASS" -eq 1 ] && [ "$PAR_J1_FAIL" -eq 2 ] && [ "$PAR_J1_SKIP" -eq 1 ] \
  && [ "$PAR_J4_PASS" -eq 1 ] && [ "$PAR_J4_FAIL" -eq 2 ] && [ "$PAR_J4_SKIP" -eq 1 ]; then
  report PASS "par counter deltas in parent (pass/fail/skip)"
else
  report FAIL "par counter deltas" "j1=$PAR_J1_PASS/$PAR_J1_FAIL/$PAR_J1_SKIP j4=$PAR_J4_PASS/$PAR_J4_FAIL/$PAR_J4_SKIP"
fi
if echo "$PAR_J4_LIST" | grep -q 'block-fail' && [ "$(echo "$PAR_J4_LIST" | tr ' ' '\n' | grep -c block-fail)" -ge 2 ]; then
  report PASS "par FAILED_CASES merged with separators"
else
  report FAIL "par FAILED_CASES" "j4=[$PAR_J4_LIST]"
fi

_par_list_sep_isolated() {
  local out="$STUB_DIR/par-listsep.log"
  local listf="$STUB_DIR/par-listsep.list"
  : >"$out"
  (
    local pass=0 fail=0 skip=0 FAILED_CASES=""
    AGENT_KIT_CASE_JOBS=1
    PAR_BLOCK_LOG="$out"
    PAR_REPORT_FAIL="report_fail_capture"
    report_fail_capture() {
      fail=$((fail + 1))
      echo "FAIL: $1" >>"$out"
    }
    par_init
    par_block block_fail_nospace nospace-a
    par_block block_fail_nospace nospace-b
    par_finish >>"$out"
    par_cleanup
    echo "$FAILED_CASES" >"$listf"
    echo "$fail" >"$STUB_DIR/par-listsep.fail"
  ) >>"$out" 2>&1
  PAR_LIST_SEP="$(cat "$listf" 2>/dev/null || echo)"
  PAR_LIST_SEP_FAIL="$(cat "$STUB_DIR/par-listsep.fail" 2>/dev/null || echo 0)"
}

_par_list_sep_isolated
if [ "$PAR_LIST_SEP" = "nospace-a nospace-b" ] && [ "$PAR_LIST_SEP_FAIL" -eq 2 ]; then
  report PASS "par list separator without leading space (two blocks)"
else
  report FAIL "par list separator nospace" "list=[$PAR_LIST_SEP] fail=$PAR_LIST_SEP_FAIL"
fi
echo "$PAR_SNAP_J4" | grep -qxF 'PASS: block-pass -- detail-one' \
  && echo "$PAR_SNAP_J4" | grep -qxF 'SKIP: block-skip' \
  && report PASS "par literal PASS/SKIP/detail lines" \
  || report FAIL "par literal output lines"

ORDER_OUT="$(
  pass=0
  fail=0
  skip=0
  AGENT_KIT_CASE_JOBS=4
  par_init
  par_block block_slow
  par_block block_fast
  par_finish
  par_cleanup
  2>&1
)"
if echo "$ORDER_OUT" | grep -q 'block-slow' && echo "$ORDER_OUT" | grep -q 'block-fast'; then
  slow_ln="$(echo "$ORDER_OUT" | grep -n 'block-slow' | head -1 | cut -d: -f1)"
  fast_ln="$(echo "$ORDER_OUT" | grep -n 'block-fast' | head -1 | cut -d: -f1)"
  if [ -n "$slow_ln" ] && [ -n "$fast_ln" ] && [ "$slow_ln" -lt "$fast_ln" ]; then
    report PASS "par declaration-order replay (slow before fast)"
  else
    report FAIL "par replay order" "slow=$slow_ln fast=$fast_ln"
  fi
else
  report FAIL "par replay order" "missing output"
fi

_par_incomplete_isolated() {
  local jobs="$1"
  local out="$STUB_DIR/par-inc-${jobs}.log"
  local failf="$STUB_DIR/par-inc-${jobs}.fail"
  : >"$out"
  (
    local pass=0 fail=0
    AGENT_KIT_CASE_JOBS="$jobs"
    PAR_REPORT_FAIL="report_fail_capture"
    report_fail_capture() {
      fail=$((fail + 1))
      echo "FAIL: $1" >>"$out"
    }
    par_init
    par_block block_exit3
    par_block block_unbound
    par_finish >>"$out"
    par_cleanup
    echo "$fail" >"$failf"
  ) >>"$out" 2>&1
  PAR_INC_OUT="$out"
  PAR_INC_FAIL="$(cat "$failf" 2>/dev/null || echo 0)"
}

for _pj in 1 4; do
  _par_incomplete_isolated "$_pj"
  if [ "$PAR_INC_FAIL" -ge 2 ]; then
    report PASS "par incomplete blocks jobs=$_pj reported FAIL"
  else
    report FAIL "par incomplete blocks jobs=$_pj" "fail=$PAR_INC_FAIL"
  fi
  if grep -q 'FAIL: par: block block_exit3 did not complete (rc=3)' "$PAR_INC_OUT" \
    && grep -q 'FAIL: par: block block_unbound did not complete' "$PAR_INC_OUT"; then
    report PASS "par incomplete unbound+exit3 text jobs=$_pj"
  else
    report FAIL "par incomplete message jobs=$_pj"
  fi
done

_wd_rc=0
_wd_start=$SECONDS
_run_with_watchdog 1 sleep 30 || _wd_rc=$?
_wd_elapsed=$((SECONDS - _wd_start))
if [ "$_wd_rc" -eq 124 ] && [ "$_wd_elapsed" -le 4 ] && ! kill -0 "$WATCHDOG_PID" 2>/dev/null; then
  report PASS "watchdog kills command at limit (rc 124, pid gone)"
else
  report FAIL "watchdog timeout path" "rc=$_wd_rc elapsed=${_wd_elapsed}s pid=$WATCHDOG_PID"
fi
_wd_rc=0
_run_with_watchdog 5 sh -c 'exit 7' || _wd_rc=$?
if [ "$_wd_rc" -eq 7 ]; then
  report PASS "watchdog passes through command rc"
else
  report FAIL "watchdog rc passthrough" "rc=$_wd_rc (expected 7)"
fi

INVALID_PAR="$STUB_DIR/test-invalid-par.sh"
cat >"$INVALID_PAR" <<EOF
#!/usr/bin/env bash
. "$HERE/parallel.sh"
par_init
par_block true
par_finish
EOF
chmod +x "$INVALID_PAR"
for _bad in x 0; do
  _rc=0
  _run_with_watchdog 15 env AGENT_KIT_CASE_JOBS="$_bad" bash "$INVALID_PAR" >/dev/null 2>&1 || _rc=$?
  if [ "$_rc" -eq 2 ]; then
    report PASS "par_init invalid AGENT_KIT_CASE_JOBS=$_bad exits 2"
  else
    report FAIL "par_init invalid jobs=$_bad" "rc=$_rc (expected 2)"
  fi
done

. "$HERE/emit-cache.sh"

EMIT_SH="$STUB_EMIT"
KIT="$KIT_DIR"
EMIT_DATE="2026-01-01"
PAR_REPORT_FAIL="report_fail_par"

CACHE_ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t ecroot)"
SELFTEST_RM="$SELFTEST_RM $CACHE_ROOT"
AGENT_KIT_EMIT_CACHE="$CACHE_ROOT"

unset AGENT_KIT_EMIT_CACHE
EMIT_STUB_COUNT="$STUB_DIR/emit-count.txt"
echo 0 >"$EMIT_STUB_COUNT"
export EMIT_STUB_COUNT
emit_cache_init
SHARED_CACHE="$AGENT_KIT_EMIT_CACHE"
block_cache_hit() {
  emit_cache_root _blk "$ANSWERS_OK" || true
  echo "$_blk" >"$STUB_DIR/block-root.txt"
}
emit_cache_root _p1 "$ANSWERS_OK" || report FAIL "shared cache parent fill"
emit_cache_root _p2 "$ANSWERS_OK" || report FAIL "shared cache parent hit"
par_init
par_block block_cache_hit
par_finish >"$STUB_DIR/block-cache.out" 2>&1
par_cleanup
emit_cache_root _p3 "$ANSWERS_OK" || report FAIL "shared cache after block"
blk_root="$(cat "$STUB_DIR/block-root.txt" 2>/dev/null || echo)"
stub_n="$(cat "$EMIT_STUB_COUNT" 2>/dev/null || echo 0)"
if [ "$stub_n" = "1" ] && [ "$_p1" = "$_p2" ] && [ "$_p1" = "$_p3" ] && [ "$_p1" = "$blk_root" ]; then
  report PASS "shared private cache one stub emit (parent+block)"
else
  report FAIL "shared private cache" "stub_emits=$stub_n blk=$blk_root p1=$_p1"
fi
_lib_par_dir="$PAR_DIR"
_lib_cache_dir="$SHARED_CACHE"
emit_cache_cleanup
par_cleanup
if [ -n "$_lib_par_dir" ] && [ -d "$_lib_par_dir" ]; then
  report FAIL "cleanup par dir" "still exists"
else
  report PASS "cleanup removes par dir"
fi
if [ -n "$_lib_cache_dir" ] && [ -d "$_lib_cache_dir" ]; then
  report FAIL "cleanup cache dir" "still exists"
else
  report PASS "cleanup removes private cache dir"
fi
par_init
par_finish
par_init
par_finish
_d1="$PAR_DIR"
par_cleanup
if [ -n "$_d1" ] && [ -d "$_d1" ]; then
  report FAIL "double par_init cleanup" "PAR_DIR remains"
else
  report PASS "double par_init leaves no par dir after cleanup"
fi

AGENT_KIT_EMIT_CACHE="$CACHE_ROOT"

emit_cache_root R1 "$ANSWERS_OK" || report FAIL "cache first fill"
emit_cache_root R2 "$ANSWERS_OK" || report FAIL "cache second fill"
if [ "$R1" = "$R2" ]; then
  report PASS "cache hit same root"
else
  report FAIL "cache hit" "roots differ"
fi

BAD_CACHE="$(mktemp -d 2>/dev/null || mktemp -d -t ecbad)"
AGENT_KIT_EMIT_CACHE="$BAD_CACHE"
EMIT_CACHE_USED=""
entries_before="$(find "$BAD_CACHE" -maxdepth 1 -type d -name 'entry-*' 2>/dev/null | wc -l | tr -d ' ')"
emit_cache_root R3 "$ANSWERS_BAD" 2>/dev/null
rc_bad=$?
entries_after="$(find "$BAD_CACHE" -maxdepth 1 -type d -name 'entry-*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$rc_bad" -ne 0 ] && [ "$entries_before" = "$entries_after" ]; then
  report PASS "cache rc!=0 not published"
else
  report FAIL "cache rc!=0" "rc=$rc_bad entries ${entries_before}->${entries_after}"
fi

_reject_ok=1
for _flag in --upgrade --force --dry-run --check-answers --root; do
  if emit_cache_root X "$ANSWERS_OK" "$_flag" 2>/dev/null; then
    report FAIL "cache reject $_flag" "expected return 2"
    _reject_ok=0
  else
    rc=$?
    if [ "$rc" -ne 2 ]; then
      report FAIL "cache reject $_flag" "rc=$rc"
      _reject_ok=0
    fi
  fi
done
if [ "$_reject_ok" -eq 1 ]; then
  report PASS "cache reject all five emit flags"
fi

cp "$STUB_EMIT" "$STUB_DIR/stub-emit2.sh"
echo '# touch' >>"$STUB_DIR/stub-emit2.sh"
EMIT_SH="$STUB_DIR/stub-emit2.sh"
emit_cache_root R4 "$ANSWERS_OK" || true
EMIT_SH="$STUB_EMIT"
emit_cache_root R5 "$ANSWERS_OK" || true
if [ "$R4" != "$R5" ]; then
  report PASS "cache miss on EMIT_SH bytes"
else
  report FAIL "cache EMIT_SH bytes" "same root"
fi

EMIT_SH="$STUB_EMIT"
echo 'v2' >"$KIT_DIR/sample.txt"
emit_cache_root R6 "$ANSWERS_OK" || true
if [ "$R2" != "$R6" ]; then
  report PASS "cache miss on kit content"
else
  report FAIL "cache kit content"
fi

echo 'v2b' >"$KIT_DIR/extra.txt"
chmod +x "$KIT_DIR/extra.txt"
emit_cache_root R7 "$ANSWERS_OK" || true
chmod -x "$KIT_DIR/extra.txt"
emit_cache_root R8 "$ANSWERS_OK" || true
if [ "$R7" != "$R8" ]; then
  report PASS "cache miss on exec bit"
else
  report FAIL "cache exec bit"
fi

echo 'v2c' >"$KIT_DIR/sample.txt"
OLD_PATH="$PATH"
PATH="/tmp/cache-path-test-$$:${OLD_PATH}"
emit_cache_root R9 "$ANSWERS_OK" || true
PATH="$OLD_PATH"
emit_cache_root R10 "$ANSWERS_OK" || true
if [ "$R9" != "$R10" ]; then
  report PASS "cache miss on PATH"
else
  report FAIL "cache PATH"
fi

CON_CACHE="$(mktemp -d 2>/dev/null || mktemp -d -t eccon)"
AGENT_KIT_EMIT_CACHE="$CON_CACHE"
echo 'v-con' >"$KIT_DIR/sample.txt"
(
  emit_cache_root _r "$ANSWERS_OK"
  echo "$_r" >"$CON_CACHE/root-a"
) &
p1=$!
(
  emit_cache_root _r "$ANSWERS_OK"
  echo "$_r" >"$CON_CACHE/root-b"
) &
p2=$!
wait "$p1" 2>/dev/null
wait "$p2" 2>/dev/null
RCON1="$(cat "$CON_CACHE/root-a" 2>/dev/null || echo)"
RCON2="$(cat "$CON_CACHE/root-b" 2>/dev/null || echo)"
entries="$(find "$CON_CACHE" -maxdepth 1 -type d -name 'entry-*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$RCON1" = "$RCON2" ] && [ -n "$RCON1" ] && [ "$entries" = "1" ]; then
  report PASS "cache concurrent fill one entry"
else
  report FAIL "cache concurrent" "entries=$entries"
fi

LOCK_GONE="$(mktemp -d 2>/dev/null || mktemp -d -t eclock)"
AGENT_KIT_EMIT_CACHE="$LOCK_GONE"
EMIT_SH="$STUB_SLOW"
(
  emit_cache_root _slow "$ANSWERS_OK"
) &
slow_pid=$!
sleep 0.25
(
  emit_cache_root _waiter "$ANSWERS_OK"
) &
waiter_pid=$!
sleep 1
rm -rf "$LOCK_GONE"
lock_rc=0
wait "$waiter_pid" 2>/dev/null || lock_rc=$?
wait "$slow_pid" 2>/dev/null || true
EMIT_SH="$STUB_EMIT"
if [ "$lock_rc" -ne 0 ]; then
  report PASS "cache lock wait gives up when cache dir gone"
else
  report FAIL "cache lock wait" "expected non-zero when dir removed, rc=$lock_rc"
fi

VERIFY_CACHE="$(mktemp -d 2>/dev/null || mktemp -d -t ecver)"
AGENT_KIT_EMIT_CACHE="$VERIFY_CACHE"
EMIT_CACHE_USED=""
echo 'v-verify' >"$KIT_DIR/sample.txt"
emit_cache_root RCLEAN "$ANSWERS_OK" || true
fail_before="$fail"
verify_out="$STUB_DIR/verify-clean.out"
: >"$verify_out"
VERIFY_CAPTURE_FILE="$verify_out"
PAR_REPORT_FAIL_SAVE="$PAR_REPORT_FAIL"
PAR_REPORT_FAIL="report_fail_verify_capture"
emit_cache_verify
PAR_REPORT_FAIL="$PAR_REPORT_FAIL_SAVE"
if [ "$fail" -eq "$fail_before" ] && [ ! -s "$verify_out" ]; then
  report PASS "emit_cache_verify silent when clean"
else
  report FAIL "emit_cache_verify clean" "out=[$(cat "$verify_out" 2>/dev/null)]"
fi
block_verify_mutate() {
  emit_cache_root _vblk "$ANSWERS_OK" || true
  echo "$_vblk" >"$STUB_DIR/verify-blk-root.txt"
}
par_init
par_block block_verify_mutate
par_finish >"$STUB_DIR/verify-blk.out" 2>&1
par_cleanup
_vroot="$(cat "$STUB_DIR/verify-blk-root.txt" 2>/dev/null || echo)"
if [ -n "$_vroot" ] && [ -f "$_vroot/stamp" ]; then
  echo mutated >>"$_vroot/stamp"
  fail_before="$fail"
  _vout="$STUB_DIR/verify-blk-mut.out"
  : >"$_vout"
  VERIFY_CAPTURE_FILE="$_vout"
  PAR_REPORT_FAIL="report_fail_verify_capture"
  emit_cache_verify
  PAR_REPORT_FAIL="$PAR_REPORT_FAIL_SAVE"
  if [ "$fail" -gt "$fail_before" ] && grep -q 'emit-cache: entry mutated' "$_vout"; then
    fail=$((fail - 1))
    report PASS "emit_cache_verify FAIL after block cache use + mutation"
  else
    report FAIL "emit_cache_verify block mutation"
  fi
else
  report FAIL "emit_cache_verify block mutation" "no root"
fi
echo mutated >>"$RCLEAN/stamp"
fail_before="$fail"
_vout2="$STUB_DIR/verify-mut.out"
: >"$_vout2"
VERIFY_CAPTURE_FILE="$_vout2"
PAR_REPORT_FAIL="report_fail_verify_capture"
emit_cache_verify
PAR_REPORT_FAIL="$PAR_REPORT_FAIL_SAVE"
if [ "$fail" -gt "$fail_before" ] && grep -q 'emit-cache: entry mutated' "$_vout2"; then
  fail=$((fail - 1))
  report PASS "emit_cache_verify FAIL on mutation"
else
  report FAIL "emit_cache_verify mutation"
fi

AGENT_KIT_EMIT_CACHE=off
emit_cache_init
echo 'v-off' >"$KIT_DIR/sample.txt"
rm -f "$KIT_DIR/extra.txt"
_off1=""
_off2=""
emit_cache_root _off1 "$ANSWERS_OK" || true
emit_cache_root _off2 "$ANSWERS_OK" || true
if [ -n "$_off1" ] && [ -n "$_off2" ] && [ "$_off1" != "$_off2" ]; then
  report PASS "cache off fresh roots"
else
  report FAIL "cache off"
fi
off_list="$(find "$_off1" -type f 2>/dev/null | sed "s|^$_off1/||" | LC_ALL=C sort | tr '\n' ' ')"
if [ "$off_list" = "out/sample.txt stamp " ] || [ "$off_list" = "out/sample.txt stamp" ]; then
  report PASS "cache off root has stub files only"
else
  report FAIL "cache off root pollution" "files=$off_list"
fi
if [ ! -f "$_off1/.emit.rc" ] && [ ! -f "$_off1/.emit.stdout" ]; then
  report PASS "cache off rc/stdout outside root"
else
  report FAIL "cache off emit meta inside root"
fi

AGENT_KIT_EMIT_CACHE="$CACHE_ROOT"
EMIT_CACHE_USED=""
COPYDEST="$(mktemp -d "$FIXTURE_TMPDIR/copydest.XXXXXX")" || exit 1
assert_fixture_root "$COPYDEST" || exit 1
emit_cache_copy "$COPYDEST" "$ANSWERS_OK" || report FAIL "emit_cache_copy"
if [ -f "$COPYDEST/stamp" ]; then
  report PASS "emit_cache_copy tree"
else
  report FAIL "emit_cache_copy missing stamp"
fi
if ( _emit_cache_assert_writable_root "$REPO_ROOT" 2>/dev/null ); then
  report FAIL "emit-cache writable-root probe accepted repository root"
else
  report PASS "emit-cache writable-root probe rejects repository root"
fi

# Guard-absent fallback in _emit_cache_assert_writable_root (callers that never sourced
# fixture-root.sh): the cache-dir rule applies to every root. The control proves the guard really
# is absent in the subshell and that a fixture root is still accepted, so the two negatives below
# can only pass through the fallback's own refusal.
if ( unset -f assert_fixture_root; ! type assert_fixture_root >/dev/null 2>&1 \
  && _emit_cache_assert_writable_root "$COPYDEST" 2>/dev/null ); then
  report PASS "emit-cache guard-absent fallback accepts a fixture root (control)"
else
  report FAIL "emit-cache guard-absent fallback accepts a fixture root (control)"
fi
if ( unset -f assert_fixture_root; _emit_cache_assert_writable_root "$REPO_ROOT" 2>/dev/null ); then
  report FAIL "emit-cache guard-absent fallback rejects repository root"
else
  report PASS "emit-cache guard-absent fallback rejects repository root"
fi
if ( unset -f assert_fixture_root; _emit_cache_assert_writable_root "" 2>/dev/null ); then
  report FAIL "emit-cache guard-absent fallback rejects empty root"
else
  report PASS "emit-cache guard-absent fallback rejects empty root"
fi

# Cache-dir rule (_emit_cache_assert_cache_dir): independent of the fixture-root guard.
if ( _emit_cache_assert_cache_dir "" 2>/dev/null ); then
  report FAIL "cache-dir rule rejects empty cache dir"
else
  report PASS "cache-dir rule rejects empty cache dir"
fi
if ( _emit_cache_assert_cache_dir "relative/cache" 2>/dev/null ); then
  report FAIL "cache-dir rule rejects relative cache dir"
else
  report PASS "cache-dir rule rejects relative cache dir"
fi
if ( _emit_cache_assert_cache_dir "$REPO_ROOT" 2>/dev/null ); then
  report FAIL "cache-dir rule rejects repository cache dir"
else
  report PASS "cache-dir rule rejects repository cache dir"
fi
if ( _emit_cache_assert_cache_dir "$REPO_ROOT/tests" 2>/dev/null ); then
  report FAIL "cache-dir rule rejects in-repo cache dir"
else
  report PASS "cache-dir rule rejects in-repo cache dir"
fi

# Init-failure latch, run in a subshell with its cache under FIXTURE_TMPDIR (never under REPO_ROOT).
# Init fails because the cache dir does not exist yet; the dir is then created, so only the latch
# can still make emit_cache_root refuse. Without the latch the stub emit would succeed in the cache.
_latch_rc=0
_latch_out="$(
  AGENT_KIT_EMIT_CACHE="$FIXTURE_TMPDIR/latch-cache"
  _l_init=0
  emit_cache_init 2>/dev/null || _l_init=$?
  mkdir -p "$AGENT_KIT_EMIT_CACHE"
  _l_after=0
  emit_cache_root _bad "$ANSWERS_OK" >/dev/null 2>&1 || _l_after=$?
  printf 'init=%s after=%s' "$_l_init" "$_l_after"
  [ "$_l_init" -ne 0 ] && [ "$_l_after" -ne 0 ]
)" || _latch_rc=$?
if [ "$_latch_rc" -eq 0 ]; then
  report PASS "emit-cache refuses operations after init failure"
else
  report FAIL "emit-cache init failure latch" "$_latch_out"
fi

SELFTEST_RM="$SELFTEST_RM $BAD_CACHE $CON_CACHE $VERIFY_CACHE $LOCK_GONE $COPYDEST"
emit_cache_cleanup
par_cleanup
_selftest_exit_cleanup
trap - EXIT

if ( assert_fixture_root "$REPO_ROOT" 2>/dev/null ); then
  report FAIL "fixture-root guard rejects repository root"
else
  report PASS "fixture-root guard rejects repository root"
fi
if ( assert_fixture_root "" 2>/dev/null ); then
  report FAIL "fixture-root guard rejects empty root"
else
  report PASS "fixture-root guard rejects empty root"
fi

echo "PASS: $pass FAIL: $fail SKIP: $skip"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
