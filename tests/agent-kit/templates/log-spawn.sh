#!/usr/bin/env bash
# Guard: the `log-spawn` orchestration-log writer twins.
#
# Behavioral section — runs the CANONICAL skills/agent-kit/templates/tools/log-spawn.sh
# (override with LOG_SPAWN_BIN=<path> for mutation testing) from a mktemp cwd holding
# `_memory/work/goals/demo/spawns/`:
#   (a) spawn #01 (101-byte context)            → SPAWN heading + context_chars: 101
#   (b) outcome #01 (40-byte report, no Footprint) → report_chars: 40 · io_est_tokens: 35
#       (floor 141/4) · work n/a · running io: 35 · running work: 0
#   (c) spawn/outcome #02 (200 / 0 bytes)       → io_est_tokens: 50 · running io: 85
#   (d) note                                    → heading appended
#   (e) exit codes 2 / 3 / 4 on the documented error paths
#   (e4) spawn / outcome / note with explicit --root "" → exit 2, stderr names --root, no log file
#   (e5) mutation: removing the empty-root check → not exit 2 (canonical exit 2)
#   (e2) `héllo`+LF context (7 bytes / 6 chars)  → context_chars: 7 (bytes, not chars)
#   (e3) log has no UTF-8 BOM and no CR
#   (f) every success call prints exactly one stdout line
#   (g) header present; line count strictly increasing (append-only)
#   (i)–(v) Footprint / --work-chars / pre-v0.26 fallback in a second fixture
#   keys: KEYS / REPEAT lines from a report's `### Required fixes` items — the two-evaluation
#         [structural] REPEAT, a repeated [line-patch] REPEAT, `none`, line stripping,
#         justification-clause exclusion, `[-]` for absent tags, `audit` / `09a` task values,
#         duplicate-KEYS / missing-SPAWN / missing-log exit 3, exit 2 / 4 in the frozen order,
#         KEYS text never feeding running totals, and an unchanged spawn/outcome/note literal
#   Structural checks align emitters/manifest/instance with _kit/log-spawn.sh + .cmd
#   (retired log-spawn.ps1 twin must not appear).
# Structural section — emitters, canonical + instance feature skills / ORCHESTRATION
# files, manifest keys, instance `_kit/` byte-identity (SKIP when an instance file is
# absent).
#
# Exit 0 when no FAIL; 1 otherwise.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
FIXTURE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/logspawn.XXXXXX")" || exit 1
export TMPDIR="$FIXTURE_TMPDIR"
# shellcheck source=../lib/fixture-root.sh
. "$HERE/../lib/fixture-root.sh"

alloc_fx() {
  local d
  d="$(mktemp -d "$FIXTURE_TMPDIR/fx.XXXXXX")" || exit 1
  assert_fixture_root "$d" || exit 1
  printf '%s' "$d"
}

CANON_SH="$REPO_ROOT/skills/agent-kit/templates/tools/log-spawn.sh"
LAUNCHER_CMD="$REPO_ROOT/skills/agent-kit/templates/tools/bash-launcher.cmd"
BIN="${LOG_SPAWN_BIN:-$CANON_SH}"

pass=0; fail=0; skip=0
report() { # report <PASS|FAIL|SKIP> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    PASS) pass=$((pass + 1)); echo "PASS: $name" ;;
    SKIP) skip=$((skip + 1)); echo "SKIP: $name${detail:+ -- $detail}" ;;
    *)    fail=$((fail + 1)); echo "FAIL: $name${detail:+ -- $detail}" >&2 ;;
  esac
}

TS_RE='s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}/TS/g'

make_fixture() { # make_fixture → prints fixture dir
  local d; d="$(mktemp -d "$FIXTURE_TMPDIR/fx.XXXXXX")" || exit 1
  assert_fixture_root "$d" || exit 1
  mkdir -p "$d/_memory/work/goals/demo/spawns"
  head -c 101 /dev/zero | tr '\0' 'x' > "$d/_memory/work/goals/demo/spawns/01-context.md"
  printf 'h\xc3\xa9llo\n' > "$d/_memory/work/goals/demo/spawns/03-context.md"   # héllo + LF: 7 bytes, 6 chars
  head -c 40  /dev/zero | tr '\0' 'y' > "$d/_memory/work/goals/demo/spawns/01-report.md"
  head -c 200 /dev/zero | tr '\0' 'x' > "$d/_memory/work/goals/demo/spawns/02-context.md"
  : > "$d/_memory/work/goals/demo/spawns/02-report.md"
  printf '%s' "$d"
}

