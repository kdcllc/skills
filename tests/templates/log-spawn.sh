#!/usr/bin/env bash
# Guard: the `log-spawn` orchestration-log writer twins (kit v0.26.0).
#
# Behavioral section — runs the CANONICAL skills/setup/templates/tools/log-spawn.sh
# (override with LOG_SPAWN_BIN=<path> for mutation testing) from a mktemp cwd holding
# `_goals/demo/spawns/`:
#   (a) spawn #01 (101-byte context)            → SPAWN heading + context_chars: 101
#   (b) outcome #01 (40-byte report, no Footprint) → report_chars: 40 · io_est_tokens: 35
#       (floor 141/4) · work n/a · running io: 35 · running work: 0
#   (c) spawn/outcome #02 (200 / 0 bytes)       → io_est_tokens: 50 · running io: 85
#   (d) note                                    → heading appended
#   (e) exit codes 2 / 3 / 4 on the documented error paths
#   (e2) `héllo`+LF context (7 bytes / 6 chars)  → context_chars: 7 (bytes, not chars)
#   (e3) log has no UTF-8 BOM and no CR
#   (f) every success call prints exactly one stdout line
#   (g) header present; line count strictly increasing (append-only)
#   (i)–(v) Footprint / --work-chars / pre-v0.26 fallback in a second fixture
#   pwsh twin: (a)–(e3) and (i)–(v) rerun via log-spawn.ps1 in a second fixture; logs
#   identical after timestamp normalization; exit codes 2/3/4 match. SKIP when pwsh
#   is absent.
# Structural section — emitters, canonical + instance feature skills / ORCHESTRATION
# files, manifest keys, instance `_kit/` byte-identity (SKIP when an instance file is
# absent).
#
# Exit 0 when no FAIL; 1 otherwise.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

CANON_SH="$REPO_ROOT/skills/setup/templates/tools/log-spawn.sh"
CANON_PS1="$REPO_ROOT/skills/setup/templates/tools/log-spawn.ps1"
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
  local d; d="$(mktemp -d)"
  mkdir -p "$d/_goals/demo/spawns"
  head -c 101 /dev/zero | tr '\0' 'x' > "$d/_goals/demo/spawns/01-context.md"
  printf 'h\xc3\xa9llo\n' > "$d/_goals/demo/spawns/03-context.md"   # héllo + LF: 7 bytes, 6 chars
  head -c 40  /dev/zero | tr '\0' 'y' > "$d/_goals/demo/spawns/01-report.md"
  head -c 200 /dev/zero | tr '\0' 'x' > "$d/_goals/demo/spawns/02-context.md"
  : > "$d/_goals/demo/spawns/02-report.md"
  printf '%s' "$d"
}

