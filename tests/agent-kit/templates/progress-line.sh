#!/usr/bin/env bash
# Guards feature-template progress-line wiring and loop-driver stderr progress behavior.
# Also guards loop-driver `attempts` handling: story selection, the invalid-value warning, and the done counter.
# Also guards loop-driver `priority` handling: ordering parity, the invalid-value warning, ties, and no evaluation of the value.
# Driver cases need timeout or gtimeout and SKIP with that reason when neither is on PATH.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/akprogress.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
source "$HERE/../lib/fixture-root.sh"

DRIVER_SRC="${PROGRESS_LINE_DRIVER:-$REPO_ROOT/_loop/loop.sh}"
BREAKER_SRC="$REPO_ROOT/_loop/breaker.sh"
PROMPT_SRC="$REPO_ROOT/_loop/PROMPT.md"
TEMPLATES_SRC="${PROGRESS_LINE_TEMPLATES:-$REPO_ROOT/skills/agent-kit/templates}"

pass=0
fail=0
skip=0
# Same resolution order as the driver (loop.sh) and loop-guards.sh.
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="$(command -v timeout)"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="$(command -v gtimeout)"
fi
BACKGROUND_PIDS="$FIXTURE_TMPDIR/background-pids"
SUITE_START=$SECONDS

cleanup() {
  if [[ -f "$BACKGROUND_PIDS" ]]; then
    while IFS= read -r pid; do
      [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
    done < "$BACKGROUND_PIDS"
  fi
  rm -rf "$FIXTURE_TMPDIR"
}
trap cleanup EXIT

report() {
  case "$1" in
    PASS) pass=$((pass + 1)); printf 'PASS: %s\n' "$2" ;;
    SKIP) skip=$((skip + 1)); printf 'SKIP: %s%s\n' "$2" "${3:+ -- $3}" ;;
    *)
      fail=$((fail + 1))
      printf 'FAIL: %s -- %s\n' "$2" "$3" >&2
      ;;
  esac
}

fail_case() {
  report FAIL "$1" "$2"
  return 1
}

need_timeout() {
  [[ -n "$TIMEOUT_BIN" ]] && return 0
  report SKIP "$1" "neither timeout nor gtimeout on PATH"
  return 1
}

case_a() {
  local file="$TEMPLATES_SRC/skills/feature/reference/progress-line.md"
  local actual="$FIXTURE_TMPDIR/a-headings" expected="$FIXTURE_TMPDIR/a-expected"
  [[ -f "$file" ]] || { fail_case "a: feature reference" "missing $file"; return; }
  printf '%s\n' \
    '## Format' \
    '## Feature metric v1' \
    '## When it is printed' \
    '## Deriving the line' \
    '## Versioning' \
    '## Examples' \
    '## Loop driver' > "$expected"
  grep '^## ' "$file" > "$actual" || :
  cmp -s "$expected" "$actual" || { fail_case "a: feature reference" "heading order differs"; return; }
  grep -Fqx '`Progress: <pct>% (<done>/<total> steps, metric v1); <current unit>, <in flight>.`' "$file" \
    || { fail_case "a: feature reference" "format line missing"; return; }
  report PASS "a: feature reference headings and format"
}

case_b() {
  local file="$TEMPLATES_SRC/skills/feature/SKILL.template.md" count bytes
  [[ -f "$file" ]] || { fail_case "b: feature skill pointer" "missing $file"; return; }
  count="$(awk '
    /^### Goal checkpoint and resume$/ { in_section=1; next }
    /^### / && in_section { in_section=0 }
    in_section && /\(`reference\/progress-line\.md`\)/ { count++ }
    END { print count+0 }
  ' "$file")"
  [[ "$count" == "1" ]] || { fail_case "b: feature skill pointer" "expected one pointer in section, found $count"; return; }
  bytes="$(wc -c < "$file")"
  (( bytes <= 11264 )) || { fail_case "b: feature skill pointer" "file is $bytes bytes (maximum 11264)"; return; }
  report PASS "b: feature skill pointer and byte limit"
}

case_c() {
  local file="$TEMPLATES_SRC/skills/feature/templates/progress.md"
  [[ -f "$file" ]] || { fail_case "c: progress template" "missing $file"; return; }
  awk '
    NR==2 && $0 !~ /^updated: / { exit 1 }
    NR==3 && $0 !~ /^status: / { exit 1 }
    NR==4 && $0 !~ /^phase: / { exit 1 }
    NR==5 && ($0 !~ /^progress: / || $0 !~ /reference\/progress-line\.md/) { exit 1 }
    END { if (NR < 5) exit 1 }
  ' "$file" || { fail_case "c: progress template" "header lines 2-5 are out of contract"; return; }
  report PASS "c: progress template header"
}

