#!/usr/bin/env bash
# Deterministic behavioral test harness for the AI Orchestration Kit's loop /
# breaker / checks tooling (tracked repo tooling — test-ladder rung 3
# territory, run manually or in CI; NOT wired as a manifest-emitted instance
# file). Persisted from the story-002/006/007 session scratchpad harness.
# Exercises:
#   - the canonical breaker.sh state machine (assertions 1-12, 11b, 11c) with
#     injected timestamps -- no wall-clock reads;
#   - the LIVE detect_rate_limit function extracted verbatim from canonical
#     loop.sh (assertions 13-14, 13b, 13c), so the detector under test is the
#     real, perf-fixed (two-stage grep) function, not a reimplementation;
#   - a CB1 carve-out end-to-end stub run of the RE-EMITTED instance
#     _loop/loop.sh + _loop/breaker.sh inside a throwaway git repo (assertion
#     15) — requires the repo's own self-install (_loop/) to exist;
#   - T1a/T1b PowerShell structural guards, A1-A3 emitter/SKILL text coverage,
#     the story-006 T2a herestring SIGPIPE regression + its pre-fix control
#     (assertions 16-19-ish);
#   - story-007 additions: checks J (manifest hash join, self-excluding,
#     seed-aware) and K (ownership-contract shape) mutation-proven via the
#     CHECKS_MANIFEST override and copy-based grep replication; the task-02
#     pristine-clause literal tripwire; and a frozen TMPDIR characterization
#     of the herestring sentinel check under an unwritable TMPDIR.
#
# Every assertion is outcome-verifying: it inspects the resulting state file /
# stdout / stderr / exit code and FAILs loudly (non-zero exit, explicit FAIL
# line) if behavior regresses. No network, no external services. Mutations
# run ONLY on copies under this run's mktemp workdir -- repo files (including
# .claude/checks.sh and the task template) are never written to.
set -u

# ---------------------------------------------------------------------------
# Repo-root auto-detection, relative to this script's own location (works
# from any cwd, any clone path -- no hardcoded absolute paths).
# ---------------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# ---------------------------------------------------------------------------
# Top guard: this harness re-emits/inspects the self-install under _loop/. A
# fresh clone (or the canonical templates repo itself, pre-/setup) has none --
# SKIP cleanly rather than failing on a precondition the harness cannot meet.
# ---------------------------------------------------------------------------
if [[ ! -f "$REPO_ROOT/_loop/loop.sh" ]]; then
  echo "SKIP: harness requires a self-install; run /setup first"
  exit 0
fi

BREAKER_SH="$REPO_ROOT/skills/setup/templates/loop/breaker.sh"
LOOP_SH="$REPO_ROOT/skills/setup/templates/loop/loop.sh"
INSTANCE_LOOP_SH="$REPO_ROOT/_loop/loop.sh"
INSTANCE_LOOP_PS1="$REPO_ROOT/_loop/loop.ps1"
INSTANCE_BREAKER_SH="$REPO_ROOT/_loop/breaker.sh"
INSTANCE_PROMPT_MD="$REPO_ROOT/_loop/PROMPT.md"
SETUP_SKILL_MD="$REPO_ROOT/skills/setup/SKILL.md"
CURSOR_MD="$REPO_ROOT/skills/setup/emitters/cursor.md"
CLAUDE_CODE_MD="$REPO_ROOT/skills/setup/emitters/claude-code.md"
CODEX_MD="$REPO_ROOT/skills/setup/emitters/codex.md"
COPILOT_MD="$REPO_ROOT/skills/setup/emitters/copilot.md"
CHECKS_SH="$REPO_ROOT/.claude/checks.sh"
TASK_TPL="$REPO_ROOT/skills/setup/templates/skills/feature/templates/task.md"
CRITERIA_TPL="$REPO_ROOT/skills/setup/templates/skills/goal-criteria/SKILL.md"
MANIFEST_JSON="$REPO_ROOT/orchestration-kit.manifest.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail_count=0
pass_count=0

report() { # report <PASS|FAIL> <name> [detail]
  local status="$1" name="$2" detail="${3:-}"
  if [[ "$status" == "PASS" ]]; then
    pass_count=$((pass_count + 1))
    echo "PASS: $name"
  else
    fail_count=$((fail_count + 1))
    echo "FAIL: $name${detail:+ -- $detail}" >&2
  fi
}

# shellcheck source=/dev/null
source "$BREAKER_SH"

# ---------------------------------------------------------------------------
# Assertions 1-10: sequential state-machine scenario over one state file, chain
# of four models so index-advance (8) and chain-end (9) are distinguishable.
# ---------------------------------------------------------------------------
CHAIN="modelA,modelB,modelC,modelD"
S1="$TMP/scenario.json"

# 1. fresh-create -> CLOSED, chain seeded, currentModel=chain[0]
[[ -f "$S1" ]] && rm -f "$S1"
breaker_load "$S1" "$CHAIN"
state="$(_breaker_get "$S1" state)"; chain="$(_breaker_get "$S1" chain)"
model="$(_breaker_get "$S1" currentModel)"
if [[ "$state" == "CLOSED" && "$chain" == "$CHAIN" && "$model" == "modelA" ]]; then
  report PASS "1: fresh-create seeds CLOSED/chain/currentModel"
else
  report FAIL "1: fresh-create seeds CLOSED/chain/currentModel" "state=$state chain=$chain model=$model"
fi

# 2. CLOSED+success -> no-op (file byte-unchanged)
sum_before="$(sha256sum "$S1" | cut -d' ' -f1)"
breaker_record "$S1" 0 1000
sum_after="$(sha256sum "$S1" | cut -d' ' -f1)"
if [[ "$sum_before" == "$sum_after" ]]; then
  report PASS "2: CLOSED+success is a no-op (file byte-unchanged)"
else
  report FAIL "2: CLOSED+success is a no-op (file byte-unchanged)" "checksum changed"
fi

# 3. CLOSED+RL -> OPEN, index 1, model=chain[1], openedAt set, totalFallbacks=1
T0=1000000
breaker_record "$S1" 1 "$T0"
state="$(_breaker_get "$S1" state)"; idx="$(_breaker_get "$S1" fallbackIndex)"
model="$(_breaker_get "$S1" currentModel)"; opened="$(_breaker_get "$S1" openedAt)"
fb="$(_breaker_get "$S1" totalFallbacks)"
if [[ "$state" == "OPEN" && "$idx" == "1" && "$model" == "modelB" && "$opened" == "$T0" && "$fb" == "1" ]]; then
  report PASS "3: CLOSED+RL -> OPEN, index 1, modelB, openedAt, totalFallbacks=1"
else
  report FAIL "3: CLOSED+RL -> OPEN, index 1, modelB, openedAt, totalFallbacks=1" \
    "state=$state idx=$idx model=$model opened=$opened fb=$fb"
fi