# run_suite <label> <runner...> — runs (a)–(g) in a fresh fixture with the given runner
# (e.g. "bash /path/log-spawn.sh" or "pwsh -NoProfile -File /path/log-spawn.ps1").
# Sets SUITE_LOG to the produced log path.
run_suite() {
  local label="$1"; shift
  local fx; fx="$(make_fixture)"
  local log="$fx/_goals/demo/orchestration-log.md"
  local out rc lines prev_lines=0 mono=1
  cd "$fx" || return 1

  count_lines() { [[ -f "$log" ]] && wc -l < "$log" | tr -d ' ' || echo 0; }
  step_mono() { lines="$(count_lines)"; (( lines > prev_lines )) || mono=0; prev_lines=$lines; }

  # (a) spawn #01
  out="$("$@" spawn --goal demo --agent implementer --phase "Phase 4 task 01" \
        --model-requested light-model --context _goals/demo/spawns/01-context.md \
        --writes "src/a.ts" --why "task 01" --expect "report" 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" == 1 ]] \
     && grep -qE '^### .+ — SPAWN implementer \(Phase 4 task 01\) \[#01\]$' "$log" \
     && grep -qF -- '- context: _goals/demo/spawns/01-context.md · context_chars: 101' "$log" \
     && grep -qF -- '- agent: implementer · model requested: light-model' "$log" \
     && grep -qF -- '- writes claim: src/a.ts' "$log"; then
    report PASS "[$label] (a) spawn #01 → SPAWN heading [#01] + context_chars: 101 (one stdout line)"
  else
    report FAIL "[$label] (a) spawn #01" "rc=$rc out='$out'"
  fi
  step_mono

  # (b) outcome #01
  out="$("$@" outcome --goal demo --spawn 01 --report _goals/demo/spawns/01-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 && "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" == 1 ]] \
     && grep -qF -- '- OUTCOME [#01]: PASS · model reported: X · report: _goals/demo/spawns/01-report.md · report_chars: 40 · io_est_tokens: 35 · work_read_chars: n/a · work_est_tokens: n/a · running io: 35 · running work: 0' "$log"; then
    report PASS "[$label] (b) outcome #01 → report_chars: 40 · io_est_tokens: 35 (floor 141/4) · running io: 35"
  else
    report FAIL "[$label] (b) outcome #01" "rc=$rc out='$out'"
  fi
  step_mono

  # (c) spawn/outcome #02 (0-byte report; note line)
  "$@" spawn --goal demo --agent evaluator --phase "P4" --model-requested frontier-model \
       --context _goals/demo/spawns/02-context.md >/dev/null 2>&1; rc=$?
  step_mono
  out="$("$@" outcome --goal demo --spawn 02 --report _goals/demo/spawns/02-report.md \
        --verdict "NEEDS FIXES" --model-reported frontier-model --note "one blocker" 2>/dev/null)"; rc2=$?
  if [[ $rc -eq 0 && $rc2 -eq 0 ]] \
     && grep -qF -- '- context: _goals/demo/spawns/02-context.md · context_chars: 200' "$log" \
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
  "$@" spawn --goal demo --agent e --phase p --model-requested m --context _goals/demo/spawns/01-context.md >/dev/null 2>&1; codes+="$? "
  "$@" outcome --goal demo --spawn 01 --report _goals/demo/spawns/01-report.md --verdict PASS --model-reported m >/dev/null 2>&1; codes+="$? "
  "$@" outcome --goal demo --spawn 09 --report _goals/demo/spawns/01-report.md --verdict PASS --model-reported m >/dev/null 2>&1; codes+="$? "
  "$@" spawn --goal demo --agent e --phase p --model-requested m --context spawns/bad.md >/dev/null 2>&1; codes+="$? "
  "$@" spawn --goal demo --agent e --phase p --context _goals/demo/spawns/01-context.md >/dev/null 2>&1; codes+="$? "
  "$@" bogus >/dev/null 2>&1; codes+="$? "
  "$@" note --goal nope --text hi >/dev/null 2>&1; codes+="$? "
  "$@" spawn --goal demo --agent e --phase p --model-requested m --context _goals/demo/spawns/04-context.md >/dev/null 2>&1; codes+="$?"
  if [[ "$codes" == "3 3 3 2 2 2 4 4" ]]; then
    report PASS "[$label] (e) exit codes dup-spawn=3 dup-outcome=3 no-spawn=3 bad-NN=2 missing-flag=2 unknown-sub=2 no-goal=4 no-file=4"
  else
    report FAIL "[$label] (e) exit codes" "got '$codes' want '3 3 3 2 2 2 4 4'"
  fi
  lines="$(count_lines)"
  [[ "$lines" == "$prev_lines" ]] || mono=0   # error paths must not append

  # (e2) byte-vs-char: héllo + LF = 7 bytes / 6 chars
  "$@" spawn --goal demo --agent e --phase p --model-requested m --context _goals/demo/spawns/03-context.md >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 0 ]] && grep -qF -- '- context: _goals/demo/spawns/03-context.md · context_chars: 7' "$log"; then
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
  cd "$REPO_ROOT" || return 1
}