case_d() {
  local file="$TEMPLATES_SRC/skills/feature/reference/resume.md" section
  [[ -f "$file" ]] || { fail_case "d: resume reference" "missing $file"; return; }
  section="$(awk '
    /^## When progress\.md is written$/ { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file")"
  [[ -n "$section" && "$section" == *'`progress:`'* && "$section" == *'reference/progress-line.md'* ]] \
    || { fail_case "d: resume reference" "section is missing progress pointer or field"; return; }
  report PASS "d: resume reference progress wiring"
}

case_e() {
  local file="$TEMPLATES_SRC/ORCHESTRATION.md" count
  [[ -f "$file" ]] || { fail_case "e: orchestration references" "missing $file"; return; }
  count="$(grep -Fc 'memory-protocol.md,progress-line.md,memory-capture.md' "$file" || :)"
  [[ "$count" == "4" ]] || { fail_case "e: orchestration references" "expected 4 matching lines, found $count"; return; }
  report PASS "e: orchestration references"
}

story() {
  local id="$1" priority="$2" attempts="$3" passes="$4" blocked="$5" writes="$6"
  printf '\n## %s: progress-line fixture\n\n**Acceptance criteria**\n- [ ] fixture passes\n\n' "$id"
  printf -- '- priority: %s\n- passes: %s\n- attempts: %s\n- blocked: %s\n- writes: %s\n' \
    "$priority" "$passes" "$attempts" "$blocked" "$writes"
}

make_sandbox() {
  local name="$1" dir
  dir="$(mktemp -d "$FIXTURE_TMPDIR/$name.XXXXXX")" || return 1
  assert_fixture_root "$dir" || return 1
  mkdir -p "$dir/_loop" "$dir/_memory/loop" "$dir/.claude" || return 1
  cp "$DRIVER_SRC" "$dir/_loop/loop.sh" || return 1
  cp "$BREAKER_SRC" "$PROMPT_SRC" "$dir/_loop/" || return 1
  chmod +x "$dir/_loop/loop.sh" "$dir/_loop/breaker.sh" || return 1
  printf 'placeholder\n' > "$dir/.claude/.keep"
  touch "$dir/orchestration-kit.manifest.json" "$dir/.gitattributes"
  : > "$dir/.gitignore"
  (
    cd "$dir" || exit 1
    git init -q
    assert_fixture_repo "$dir" || exit 1
    git add -A && git commit -qm init
  ) || return 1
  printf '%s\n' "$dir"
}

write_stub() {
  local path="$1"
  assert_fixture_root "$(dirname "$path")" || return 1
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$$" >> "$PL_PID_FILE"
story="$(grep -oE 'STORY-[0-9]+' <<< "${@: -1}" | head -1)"
story="${story:-STORY-101}"
[[ "${PL_VERDICT:-passed}" == passed ]] || {
  printf 'failure\n' > "progress-$story.txt"
  git add "progress-$story.txt" && git commit -qm "failed $story"
  printf 'ITERATION: %s failed (attempt 1/3)\n' "$story"
  exit 0
}
printf 'passed\n' > "progress-$story.txt"
git add "progress-$story.txt" && git commit -qm "passed $story"
printf 'ITERATION: %s passed (attempt 1/3)\n' "$story"
STUB
  chmod +x "$path"
}

run_loop() {
  local dir="$1" iterations="$2" out="$3" err="$4"
  shift 4
  (
    cd "$dir" || exit 1
    env PL_PID_FILE="$BACKGROUND_PIDS" LOOP_USAGE_FORMAT=none "$@" \
      "$TIMEOUT_BIN" 20s bash ./_loop/loop.sh "$iterations"
  ) > "$out" 2> "$err"
}

assert_progress() {
  local err="$1" expected="$2" actual="$3"
  grep '^Progress: ' "$err" > "$actual" || :
  cmp -s "$expected" "$actual"
}

assert_no_progress_stdout() {
  local out="$1" case_name="$2"
  ! grep -q '^Progress: ' "$out" || { fail_case "$case_name" "progress leaked to stdout"; return 1; }
}