# run_suite <label> <runner...> — runs (a)–(g) in a fresh fixture with the given runner
# (e.g. "bash /path/log-spawn.sh").
# Sets SUITE_LOG to the produced log path.
run_suite() {
  local label="$1"; shift
  local fx; fx="$(make_fixture)"
  local log="$fx/_memory/work/goals/demo/orchestration-log.md"
  local out rc lines prev_lines=0 mono=1
  cd "$fx" || return 1

  count_lines() { [[ -f "$log" ]] && wc -l < "$log" | tr -d ' ' || echo 0; }
  step_mono() { lines="$(count_lines)"; (( lines > prev_lines )) || mono=0; prev_lines=$lines; }

  # (a) spawn #01
  out="$("$@" spawn --goal demo --agent implementer --phase "Phase 4 task 01" \
        --model-requested light-model --context _memory/work/goals/demo/spawns/01-context.md \
        --writes "src/a.ts" --why "task 01" --expect "report" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" == 1 ]] \
     && grep -qE '^### .+ — SPAWN implementer \(Phase 4 task 01\) \[#01\]$' "$log" \
     && grep -qF -- '- context: _memory/work/goals/demo/spawns/01-context.md · context_chars: 101' "$log" \
     && grep -qF -- '- agent: implementer · model requested: light-model' "$log" \
     && grep -qF -- '- writes claim: src/a.ts' "$log"; then
    report PASS "[$label] (a) spawn #01 → SPAWN heading [#01] + context_chars: 101 (one stdout line)"
  else
    report FAIL "[$label] (a) spawn #01" "rc=$rc out='$out'"
  fi
  step_mono

  # (b) outcome #01
  out="$("$@" outcome --goal demo --spawn 01 --report _memory/work/goals/demo/spawns/01-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" == 1 ]] \
     && grep -qF -- '- OUTCOME [#01]: PASS · model reported: X · model_check: unverified · report: _memory/work/goals/demo/spawns/01-report.md · report_chars: 40 · io_est_tokens: 35 · work_read_chars: n/a · work_est_tokens: n/a · running io: 35 · running work: 0' "$log"; then
    report PASS "[$label] (b) outcome #01 → model_check: unverified · report_chars: 40 · io_est_tokens: 35 · running io: 35"
  else
    report FAIL "[$label] (b) outcome #01" "rc=$rc out='$out'"
  fi
  step_mono

  # (c) spawn/outcome #02 (0-byte report; note line)
  "$@" spawn --goal demo --agent evaluator --phase "P4" --model-requested frontier-model \
       --context _memory/work/goals/demo/spawns/02-context.md >/dev/null 2>&1; rc=$?
  step_mono
  out="$("$@" outcome --goal demo --spawn 02 --report _memory/work/goals/demo/spawns/02-report.md \
        --verdict "NEEDS FIXES" --model-reported frontier-model --note "one blocker" 2>/dev/null)"; rc2=$?
  if [[ $rc -eq 0 && $rc2 -eq 0 ]] \
     && grep -qF -- '- context: _memory/work/goals/demo/spawns/02-context.md · context_chars: 200' "$log" \
     && grep -qF -- 'report_chars: 0 · io_est_tokens: 50 · work_read_chars: n/a · work_est_tokens: n/a · running io: 85 · running work: 0' "$log" \
     && grep -qF -- '  one blocker' "$log"; then
    report PASS "[$label] (c) #02 → io_est_tokens: 50 · running io: 85 (+ indented note)"
  else
    report FAIL "[$label] (c) #02" "rc=$rc rc2=$rc2"
  fi
  step_mono

  # (d) note
  out="$("$@" note --goal demo --text "Phase 2 complete" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" == 1 ]] \
     && grep -qE '^### .+ — Phase 2 complete$' "$log"; then
    report PASS "[$label] (d) note → heading appended (one stdout line)"
  else
    report FAIL "[$label] (d) note" "rc=$rc out='$out'"
  fi
  step_mono

  # (e) exit codes
  local codes=""
  "$@" spawn --goal demo --agent e --phase p --model-requested m --context _memory/work/goals/demo/spawns/01-context.md >/dev/null 2>&1; codes+="$? "
  "$@" outcome --goal demo --spawn 01 --report _memory/work/goals/demo/spawns/01-report.md --verdict PASS --model-reported m >/dev/null 2>&1; codes+="$? "
  "$@" outcome --goal demo --spawn 09 --report _memory/work/goals/demo/spawns/01-report.md --verdict PASS --model-reported m >/dev/null 2>&1; codes+="$? "
  "$@" spawn --goal demo --agent e --phase p --model-requested m --context spawns/bad.md >/dev/null 2>&1; codes+="$? "
  "$@" spawn --goal demo --agent e --phase p --context _memory/work/goals/demo/spawns/01-context.md >/dev/null 2>&1; codes+="$? "
  "$@" bogus >/dev/null 2>&1; codes+="$? "
  "$@" note --goal nope --text hi >/dev/null 2>&1; codes+="$? "
  "$@" spawn --goal demo --agent e --phase p --model-requested m --context _memory/work/goals/demo/spawns/04-context.md >/dev/null 2>&1; codes+="$?"
  if [[ "$codes" == "3 3 3 2 2 2 4 4" ]]; then
    report PASS "[$label] (e) exit codes dup-spawn=3 dup-outcome=3 no-spawn=3 bad-NN=2 missing-flag=2 unknown-sub=2 no-goal=4 no-file=4"
  else
    report FAIL "[$label] (e) exit codes" "got '$codes' want '3 3 3 2 2 2 4 4'"
  fi
  lines="$(count_lines)"
  [[ "$lines" == "$prev_lines" ]] || mono=0   # error paths must not append

  # (e2) byte-vs-char: héllo + LF = 7 bytes / 6 chars
  "$@" spawn --goal demo --agent e --phase p --model-requested m --context _memory/work/goals/demo/spawns/03-context.md >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 0 ]] && grep -qF -- '- context: _memory/work/goals/demo/spawns/03-context.md · context_chars: 7' "$log"; then
    report PASS "[$label] (e2) héllo+LF context → context_chars: 7 (file bytes, not string length)"
  else
    report FAIL "[$label] (e2) byte-vs-char" "rc=$rc $(grep -F '03-context.md' "$log" | tail -1)"
  fi
  step_mono

  # (e3) encoding: no BOM, no CR
  if [[ "$(head -c 3 "$log" | od -An -tx1 | tr -d ' \n')" != "efbbbf" ]] && ! grep -q $'\r' "$log"; then
    report PASS "[$label] (e3) log is UTF-8 without BOM and has no CR bytes"
  else
    report FAIL "[$label] (e3) log has a BOM or CR bytes"
  fi

  # (f) covered inline above (one stdout line per success) — explicit summary assertion
  report PASS "[$label] (f) success calls printed exactly one stdout line (asserted in a/b/d)"

  # (g) header + monotonic growth
  if head -n1 "$log" | grep -qF '# Orchestration Log — demo' \
     && sed -n 3p "$log" | grep -qF 'Append-only spawn ledger. Running io_est_tokens (orchestrator I/O proxy, chars/4) and work_est_tokens (subagent self-reported footprint /4): see latest entry.' \
     && sed -n 5p "$log" | grep -qx -- '---' && [[ $mono -eq 1 ]]; then
    report PASS "[$label] (g) five-line header present; line count strictly increasing on success, unchanged on error"
  else
    report FAIL "[$label] (g) header / append-only" "mono=$mono"
  fi
  SUITE_LOG="$log"
  SUITE_CODES="$codes"
}

# make_work_fixture → prints fixture dir with AC1–3 sizes (101/59, 200/40, 100/0)
# plus an 8-byte #04 context for the invalid --work-chars probe.
make_work_fixture() {
  local d; d="$(mktemp -d "$FIXTURE_TMPDIR/wfx.XXXXXX")" || exit 1
  assert_fixture_root "$d" || exit 1
  mkdir -p "$d/_memory/work/goals/demo/spawns"
  head -c 101 /dev/zero | tr '\0' 'x' > "$d/_memory/work/goals/demo/spawns/01-context.md"
  printf '%s\n' '### Footprint' 'files_read: 3 (~12000 chars)' 'commands_run: 2' \
    > "$d/_memory/work/goals/demo/spawns/01-report.md"
  head -c 200 /dev/zero | tr '\0' 'x' > "$d/_memory/work/goals/demo/spawns/02-context.md"
  head -c 40 /dev/zero | tr '\0' 'y' > "$d/_memory/work/goals/demo/spawns/02-report.md"
  head -c 100 /dev/zero | tr '\0' 'x' > "$d/_memory/work/goals/demo/spawns/03-context.md"
  : > "$d/_memory/work/goals/demo/spawns/03-report.md"
  head -c 8 /dev/zero | tr '\0' 'x' > "$d/_memory/work/goals/demo/spawns/04-context.md"
  : > "$d/_memory/work/goals/demo/spawns/04-report.md"
  printf '%s' "$d"
}