# 4. OPEN, now<openedAt+600 -> should_skip echoes remaining, state still OPEN
remaining="$(breaker_should_skip "$S1" $((T0 + 100)))"
state="$(_breaker_get "$S1" state)"
if [[ "$remaining" == "500" && "$state" == "OPEN" ]]; then
  report PASS "4: OPEN + cooldown not elapsed -> echoes remaining, stays OPEN"
else
  report FAIL "4: OPEN + cooldown not elapsed -> echoes remaining, stays OPEN" "remaining=$remaining state=$state"
fi

# 5. clamp guard: now far BEFORE openedAt (backward clock skew) -> remaining
#    clamped to [0, cooldownSeconds]; state unaffected (still OPEN, openedAt
#    unchanged) since remaining>0 never transitions.
remaining="$(breaker_should_skip "$S1" $((T0 - 10000)))"
state="$(_breaker_get "$S1" state)"; opened="$(_breaker_get "$S1" openedAt)"
if [[ "$remaining" -ge 0 && "$remaining" -le 600 && "$remaining" == "600" \
      && "$state" == "OPEN" && "$opened" == "$T0" ]]; then
  report PASS "5: clamp guard on backward clock skew (remaining clamped to 600)"
else
  report FAIL "5: clamp guard on backward clock skew (remaining clamped to 600)" \
    "remaining=$remaining state=$state opened=$opened"
fi

# 6. OPEN, now>=openedAt+600 -> HALF-OPEN, successes=0
remaining="$(breaker_should_skip "$S1" $((T0 + 600)))"
state="$(_breaker_get "$S1" state)"; half="$(_breaker_get "$S1" halfOpenSuccesses)"
if [[ "$remaining" == "0" && "$state" == "HALF-OPEN" && "$half" == "0" ]]; then
  report PASS "6: OPEN + cooldown elapsed -> HALF-OPEN, successes=0"
else
  report FAIL "6: OPEN + cooldown elapsed -> HALF-OPEN, successes=0" "remaining=$remaining state=$state half=$half"
fi

# 7. HALF-OPEN+success x1 -> HALF-OPEN(1); x2 -> CLOSED, counters reset, totalRecoveries=1
breaker_record "$S1" 0 $((T0 + 601))
state="$(_breaker_get "$S1" state)"; half="$(_breaker_get "$S1" halfOpenSuccesses)"
if [[ "$state" == "HALF-OPEN" && "$half" == "1" ]]; then
  report PASS "7a: HALF-OPEN + 1st success -> HALF-OPEN(1)"
else
  report FAIL "7a: HALF-OPEN + 1st success -> HALF-OPEN(1)" "state=$state half=$half"
fi
breaker_record "$S1" 0 $((T0 + 602))
state="$(_breaker_get "$S1" state)"; half="$(_breaker_get "$S1" halfOpenSuccesses)"
opened="$(_breaker_get "$S1" openedAt)"; rec="$(_breaker_get "$S1" totalRecoveries)"
if [[ "$state" == "CLOSED" && "$half" == "0" && "$opened" == "0" && "$rec" == "1" ]]; then
  report PASS "7b: HALF-OPEN + 2nd success -> CLOSED, counters reset, totalRecoveries=1"
else
  report FAIL "7b: HALF-OPEN + 2nd success -> CLOSED, counters reset, totalRecoveries=1" \
    "state=$state half=$half opened=$opened rec=$rec"
fi

# Re-trip to get back to HALF-OPEN with a distinct index/model, so assertion 8
# (HALF-OPEN+RL) exercises a genuine mid-chain index-advance, not chain-end.
T1=2000000
breaker_record "$S1" 1 "$T1"   # CLOSED+RL -> OPEN, index 1->2, modelC, totalFallbacks=2
idx="$(_breaker_get "$S1" fallbackIndex)"; model="$(_breaker_get "$S1" currentModel)"
fb="$(_breaker_get "$S1" totalFallbacks)"
if [[ "$idx" == "2" && "$model" == "modelC" && "$fb" == "2" ]]; then
  report PASS "3b (re-trip): CLOSED+RL advances index 1->2 (modelC), totalFallbacks=2"
else
  report FAIL "3b (re-trip): CLOSED+RL advances index 1->2 (modelC), totalFallbacks=2" "idx=$idx model=$model fb=$fb"
fi
breaker_should_skip "$S1" $((T1 + 600)) >/dev/null   # -> HALF-OPEN

# 8. HALF-OPEN+RL -> OPEN again, index advances (2->3, modelC->modelD)
breaker_record "$S1" 1 $((T1 + 700))
state="$(_breaker_get "$S1" state)"; idx="$(_breaker_get "$S1" fallbackIndex)"
model="$(_breaker_get "$S1" currentModel)"; opened="$(_breaker_get "$S1" openedAt)"
if [[ "$state" == "OPEN" && "$idx" == "3" && "$model" == "modelD" && "$opened" == "$((T1 + 700))" ]]; then
  report PASS "8: HALF-OPEN+RL -> OPEN again, index advances (2->3, modelD)"
else
  report FAIL "8: HALF-OPEN+RL -> OPEN again, index advances (2->3, modelD)" \
    "state=$state idx=$idx model=$model opened=$opened"
fi

# 9. chain end: further trips -> currentModel="" (omit-pin), NO index overflow.
# Chain has 4 entries (indices 0-3); we are already at index 3 (the last).
breaker_should_skip "$S1" $((T1 + 700 + 600)) >/dev/null   # -> HALF-OPEN
breaker_record "$S1" 1 $((T1 + 1400))                       # HALF-OPEN+RL at chain end
state="$(_breaker_get "$S1" state)"; idx="$(_breaker_get "$S1" fallbackIndex)"
model="$(_breaker_get "$S1" currentModel)"
if [[ "$state" == "OPEN" && "$idx" == "3" && "$model" == "" ]]; then
  report PASS "9a: chain-end trip -> currentModel empty, index does not overflow (stays 3)"
else
  report FAIL "9a: chain-end trip -> currentModel empty, index does not overflow (stays 3)" \
    "state=$state idx=$idx model='$model'"
fi
# repeat once more to prove idempotence at chain end (no crash, no overflow)
breaker_should_skip "$S1" $((T1 + 1400 + 600)) >/dev/null
breaker_record "$S1" 1 $((T1 + 2000))
idx="$(_breaker_get "$S1" fallbackIndex)"; model="$(_breaker_get "$S1" currentModel)"
if [[ "$idx" == "3" && "$model" == "" ]]; then
  report PASS "9b: repeated chain-end trip stays idempotent (index still 3, model still empty)"
else
  report FAIL "9b: repeated chain-end trip stays idempotent (index still 3, model still empty)" "idx=$idx model='$model'"
fi