case_f() {
  need_timeout "f: blocked backlog" || return 0
  local dir out err expected actual rc
  dir="$(make_sandbox f)" || { fail_case "f: blocked backlog" "sandbox setup"; return; }
  {
    printf '# backlog\n'
    story STORY-101 1 0 false false src/101.txt
    story STORY-102 2 0 false false src/102.txt
    story STORY-103 3 0 false true src/103.txt
  } > "$dir/_memory/loop/backlog.md"
  git -C "$dir" add _memory/loop/backlog.md && git -C "$dir" commit -qm backlog
  write_stub "$dir/_loop/stub.sh" || { fail_case "f: blocked backlog" "stub setup"; return; }
  out="$dir/stdout" err="$dir/stderr" expected="$dir/expected" actual="$dir/actual"
  printf '%s\n' \
    'Progress: 33% (1/3 steps, 1 blocked, metric v1); STORY-101 attempt 1 passed, idle.' \
    'Progress: 66% (2/3 steps, 1 blocked, metric v1); STORY-102 attempt 1 passed, idle.' > "$expected"
  run_loop "$dir" 2 "$out" "$err" LOOP_CLI="$dir/_loop/stub.sh"
  rc=$?
  [[ "$rc" -eq 0 ]] || { fail_case "f: blocked backlog" "loop exit $rc"; return; }
  assert_progress "$err" "$expected" "$actual" || { fail_case "f: blocked backlog" "stderr progress lines differ"; return; }
  assert_no_progress_stdout "$out" "f: blocked backlog" || return
  report PASS "f: one blocked story and exact progress lines"
}

case_g() {
  need_timeout "g: failed verdict" || return 0
  local dir out err expected actual rc
  dir="$(make_sandbox g)" || { fail_case "g: failed verdict" "sandbox setup"; return; }
  { printf '# backlog\n'; story STORY-101 1 0 false false src/101.txt; story STORY-102 2 0 false false src/102.txt; } \
    > "$dir/_memory/loop/backlog.md"
  git -C "$dir" add _memory/loop/backlog.md && git -C "$dir" commit -qm backlog
  write_stub "$dir/_loop/stub.sh" || { fail_case "g: failed verdict" "stub setup"; return; }
  out="$dir/stdout" err="$dir/stderr" expected="$dir/expected" actual="$dir/actual"
  printf '%s\n' 'Progress: 0% (0/2 steps, metric v1); STORY-101 attempt 1 failed, idle.' > "$expected"
  run_loop "$dir" 1 "$out" "$err" LOOP_CLI="$dir/_loop/stub.sh" PL_VERDICT=failed
  rc=$?
  [[ "$rc" -eq 0 || "$rc" -eq 1 ]] || { fail_case "g: failed verdict" "loop exit $rc"; return; }
  assert_progress "$err" "$expected" "$actual" || { fail_case "g: failed verdict" "stderr progress line differs"; return; }
  assert_no_progress_stdout "$out" "g: failed verdict" || return
  report PASS "g: failed verdict remains incomplete"
}

case_h() {
  need_timeout "h: attempts cap" || return 0
  local dir out err expected actual rc
  dir="$(make_sandbox h)" || { fail_case "h: attempts cap" "sandbox setup"; return; }
  { printf '# backlog\n'; story STORY-101 1 3 false false src/101.txt; story STORY-102 2 0 false false src/102.txt; } \
    > "$dir/_memory/loop/backlog.md"
  git -C "$dir" add _memory/loop/backlog.md && git -C "$dir" commit -qm backlog
  write_stub "$dir/_loop/stub.sh" || { fail_case "h: attempts cap" "stub setup"; return; }
  out="$dir/stdout" err="$dir/stderr" expected="$dir/expected" actual="$dir/actual"
  printf '%s\n' 'Progress: 50% (1/2 steps, 1 blocked, metric v1); STORY-102 attempt 1 passed, idle.' > "$expected"
  run_loop "$dir" 1 "$out" "$err" LOOP_CLI="$dir/_loop/stub.sh"
  rc=$?
  [[ "$rc" -eq 0 ]] || { fail_case "h: attempts cap" "loop exit $rc"; return; }
  assert_progress "$err" "$expected" "$actual" || { fail_case "h: attempts cap" "attempt-cap progress line differs"; return; }
  assert_no_progress_stdout "$out" "h: attempts cap" || return
  report PASS "h: exhausted attempts count as blocked"
}