# run_work_suite <label> <runner...> — (i)–(v) in a fresh fixture (and a seeded
# pre-v0.26 log for (v)). Sets WORK_LOG and FALLBACK_LOG.
run_work_suite() {
  local label="$1"; shift
  local fx log out rc wb lines_before lines_after
  fx="$(make_work_fixture)"
  log="$fx/_memory/work/goals/demo/orchestration-log.md"
  cd "$fx" || return 1

  # (i) 101-byte context + 59-byte Footprint report → T=40, W=3000
  "$@" spawn --goal demo --agent implementer --phase "P4" \
        --model-requested light-model --context _memory/work/goals/demo/spawns/01-context.md \
        >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 01 --report _memory/work/goals/demo/spawns/01-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  wb="$(wc -c < "$fx/_memory/work/goals/demo/spawns/01-report.md" | tr -d ' ')"
  if [[ $rc -eq 0 && "$wb" == 59 ]] \
     && grep -qF -- 'report_chars: 59 · io_est_tokens: 40 · work_read_chars: 12000 · work_est_tokens: 3000 · running io: 40 · running work: 3000' "$log"; then
    report PASS "[$label] (i) Footprint files_read: 3 (~12000 chars) → work_read_chars: 12000 · work_est_tokens: 3000 · running work: 3000"
  else
    report FAIL "[$label] (i) Footprint ingestion" "rc=$rc wb=$wb out='$out'"
  fi

  # (ii) 200 + 40 (no Footprint) → T=60, running io 100, running work unchanged
  "$@" spawn --goal demo --agent evaluator --phase "P4" --model-requested frontier-model \
       --context _memory/work/goals/demo/spawns/02-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 02 --report _memory/work/goals/demo/spawns/02-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] \
     && grep -qF -- 'report_chars: 40 · io_est_tokens: 60 · work_read_chars: n/a · work_est_tokens: n/a · running io: 100 · running work: 3000' "$log"; then
    report PASS "[$label] (ii) report without Footprint → work n/a, running work unchanged"
  else
    report FAIL "[$label] (ii) n/a Footprint" "rc=$rc out='$out'"
  fi

  # (iii) 100 + 0 with --work-chars 400 → T=25, W=100, running io 125, running work 3100
  "$@" spawn --goal demo --agent implementer --phase "P4" --model-requested light-model \
       --context _memory/work/goals/demo/spawns/03-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 03 --report _memory/work/goals/demo/spawns/03-report.md \
        --verdict PASS --model-reported X --work-chars 400 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] \
     && grep -qF -- 'io_est_tokens: 25 · work_read_chars: 400 · work_est_tokens: 100 · running io: 125 · running work: 3100' "$log"; then
    report PASS "[$label] (iii) --work-chars 400 → work_est_tokens: 100 · running work: 3100"
  else
    report FAIL "[$label] (iii) --work-chars override" "rc=$rc out='$out'"
  fi

  # (iv) --work-chars 4x0 → exit 2, nothing appended
  "$@" spawn --goal demo --agent implementer --phase "P4" --model-requested light-model \
       --context _memory/work/goals/demo/spawns/04-context.md >/dev/null 2>&1
  lines_before="$(wc -l < "$log" | tr -d ' ')"
  out="$("$@" outcome --goal demo --spawn 04 --report _memory/work/goals/demo/spawns/04-report.md \
        --verdict PASS --model-reported X --work-chars 4x0 2>/dev/null)"; rc=$?
  lines_after="$(wc -l < "$log" | tr -d ' ')"
  if [[ $rc -eq 2 && "$lines_after" == "$lines_before" ]] \
     && ! grep -qF -- '- OUTCOME [#04]:' "$log"; then
    report PASS "[$label] (iv) --work-chars 4x0 → exit 2, nothing appended"
  else
    report FAIL "[$label] (iv) invalid --work-chars" "rc=$rc lines $lines_before->$lines_after out='$out'"
  fi
  WORK_LOG="$log"

  # (v) pre-v0.26 log seeded with running total: 85 (no running io)
  local fx2 log2
  fx2="$(alloc_fx)"
  mkdir -p "$fx2/_memory/work/goals/demo/spawns"
  head -c 100 /dev/zero | tr '\0' 'x' > "$fx2/_memory/work/goals/demo/spawns/02-context.md"
  : > "$fx2/_memory/work/goals/demo/spawns/02-report.md"
  printf '%s\n' \
    '# Orchestration Log — demo' \
    '' \
    'Append-only spawn ledger. Running est_tokens total (proxy, chars/4): see latest entry.' \
    '' \
    '---' \
    '' \
    '### 2026-09-01T12:00-04:00 — SPAWN implementer (P4) [#01]' \
    '- agent: implementer · model requested: light-model' \
    '- why: —' \
    '- writes claim: none' \
    '- expected output: —' \
    '- context: _memory/work/goals/demo/spawns/01-context.md · context_chars: 101' \
    '- OUTCOME [#01]: PASS · model reported: X · report: _memory/work/goals/demo/spawns/01-report.md · report_chars: 40 · est_tokens: 35 · running total: 85' \
    > "$fx2/_memory/work/goals/demo/orchestration-log.md"
  cd "$fx2" || return 1
  log2="$fx2/_memory/work/goals/demo/orchestration-log.md"
  "$@" spawn --goal demo --agent evaluator --phase "P4" --model-requested frontier-model \
       --context _memory/work/goals/demo/spawns/02-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 02 --report _memory/work/goals/demo/spawns/02-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] \
     && grep -qF -- 'io_est_tokens: 25 · work_read_chars: n/a · work_est_tokens: n/a · running io: 110 · running work: 0' "$log2"; then
    report PASS "[$label] (v) pre-v0.26 running total: 85 fallback → running io: 110 (85+T) · running work: 0"
  else
    report FAIL "[$label] (v) pre-v0.26 fallback" "rc=$rc out='$out'"
  fi
  FALLBACK_LOG="$log2"
}

# empty --root guard (spawn / outcome / note); rc 0 guard holds, 1 guard missing
assert_empty_root_sub() {
  local sub="$1"; shift
  local d rc out files_before files_after log
  d="$(mktemp -d "$FIXTURE_TMPDIR/emptyroot.XXXXXX")" || return 2
  assert_fixture_root "$d" || return 2
  mkdir -p "$d/_memory/work/goals/demo/spawns"
  head -c 10 /dev/zero | tr '\0' 'a' > "$d/_memory/work/goals/demo/spawns/01-context.md"
  head -c 5 /dev/zero | tr '\0' 'b' > "$d/_memory/work/goals/demo/spawns/01-report.md"
  log="$d/_memory/work/goals/demo/orchestration-log.md"
  files_before="$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
  set +e
  out="$( ( cd "$d" && bash "$BIN" "$sub" "$@" --root "" 2>&1 ) )"
  rc=$?
  files_after="$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$rc" -eq 2 ]] && grep -qF -- '--root needs a directory' <<<"$out" \
     && [[ "$files_before" -eq "$files_after" ]] && [[ ! -f "$log" ]]; then
    return 0
  fi
  return 1
}