# 10. OPEN + record (defensive, bypassing should_skip) -> behaves as HALF-OPEN
#     input + warning line. State is OPEN from assertion 9b's last transition.
state_before="$(_breaker_get "$S1" state)"
half_before="$(_breaker_get "$S1" halfOpenSuccesses)"
stderr_out="$(breaker_record "$S1" 0 $((T1 + 2600)) 2>&1 >/dev/null)"
state="$(_breaker_get "$S1" state)"; half="$(_breaker_get "$S1" halfOpenSuccesses)"
if [[ "$state_before" == "OPEN" && "$stderr_out" == *"breaker_record called while OPEN"* \
      && "$state" == "HALF-OPEN" && "$half" == "$((half_before + 1))" ]]; then
  report PASS "10: OPEN + breaker_record (defensive) -> treated as HALF-OPEN + warning"
else
  report FAIL "10: OPEN + breaker_record (defensive) -> treated as HALF-OPEN + warning" \
    "state_before=$state_before stderr='$stderr_out' state=$state half=$half half_before=$half_before"
fi

# ---------------------------------------------------------------------------
# 11. corrupted JSON (not JSON-like at all) -> fresh CLOSED + stderr warning
# ---------------------------------------------------------------------------
S11="$TMP/corrupted.json"
printf 'not json at all\njust garbage\n' > "$S11"
stderr_out="$(breaker_load "$S11" "$CHAIN" 2>&1 >/dev/null)"
state="$(_breaker_get "$S11" state)"; chain="$(_breaker_get "$S11" chain)"
model="$(_breaker_get "$S11" currentModel)"
if [[ "$state" == "CLOSED" && "$chain" == "$CHAIN" && "$model" == "modelA" \
      && "$stderr_out" == *"unparseable"* ]]; then
  report PASS "11: corrupted (non-JSON) state -> fresh CLOSED + stderr warning"
else
  report FAIL "11: corrupted (non-JSON) state -> fresh CLOSED + stderr warning" \
    "state=$state chain=$chain model=$model stderr='$stderr_out'"
fi

# ---------------------------------------------------------------------------
# 11b (BINDING carry-forward, task-01 judgment): a state file whose STATE
# VALUE carries a leading CR inside the quotes (e.g. "state": "\rCLOSED",) ->
# fresh CLOSED + exactly one stderr warning, wrapped in `timeout 10` as an
# infinite-spin regression guard.
# ---------------------------------------------------------------------------
S11B="$TMP/leading_cr.json"
{
  printf '{\n'
  printf '"state": "\rCLOSED",\n'
  printf '"chain": "%s",\n' "$CHAIN"
  printf '"fallbackIndex": 0,\n'
  printf '"currentModel": "modelA",\n'
  printf '"cooldownSeconds": 600,\n'
  printf '"openedAt": 0,\n'
  printf '"halfOpenSuccesses": 0,\n'
  printf '"totalFallbacks": 0,\n'
  printf '"totalRecoveries": 0\n'
  printf '}\n'
} > "$S11B"

stderr_file="$TMP/11b-stderr.txt"
timeout 10 bash -c "source '$BREAKER_SH'; breaker_load '$S11B' '$CHAIN'" 2>"$stderr_file"
rc=$?
warn_lines=$(wc -l < "$stderr_file")
state="$(_breaker_get "$S11B" state)"
if [[ "$rc" -eq 0 && "$warn_lines" -eq 1 && "$(grep -c "unparseable" "$stderr_file")" -eq 1 \
      && "$state" == "CLOSED" ]]; then
  report PASS "11b: leading-CR corrupted value -> fresh CLOSED + ONE warning, terminates under timeout 10 (infinite-spin regression)"
else
  report FAIL "11b: leading-CR corrupted value -> fresh CLOSED + ONE warning, terminates under timeout 10 (infinite-spin regression)" \
    "rc=$rc warn_lines=$warn_lines state=$state ($( [[ $rc -eq 124 ]] && echo 'TIMED OUT -- infinite spin regressed!'))"
fi

# ---------------------------------------------------------------------------
# 11c (BINDING carry-forward, task-01 judgment): a fully CRLF-normalized but
# otherwise VALID OPEN state file -> VALIDATES and is preserved (state stays
# OPEN), NOT reset. No stderr warning; file byte-unchanged by the load call.
# ---------------------------------------------------------------------------
S11C_LF="$TMP/valid_open_lf.json"
_breaker_write "$S11C_LF" OPEN "$CHAIN" 2 modelC 600 123456 0 1 0
S11C="$TMP/valid_open_crlf.json"
sed 's/$/\r/' "$S11C_LF" > "$S11C"   # normalize every line ending to CRLF

sum_before="$(sha256sum "$S11C" | cut -d' ' -f1)"
stderr_out="$(breaker_load "$S11C" "$CHAIN" 2>&1 >/dev/null)"
sum_after="$(sha256sum "$S11C" | cut -d' ' -f1)"
state="$(_breaker_get "$S11C" state)"
if [[ -z "$stderr_out" && "$state" == "OPEN" && "$sum_before" == "$sum_after" ]]; then
  report PASS "11c: CRLF-normalized VALID OPEN file validates and is preserved (not reset)"
else
  report FAIL "11c: CRLF-normalized VALID OPEN file validates and is preserved (not reset)" \
    "stderr='$stderr_out' state=$state checksum_changed=$([[ "$sum_before" != "$sum_after" ]] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# 12. empty chain -> tracked state, empty model, no crash (record with RL=1
# against a zero-length chain must not index out of bounds).
# ---------------------------------------------------------------------------
S12="$TMP/empty_chain.json"
breaker_load "$S12" ""
state="$(_breaker_get "$S12" state)"; chain="$(_breaker_get "$S12" chain)"
model="$(_breaker_get "$S12" currentModel)"
ok1=0
[[ "$state" == "CLOSED" && "$chain" == "" && "$model" == "" ]] && ok1=1
# no-crash exercise: rate-limit trip against an empty chain. Guarded via an
# if/else (never a bare `set +e`/`set -e` toggle -- errexit is not enabled in
# this script, and flipping it on by mistake would silently abort every
# subsequent assertion, including 15's non-zero-exit-by-design loop.sh run).
if breaker_record "$S12" 1 5000; then rec_rc=0; else rec_rc=$?; fi
state2="$(_breaker_get "$S12" state)"; idx2="$(_breaker_get "$S12" fallbackIndex)"
model2="$(_breaker_get "$S12" currentModel)"
if [[ "$ok1" -eq 1 && "$rec_rc" -eq 0 && "$state2" == "OPEN" && "$idx2" == "0" && "$model2" == "" ]]; then
  report PASS "12: empty chain -> tracked state, empty model, no crash on trip"
else
  report FAIL "12: empty chain -> tracked state, empty model, no crash on trip" \
    "state=$state chain='$chain' model='$model' rec_rc=$rec_rc state2=$state2 idx2=$idx2 model2='$model2'"
fi