case_i() {
  need_timeout "i: multi-slot in-flight" || return 0
  local dir out err expected actual route marker pid rc found i
  dir="$(make_sandbox i)" || { fail_case "i: multi-slot in-flight" "sandbox setup"; return; }
  { printf '# backlog\n'; story STORY-101 1 0 false false src/101.txt; story STORY-102 2 0 false false src/102.txt; } \
    > "$dir/_memory/loop/backlog.md"
  git -C "$dir" add _memory/loop/backlog.md && git -C "$dir" commit -qm backlog
  route="$dir/_loop/route.sh"
  marker="$FIXTURE_TMPDIR/release-story-102"
  out="$dir/stdout" err="$dir/stderr" expected="$dir/expected" actual="$dir/actual"
  cat > "$route" <<'ROUTE'
#!/usr/bin/env bash
set -u
printf '%s\n' "$$" >> "$PL_PID_FILE"
story="$(grep -oE 'STORY-[0-9]+' <<< "${@: -1}" | head -1)"
if [[ "$story" == STORY-102 ]]; then
  for ((i=0; i<500; i++)); do
    [[ -e "$PL_MARKER" ]] && break
    sleep 0.01
  done
  [[ -e "$PL_MARKER" ]] || { echo "marker wait timed out" >&2; exit 1; }
fi
case "$story" in
  STORY-101) write_path=src/101.txt ;;
  STORY-102) write_path=src/102.txt ;;
  *) echo "unexpected story: $story" >&2; exit 2 ;;
esac
mkdir -p src
printf 'passed\n' > "$write_path"
git add "$write_path" && git commit -qm "passed $story"
printf 'ITERATION: %s passed (attempt 1/3)\n' "$story"
ROUTE
  chmod +x "$route"
  printf '%s\n' \
    'Progress: 50% (1/2 steps, metric v1); STORY-101 attempt 1 passed, 1 slot running (STORY-102 attempt 1).' \
    'Progress: 100% (2/2 steps, metric v1); STORY-102 attempt 1 passed, idle.' > "$expected"
  (
    cd "$dir" || exit 1
    env PL_PID_FILE="$BACKGROUND_PIDS" PL_MARKER="$marker" LOOP_USAGE_FORMAT=none \
      LOOP_WORKTREE=1 LOOP_SLOTS=2 LOOP_CLI="$route" "$TIMEOUT_BIN" 20s bash ./_loop/loop.sh 2
  ) > "$out" 2> "$err" &
  pid=$!
  printf '%s\n' "$pid" >> "$BACKGROUND_PIDS"
  found=0
  for ((i=0; i<80; i++)); do
    if grep -q '^Progress: ' "$err" 2>/dev/null; then
      found=1
      break
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  : > "$marker"
  wait "$pid"
  rc=$?
  [[ "$found" -eq 1 ]] || { fail_case "i: multi-slot in-flight" "first progress line did not appear within 8 seconds"; return; }
  [[ "$rc" -eq 0 ]] || { fail_case "i: multi-slot in-flight" "loop exit $rc"; return; }
  assert_progress "$err" "$expected" "$actual" || { fail_case "i: multi-slot in-flight" "stderr progress lines differ"; return; }
  assert_no_progress_stdout "$out" "i: multi-slot in-flight" || return
  report PASS "i: in-flight slot appears between reaps"
}

case_j() {
  need_timeout "j: no-iteration modes" || return 0
  local dir out err rc
  dir="$(make_sandbox j)" || { fail_case "j: no-iteration modes" "sandbox setup"; return; }
  { printf '# backlog\n'; story STORY-101 1 0 false false src/101.txt; } > "$dir/_memory/loop/backlog.md"
  git -C "$dir" add _memory/loop/backlog.md && git -C "$dir" commit -qm backlog
  write_stub "$dir/_loop/stub.sh" || { fail_case "j: no-iteration modes" "stub setup"; return; }
  out="$dir/zero.out" err="$dir/zero.err"
  run_loop "$dir" 0 "$out" "$err" LOOP_CLI="$dir/_loop/stub.sh"
  rc=$?
  [[ ! -s "$err" ]] || { fail_case "j: no-iteration modes" "zero-iteration stderr nonempty (exit $rc)"; return; }
  assert_no_progress_stdout "$out" "j: no-iteration modes (zero iterations)" || return
  out="$dir/lint.out" err="$dir/lint.err"
  run_loop "$dir" --lint "$out" "$err" LOOP_CLI="$dir/_loop/stub.sh"
  rc=$?
  [[ "$rc" -eq 0 ]] || { fail_case "j: no-iteration modes" "lint exit $rc"; return; }
  ! grep -q '^Progress: ' "$out" || { fail_case "j: no-iteration modes" "lint printed a progress line to stdout"; return; }
  ! grep -q '^Progress: ' "$err" || { fail_case "j: no-iteration modes" "lint printed a progress line to stderr"; return; }
  report PASS "j: zero iterations and lint omit progress"
}