log_spawn_mut_empty_root() {
  local canon_rc mut_rc d out mutsh changed
  d="$(mktemp -d "$FIXTURE_TMPDIR/emptyrootmut.XXXXXX")" || return 2
  assert_fixture_root "$d" || return 2
  mkdir -p "$d/_memory/work/goals/x"
  mutsh="$(mktemp "${TMPDIR:-/tmp}/logspawnmut.XXXXXX")"
  sed '/die 2 "--root needs a directory"/d' "$CANON_SH" > "$mutsh"
  chmod +x "$mutsh"
  changed="$(diff -u "$CANON_SH" "$mutsh" 2>/dev/null | tail -n +3 | grep -c '^-' || true)"
  if [[ "$changed" -ne 1 ]]; then
    rm -f "$mutsh"
    return 2
  fi
  if ! bash -n "$mutsh" 2>/dev/null; then
    rm -f "$mutsh"
    return 2
  fi
  set +e
  out="$( ( cd "$d" && bash "$CANON_SH" note --goal x --text t --root "" 2>&1 ) )"
  canon_rc=$?
  out="$( ( cd "$d" && bash "$mutsh" note --goal x --text t --root "" 2>&1 ) )"
  mut_rc=$?
  rm -f "$mutsh"
  [[ "$canon_rc" -eq 2 ]] || return 1
  [[ "$mut_rc" -eq 4 ]] || return 1
  return 0
}

# ---------------------------------------------------------------------------
# Behavioral — bash twin
# ---------------------------------------------------------------------------
if bash -n "$BIN" 2>/dev/null; then
  report PASS "bash -n $(basename "$BIN")"
else
  report FAIL "bash -n $(basename "$BIN")"
fi

if assert_empty_root_sub spawn --goal demo --agent e --phase p --model-requested m \
     --context _memory/work/goals/demo/spawns/01-context.md; then
  report PASS "empty --root spawn → exit 2, stderr names --root, no orchestration-log.md"
else
  report FAIL "empty --root spawn guard"
fi
if assert_empty_root_sub outcome --goal demo --spawn 01 \
     --report _memory/work/goals/demo/spawns/01-report.md --verdict PASS --model-reported m; then
  report PASS "empty --root outcome → exit 2, stderr names --root, no orchestration-log.md"
else
  report FAIL "empty --root outcome guard"
fi
if assert_empty_root_sub note --goal demo --text hi; then
  report PASS "empty --root note → exit 2, stderr names --root, no orchestration-log.md"
else
  report FAIL "empty --root note guard"
fi
if log_spawn_mut_empty_root; then
  report PASS "mutation empty-root: canonical exit 2, mutant exit 4 (sed removed exactly 1 line)"
else
  report FAIL "mutation empty-root guard"
fi

run_suite bash bash "$BIN"
run_work_suite bash bash "$BIN"

# ---------------------------------------------------------------------------
# model_check — match / MISMATCH / unverified / openai family (log-spawn emitter)
# ---------------------------------------------------------------------------
run_model_check_case() { # <label> <runner...>
  local label="$1"; shift
  local fx log out rc err spawn_line
  fx="$(alloc_fx)"
  mkdir -p "$fx/_memory/work/goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_memory/work/goals/demo/spawns/05-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_memory/work/goals/demo/spawns/05-report.md"
  log="$fx/_memory/work/goals/demo/orchestration-log.md"
  cd "$fx" || return 1

  # match (openai: gpt-… requested, o3 reported)
  "$@" spawn --goal demo --agent implementer --phase P4 --model-requested gpt-4.1-mini \
       --context _memory/work/goals/demo/spawns/05-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 05 --report _memory/work/goals/demo/spawns/05-report.md \
        --verdict PASS --model-reported o3 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$out" == *'model_check: match'* ]]; then
    report PASS "[$label] model_check match (gpt-4.1-mini vs o3, exit 0)"
  else
    report FAIL "[$label] model_check match" "rc=$rc out='$out'"
  fi

  # MISMATCH + stderr warning, exit 0
  fx="$(alloc_fx)"
  mkdir -p "$fx/_memory/work/goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_memory/work/goals/demo/spawns/06-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_memory/work/goals/demo/spawns/06-report.md"
  log="$fx/_memory/work/goals/demo/orchestration-log.md"
  cd "$fx" || return 1
  "$@" spawn --goal demo --agent implementer --phase P4 --model-requested claude-sonnet-5-5 \
       --context _memory/work/goals/demo/spawns/06-context.md >/dev/null 2>&1
  err="$("$@" outcome --goal demo --spawn 06 --report _memory/work/goals/demo/spawns/06-report.md \
        --verdict PASS --model-reported gpt-4.1 2>&1 >/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$err" == *'log-spawn: MODEL-FAMILY-MISMATCH requested=claude-sonnet-5-5 reported=gpt-4.1'* ]] \
     && grep -qF 'model_check: MISMATCH' "$log"; then
    report PASS "[$label] model_check MISMATCH → stderr warning, exit 0"
  else
    report FAIL "[$label] model_check MISMATCH" "rc=$rc err='$err'"
  fi

  # blank requested id → unverified
  fx="$(alloc_fx)"
  mkdir -p "$fx/_memory/work/goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_memory/work/goals/demo/spawns/07-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_memory/work/goals/demo/spawns/07-report.md"
  log="$fx/_memory/work/goals/demo/orchestration-log.md"
  cd "$fx" || return 1
  "$@" spawn --goal demo --agent implementer --phase P4 --model-requested " " \
       --context _memory/work/goals/demo/spawns/07-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 07 --report _memory/work/goals/demo/spawns/07-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$out" == *'model_check: unverified'* ]]; then
    report PASS "[$label] blank model-requested → model_check: unverified, exit 0"
  else
    report FAIL "[$label] blank model-requested" "rc=$rc out='$out'"
  fi

  # missing model requested bullet → unverified
  fx="$(alloc_fx)"
  mkdir -p "$fx/_memory/work/goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_memory/work/goals/demo/spawns/08-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_memory/work/goals/demo/spawns/08-report.md"
  log="$fx/_memory/work/goals/demo/orchestration-log.md"
  printf '%s\n' \
    '# Orchestration Log — demo' '' \
    'Append-only spawn ledger. Running io_est_tokens (orchestrator I/O proxy, chars/4) and work_est_tokens (subagent self-reported footprint /4): see latest entry.' \
    '' '---' '' \
    '### 2026-09-01T12:00-04:00 — SPAWN implementer (P4) [#08]' \
    '- agent: implementer' \
    '- context: _memory/work/goals/demo/spawns/08-context.md · context_chars: 20' \
    > "$log"
  cd "$fx" || return 1
  out="$("$@" outcome --goal demo --spawn 08 --report _memory/work/goals/demo/spawns/08-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$out" == *'model_check: unverified'* ]]; then
    report PASS "[$label] missing model requested bullet → model_check: unverified, exit 0"
  else
    report FAIL "[$label] missing model requested bullet" "rc=$rc out='$out'"
  fi
}

run_model_check_case bash bash "$BIN"