# ---------------------------------------------------------------------------
# 13/14: detector -- the LIVE detect_rate_limit function extracted verbatim
# from canonical loop.sh (never a reimplementation), so these assertions test
# the real, perf-fixed (two-stage grep pipeline) detector.
# ---------------------------------------------------------------------------
detector_src="$(sed -n '/^detect_rate_limit() {/,/^}/p' "$LOOP_SH")"
if [[ -z "$detector_src" ]]; then
  report FAIL "13/14 setup: extract detect_rate_limit from canonical loop.sh" "function not found -- loop.sh structure changed?"
else
  eval "$detector_src"

  # 13. Detector positives -> match (exit 0)
  declare -a positives=(
    "HTTP 429 error"
    "Rate limit exceeded"
    "too many requests"
    "quota exceeded"
  )
  pos_ok=1
  for line in "${positives[@]}"; do
    if detect_rate_limit "$line"; then :; else pos_ok=0; report FAIL "13: detector positive" "'$line' did not match"; fi
  done
  ((pos_ok)) && report PASS "13: detector positives all match (HTTP 429 error / Rate limit exceeded / too many requests / quota exceeded)"

  # 14. Detector negatives (mandated) -> no match (exit 1), plus the mandated
  # multi-line negative proving line-orientation (never merges across lines).
  declare -a negatives=(
    "wrote 429 tokens"
    "sha 429abc0"
    "quota of work"
    "429 files changed"
  )
  neg_ok=1
  for line in "${negatives[@]}"; do
    if detect_rate_limit "$line"; then neg_ok=0; report FAIL "14: detector negative" "'$line' incorrectly matched"; fi
  done
  multiline=$'wrote 429 tokens\nerror: build failed'
  if detect_rate_limit "$multiline"; then
    neg_ok=0
    report FAIL "14: multi-line negative (line-orientation proof)" "'429' on one line + 'error' on another falsely matched"
  fi
  ((neg_ok)) && report PASS "14: detector negatives (mandated) all correctly non-matching, incl. multi-line line-orientation proof"
fi

# ---------------------------------------------------------------------------
# 13b (PHASE 5 REMEDIATION, audit-specified blocker): large-capture SIGPIPE
# regression. Under `set -o pipefail`, a `printf | grep -q` pipeline whose
# `grep -q` matches early and exits can SIGPIPE the still-writing producer on
# captures large enough to exceed the pipe buffer; pipefail then reports the
# pipeline's status as the PRODUCER's non-zero (SIGPIPE, 141) rather than the
# grep's own successful 0 -- silently flipping a real match into "no match".
# The fix (herestrings `<<<`, materialized via a temp file with no live
# producer process to SIGPIPE) is re-verified here: the LIVE detector is
# extracted (same $detector_src as 13/14, never a reimplementation) and run
# inside its OWN `bash -euo pipefail` subshell against a >=256KB capture with
# the rate-limit line FIRST -- must detect. A same-scale multi-line negative
# must still correctly report not-detected.
# ---------------------------------------------------------------------------
if [[ -z "$detector_src" ]]; then
  report FAIL "13b: large-capture SIGPIPE regression" "detect_rate_limit extraction failed (see 13/14 setup)"
else
  detect_script="$TMP/13b_detect.sh"
  {
    printf '%s\n' "$detector_src"
    printf '%s\n' 'output="$(cat "$1")"'
    printf '%s\n' 'if detect_rate_limit "$output"; then exit 0; else exit 1; fi'
  } > "$detect_script"

  # >=256KB capture, rate-limit line FIRST (matches the pinned pattern
  # directly), a large volume of filler after it.
  big_capture="$TMP/13b_big_capture.txt"
  {
    printf 'HTTP 429 rate limit exceeded -- please retry later\n'
    for _ in $(seq 1 6000); do
      printf 'filler filler filler filler filler line padding text here\n'
    done
  } > "$big_capture"
  big_size=$(wc -c < "$big_capture")

  if bash -euo pipefail "$detect_script" "$big_capture"; then big_detected=1; else big_detected=0; fi

  # Same-scale multi-line NEGATIVE: "429" recurs on thousands of lines (so the
  # inner grep|grep pipe streams a large volume), but no line ever carries a
  # keyword alongside it, and the lone "error" line at the end never shares a
  # line with "429" -- must still resolve to not-detected.
  big_negative="$TMP/13b_big_negative.txt"
  {
    printf 'wrote 429 tokens\n'
    for _ in $(seq 1 6000); do
      printf '429 noise filler filler filler filler line here\n'
    done
    printf 'error: build failed\n'
  } > "$big_negative"
  neg_size=$(wc -c < "$big_negative")

  if bash -euo pipefail "$detect_script" "$big_negative"; then big_neg_detected=1; else big_neg_detected=0; fi

  if [[ "$big_size" -ge 262144 && "$big_detected" -eq 1 && "$neg_size" -ge 262144 && "$big_neg_detected" -eq 0 ]]; then
    report PASS "13b: large-capture (>=256KB) SIGPIPE regression -- rate-limit-first capture detected (size=${big_size}B), large multi-line negative still not-detected (size=${neg_size}B)"
  else
    report FAIL "13b: large-capture (>=256KB) SIGPIPE regression" \
      "size=$big_size detected=$big_detected neg_size=$neg_size neg_detected=$big_neg_detected"
  fi
fi

# ---------------------------------------------------------------------------
# 13c (REMEDIATION ROUND 2, audit-specified): closes the residual stage-2
# gap flagged after 13b -- stage 2 used to be `grep '429' | grep -q keyword`
# (still a two-process pipe, still SIGPIPE-able under adversarial flooding
# even after 13b's stage-1 herestring fix). Stage 2 is now ONE grep with a
# bidirectional same-line alternation ('429.*(keyword)|(keyword).*429'), no
# inter-grep pipe at all. This mirrors the exact adversarial reproduction
# that previously false-negatived: a >=2MB capture whose EARLY line matches
# stage 2 ONLY (no rate-limit phrasing, so stage 1 can't short-circuit it),
# followed by thousands of "429"-bearing filler lines -- must still detect.
# ---------------------------------------------------------------------------
if [[ -z "$detector_src" ]]; then
  report FAIL "13c: stage-2 large-capture SIGPIPE regression" "detect_rate_limit extraction failed (see 13/14 setup)"
else
  # detect_script (built for 13b, same $detector_src) is reused as-is.
  big2_capture="$TMP/13c_big_capture.txt"
  {
    printf 'HTTP 429 error\n'   # stage-2-ONLY match: no "rate limit"/"too many requests"/"quota" phrasing
    for _ in $(seq 1 50000); do
      printf '429 noise filler filler filler filler line here\n'
    done
  } > "$big2_capture"
  big2_size=$(wc -c < "$big2_capture")

  if bash -euo pipefail "$detect_script" "$big2_capture"; then big2_detected=1; else big2_detected=0; fi

  if [[ "$big2_size" -ge 2097152 && "$big2_detected" -eq 1 ]]; then
    report PASS "13c: stage-2-only large-capture (>=2MB) SIGPIPE regression -- early stage-2-only match detected (size=${big2_size}B), no inter-grep pipe remains"
  else
    report FAIL "13c: stage-2-only large-capture (>=2MB) SIGPIPE regression" "size=$big2_size detected=$big2_detected"
  fi