case_k() {
  need_timeout "k: leading-zero attempts" || return 0
  local dir out err expected actual rc
  dir="$(make_sandbox k)" || { fail_case "k: leading-zero attempts" "sandbox setup"; return; }
  { printf '# backlog\n'; story STORY-101 1 0 false false src/101.txt; story STORY-102 2 03 false false src/102.txt; } \
    > "$dir/_memory/loop/backlog.md"
  git -C "$dir" add _memory/loop/backlog.md && git -C "$dir" commit -qm backlog
  write_stub "$dir/_loop/stub.sh" || { fail_case "k: leading-zero attempts" "stub setup"; return; }
  out="$dir/stdout" err="$dir/stderr" expected="$dir/expected" actual="$dir/actual"
  printf '%s\n' 'Progress: 50% (1/2 steps, metric v1); STORY-101 attempt 1 passed, idle.' > "$expected"
  run_loop "$dir" 1 "$out" "$err" LOOP_CLI="$dir/_loop/stub.sh"
  rc=$?
  [[ "$rc" -eq 0 ]] || { fail_case "k: leading-zero attempts" "loop exit $rc"; return; }
  assert_progress "$err" "$expected" "$actual" || { fail_case "k: leading-zero attempts" "leading-zero progress line differs"; return; }
  assert_no_progress_stdout "$out" "k: leading-zero attempts" || return
  report PASS "k: leading-zero attempts are pending, not blocked"
}

# --- attempts handling (selection, warning, injection, counter) ---

# run_att <name> <attempts> <passes> <blocked> -> sets ATT_DIR, ATT_RC.
# STORY-101 (priority 1) carries the value under test; STORY-102 (priority 2) is pending.
run_att() {
  local name="$1" value="$2" passes="$3" blocked="$4" prio="${5:-1}" dir
  ATT_DIR="" ATT_RC=""
  dir="$(make_sandbox "$name")" || return 1
  { printf '# backlog\n'; story STORY-101 "$prio" "$value" "$passes" "$blocked" src/STORY-101.txt
    story STORY-102 2 0 false false src/STORY-102.txt; } > "$dir/_memory/loop/backlog.md"
  cat > "$dir/_loop/rec-stub.sh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$$" >> "$PL_PID_FILE"
story="$(grep -oE 'STORY-[0-9]+' <<< "${@: -1}" | head -1)"
printf '%s\n' "$story" >> "$PL_RECORD"
mkdir -p src
printf 'passed\n' > "src/$story.txt"
git add "src/$story.txt" && git commit -qm "passed $story"
printf 'ITERATION: %s passed (attempt 1/3)\n' "$story"
STUB
  chmod +x "$dir/_loop/rec-stub.sh"
  git -C "$dir" add _memory/loop/backlog.md _loop/rec-stub.sh && git -C "$dir" commit -qm backlog || return 1
  : > "$dir/record"
  run_loop "$dir" 2 "$dir/stdout" "$dir/stderr" PL_RECORD="$dir/record" LOOP_CLI="$dir/_loop/rec-stub.sh"
  ATT_RC=$?
  ATT_DIR="$dir"
}

# claimed_attempts <dir> -> STORY-101 attempts line value in the backlog
claimed_attempts() {
  awk '/^## STORY-101:/{s=1;next} /^## STORY-/{s=0} s && /^- attempts:/{sub(/^- attempts: */,""); print; exit}' \
    "$1/_memory/loop/backlog.md"
}

# check_att <label> <value> <dispatch yes|no> <claimed|-> <warn-count>
check_att() {
  local label="$1" value="$2" want_disp="$3" want_claim="$4" want_warn="$5" disp=no claim warn
  if grep -qE 'unbound variable|value too great for base' "$ATT_DIR/stderr"; then
    fail_case "$label" "driver crash text on stderr: $(grep -m1 -E 'unbound variable|value too great for base' "$ATT_DIR/stderr")"
    return 1
  fi
  grep -qx 'STORY-101' "$ATT_DIR/record" && disp=yes
  [[ "$disp" == "$want_disp" ]] || { fail_case "$label" "STORY-101 dispatched=$disp, expected $want_disp"; return 1; }
  if [[ "$want_disp" == yes ]]; then
    claim="$(claimed_attempts "$ATT_DIR")"
    [[ "$claim" == "$want_claim" ]] || { fail_case "$label" "claimed attempts '$claim', expected '$want_claim'"; return 1; }
  fi
  warn="$(grep -cxF "!!! backlog: STORY-101 has an invalid attempts value '$value' -- INELIGIBLE" "$ATT_DIR/stderr" || :)"
  [[ "$warn" == "$want_warn" ]] || { fail_case "$label" "warning line count $warn, expected $want_warn"; return 1; }
  grep -qx 'STORY-102' "$ATT_DIR/record" || { fail_case "$label" "STORY-102 was not dispatched"; return 1; }
  [[ "$ATT_RC" -eq 0 ]] || { fail_case "$label" "loop exit $ATT_RC"; return 1; }
  return 0
}