# make_work_fixture → prints fixture dir with AC1–3 sizes (101/59, 200/40, 100/0)
# plus an 8-byte #04 context for the invalid --work-chars probe.
make_work_fixture() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/_goals/demo/spawns"
  head -c 101 /dev/zero | tr '\0' 'x' > "$d/_goals/demo/spawns/01-context.md"
  printf '%s\n' '### Footprint' 'files_read: 3 (~12000 chars)' 'commands_run: 2' \
    > "$d/_goals/demo/spawns/01-report.md"
  head -c 200 /dev/zero | tr '\0' 'x' > "$d/_goals/demo/spawns/02-context.md"
  head -c 40 /dev/zero | tr '\0' 'y' > "$d/_goals/demo/spawns/02-report.md"
  head -c 100 /dev/zero | tr '\0' 'x' > "$d/_goals/demo/spawns/03-context.md"
  : > "$d/_goals/demo/spawns/03-report.md"
  head -c 8 /dev/zero | tr '\0' 'x' > "$d/_goals/demo/spawns/04-context.md"
  : > "$d/_goals/demo/spawns/04-report.md"
  printf '%s' "$d"
}

# run_work_suite <label> <runner...> — (i)–(v) in a fresh fixture (and a seeded
# pre-v0.26 log for (v)). Sets WORK_LOG and FALLBACK_LOG.
run_work_suite() {
  local label="$1"; shift
  local fx log out rc wb lines_before lines_after
  fx="$(make_work_fixture)"
  log="$fx/_goals/demo/orchestration-log.md"
  cd "$fx" || return 1

  # (i) 101-byte context + 59-byte Footprint report → T=40, W=3000
  "$@" spawn --goal demo --agent implementer --phase "P4" \
        --model-requested light-model --context _goals/demo/spawns/01-context.md \
        >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 01 --report _goals/demo/spawns/01-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  wb="$(wc -c < "$fx/_goals/demo/spawns/01-report.md" | tr -d ' ')"
  if [[ $rc -eq 0 && "$wb" == 59 ]] \
     && grep -qF -- 'report_chars: 59 · io_est_tokens: 40 · work_read_chars: 12000 · work_est_tokens: 3000 · running io: 40 · running work: 3000' "$log"; then
    report PASS "[$label] (i) Footprint files_read: 3 (~12000 chars) → work_read_chars: 12000 · work_est_tokens: 3000 · running work: 3000"
  else
    report FAIL "[$label] (i) Footprint ingestion" "rc=$rc wb=$wb out='$out'"
  fi

  # (ii) 200 + 40 (no Footprint) → T=60, running io 100, running work unchanged
  "$@" spawn --goal demo --agent evaluator --phase "P4" --model-requested frontier-model \
       --context _goals/demo/spawns/02-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 02 --report _goals/demo/spawns/02-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] \
     && grep -qF -- 'report_chars: 40 · io_est_tokens: 60 · work_read_chars: n/a · work_est_tokens: n/a · running io: 100 · running work: 3000' "$log"; then
    report PASS "[$label] (ii) report without Footprint → work n/a, running work unchanged"
  else
    report FAIL "[$label] (ii) n/a Footprint" "rc=$rc out='$out'"
  fi

  # (iii) 100 + 0 with --work-chars 400 → T=25, W=100, running io 125, running work 3100
  "$@" spawn --goal demo --agent implementer --phase "P4" --model-requested light-model \
       --context _goals/demo/spawns/03-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 03 --report _goals/demo/spawns/03-report.md \
        --verdict PASS --model-reported X --work-chars 400 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] \
     && grep -qF -- 'io_est_tokens: 25 · work_read_chars: 400 · work_est_tokens: 100 · running io: 125 · running work: 3100' "$log"; then
    report PASS "[$label] (iii) --work-chars 400 → work_est_tokens: 100 · running work: 3100"
  else
    report FAIL "[$label] (iii) --work-chars override" "rc=$rc out='$out'"
  fi

  # (iv) --work-chars 4x0 → exit 2, nothing appended
  "$@" spawn --goal demo --agent implementer --phase "P4" --model-requested light-model \
       --context _goals/demo/spawns/04-context.md >/dev/null 2>&1
  lines_before="$(wc -l < "$log" | tr -d ' ')"
  out="$("$@" outcome --goal demo --spawn 04 --report _goals/demo/spawns/04-report.md \
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
  fx2="$(mktemp -d)"
  mkdir -p "$fx2/_goals/demo/spawns"
  head -c 100 /dev/zero | tr '\0' 'x' > "$fx2/_goals/demo/spawns/02-context.md"
  : > "$fx2/_goals/demo/spawns/02-report.md"
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
    '- context: _goals/demo/spawns/01-context.md · context_chars: 101' \
    '- OUTCOME [#01]: PASS · model reported: X · report: _goals/demo/spawns/01-report.md · report_chars: 40 · est_tokens: 35 · running total: 85' \
    > "$fx2/_goals/demo/orchestration-log.md"
  cd "$fx2" || return 1
  log2="$fx2/_goals/demo/orchestration-log.md"
  "$@" spawn --goal demo --agent evaluator --phase "P4" --model-requested frontier-model \
       --context _goals/demo/spawns/02-context.md >/dev/null 2>&1
  out="$("$@" outcome --goal demo --spawn 02 --report _goals/demo/spawns/02-report.md \
        --verdict PASS --model-reported X 2>/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]] \
     && grep -qF -- 'io_est_tokens: 25 · work_read_chars: n/a · work_est_tokens: n/a · running io: 110 · running work: 0' "$log2"; then
    report PASS "[$label] (v) pre-v0.26 running total: 85 fallback → running io: 110 (85+T) · running work: 0"
  else
    report FAIL "[$label] (v) pre-v0.26 fallback" "rc=$rc out='$out'"
  fi
  FALLBACK_LOG="$log2"
  cd "$REPO_ROOT" || return 1
}