fi

# ---------------------------------------------------------------------------
# 15. CB1 carve-out stub (SCAFFOLDING, goal-judge note 2): the RE-EMITTED
# instance _loop/loop.sh + _loop/breaker.sh (resolved tokens) copied alongside
# PROMPT.md into a throwaway git-init repo under this run's mktemp workdir. A
# stub CLI always prints a real rate-limit line. max-iterations=4,
# cooldownSeconds=0 via a pre-seeded state file (tiny/instant cooldown --
# fully deterministic, no real sleeps). Verifies the CB1-exempt log line
# appears and the run does NOT exit 2 after 3+ rate-limited passes.
# ---------------------------------------------------------------------------
if [[ ! -f "$INSTANCE_LOOP_SH" || ! -f "$INSTANCE_BREAKER_SH" ]]; then
  report FAIL "15: CB1 carve-out stub" "instance _loop/loop.sh or _loop/breaker.sh missing"
else
  CB1_DIR="$TMP/cb1-repo"
  rm -rf "$CB1_DIR"
  mkdir -p "$CB1_DIR/_loop" "$CB1_DIR/_goals"
  cp "$INSTANCE_LOOP_SH" "$CB1_DIR/_loop/loop.sh"
  cp "$INSTANCE_BREAKER_SH" "$CB1_DIR/_loop/breaker.sh"
  cp "$INSTANCE_PROMPT_MD" "$CB1_DIR/_loop/PROMPT.md"
  chmod +x "$CB1_DIR/_loop/loop.sh"

  cat > "$CB1_DIR/_loop/stub-cli.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Deterministic stub CLI for the CB1 carve-out scaffolding test: always prints
# a real rate-limit line (so the driver's detector fires every iteration) and
# never commits (so every pass is a no-progress pass).
echo "HTTP 429 rate limit exceeded -- please retry later"
exit 0
STUBEOF
  chmod +x "$CB1_DIR/_loop/stub-cli.sh"

  cat > "$CB1_DIR/_goals/breaker-state.json" <<STATEEOF
{
"state": "CLOSED",
"chain": "sonnet",
"fallbackIndex": 0,
"currentModel": "sonnet",
"cooldownSeconds": 0,
"openedAt": 0,
"halfOpenSuccesses": 0,
"totalFallbacks": 0,
"totalRecoveries": 0
}
STATEEOF

  (
    cd "$CB1_DIR" && \
    git init -q && \
    git config user.email test@example.com && \
    git config user.name "cb1-test" && \
    git add -A && \
    git commit -qm init
  )

  cb1_log="$TMP/cb1-run.log"
  (
    cd "$CB1_DIR" && \
    LOOP_CLI="$CB1_DIR/_loop/stub-cli.sh" ./_loop/loop.sh 4
  ) > "$cb1_log" 2>&1
  cb1_status=$?

  exempt_count=$(grep -c "rate-limited pass — CB1 exempt (breaker owns it)" "$cb1_log")
  if [[ "$exempt_count" -ge 3 && "$cb1_status" -ne 2 && "$cb1_status" -eq 1 ]]; then
    report PASS "15: CB1 carve-out stub -- $exempt_count exempt passes logged, exit=$cb1_status (not 2, breaker survives its own cooldown)"
  else
    report FAIL "15: CB1 carve-out stub" "exempt_count=$exempt_count status=$cb1_status (log: $cb1_log)"
    sed 's/^/    /' "$cb1_log" >&2
  fi
fi

# ---------------------------------------------------------------------------
# 16 (T2a regression, story-006 task 03): the LIVE sentinel-check line PLUS
# the SENTINEL='...' assignment, extracted VERBATIM from the RE-EMITTED
# instance _loop/loop.sh (never a reimplementation), wrapped in a minimal
# function. Mirrors 13b's shape: sentinel EARLY in a >=256KB capture, run
# under `bash -euo pipefail` -> must detect. The herestring form has no live
# producer process for a downstream grep match to SIGPIPE, closing the
# false-negative path the piped form (assertion 17) is still exposed to.
# ---------------------------------------------------------------------------
sentinel_line="$(grep -m1 '^SENTINEL=' "$INSTANCE_LOOP_SH" || true)"
sentinel_check_line="$(grep -m1 'grep -qF "\$SENTINEL" <<< "\$output"' "$INSTANCE_LOOP_SH" || true)"

if [[ -z "$sentinel_line" || -z "$sentinel_check_line" ]]; then
  report FAIL "16 setup: extract sentinel line + check line from instance loop.sh" \
    "sentinel_line='$sentinel_line' sentinel_check_line='$sentinel_check_line' -- instance re-emit missing or loop.sh structure changed?"
else
  t2a_script="$TMP/t2a_check.sh"
  cat > "$t2a_script" <<'SCRIPTEOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPTEOF
  printf '%s\n' "$sentinel_line" >> "$t2a_script"
  cat >> "$t2a_script" <<'SCRIPTEOF'
check_sentinel() {
  local output="$1"
SCRIPTEOF
  printf '  %s\n' "$sentinel_check_line" >> "$t2a_script"
  cat >> "$t2a_script" <<'SCRIPTEOF'
    return 0
  else
    return 1
  fi
}
output="$(cat "$1")"
if check_sentinel "$output"; then exit 0; else exit 1; fi
SCRIPTEOF

  # >=256KB capture, sentinel line FIRST, large filler volume after it (mirrors
  # 13b's shape: match up front, huge write still in flight behind it).
  t2a_capture="$TMP/t2a_big_capture.txt"
  {
    printf '<promise>COMPLETE</promise>\n'
    for _ in $(seq 1 4500); do
      printf 'filler filler filler filler filler line padding text here padding more text\n'
    done
  } > "$t2a_capture"
  t2a_size=$(wc -c < "$t2a_capture")

  if bash -euo pipefail "$t2a_script" "$t2a_capture"; then t2a_detected=1; else t2a_detected=0; fi

  if [[ "$t2a_size" -ge 262144 && "$t2a_detected" -eq 1 ]]; then
    report PASS "16: T2a regression -- LIVE-extracted herestring sentinel check detects sentinel early in >=256KB capture (size=${t2a_size}B) under bash -euo pipefail"
  else
    report FAIL "16: T2a regression" "size=$t2a_size detected=$t2a_detected"
  fi

  # -------------------------------------------------------------------------
  # 17 (T2a PRE-FIX CONTROL, story-006 task 03): the OLD piped form
  # (`printf '%s' "$output" | grep -qF "$SENTINEL"`) against the IDENTICAL
  # capture used in 16 must FALSE-NEGATIVE under pipefail -- the downstream
  # grep's early match SIGPIPEs the still-writing printf producer, and
  # pipefail then reports the pipeline's status as the producer's non-zero
  # (SIGPIPE/141), flipping a real match into "no match". story-006 task 01
  # already demonstrated this deterministically at 282027 bytes; this capture
  # is >=256KB so it is expected to reproduce here. If it unexpectedly PASSES
  # (detects) at this size, the capture is grown and the measured failing
  # size is recorded in the FAIL detail below.
  # -------------------------------------------------------------------------
  t2a_oldform_script="$TMP/t2a_oldform_check.sh"
  cat > "$t2a_oldform_script" <<'SCRIPTEOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPTEOF
  printf '%s\n' "$sentinel_line" >> "$t2a_oldform_script"
  cat >> "$t2a_oldform_script" <<'SCRIPTEOF'