case_l() {
  need_timeout "l: attempts selection table" || return 0
  local values=(-1 0 00 01 02 2 -9 +1 3 07 08 -08 x '' 1+1)
  local disp=(yes yes yes yes yes yes yes yes no no no no no no no)
  local claim=(0 1 1 2 3 3 -8 2 - - - - - - -)
  local warn=(0 0 0 0 0 0 0 0 0 0 1 1 1 1 1)
  local i v label
  for i in "${!values[@]}"; do
    v="${values[$i]}"
    label="l: attempts '$v'"
    run_att "l$i" "$v" false false || { fail_case "$label" "sandbox setup"; continue; }
    check_att "$label" "$v" "${disp[$i]}" "${claim[$i]}" "${warn[$i]}" \
      && report PASS "$label dispatch=${disp[$i]} claimed=${claim[$i]} warnings=${warn[$i]}"
  done
}

case_m() {
  need_timeout "m: done and blocked stories skip the attempts/priority warning" || return 0
  local label="m: invalid attempts/priority on done/blocked story" field mode passes blocked n
  for field in attempts priority; do
    for mode in passes blocked; do
      passes=false blocked=false
      [[ "$mode" == passes ]] && passes=true || blocked=true
      if [[ "$field" == attempts ]]; then
        run_att "m-$mode" x "$passes" "$blocked" || { fail_case "$label" "sandbox setup ($mode)"; return; }
      else
        run_att "m-$mode-prio" 0 "$passes" "$blocked" x || { fail_case "$label" "sandbox setup ($field $mode)"; return; }
      fi
      n="$(grep -c "has an invalid $field value" "$ATT_DIR/stderr" || :)"
      [[ "$n" == 0 ]] || { fail_case "$label" "$field $mode run printed $n warning lines"; return; }
      ! grep -qx 'STORY-101' "$ATT_DIR/record" || { fail_case "$label" "$field $mode run dispatched STORY-101"; return; }
      grep -qx 'STORY-102' "$ATT_DIR/record" || { fail_case "$label" "$field $mode run did not dispatch STORY-102"; return; }
      [[ "$ATT_RC" -eq 0 ]] || { fail_case "$label" "$field $mode run exit $ATT_RC"; return; }
    done
  done
  report PASS "$label print no warning and run STORY-102"
}

case_n() {
  need_timeout "n: attempts injection" || return 0
  local label="n: attempts injection" marker="$FIXTURE_TMPDIR/n-injected-marker" v
  rm -f "$marker"
  v="_bl_id[\$(touch\${IFS}$marker)0]"
  run_att n "$v" false false || { fail_case "$label" "sandbox setup"; return; }
  [[ ! -e "$marker" ]] || { fail_case "$label" "marker file was created: attempts value was evaluated"; return; }
  ! grep -qx 'STORY-101' "$ATT_DIR/record" || { fail_case "$label" "STORY-101 was dispatched"; return; }
  check_att "$label" "$v" no - 1 || return
  report PASS "$label is never evaluated, warns once, STORY-102 runs"
}

case_o() {
  need_timeout "o: done counter ignores attempts" || return 0
  local label="o: done counter ignores attempts" dir expected actual
  dir="$(make_sandbox o)" || { fail_case "$label" "sandbox setup"; return; }
  { printf '# backlog\n'; story STORY-101 1 -1 true false src/101.txt; story STORY-102 2 0 false false src/102.txt; } \
    > "$dir/_memory/loop/backlog.md"
  git -C "$dir" add _memory/loop/backlog.md && git -C "$dir" commit -qm backlog
  write_stub "$dir/_loop/stub.sh" || { fail_case "$label" "stub setup"; return; }
  expected="$dir/expected" actual="$dir/actual"
  printf '%s\n' 'Progress: 100% (2/2 steps, metric v1); STORY-102 attempt 1 passed, idle.' > "$expected"
  run_loop "$dir" 1 "$dir/stdout" "$dir/stderr" LOOP_CLI="$dir/_loop/stub.sh"
  [[ "$?" -eq 0 ]] || { fail_case "$label" "loop exit nonzero"; return; }
  assert_progress "$dir/stderr" "$expected" "$actual" || { fail_case "$label" "progress line differs: $(cat "$actual")"; return; }
  report PASS "$label (passes: true with attempts -1 is done)"
}

# --- priority handling (ordering parity, invalid-value warning, injection) ---