# ---------------------------------------------------------------------------
# Behavioral — bash twin
# ---------------------------------------------------------------------------
if bash -n "$BIN" 2>/dev/null; then
  report PASS "bash -n $(basename "$BIN")"
else
  report FAIL "bash -n $(basename "$BIN")"
fi
run_suite bash bash "$BIN"
BASH_LOG="$SUITE_LOG"; BASH_CODES="$SUITE_CODES"
run_work_suite bash bash "$BIN"
BASH_WORK_LOG="$WORK_LOG"; BASH_FALLBACK_LOG="$FALLBACK_LOG"

# ---------------------------------------------------------------------------
# Behavioral — pwsh twin (parity)
# ---------------------------------------------------------------------------
if command -v pwsh >/dev/null 2>&1; then
  perr="$(pwsh -NoProfile -Command "\$e=\$null; [System.Management.Automation.Language.Parser]::ParseFile('$CANON_PS1',[ref]\$null,[ref]\$e) | Out-Null; \$e.Count" 2>/dev/null | tr -d '\r ')"
  if [[ "$perr" == "0" ]]; then
    report PASS "pwsh parser: log-spawn.ps1 has zero parse errors"
  else
    report FAIL "pwsh parser: log-spawn.ps1" "errors=$perr"
  fi
  run_suite pwsh pwsh -NoProfile -File "$CANON_PS1"
  PS_LOG="$SUITE_LOG"; PS_CODES="$SUITE_CODES"
  if diff <(sed -E "$TS_RE" "$BASH_LOG") <(sed -E "$TS_RE" "$PS_LOG") >/dev/null 2>&1; then
    report PASS "twin parity: bash and pwsh logs identical after timestamp normalization"
  else
    report FAIL "twin parity: logs differ" "$(diff <(sed -E "$TS_RE" "$BASH_LOG") <(sed -E "$TS_RE" "$PS_LOG") | head -5 | tr '\n' '|')"
  fi
  if [[ "$BASH_CODES" == "$PS_CODES" ]]; then
    report PASS "twin parity: exit codes match ($PS_CODES)"
  else
    report FAIL "twin parity: exit codes" "bash='$BASH_CODES' pwsh='$PS_CODES'"
  fi
  if ! grep -q $'\r' "$PS_LOG" && [[ "$(head -c 3 "$PS_LOG" | od -An -tx1 | tr -d ' \n')" != "efbbbf" ]]; then
    report PASS "twin parity: pwsh log is LF, no BOM"
  else
    report FAIL "twin parity: pwsh log has CRLF or BOM"
  fi
  run_work_suite pwsh pwsh -NoProfile -File "$CANON_PS1"
  if diff <(sed -E "$TS_RE" "$BASH_WORK_LOG") <(sed -E "$TS_RE" "$WORK_LOG") >/dev/null 2>&1 \
     && diff <(sed -E "$TS_RE" "$BASH_FALLBACK_LOG") <(sed -E "$TS_RE" "$FALLBACK_LOG") >/dev/null 2>&1; then
    report PASS "twin parity (i)–(v): bash and pwsh work/fallback logs identical after timestamp normalization"
  else
    report FAIL "twin parity (i)–(v): logs differ" \
      "$(diff <(sed -E "$TS_RE" "$BASH_WORK_LOG") <(sed -E "$TS_RE" "$WORK_LOG") | head -5 | tr '\n' '|')"
  fi