output="$(cat "$1")"
if printf '%s' "$output" | grep -qF "$SENTINEL"; then
  exit 0
else
  exit 1
fi
SCRIPTEOF

  run_oldform() { # run_oldform <capture-file> -> sets old_detected 0|1
    local cap="$1"
    if bash -euo pipefail "$t2a_oldform_script" "$cap"; then old_detected=1; else old_detected=0; fi
  }

  run_oldform "$t2a_capture"
  control_size="$t2a_size"
  control_capture="$t2a_capture"
  grow_attempts=0
  # Growth loop (story-002 pattern: 131072->141): if the control unexpectedly
  # PASSES at this box's current size, double the filler volume and retry,
  # recording the measured size that finally reproduces the false-negative.
  while [[ "$old_detected" -eq 1 && "$grow_attempts" -lt 6 ]]; do
    grow_attempts=$((grow_attempts + 1))
    grown_capture="$TMP/t2a_big_capture_grown_${grow_attempts}.txt"
    {
      printf '<promise>COMPLETE</promise>\n'
      for _ in $(seq 1 $((4500 * (2 ** grow_attempts)))); do
        printf 'filler filler filler filler filler line padding text here padding more text\n'
      done
    } > "$grown_capture"
    control_capture="$grown_capture"
    control_size=$(wc -c < "$grown_capture")
    run_oldform "$control_capture"
  done

  if [[ "$old_detected" -eq 0 ]]; then
    if [[ "$grow_attempts" -eq 0 ]]; then
      report PASS "17: T2a PRE-FIX CONTROL -- old piped form ('printf | grep -qF') FALSE-NEGATIVES on the identical >=256KB sentinel-early capture (size=${control_size}B) that 16's herestring fix correctly detects"
    else
      report PASS "17: T2a PRE-FIX CONTROL -- old piped form FALSE-NEGATIVES after growing the capture ${grow_attempts} time(s); measured failing size=${control_size}B (256KB capture unexpectedly passed on this box)"
    fi
  else
    report FAIL "17: T2a PRE-FIX CONTROL" "old piped form still detected=1 after ${grow_attempts} growth attempt(s), final size=${control_size}B -- could not reproduce the false-negative on this box"
  fi
fi

# ---------------------------------------------------------------------------
# 18 (T1a, structural -- pwsh absent on this box; PRECISION FIX story-006
# task-03 judge): the RE-EMITTED instance _loop/loop.ps1 carries the
# Get-Command guard AND the exit 127 it triggers COUPLED within the same
# guard block -- a line-window match anchored at the Get-Command line, not
# two independent file-wide greps (which a decoy `exit 127` elsewhere in the
# file, with no guard of its own, could satisfy). Structural by construction
# -- never runtime-verified here.
# ---------------------------------------------------------------------------
t1a_check() { # t1a_check <file> -> 0 if Get-Command git + exit 127 are coupled within a 6-line window
  local f="$1" ln window
  [[ -f "$f" ]] || return 1
  ln="$(grep -n 'Get-Command git' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 5))p" "$f")"
  grep -qE 'exit 127' <<< "$window"
}
if t1a_check "$INSTANCE_LOOP_PS1"; then
  report PASS "18 (structural, coupled): T1a -- instance loop.ps1 carries Get-Command git + exit 127 within the SAME guard block (6-line window), not two independent file-wide greps; not runtime-verified, pwsh absent"
else
  report FAIL "18 (structural, coupled): T1a" "Get-Command guard and exit 127 not found coupled within a 6-line window in $INSTANCE_LOOP_PS1"
fi

# 18-mutation-proof: a copy carrying a decoy `exit 127` elsewhere in the file
# (not inside any Get-Command guard) must FAIL the coupled check even though
# the old two-independent-greps form would have PASSED it.
t18_decoy="$TMP/loop_decoy.ps1"
cp "$INSTANCE_LOOP_PS1" "$t18_decoy"
# neutralize the real guard's own exit 127 so only the decoy remains
sed -i '0,/exit 127/{s/exit 127/exit 99/}' "$t18_decoy"
printf '\nexit 127  # decoy, unrelated to any git guard\n' >> "$t18_decoy"
if t1a_check "$t18_decoy"; then
  report FAIL "18-mutation-proof: decoy exit 127 (uncoupled) must FAIL the coupled check" "decoy copy incorrectly PASSED"
else
  report PASS "18-mutation-proof: decoy exit 127 (uncoupled, no guard) correctly FAILS the coupled check -- precision fix confirmed"
fi

# ---------------------------------------------------------------------------
# 19 (T1b, structural -- pwsh absent on this box): the RE-EMITTED instance
# _loop/loop.ps1 carries the NULL-ONLY coalescing guard (`$null -eq`) around
# the PROMPT.md -Raw read, guarding exactly the literal-null case (0-byte
# file) without coalescing whitespace-only content. Structural by
# construction -- never runtime-verified here.
# ---------------------------------------------------------------------------
if [[ -f "$INSTANCE_LOOP_PS1" ]] && grep -qE '\$null -eq \$raw' "$INSTANCE_LOOP_PS1"; then
  report PASS "19 (structural): T1b -- instance loop.ps1 carries the null-only guard (\$null -eq \$raw) around the PROMPT.md read; not runtime-verified, pwsh absent"
else
  report FAIL "19 (structural): T1b" "null-only guard (\$null -eq \$raw) not found in $INSTANCE_LOOP_PS1"
fi

# ---------------------------------------------------------------------------
# 20 (A1, task-02 coverage): cursor.md's loop row carries the literal per-OS
# invocation forms inline, matching the copilot/codex emitter cells, while
# keeping the "as in the Claude Code emitter" pointer.
# ---------------------------------------------------------------------------
if [[ -f "$CURSOR_MD" ]] \
   && grep -qF 'as in the Claude Code emitter' "$CURSOR_MD" \
   && grep -qF '_loop/loop.sh [max-iterations]' "$CURSOR_MD" \
   && grep -qF 'pwsh _loop/loop.ps1 [MaxIterations]' "$CURSOR_MD"; then
  report PASS "20: A1 -- cursor.md loop row carries the literal per-OS invocation forms inline"
else
  report FAIL "20: A1" "literal invocation forms not found in $CURSOR_MD"
fi