# run_prio <name> <layout mix|last|alone> <priority> <iterations> -> sets PRIO_DIR, PRIO_RC.
# mix: STORY-101 (value under test) first, 102 priority 5, 103 priority 1.
# last: 102 priority 5, 103 priority 1, then 101 (value under test) last in the file.
# alone: STORY-101 only.
run_prio() {
  local name="$1" layout="$2" value="$3" iters="$4" dir
  PRIO_DIR="" PRIO_RC=""
  dir="$(make_sandbox "$name")" || return 1
  {
    printf '# backlog\n'
    case "$layout" in
      mix) story STORY-101 "$value" 0 false false src/STORY-101.txt
           story STORY-102 5 0 false false src/STORY-102.txt
           story STORY-103 1 0 false false src/STORY-103.txt ;;
      last) story STORY-102 5 0 false false src/STORY-102.txt
            story STORY-103 1 0 false false src/STORY-103.txt
            story STORY-101 "$value" 0 false false src/STORY-101.txt ;;
      *) story STORY-101 "$value" 0 false false src/STORY-101.txt ;;
    esac
  } > "$dir/_memory/loop/backlog.md"
  cat > "$dir/_loop/rec-stub.sh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$$" >> "$PL_PID_FILE"
story="$(grep -oE 'STORY-[0-9]+' <<< "${@: -1}" | head -1)"
printf '%s\n' "$story" >> "$PL_RECORD"
mkdir -p src
printf 'passed\n' > "src/$story.txt"
git add "src/$story.txt" && git commit -qm "passed $story"
printf 'ITERATION: %s passed (attempt 1/3)\n' "$story"
STUB
  chmod +x "$dir/_loop/rec-stub.sh"
  git -C "$dir" add _memory/loop/backlog.md _loop/rec-stub.sh && git -C "$dir" commit -qm backlog || return 1
  : > "$dir/record"
  run_loop "$dir" "$iters" "$dir/stdout" "$dir/stderr" PL_RECORD="$dir/record" LOOP_CLI="$dir/_loop/rec-stub.sh"
  PRIO_RC=$?
  PRIO_DIR="$dir"
}

# prio_order -> dispatch order of the last run_prio, e.g. 101,103,102
prio_order() { sed 's/^STORY-//' "$PRIO_DIR/record" | paste -sd, -; }

# prio_no_crash <label> -> fails when the driver printed crash text
prio_no_crash() {
  if grep -qE 'unbound variable|value too great for base|syntax error' "$PRIO_DIR/stderr"; then
    fail_case "$1" "driver crash text on stderr: $(grep -m1 -E 'unbound variable|value too great for base|syntax error' "$PRIO_DIR/stderr")"
    return 1
  fi
}

# prio_warn_count <value> -> exact-line count of the STORY-101 invalid-priority warning
prio_warn_count() {
  grep -cxF "!!! backlog: STORY-101 has an invalid priority value '$1' -- INELIGIBLE" "$PRIO_DIR/stderr" || :
}

case_p() {
  need_timeout "p: priority ordering parity" || return 0
  local values=(-1 0 00 01 2 5 +3 10 07)
  local orders=(101,103,102 101,103,102 101,103,102 101,103,102 103,101,102 103,101,102 103,101,102 103,102,101 103,102,101)
  local i v label order
  for i in "${!values[@]}"; do
    v="${values[$i]}"
    label="p: priority '$v'"
    run_prio "p$i" mix "$v" 3 || { fail_case "$label" "sandbox setup"; continue; }
    prio_no_crash "$label" || continue
    order="$(prio_order)"
    [[ "$order" == "${orders[$i]}" ]] || { fail_case "$label" "dispatch order $order, expected ${orders[$i]}"; continue; }
    [[ "$(grep -c 'has an invalid priority value' "$PRIO_DIR/stderr" || :)" == 0 ]] \
      || { fail_case "$label" "valid priority printed an invalid-priority warning"; continue; }
    [[ "$PRIO_RC" -eq 0 ]] || { fail_case "$label" "loop exit $PRIO_RC"; continue; }
    report PASS "$label order=${orders[$i]} no warning"
  done
  label="p: tie with earlier story keeps file order"
  run_prio p-tie last 01 3 || { fail_case "$label" "sandbox setup"; return; }
  prio_no_crash "$label" || return
  order="$(prio_order)"
  [[ "$order" == 103,101,102 ]] || { fail_case "$label" "dispatch order $order, expected 103,101,102"; return; }
  [[ "$(grep -c 'has an invalid priority value' "$PRIO_DIR/stderr" || :)" == 0 ]] \
    || { fail_case "$label" "tie run printed an invalid-priority warning"; return; }
  [[ "$PRIO_RC" -eq 0 ]] || { fail_case "$label" "loop exit $PRIO_RC"; return; }
  report PASS "$label (priority 01 last in file: 103,101,102)"
}