# ---------------------------------------------------------------------------
# model-reported self (degraded mode) → unverified even when spawn pinned a model id
# ---------------------------------------------------------------------------
run_model_reported_self_case() { # <label> <runner...>
  local label="$1"; shift
  local fx log out rc
  fx="$(alloc_fx)"
  mkdir -p "$fx/_memory/work/goals/demo/spawns"
  head -c 20 /dev/zero | tr '\0' 'a' > "$fx/_memory/work/goals/demo/spawns/09-context.md"
  head -c 10 /dev/zero | tr '\0' 'b' > "$fx/_memory/work/goals/demo/spawns/09-report.md"
  log="$fx/_memory/work/goals/demo/orchestration-log.md"
  cd "$fx" || return 1
  "$@" spawn --goal demo --agent implementer --phase P4 --model-requested claude-opus-5-5-high \
       --context _memory/work/goals/demo/spawns/09-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 09 --report _memory/work/goals/demo/spawns/09-report.md \
        --verdict PASS --model-reported self 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] \
     && grep -qF 'model reported: self · model_check: unverified' "$log" \
     && [[ "$out" == *'model reported: self · model_check: unverified'* ]]; then
    report PASS "[$label] model-reported self vs pinned request → model_check: unverified (degraded ledger)"
  else
    report FAIL "[$label] model-reported self vs pinned request" "rc=$rc out='$out' log=$(grep OUTCOME "$log" | tail -1)"
  fi
}

run_model_reported_self_case bash bash "$BIN"

# ---------------------------------------------------------------------------
# keys — KEYS / REPEAT lines computed from a report's `### Required fixes` items
# ---------------------------------------------------------------------------
KEYS_G="_memory/work/goals/demo"

make_keys_fixture() { # → fixture dir whose log already holds SPAWN headings [#01]..[#15]
  local d i nn
  d="$(alloc_fx)"
  mkdir -p "$d/$KEYS_G/spawns"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    nn="$(printf '%02d' "$i")"
    printf 'ctx %s\n' "$nn" > "$d/$KEYS_G/spawns/$nn-context.md"
    bash "$BIN" spawn --root "$d" --goal demo --agent evaluator --phase P4 \
      --model-requested m --context "$KEYS_G/spawns/$nn-context.md" >/dev/null 2>&1
  done
  printf '%s' "$d"
}

kreport() { # <fx> <name> <report lines…>
  local fx="$1" name="$2"; shift 2
  printf '%s\n' "$@" > "$fx/$KEYS_G/spawns/$name"
}

kkeys() { # <fx> <spawn> <task> <report-name> → K_OUT / K_RC / K_ERR
  local fx="$1" sp="$2" tk="$3" rp="$4"
  K_OUT="$(bash "$BIN" keys --root "$fx" --goal demo --spawn "$sp" --task "$tk" \
    --report "$KEYS_G/spawns/$rp" 2>"$fx/k.err")"; K_RC=$?
  K_ERR="$(cat "$fx/k.err")"
}