# ---------------------------------------------------------------------------
# 21 (A2, task-02 coverage): the Windows-gate clause is gone from
# skills/setup/SKILL.md -- the checks-script guidance keys purely on
# adoption, not on "and the loop is enabled or Windows is a target
# platform". Whole-file, newline-folded grep (the clause could wrap across
# lines), expects a zero count.
# ---------------------------------------------------------------------------
a2_count="$(tr '\n' ' ' < "$SETUP_SKILL_MD" | grep -c 'Windows is a target platform')"
if [[ "$a2_count" -eq 0 ]]; then
  report PASS "21: A2 -- 'Windows is a target platform' gate clause absent from skills/setup/SKILL.md (count=0)"
else
  report FAIL "21: A2" "gate clause still present, count=$a2_count"
fi

# ---------------------------------------------------------------------------
# 22 (A3, task-02 coverage): the seedFiles contract lands in BOTH Step 6's
# manifest schema example AND the Upgrading section of skills/setup/SKILL.md.
# ---------------------------------------------------------------------------
step6_block="$(awk '/^## Step 6/{flag=1} /^## Upgrading/{flag=0} flag' "$SETUP_SKILL_MD")"
upgrading_block="$(awk '/^## Upgrading/{flag=1} flag' "$SETUP_SKILL_MD")"
if grep -qF 'seedFiles' <<< "$step6_block" && grep -qF 'seedFiles' <<< "$upgrading_block"; then
  report PASS "22: A3 -- 'seedFiles' present in both Step 6's schema example and the Upgrading section"
else
  report FAIL "22: A3" "seedFiles missing from Step 6 block and/or Upgrading block"
fi

# ---------------------------------------------------------------------------
# 23 (A3, task-02 coverage; PRECISION FIX story-006 task-03 judge): the
# _goals/backlog.md CELL (the table row containing the literal
# "_goals/backlog.md") in each emitter carries a "create if missing" note
# WITHIN THAT SAME LINE -- not a whole-file grep, which a decoy note
# elsewhere on an unrelated row (e.g. codex.md:12's AGENTS.md cell) could
# satisfy even if the backlog cell itself lost its note.
# ---------------------------------------------------------------------------
a3_row_check() { # a3_row_check <file> -> 0 if the _goals/backlog.md row contains "create if missing"
  local f="$1" row
  [[ -f "$f" ]] || return 1
  row="$(grep -F '_goals/backlog.md' "$f" | head -1)"
  [[ -n "$row" ]] && grep -qF 'create if missing' <<< "$row"
}
a3_missing=()
for f in "$CLAUDE_CODE_MD" "$CODEX_MD" "$COPILOT_MD"; do
  a3_row_check "$f" || a3_missing+=("$f")