case_q() {
  need_timeout "q: invalid priority forms" || return 0
  local values=(08 x '' 1+1) i v label warn
  for i in "${!values[@]}"; do
    v="${values[$i]}"
    label="q: priority '$v'"
    run_prio "q$i" mix "$v" 3 || { fail_case "$label" "sandbox setup"; continue; }
    prio_no_crash "$label" || continue
    ! grep -qx 'STORY-101' "$PRIO_DIR/record" || { fail_case "$label" "STORY-101 was dispatched"; continue; }
    [[ "$(prio_order)" == 103,102 ]] || { fail_case "$label" "dispatch order $(prio_order), expected 103,102"; continue; }
    warn="$(prio_warn_count "$v")"
    [[ "$warn" == 1 ]] || { fail_case "$label" "warning line count $warn, expected 1"; continue; }
    [[ "$PRIO_RC" -eq 0 ]] || { fail_case "$label" "loop exit $PRIO_RC"; continue; }
    report PASS "$label is skipped with one warning, order 103,102"
  done
  label="q: lone story with priority 'x'"
  run_prio q-alone alone x 1 || { fail_case "$label" "sandbox setup"; return; }
  prio_no_crash "$label" || return
  ! grep -qx 'STORY-101' "$PRIO_DIR/record" || { fail_case "$label" "STORY-101 was dispatched"; return; }
  warn="$(prio_warn_count x)"
  [[ "$warn" == 1 ]] || { fail_case "$label" "warning line count $warn, expected 1"; return; }
  [[ "$PRIO_RC" -eq 0 || "$PRIO_RC" -eq 1 ]] || { fail_case "$label" "loop exit $PRIO_RC"; return; }
  report PASS "$label is never dispatched, warns once, no crash"
}

case_r() {
  need_timeout "r: priority injection" || return 0
  local label="r: priority injection" marker="$FIXTURE_TMPDIR/r-injected-marker" v i warn
  local values=()
  values[0]="_bl_id[\$(touch\${IFS}$marker)0]"
  values[1]="\$(touch\${IFS}$marker)"
  for i in 0 1; do
    v="${values[$i]}"
    rm -f "$marker"
    run_prio "r$i" mix "$v" 3 || { fail_case "$label" "sandbox setup ($i)"; return; }
    [[ ! -e "$marker" ]] || { fail_case "$label" "marker file was created by payload $i: priority value was evaluated"; return; }
    prio_no_crash "$label (payload $i)" || return
    ! grep -qx 'STORY-101' "$PRIO_DIR/record" || { fail_case "$label" "payload $i: STORY-101 was dispatched"; return; }
    warn="$(prio_warn_count "$v")"
    [[ "$warn" == 1 ]] || { fail_case "$label" "payload $i: warning line count $warn, expected 1"; return; }
    grep -qx 'STORY-103' "$PRIO_DIR/record" && grep -qx 'STORY-102' "$PRIO_DIR/record" \
      || { fail_case "$label" "payload $i: STORY-103/STORY-102 did not both run"; return; }
  done
  report PASS "$label (subscript and command substitution) is never evaluated, warns once, 103 and 102 run"
}

if [[ ! -f "$DRIVER_SRC" || ! -f "$BREAKER_SRC" || ! -f "$PROMPT_SRC" ]]; then
  report FAIL "precheck: driver" "missing loop driver/instance files; run scripts/agent-kit/self-install.sh"
  printf 'PASS: %s   FAIL: %s   SKIP: %s\n' "$pass" "$fail" "$skip"
  exit 1
fi
case_ids=(a b c d e f g h i k j l m n o p q r)
for id in "${case_ids[@]}"; do
  if [[ -n "${PROGRESS_LINE_ONLY:-}" && "$PROGRESS_LINE_ONLY" != "$id" ]]; then
    continue
  fi
  "case_$id"
done

printf 'PASS: %s   FAIL: %s   SKIP: %s\n' "$pass" "$fail" "$skip"
elapsed=$((SECONDS - SUITE_START))
if (( elapsed >= 60 )); then
  printf 'FAIL: runtime -- suite took %ss (maximum 59s)\n' "$elapsed" >&2
  fail=$((fail + 1))
  printf 'PASS: %s   FAIL: %s   SKIP: %s\n' "$pass" "$fail" "$skip"
fi
(( fail == 0 ))