run_keys_cases() {
  local fx log want wk wr codes nlog rc lines_a lines_b d
  fx="$(make_keys_fixture)"
  log="$fx/$KEYS_G/orchestration-log.md"
  krepeats() { grep -c '^- REPEAT ' "$log" || true; }

  # Two evaluations of one task: the structural AC2 item repeats → exactly one REPEAT.
  kreport "$fx" r1.md '## Verdict' 'NEEDS FIXES' '' '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC2 `src/a.sh:12-14`: missing guard — add the check [structural]' \
    '- [ ] AC1 `b.sh:3`: wrong exit — replace `1` with `2` [line-patch]' \
    '' '### Notes (non-blocking)' '- [ ] AC9 `z.sh`: a note, not a required fix — ignore [structural]'
  kkeys "$fx" 01 01 r1.md
  wk='- KEYS [#01] task 01: ac2 src/a.sh :: missing guard [structural] [-] | ac1 b.sh :: wrong exit [line-patch] [-]'
  if [[ $K_RC -eq 0 && "$K_OUT" == "$wk" ]] && grep -qxF -- "$wk" "$log" && [[ "$(krepeats)" == 0 ]]; then
    report PASS "keys: first evaluation → one KEYS line (stdout = that line), items only from ### Required fixes, no REPEAT"
  else
    report FAIL "keys: first evaluation" "rc=$K_RC out='$K_OUT' err='$K_ERR'"
  fi
  kreport "$fx" r2.md '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC2 `src/a.sh:20`: missing guard — add the check, sharper wording [structural] [carried]' \
    '- [ ] F6 `c.sh`: dangling reference — fix the link — missed earlier: the fix added it [line-patch] [new]'
  kkeys "$fx" 02 01 r2.md
  wk='- KEYS [#02] task 01: ac2 src/a.sh :: missing guard [structural] [carried] | f6 c.sh :: dangling reference [line-patch] [new]'
  wr='- REPEAT [#02] task 01: ac2 src/a.sh :: missing guard [structural] [carried]'
  if [[ $K_RC -eq 0 ]] && grep -qxF -- "$wk" "$log" && grep -qxF -- "$wr" "$log" && [[ "$(krepeats)" == 1 ]]; then
    report PASS "keys: two-evaluation sequence → exactly one REPEAT, key 'ac2 src/a.sh :: missing guard' with [structural]"
  else
    report FAIL "keys: two-evaluation sequence" "rc=$K_RC repeats=$(krepeats) err='$K_ERR'"
  fi

  # Repeated [line-patch] item (task 02): REPEAT carries [line-patch]; task 01's earlier key is not compared.
  kreport "$fx" r3.md '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC1 `b.sh:3`: wrong exit — replace `1` with `2` [line-patch]'
  kreport "$fx" r4.md '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC1 `b.sh:5`: wrong exit — replace `1` with `2` [line-patch] [carried]'
  kkeys "$fx" 03 02 r3.md; rc=$K_RC
  kkeys "$fx" 04 02 r4.md
  wr='- REPEAT [#04] task 02: ac1 b.sh :: wrong exit [line-patch] [carried]'
  if [[ $rc -eq 0 && $K_RC -eq 0 ]] && grep -qxF -- "$wr" "$log" && [[ "$(krepeats)" == 2 ]]; then
    report PASS "keys: repeated [line-patch] item → REPEAT carries [line-patch] (and only the same --task value is compared)"
  else
    report FAIL "keys: repeated line-patch" "rc=$rc/$K_RC repeats=$(krepeats) err='$K_ERR'"
  fi

  # none: heading present with no items, and no section at all.
  kreport "$fx" r5.md '## Verdict' 'NEEDS FIXES' '' '### Required fixes (if NEEDS FIXES)' '' \
    '### Notes (non-blocking)' '- [ ] AC1 `q.sh`: only under Notes — x [structural]'
  kreport "$fx" r6.md '## Verdict' 'PASS'
  kkeys "$fx" 05 03 r5.md; rc=$K_RC
  kkeys "$fx" 06 03 r6.md
  if [[ $rc -eq 0 && $K_RC -eq 0 ]] && grep -qxF -- '- KEYS [#05] task 03: none' "$log" \
     && grep -qxF -- '- KEYS [#06] task 03: none' "$log" && [[ "$(krepeats)" == 2 ]]; then
    report PASS "keys: no required-fix items (empty section or no section) → '- KEYS [#NN] task 03: none', no REPEAT"
  else
    report FAIL "keys: none" "rc=$rc/$K_RC"
  fi

  # Line-number / anchor stripping: a.sh:12, a.sh:3-5, a.sh#L7, a.sh#L7-L9 and bare a.sh key the same.
  kreport "$fx" r7.md '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC1 `a.sh:12`: same defect — fix [structural]' \
    '- [ ] AC1 `a.sh:3-5`: same defect — fix [structural]' \
    '- [ ] AC1 `a.sh#L7`: same defect — fix [structural]' \
    '- [ ] AC1 `a.sh#L7-L9`: same defect — fix [structural]' \
    '- [ ] AC1 `a.sh`: same defect — fix [structural]'
  kkeys "$fx" 07 04 r7.md
  if [[ $K_RC -eq 0 && "$(grep -oF 'ac1 a.sh :: same defect [structural] [-]' <<<"$K_OUT" | wc -l | tr -d ' ')" == 5 ]]; then
    report PASS "keys: a.sh:12, a.sh:3-5, a.sh#L7, a.sh#L7-L9 and a.sh all key 'ac1 a.sh :: same defect'"
  else
    report FAIL "keys: line stripping" "rc=$K_RC out='$K_OUT'"
  fi

  # Justification clause / tags excluded; case + whitespace collapsed; '|' → '/'; no ' — ' and no-span forms.
  kreport "$fx" r8.md '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC3 `x.sh:1`: Mixed   CASE  defect — fix it — missed earlier: because [structural] [new]' \
    '- [ ] AC4 `y.sh:2`: left | right  — fix — reverses cycle 2: - [ ] AC4 `y.sh:2`: other [structural] [new]' \
    '- [ ] AC5 `z.sh:9`: no dash text [structural] [carried]' \
    '- [ ] AC6 plain defect with no span [line-patch]'
  kkeys "$fx" 08 05 r8.md
  wk='- KEYS [#08] task 05: ac3 x.sh :: mixed case defect [structural] [new] | ac4 y.sh :: left / right [structural] [new] | ac5 z.sh :: no dash text [structural] [carried] | ac6 - :: plain defect with no span [line-patch] [-]'
  if [[ $K_RC -eq 0 && "$K_OUT" == "$wk" ]] && [[ "$K_OUT" != *'missed earlier'* && "$K_OUT" != *'reverses cycle'* ]]; then
    report PASS "keys: justification clause excluded; lower-cased, whitespace collapsed, '|' → '/'; no-dash and no-span items key whole text"
  else
    report FAIL "keys: justification / normalization" "rc=$K_RC out='$K_OUT'"
  fi

  # Missing tags print '-'; tags are read from the item's own line only (wrapped item under-fires safely).
  kreport "$fx" r9.md '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC1 `a.sh:1`: no tags — fix' \
    '- [ ] AC2 `a.sh:1`: only kind — fix [structural]' \
    '- [ ] AC3 `a.sh:1`: only provenance — fix [new]' \
    '- [ ] AC4 `w.sh:4`: wrapped item — a fix that is long and' \
    '  wraps onto a second line [structural]'
  kkeys "$fx" 09 06 r9.md
  wk='- KEYS [#09] task 06: ac1 a.sh :: no tags [-] [-] | ac2 a.sh :: only kind [structural] [-] | ac3 a.sh :: only provenance [-] [new] | ac4 w.sh :: wrapped item [-] [-]'
  if [[ $K_RC -eq 0 && "$K_OUT" == "$wk" ]]; then
    report PASS "keys: absent kind/provenance print [-]; a wrapped item keys its first line only"
  else
    report FAIL "keys: missing tags / wrapped item" "rc=$K_RC out='$K_OUT'"
  fi

  # --task audit and 09a; a 09 call never compares against 09a's line.
  kreport "$fx" r10.md '### Required fixes (if NEEDS FIXES)' '- [ ] AC1 `a.sh:2`: audit defect — fix [structural]'
  kkeys "$fx" 10 audit r10.md; codes="$K_RC "
  kkeys "$fx" 11 audit r10.md; codes+="$K_RC "
  kkeys "$fx" 12 09a r10.md; codes+="$K_RC "
  kkeys "$fx" 13 09a r10.md; codes+="$K_RC "
  kkeys "$fx" 14 09 r10.md; codes+="$K_RC"
  if [[ "$codes" == "0 0 0 0 0" ]] \
     && grep -qxF -- '- KEYS [#10] task audit: ac1 a.sh :: audit defect [structural] [-]' "$log" \
     && grep -qxF -- '- REPEAT [#11] task audit: ac1 a.sh :: audit defect [structural] [-]' "$log" \
     && grep -qxF -- '- KEYS [#12] task 09a: ac1 a.sh :: audit defect [structural] [-]' "$log" \
     && grep -qxF -- '- REPEAT [#13] task 09a: ac1 a.sh :: audit defect [structural] [-]' "$log" \
     && grep -qxF -- '- KEYS [#14] task 09: ac1 a.sh :: audit defect [structural] [-]' "$log" \
     && ! grep -q '^- REPEAT \[#14\]' "$log" && [[ "$(krepeats)" == 4 ]]; then
    report PASS "keys: --task audit and 09a accepted; REPEAT compares the same --task value only (09 ≠ 09a, audit ≠ NN)"
  else
    report FAIL "keys: audit / 09a task values" "codes='$codes' repeats=$(krepeats)"
  fi

  # Ledger integrity (exit 3): duplicate KEYS for the spawn number, missing SPAWN heading, missing log.
  lines_a="$(wc -l < "$log" | tr -d ' ')"
  kkeys "$fx" 01 01 r1.md; rc=$K_RC; d="$K_ERR"
  kkeys "$fx" 99 01 r1.md
  lines_b="$(wc -l < "$log" | tr -d ' ')"
  if [[ $rc -eq 3 && $K_RC -eq 3 && "$lines_a" == "$lines_b" ]] \
     && [[ "$d" == *'KEYS [#01] already present'* && "$K_ERR" == *'SPAWN [#99] not found'* ]]; then
    report PASS "keys: duplicate KEYS for a spawn number → exit 3; missing SPAWN [#NN] heading → exit 3; nothing appended"
  else
    report FAIL "keys: integrity exit 3" "rc=$rc/$K_RC lines $lines_a->$lines_b d='$d' err='$K_ERR'"
  fi
  bash "$BIN" note --root "$fx" --goal demo --text 'see - KEYS [#15] discussion' >/dev/null 2>&1
  kkeys "$fx" 15 07 r1.md
  if [[ $K_RC -eq 0 ]] && grep -qxF -- '- KEYS [#15] task 07: ac2 src/a.sh :: missing guard [structural] [-] | ac1 b.sh :: wrong exit [line-patch] [-]' "$log"; then
    report PASS "keys: duplicate check is anchored — free text mentioning '- KEYS [#15] ' does not block spawn 15"
  else
    report FAIL "keys: anchored duplicate check" "rc=$K_RC err='$K_ERR'"
  fi
  d="$(alloc_fx)"
  mkdir -p "$d/$KEYS_G/spawns"
  printf '%s\n' '### Required fixes' '- [ ] AC1 `a.sh`: x — y [structural]' > "$d/$KEYS_G/spawns/r.md"
  bash "$BIN" keys --root "$d" --goal demo --spawn 01 --task 01 --report "$KEYS_G/spawns/r.md" >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 3 && ! -f "$d/$KEYS_G/orchestration-log.md" ]]; then
    report PASS "keys: no orchestration log → exit 3, no log created"
  else
    report FAIL "keys: missing log" "rc=$rc"
  fi

  # Usage (2) and path (4) errors in the frozen order: flags → paths → integrity; nothing appended.
  lines_a="$(wc -l < "$log" | tr -d ' ')"
  codes=""
  kc() { bash "$BIN" keys --root "$fx" "$@" >/dev/null 2>&1; codes+="$? "; }
  R="$KEYS_G/spawns/r1.md"
  kc --goal demo --spawn 03 --report "$R"
  kc --goal demo --task 01 --report "$R"
  kc --goal demo --spawn 03 --task 01
  kc --goal demo --spawn 3 --task 01 --report "$R"
  kc --goal demo --spawn ab --task 01 --report "$R"
  kc --goal demo --spawn 03 --task 9 --report "$R"
  kc --goal demo --spawn 03 --task 009 --report "$R"
  kc --goal demo --spawn 03 --task AUDIT --report "$R"
  kc --goal demo --spawn 03 --task 09A --report "$R"
  kc --goal demo --spawn 03 --task 09ab --report "$R"
  kc --goal demo --spawn 03 --task 01 --report "$R" --bogus x
  kc --goal demo --spawn 03 --task 9 --report "$KEYS_G/spawns/missing.md"
  kc --goal demo --spawn 03 --task 01 --report "$KEYS_G/spawns/missing.md"
  kc --goal nope --spawn 03 --task 01 --report "$R"
  kc --goal demo --spawn 99 --task 01 --report "$KEYS_G/spawns/missing.md"
  codes="${codes% }"
  lines_b="$(wc -l < "$log" | tr -d ' ')"
  want="2 2 2 2 2 2 2 2 2 2 2 2 4 4 4"
  if [[ "$codes" == "$want" && "$lines_a" == "$lines_b" ]]; then
    report PASS "keys: exit 2 (missing flag, bad --spawn, bad --task, unknown flag; before paths) and exit 4 (missing report / goal; before integrity); nothing appended"
  else
    report FAIL "keys: exit 2 / 4" "got '$codes' want '$want' lines $lines_a->$lines_b"
  fi
}