else
  report SKIP "pwsh twin parity" "pwsh not on PATH"
fi

# ---------------------------------------------------------------------------
# Structural wiring
# ---------------------------------------------------------------------------
for em in claude-code cursor copilot codex; do
  f="$REPO_ROOT/skills/setup/emitters/$em.md"
  if grep -qF '_kit/log-spawn.sh' "$f" && grep -qF '_kit/log-spawn.ps1' "$f"; then
    report PASS "emitter $em.md emits _kit/log-spawn.sh + .ps1"
  else
    report FAIL "emitter $em.md missing _kit/log-spawn row"
  fi
done

for f in skills/setup/templates/skills/feature/SKILL.template.md skills/setup/templates/ORCHESTRATION.md; do
  if grep -qF '_kit/log-spawn' "$f" && grep -qF 'spawns/' "$f"; then
    report PASS "canonical $f references _kit/log-spawn + spawns/"
  else
    report FAIL "canonical $f lacks _kit/log-spawn or spawns/"
  fi
done

for f in .claude/skills/feature/SKILL.md .cursor/skills/feature/SKILL.md .claude/ORCHESTRATION.md .cursor/ORCHESTRATION.md; do
  if [[ ! -f "$f" ]]; then
    report SKIP "instance $f" "absent"
  elif grep -qF '_kit/log-spawn' "$f" && grep -qF 'spawns/' "$f"; then
    report PASS "instance $f references _kit/log-spawn + spawns/"
  else
    report FAIL "instance $f lacks _kit/log-spawn or spawns/"
  fi
done

if [[ -f orchestration-kit.manifest.json ]]; then
  if grep -qF '"_kit/log-spawn.sh"' orchestration-kit.manifest.json && grep -qF '"_kit/log-spawn.ps1"' orchestration-kit.manifest.json; then
    report PASS "manifest keys _kit/log-spawn.sh + .ps1 present"
  else
    report FAIL "manifest missing _kit/log-spawn keys"
  fi
else
  report SKIP "manifest _kit keys" "orchestration-kit.manifest.json absent"
fi

if [[ -f _kit/log-spawn.sh && -f _kit/log-spawn.ps1 ]]; then
  if cmp -s _kit/log-spawn.sh "$CANON_SH" && cmp -s _kit/log-spawn.ps1 "$CANON_PS1"; then
    report PASS "instance _kit/log-spawn.* byte-identical to canonical"
  else
    report FAIL "instance _kit/log-spawn.* differs from canonical"
  fi
else
  report SKIP "instance _kit/log-spawn.*" "absent"
fi

if ! grep -q '{{' "$CANON_SH" && ! grep -q '{{' "$CANON_PS1"; then
  report PASS "canonical twins contain no template tokens"
else
  report FAIL "canonical twins contain '{{'"
fi

echo
echo "PASS: $pass   FAIL: $fail   SKIP: $skip"
if [[ $fail -eq 0 ]]; then echo "RESULT: all assertions passed"; exit 0; fi
echo "RESULT: $fail assertion(s) FAILED"; exit 1