done
if ((${#a3_missing[@]} == 0)); then
  report PASS "23 (row-scoped): A3 -- 'create if missing' present WITHIN the _goals/backlog.md row in all three emitter tables (claude-code.md, codex.md, copilot.md)"
else
  report FAIL "23 (row-scoped): A3" "'create if missing' absent from the _goals/backlog.md row of: ${a3_missing[*]}"
fi

# 23-mutation-proof: a codex.md copy with the backlog-cell note deleted but
# the unrelated :12 AGENTS.md decoy note left intact must FAIL the row-scoped
# check (the old whole-file grep tolerated exactly this case).
t23_decoy="$TMP/codex_decoy.md"
cp "$CODEX_MD" "$t23_decoy"
backlog_ln="$(grep -nF '_goals/backlog.md' "$t23_decoy" | head -1 | cut -d: -f1)"
sed -i "${backlog_ln}s/ (create if missing; never overwrite)//" "$t23_decoy"
if grep -qF 'create if missing' "$t23_decoy" && a3_row_check "$t23_decoy"; then
  report FAIL "23-mutation-proof: codex.md :12 decoy (AGENTS.md note intact, backlog-cell note removed) must FAIL the row-scoped check" "decoy copy incorrectly PASSED"
elif grep -qF 'create if missing' "$t23_decoy" && ! a3_row_check "$t23_decoy"; then
  report PASS "23-mutation-proof: codex.md :12 decoy correctly FAILS the row-scoped check (whole-file grep would have wrongly passed via the AGENTS.md note) -- precision fix confirmed"
else
  report FAIL "23-mutation-proof" "decoy setup broken -- 'create if missing' unexpectedly absent entirely from $t23_decoy"
fi

# ---------------------------------------------------------------------------
# 24 (story-007, check J mutation -- NEGATIVE): a manifest COPY with one
# managed (non-seed, non-self) entry's hash corrupted, run through the REAL
# .claude/checks.sh via the CHECKS_MANIFEST override (a hard feature of
# check J -- no function extraction needed) -- must FAIL and name the path.
# ---------------------------------------------------------------------------
j_neg_manifest="$TMP/j_negative_manifest.json"
j_target_path=".claude/agents/judge.md"
python3 - "$MANIFEST_JSON" "$j_neg_manifest" "$j_target_path" <<'PY'
import json, sys
manifest_path, out_path, target = sys.argv[1:4]
with open(manifest_path) as f:
    data = json.load(f)
h = data["files"][target]
data["files"][target] = ("0" if h[0] != "0" else "1") + h[1:]
with open(out_path, "w") as f:
    json.dump(data, f, indent=2)
PY
j_neg_out="$TMP/j_neg_out.txt"
j_neg_err="$TMP/j_neg_err.txt"
CHECKS_MANIFEST="$j_neg_manifest" "$CHECKS_SH" > "$j_neg_out" 2> "$j_neg_err"
if grep -qE '^FAIL  J: manifest hash join' "$j_neg_out" \
   && grep -qF "$j_target_path" "$j_neg_err"; then
  report PASS "24: check J mutation (NEGATIVE) -- corrupted managed hash for $j_target_path FAILS and names the path"
else
  report FAIL "24: check J mutation (NEGATIVE)" "expected FAIL naming $j_target_path; stdout/stderr did not match"
fi

# ---------------------------------------------------------------------------
# 25 (story-007, check J mutation -- POSITIVE): an INTERNALLY-CONSISTENT
# manifest copy -- every managed (non-seed) entry's hash recomputed against
# the CURRENT working tree first (so this proves the seed join itself, not
# story-induced drift), the seed entry (_goals/backlog.md) left at its
# existing recorded value (proving drift never fails a seed), and
# .claude/checks.sh's own entry set to its CURRENT hash (a fresh record, so
# "self, excluded" is exercised without relying on a stale value) -- must
# PASS with BOTH "seed, exempt" and "self, excluded" on stdout.
# ---------------------------------------------------------------------------
j_pos_manifest="$TMP/j_positive_manifest.json"
python3 - "$REPO_ROOT" "$MANIFEST_JSON" "$j_pos_manifest" <<'PY'
import hashlib, json, os, sys
repo_root, manifest_path, out_path = sys.argv[1:4]
with open(manifest_path) as f:
    data = json.load(f)
seed = set(data.get("seedFiles", []))
for path in list(data["files"].keys()):
    if path == ".claude/checks.sh":
        with open(os.path.join(repo_root, path), "rb") as fh:
            data["files"][path] = hashlib.sha256(fh.read()).hexdigest()
        continue
    if path in seed:
        continue  # keep the seed's existing recorded value (drift tolerated)
    with open(os.path.join(repo_root, path), "rb") as fh:
        data["files"][path] = hashlib.sha256(fh.read()).hexdigest()
with open(out_path, "w") as f:
    json.dump(data, f, indent=2)
PY
j_pos_out="$TMP/j_pos_out.txt"
j_pos_err="$TMP/j_pos_err.txt"
CHECKS_MANIFEST="$j_pos_manifest" "$CHECKS_SH" > "$j_pos_out" 2> "$j_pos_err"
if grep -qE '^PASS  J: manifest hash join' "$j_pos_out" \
   && grep -qF 'J: seed, exempt -- _goals/backlog.md' "$j_pos_out" \
   && grep -qF 'J: self, excluded -- .claude/checks.sh' "$j_pos_out"; then
  report PASS "25: check J mutation (POSITIVE) -- internally-consistent manifest PASSES with BOTH 'seed, exempt' and 'self, excluded' on stdout"
else
  report FAIL "25: check J mutation (POSITIVE)" "expected PASS + both self/seed lines on stdout; not found"
fi

# ---------------------------------------------------------------------------
# 26 (story-007, check K mutation -- NEGATIVE + POSITIVE): check K's own
# five-field grep set (writes/reads/depends_on/owner/rewrite_semantics,
# anchored at column 0, expected count exactly 1) run verbatim against a
# task-template COPY with one field deleted -- must fail; against the
# current canonical template -- must pass. No CHECKS_MANIFEST-style override
# exists for the task-template path, so this replicates check K's exact grep
# logic against the copy's path (CHECKS-style), per the task-03 spec.
# ---------------------------------------------------------------------------
k_check() { # k_check <task-template-path> -> prints missing field names (empty = all present)
  local f="$1" field n bad=()
  for field in '^writes:' '^reads:' '^depends_on:' '^owner:' '^rewrite_semantics:'; do
    n="$(grep -cE "$field" "$f")"
    [[ "$n" -ne 1 ]] && bad+=("$field:$n")
  done
  printf '%s\n' "${bad[@]}"
}
k_copy_missing_owner="$TMP/task_missing_owner.md"
grep -v '^owner:' "$TASK_TPL" > "$k_copy_missing_owner"
k_neg_result="$(k_check "$k_copy_missing_owner")"
k_pos_result="$(k_check "$TASK_TPL")"
if [[ -n "$k_neg_result" && -z "$k_pos_result" ]]; then
  report PASS "26: check K mutation -- task-template copy missing 'owner:' FAILS ($k_neg_result), current canonical template PASSES"
else
  report FAIL "26: check K mutation" "neg_result='$k_neg_result' pos_result='$k_pos_result' (expected neg non-empty, pos empty)"
fi

# ---------------------------------------------------------------------------
# 27 (story-007, task-02 clause tripwire): the normative literal
# 'bracket-literal placeholder values' (declared constant, goal pin) is
# present in the canonical goal-criteria template's Ownership contract
# section -- a PRESENCE check (grep -q), never a count.
# ---------------------------------------------------------------------------
if grep -qF 'bracket-literal placeholder values' "$CRITERIA_TPL"; then
  report PASS "27: task-02 clause tripwire -- 'bracket-literal placeholder values' present in canonical goal-criteria"
else
  report FAIL "27: task-02 clause tripwire" "'bracket-literal placeholder values' not found in $CRITERIA_TPL"
fi

# ---------------------------------------------------------------------------
# 28 (story-007, addendum 2 / TMPDIR characterization): the same
# LIVE-extracted herestring sentinel check as assertion 16, run with TMPDIR
# pointed at a directory that exists but is NOT writable (0555), against the
# identical >=256KB sentinel-early capture. OBSERVED ONCE on this box (bash
# 5.1.16): bash's here-string implementation silently falls back to its
# default temp directory (verified via strace: it does NOT attempt to write
# under the unwritable TMPDIR; no error surfaces) -- exit 0 (sentinel still
# detected), empty stderr. This is the FROZEN expected value: a future
# bash/loop change that alters this fallback behavior (e.g. a hard failure,
# or -- the disposition case that matters -- a silent false negative where
# the sentinel goes undetected with no error) flips this assertion.
#
# DISPOSITION: no false-negative was found on this box -- unwritable TMPDIR
# does not affect the sentinel check's correctness (silent, safe fallback to
# the platform default temp dir). Per the task-03 spec, only a DISCOVERED
# false-negative routes to the STORY-009 backlog addendum item (c); since
# none was discovered here, no further routing is needed this cycle.
# ---------------------------------------------------------------------------
if [[ -z "$sentinel_line" || -z "$sentinel_check_line" ]]; then
  report FAIL "28: TMPDIR characterization" "sentinel extraction failed upstream (see assertion 16 setup)"
else
  ro_tmpdir="$TMP/readonly_tmpdir"
  mkdir -p "$ro_tmpdir"
  chmod 555 "$ro_tmpdir"

  tmpdir_out="$TMP/tmpdir_stdout.txt"
  tmpdir_err="$TMP/tmpdir_stderr.txt"
  TMPDIR="$ro_tmpdir" bash -euo pipefail "$t2a_script" "$t2a_capture" > "$tmpdir_out" 2> "$tmpdir_err"
  tmpdir_rc=$?
  tmpdir_err_content="$(cat "$tmpdir_err")"

  # FROZEN expected value (observed once on this box): exit 0, empty stderr.
  frozen_expected_rc=0
  frozen_expected_err=""

  if [[ "$tmpdir_rc" -eq "$frozen_expected_rc" && "$tmpdir_err_content" == "$frozen_expected_err" ]]; then
    report PASS "28: TMPDIR characterization -- unwritable TMPDIR (0555) frozen behavior confirmed: exit=$tmpdir_rc, stderr empty, sentinel still detected (bash silently falls back to its default temp dir; no false negative found -- STORY-009 addendum item (c) not triggered)"
  else
    report FAIL "28: TMPDIR characterization -- frozen behavior REGRESSED" \
      "expected exit=$frozen_expected_rc/stderr='' got exit=$tmpdir_rc/stderr='$tmpdir_err_content' -- if this now shows exit implying not-found with sentinel actually present, this is the silent false-negative that files under the STORY-009 backlog addendum item (c)"
  fi

  chmod 755 "$ro_tmpdir" 2>/dev/null || true
fi

echo
echo "=== loop-harness summary ==="
echo "PASS: $pass_count   FAIL: $fail_count"
if ((fail_count)); then
  echo "RESULT: $fail_count assertion(s) FAILED"
  exit 1
fi
echo "RESULT: all assertions passed"
exit 0