run_keys_cases

# KEYS / REPEAT lines quote report text, so they must never feed outcome's running totals.
keys_running_totals_case() {
  local fx log out
  fx="$(make_keys_fixture)"
  log="$fx/$KEYS_G/orchestration-log.md"
  printf 'rrrrrrrrr' > "$fx/$KEYS_G/spawns/01-report.md"   # 9 bytes: floor((7 + 9) / 4) = 4
  printf 'rrrrrrrrr' > "$fx/$KEYS_G/spawns/03-report.md"
  bash "$BIN" outcome --root "$fx" --goal demo --spawn 01 --report "$KEYS_G/spawns/01-report.md" \
    --verdict PASS --model-reported X >/dev/null 2>&1
  kreport "$fx" r.md '### Required fixes (if NEEDS FIXES)' \
    '- [ ] AC1 `log.md`: quotes running io: 999 and running work: 888 — fix [structural]'
  kkeys "$fx" 02 01 r.md
  out="$(bash "$BIN" outcome --root "$fx" --goal demo --spawn 03 --report "$KEYS_G/spawns/03-report.md" \
        --verdict PASS --model-reported X 2>/dev/null)"
  if [[ $K_RC -eq 0 && "$out" == *'io_est_tokens: 4 · work_read_chars: n/a · work_est_tokens: n/a · running io: 8 · running work: 0' ]]; then
    report PASS "keys: KEYS text quoting 'running io: 999' never feeds outcome's running totals (running io: 8)"
  else
    report FAIL "keys: running totals unaffected" "rc=$K_RC out='$out'"
  fi
}
keys_running_totals_case

# spawn / outcome / note output is unchanged: the whole log matches a literal (timestamps normalized).
unchanged_output_case() {
  local fx log exp
  fx="$(make_fixture)"
  log="$fx/_memory/work/goals/demo/orchestration-log.md"
  exp="$FIXTURE_TMPDIR/expected-log.md"
  cat > "$exp" <<'EOF'
# Orchestration Log — demo

Append-only spawn ledger. Running io_est_tokens (orchestrator I/O proxy, chars/4) and work_est_tokens (subagent self-reported footprint /4): see latest entry.

---

### TS — SPAWN implementer (P4) [#01]
- agent: implementer · model requested: light-model
- why: —
- writes claim: none
- expected output: —
- context: _memory/work/goals/demo/spawns/01-context.md · context_chars: 101
- OUTCOME [#01]: PASS · model reported: X · model_check: unverified · report: _memory/work/goals/demo/spawns/01-report.md · report_chars: 40 · io_est_tokens: 35 · work_read_chars: n/a · work_est_tokens: n/a · running io: 35 · running work: 0

### TS — Phase 4 complete
EOF
  ( cd "$fx" \
    && bash "$BIN" spawn --goal demo --agent implementer --phase P4 --model-requested light-model \
         --context _memory/work/goals/demo/spawns/01-context.md >/dev/null 2>&1 \
    && bash "$BIN" outcome --goal demo --spawn 01 --report _memory/work/goals/demo/spawns/01-report.md \
         --verdict PASS --model-reported X >/dev/null 2>&1 \
    && bash "$BIN" note --goal demo --text "Phase 4 complete" >/dev/null 2>&1 )
  if sed -E "$TS_RE" "$log" | cmp -s - "$exp"; then
    report PASS "spawn / outcome / note log output byte-identical to the pre-keys literal"
  else
    report FAIL "spawn / outcome / note output changed" "$(sed -E "$TS_RE" "$log" | diff - "$exp" | head -n 6)"
  fi
}
unchanged_output_case

# --task belongs to keys alone: spawn / outcome / note keep rejecting it as an unknown flag.
task_flag_rejected_case() {
  local fx log codes errs lines_a lines_b err
  fx="$(make_fixture)"
  log="$fx/_memory/work/goals/demo/orchestration-log.md"
  bash "$BIN" spawn --root "$fx" --goal demo --agent implementer --phase P4 --model-requested m \
    --context _memory/work/goals/demo/spawns/01-context.md >/dev/null 2>&1
  lines_a="$(wc -l < "$log" | tr -d ' ')"
  codes=""; errs=""
  err="$(bash "$BIN" note --root "$fx" --goal demo --text x --task 01 2>&1 >/dev/null)"; codes+="$? "; errs+="$err"$'\n'
  err="$(bash "$BIN" spawn --root "$fx" --goal demo --agent e --phase p --model-requested m \
    --context _memory/work/goals/demo/spawns/02-context.md --task 01 2>&1 >/dev/null)"; codes+="$? "; errs+="$err"$'\n'
  err="$(bash "$BIN" outcome --root "$fx" --goal demo --spawn 01 \
    --report _memory/work/goals/demo/spawns/01-report.md --verdict PASS --model-reported X --task 01 2>&1 >/dev/null)"; codes+="$? "; errs+="$err"$'\n'
  err="$(bash "$BIN" note --root "$fx" --goal demo --text x --task 2>&1 >/dev/null)"; codes+="$?"; errs+="$err"
  lines_b="$(wc -l < "$log" | tr -d ' ')"
  if [[ "$codes" == "2 2 2 2" && "$lines_a" == "$lines_b" ]] \
     && [[ "$errs" == *"unknown flag '--task' for 'note'"* && "$errs" == *"unknown flag '--task' for 'spawn'"* \
           && "$errs" == *"unknown flag '--task' for 'outcome'"* ]]; then
    report PASS "--task on note / spawn / outcome → exit 2, stderr names --task (unknown flag), nothing appended"
  else
    report FAIL "--task rejected outside keys" "codes='$codes' lines $lines_a->$lines_b errs='$errs'"
  fi
}
task_flag_rejected_case

if grep -qF 'log-spawn.sh keys' "$BIN" && grep -qF 'bad --task' "$BIN" \
   && grep -qF 'KEYS \[#NN\] ' "$BIN"; then
  report PASS "header documents keys (flags, KEYS/REPEAT lines, exit codes incl. duplicate KEYS)"
else
  report FAIL "header documents keys"
fi

# ---------------------------------------------------------------------------
# Structural wiring
# ---------------------------------------------------------------------------
for em in claude-code cursor copilot codex; do
  f="$REPO_ROOT/skills/agent-kit/emitters/$em.md"
  if grep -qF '_kit/log-spawn.sh' "$f" && grep -qF '_kit/log-spawn.cmd' "$f" \
     && ! grep -qF '_kit/log-spawn.ps1' "$f"; then
    report PASS "emitter $em.md emits _kit/log-spawn.sh + .cmd (no .ps1)"
  else
    report FAIL "emitter $em.md missing _kit/log-spawn row"
  fi
done

for f in skills/agent-kit/templates/skills/feature/SKILL.template.md skills/agent-kit/templates/ORCHESTRATION.md; do
  cf="$REPO_ROOT/$f"
  if grep -qF '_kit/log-spawn' "$cf" && grep -qF 'spawns/' "$cf"; then
    report PASS "canonical $f references _kit/log-spawn + spawns/"
  else
    report FAIL "canonical $f lacks _kit/log-spawn or spawns/"
  fi
done

for f in .claude/skills/feature/SKILL.md .cursor/skills/feature/SKILL.md .claude/ORCHESTRATION.md .cursor/ORCHESTRATION.md; do
  inst="$REPO_ROOT/$f"
  if [[ ! -f "$inst" ]]; then
    report SKIP "instance $f" "absent"
  elif grep -qF '_kit/log-spawn' "$inst" && grep -qF 'spawns/' "$inst"; then
    report PASS "instance $f references _kit/log-spawn + spawns/"
  else
    report FAIL "instance $f lacks _kit/log-spawn or spawns/"
  fi
done

if [[ -f "$REPO_ROOT/orchestration-kit.manifest.json" ]]; then
  if grep -qF '"_kit/log-spawn.sh"' "$REPO_ROOT/orchestration-kit.manifest.json" \
     && grep -qF '"_kit/log-spawn.cmd"' "$REPO_ROOT/orchestration-kit.manifest.json" \
     && ! grep -qF '"_kit/log-spawn.ps1"' "$REPO_ROOT/orchestration-kit.manifest.json"; then
    report PASS "manifest keys _kit/log-spawn.sh + .cmd present (no .ps1)"
  else
    report FAIL "manifest missing _kit/log-spawn keys"
  fi
else
  report SKIP "manifest _kit keys" "orchestration-kit.manifest.json absent"
fi

if [[ -f "$REPO_ROOT/_kit/log-spawn.sh" && -f "$REPO_ROOT/_kit/log-spawn.cmd" && ! -f "$REPO_ROOT/_kit/log-spawn.ps1" ]]; then
  if cmp -s "$REPO_ROOT/_kit/log-spawn.sh" "$CANON_SH" \
     && cmp -s "$REPO_ROOT/_kit/log-spawn.cmd" "$LAUNCHER_CMD"; then
    report PASS "instance _kit/log-spawn.sh + .cmd byte-identical to canonical"
  else
    report FAIL "instance _kit/log-spawn.sh/.cmd differs from canonical"
  fi
else
  report SKIP "instance _kit/log-spawn.sh/.cmd" "absent or stale .ps1 present"
fi

if ! grep -q '{{' "$CANON_SH"; then
  report PASS "canonical log-spawn.sh contains no template tokens"
else
  report FAIL "canonical log-spawn.sh contains '{{'"
fi

# Upgrade prune: stale _kit/log-spawn.ps1 from a prior manifest is removed.
upgrade_prune_logspawn_ps1() {
  local root mf out pruned
  command -v jq >/dev/null 2>&1 || return 2
  root="$(alloc_fx)"
  mf="$root/orchestration-kit.manifest.json"
  cp "$REPO_ROOT/tests/agent-kit/fixtures/self-answers.json" "$root/.answers.json"
  run_emit_sh() {
    assert_fixture_root "$root" || return 1
    bash "$REPO_ROOT/skills/agent-kit/bin/emit.sh" --root "$root" --kit "$REPO_ROOT/skills/agent-kit" "$@"
  }
  run_emit_sh --answers "$root/.answers.json" >/dev/null 2>&1 || return 1
  mf="$root/orchestration-kit.manifest.json"
  printf 'stale ps1 twin\n' > "$root/_kit/log-spawn.ps1"
  pruned="$(sha256sum "$root/_kit/log-spawn.ps1" | awk '{print $1}')"
  jq --arg h "$pruned" '.files["_kit/log-spawn.ps1"]=$h' "$mf" > "${mf}.tmp" && mv "${mf}.tmp" "$mf"
  out="$(run_emit_sh --upgrade 2>&1)" || return 1
  grep -qE '· pruned [1-9][0-9]* ·' <<<"$out" || return 1
  [[ ! -f "$root/_kit/log-spawn.ps1" ]] || return 1
  rm -rf "$root"
}
if ! command -v jq >/dev/null 2>&1; then
  report SKIP "upgrade prune log-spawn.ps1" "jq not on PATH"
elif upgrade_prune_logspawn_ps1; then
  report PASS "upgrade prunes stale _kit/log-spawn.ps1 (stdout prune count ≥ 1)"
else
  report FAIL "upgrade prune stale _kit/log-spawn.ps1"
fi

echo
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if [[ $fail -eq 0 ]]; then echo "RESULT: all assertions passed"; exit 0; fi
echo "RESULT: $fail assertion(s) FAILED"; exit 1
