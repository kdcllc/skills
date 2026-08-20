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
BREAKER_PS1="$REPO_ROOT/skills/setup/templates/loop/breaker.ps1"
LOOP_SH="$REPO_ROOT/skills/setup/templates/loop/loop.sh"
LOOP_PS1="$REPO_ROOT/skills/setup/templates/loop/loop.ps1"
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
# 11 (UPDATED, story-009 fail-safe inversion, task-03): corrupted JSON (not
# JSON-like at all -- no keys at all, so _breaker_valid_fields fails outright,
# no retry) -> the NEW contract is fail-SAFE to OPEN (never fresh CLOSED,
# which would have re-armed a full-rate retry silently). openedAt is set from
# the injected `now`; chain is seeded from the <chain> ARGUMENT (the garbage
# has no parseable chain key at all); currentModel is DERIVED as
# chain[fallbackIndex] (0) = modelA, never blindly re-pinned; exactly ONE
# stderr warning containing "failing SAFE to OPEN" (the new message text --
# "unparseable" is no longer part of it).
# ---------------------------------------------------------------------------
S11="$TMP/corrupted.json"
printf 'not json at all\njust garbage\n' > "$S11"
T11=9000000
stderr_file11="$TMP/11-stderr.txt"
breaker_load "$S11" "$CHAIN" "$T11" >/dev/null 2>"$stderr_file11"
state="$(_breaker_get "$S11" state)"; chain="$(_breaker_get "$S11" chain)"
model="$(_breaker_get "$S11" currentModel)"; opened="$(_breaker_get "$S11" openedAt)"
warn_lines11=$(wc -l < "$stderr_file11")
if [[ "$state" == "OPEN" && "$opened" == "$T11" && "$opened" -gt 0 && "$chain" == "$CHAIN" \
      && "$model" == "modelA" && "$warn_lines11" -eq 1 \
      && "$(grep -c "failing SAFE to OPEN" "$stderr_file11")" -eq 1 ]]; then
  report PASS "11: corrupted (non-JSON) state -> fail-safe OPEN, openedAt>0 (=$T11), chain seeded from argument, currentModel derived (modelA), ONE stderr warning ('failing SAFE to OPEN')"
else
  report FAIL "11: corrupted (non-JSON) state -> fail-safe OPEN, openedAt>0, chain seeded from argument, currentModel derived, ONE stderr warning" \
    "state=$state opened=$opened chain=$chain model=$model warn_lines=$warn_lines11 stderr='$(cat "$stderr_file11")'"
fi

# ---------------------------------------------------------------------------
# 11b (UPDATED, story-009 fail-safe inversion, task-03; carries forward the
# task-01 infinite-spin regression guard verbatim): a state file whose STATE
# VALUE carries a leading CR inside the quotes (e.g. "state": "\rCLOSED",) --
# the state enum comparison fails so _breaker_valid_fields is invalid for a
# reason OTHER than the terminator (no retry loop entered) -> the NEW
# contract is fail-SAFE to OPEN (never fresh CLOSED): openedAt set from the
# injected `now`; chain/fallbackIndex/currentModel are all PRESERVED here
# because those key lines parse fine in this fixture (only "state" itself is
# corrupted) -- chain stays $CHAIN, currentModel stays "modelA"; exactly ONE
# stderr warning containing "failing SAFE to OPEN"; still wrapped in
# `timeout 10` as the infinite-spin regression guard (unchanged from task-01).
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

T11B=9100000
stderr_file="$TMP/11b-stderr.txt"
timeout 10 bash -c "source '$BREAKER_SH'; breaker_load '$S11B' '$CHAIN' '$T11B'" 2>"$stderr_file"
rc=$?
warn_lines=$(wc -l < "$stderr_file")
state="$(_breaker_get "$S11B" state)"; chain="$(_breaker_get "$S11B" chain)"
model="$(_breaker_get "$S11B" currentModel)"; opened="$(_breaker_get "$S11B" openedAt)"
if [[ "$rc" -eq 0 && "$warn_lines" -eq 1 && "$(grep -c "failing SAFE to OPEN" "$stderr_file")" -eq 1 \
      && "$state" == "OPEN" && "$opened" == "$T11B" && "$chain" == "$CHAIN" && "$model" == "modelA" ]]; then
  report PASS "11b: leading-CR corrupted value -> fail-safe OPEN (openedAt=$T11B, chain/currentModel preserved) + ONE warning, terminates under timeout 10 (infinite-spin regression)"
else
  report FAIL "11b: leading-CR corrupted value -> fail-safe OPEN + ONE warning, terminates under timeout 10 (infinite-spin regression)" \
    "rc=$rc warn_lines=$warn_lines state=$state opened=$opened chain=$chain model=$model ($( [[ $rc -eq 124 ]] && echo 'TIMED OUT -- infinite spin regressed!'))"
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
# FIX-CYCLE-2 (routed from task 04's escalation, seam inherited via the
# instance re-emit, not a defect introduced here): task 02's 126/127
# documentation clause puts a plain-text `exit 127` inside a COMMENT ahead of
# the real Get-Command guard, so the old FIRST-textual-hit neutralization
# below (`sed -i '0,/exit 127/{...}'`) silently neutralized the COMMENT's
# occurrence instead of the real guard's, leaving the real guard's own
# `exit 127` intact -- the decoy then satisfied the coupled check via the
# untouched real guard, and the mutation-proof FAILed. Fixed by anchoring the
# neutralization at the guard itself (content-anchored on 'Get-Command git',
# a small window forward), the same anchoring style already used by
# t1a_check/the assertion-23 row-scoped precedent -- this survives future
# line drift (e.g. more comment text landing above the guard) because it
# locates the guard by content, never by an absolute line number or a
# first-textual-hit assumption.
t18_decoy="$TMP/loop_decoy.ps1"
cp "$INSTANCE_LOOP_PS1" "$t18_decoy"
# neutralize the real guard's own exit 127 (content-anchored at the guard, not
# a first-textual-hit assumption) so only the decoy remains
guard_ln="$(grep -n 'Get-Command git' "$t18_decoy" | head -1 | cut -d: -f1)"
sed -i "${guard_ln},$((guard_ln + 5)){s/exit 127/exit 99/}" "$t18_decoy"
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

# ---------------------------------------------------------------------------
# 29 (NEW, story-009 task-03 hardening): torn-file retry/fail-safe. A valid
# OPEN state (chain "modelA,modelB", fallbackIndex 1, currentModel modelB) has
# EXACTLY its final `}` line deleted -- all nine keys stay intact, only the
# terminator is missing (the ONLY shape that reaches the terminator-only
# retry branch, per the goal pin). The file never heals on its own, so all
# 3 retries (3x~50ms backoff) exhaust and fall through to fail-safe OPEN:
# openedAt is set from the injected `now` (NOT preserved from the pre-tear
# file); chain/fallbackIndex/currentModel are all PRESERVED (their key lines
# parse fine). Elapsed time is loosely checked >= ~100ms to prove the retry
# loop actually ran (contrasts with 30's ~0ms immediate path).
# ---------------------------------------------------------------------------
S29_valid="$TMP/torn_valid.json"
_breaker_write "$S29_valid" OPEN "modelA,modelB" 1 modelB 600 555000 0 1 0
S29="$TMP/torn.json"
cp "$S29_valid" "$S29"
sed -i '$d' "$S29"   # delete EXACTLY the final `}` line

T29=20000000
stderr_file29="$TMP/29-stderr.txt"
start_ns=$(date +%s%N)
breaker_load "$S29" "$CHAIN" "$T29" 2>"$stderr_file29"
end_ns=$(date +%s%N)
elapsed_ms29=$(( (end_ns - start_ns) / 1000000 ))

state="$(_breaker_get "$S29" state)"; chain="$(_breaker_get "$S29" chain)"
idx="$(_breaker_get "$S29" fallbackIndex)"; model="$(_breaker_get "$S29" currentModel)"
opened="$(_breaker_get "$S29" openedAt)"
warn_lines29=$(wc -l < "$stderr_file29")
if [[ "$state" == "OPEN" && "$opened" == "$T29" && "$chain" == "modelA,modelB" \
      && "$idx" == "1" && "$model" == "modelB" && "$elapsed_ms29" -ge 100 \
      && "$warn_lines29" -eq 1 ]]; then
  report PASS "29: torn-file (final \`}\` line deleted, nine keys intact) -> after ~3 retries seeds fail-safe OPEN (openedAt=$T29), preserved chain/fallbackIndex/currentModel (=modelB), elapsed=${elapsed_ms29}ms (>=100ms loose bound proves retries ran)"
else
  report FAIL "29: torn-file (final \`}\` line deleted, nine keys intact) -> after ~3 retries seeds fail-safe OPEN, preserved chain/fallbackIndex/currentModel" \
    "state=$state opened=$opened chain=$chain idx=$idx model=$model elapsed_ms=$elapsed_ms29 warn_lines=$warn_lines29"
fi

# ---------------------------------------------------------------------------
# 30 (NEW, story-009 task-03 hardening; "the common real tear"): key-dropping
# truncation. A writer process killed almost immediately after opening the
# file leaves only `{` and the state line on disk -- chain and every field
# after it, INCLUDING chain itself, never made it out. _breaker_valid_fields
# fails OUTRIGHT (multiple required keys absent, not merely the terminator),
# so breaker_load takes the IMMEDIATE fail-safe path with NO retry sleep at
# all (elapsed checked < 100ms -- fix-cycle-1: loosened from <50ms, which had
# only 1.7x margin under CPU saturation [worst observed 29ms]; 100ms still
# sits far under the retry path's hard 150ms sleep floor [3x50ms], so
# discrimination from 29's >=100ms is fully preserved). Because the chain key
# itself never made it to disk, chain is seeded
# from the <chain> ARGUMENT (not preserved), and currentModel is DERIVED as
# chain[0] = modelA.
# ---------------------------------------------------------------------------
S30_valid="$TMP/trunc_valid.json"
_breaker_write "$S30_valid" OPEN "modelA,modelB" 1 modelB 600 555000 0 1 0
S30="$TMP/trunc.json"
head -n 2 "$S30_valid" > "$S30"   # only `{` and the state line survive

T30=21000000
stderr_file30="$TMP/30-stderr.txt"
start_ns=$(date +%s%N)
breaker_load "$S30" "$CHAIN" "$T30" 2>"$stderr_file30"
end_ns=$(date +%s%N)
elapsed_ms30=$(( (end_ns - start_ns) / 1000000 ))

state="$(_breaker_get "$S30" state)"; chain="$(_breaker_get "$S30" chain)"
model="$(_breaker_get "$S30" currentModel)"; opened="$(_breaker_get "$S30" openedAt)"
warn_lines30=$(wc -l < "$stderr_file30")
if [[ "$state" == "OPEN" && "$opened" == "$T30" && "$chain" == "$CHAIN" && "$model" == "modelA" \
      && "$elapsed_ms30" -lt 100 && "$warn_lines30" -eq 1 \
      && "$(grep -c "failing SAFE to OPEN" "$stderr_file30")" -eq 1 ]]; then
  report PASS "30: key-dropping truncation (chain + trailing keys missing) -> IMMEDIATE fail-safe OPEN, chain seeded from argument, currentModel derived (modelA), NO retry (elapsed=${elapsed_ms30}ms < 100ms)"
else
  report FAIL "30: key-dropping truncation (chain + trailing keys missing) -> IMMEDIATE fail-safe OPEN, chain seeded from argument, NO retry" \
    "state=$state chain=$chain model=$model opened=$opened elapsed_ms=$elapsed_ms30 warn_lines=$warn_lines30"
fi

# ---------------------------------------------------------------------------
# 31 (NEW, story-009 task-03 hardening; FIX-CYCLE-1 REWORK -- deterministic,
# no wall-clock dependence): retry-RECOVERY. The file is torn exactly as in
# 29 (final `}` deleted). Fix-cycle-1 instrumented proof: the goal pin's
# `sleep 0.03` background-restore recipe is NOT "generous" in practice -- the
# INITIAL `_breaker_valid` check inside breaker_load (9 greps + 6
# `_breaker_get` forks) alone costs ~30ms on this box, so a 0.03s background
# restore can land INSIDE that initial check's own window and heal the file
# before the retry loop is ever entered at all -- coin-flip-at-best coverage
# of the actual retry branch (judge-measured: retry-block deletion still
# passed 5/8 runs; the exact retry-never-recovers defect passed 2/4). Fixed
# by shadowing `sleep` for this assertion's scope ONLY: a bash function named
# `sleep` shadows the external command for anything executing in THIS shell
# -- including breaker_load's own bare `sleep 0.05` call inside its retry
# loop, since breaker_load runs in-process here (no subshell). The shadow
# performs the atomic restore (goal-judge's atomic recipe: `cp` to a
# `.restore.$$` sibling, then `mv -f` onto the live path -- a bare `cp` onto
# the live path would reproduce the very race under test) on its FIRST
# invocation and increments a counter, then delegates to the real `sleep` via
# `command sleep`. Because the restore can now ONLY happen inside a `sleep`
# call, and `sleep` can only be called from INSIDE the retry loop, the retry
# loop is GUARANTEED to run at least once before recovery -- zero wall-clock
# race, zero flakiness. `retry_sleep_calls31 >= 1` is asserted IN ADDITION TO
# (not instead of) the existing checksum/openedAt-unchanged/no-warning
# proofs, so this assertion now proves the retry loop itself ran and itself
# recovered mid-loop, not merely that some code path left the state healed.
# The shadow is `unset -f` immediately after use so it cannot leak into any
# later assertion.
# ---------------------------------------------------------------------------
S31_valid="$TMP/recovery_valid.json"
_breaker_write "$S31_valid" OPEN "modelA,modelB" 1 modelB 600 777000 0 1 0
valid_sum31="$(sha256sum "$S31_valid" | cut -d' ' -f1)"

S31="$TMP/recovery.json"
cp "$S31_valid" "$S31"
sed -i '$d' "$S31"   # tear: delete EXACTLY the final `}` line

retry_sleep_calls31=0
sleep() { # shadow, scoped to this assertion only -- unset immediately below
  retry_sleep_calls31=$((retry_sleep_calls31 + 1))
  if [[ "$retry_sleep_calls31" -eq 1 ]]; then
    cp "$S31_valid" "$S31.restore.$$"
    mv -f "$S31.restore.$$" "$S31"
  fi
  command sleep "$@"
}

T31=22000000
stderr_file31="$TMP/31-stderr.txt"
breaker_load "$S31" "$CHAIN" "$T31" 2>"$stderr_file31"
unset -f sleep   # restore the real `sleep` immediately -- no leakage downstream

sum_after31="$(sha256sum "$S31" | cut -d' ' -f1)"
warn_lines31=$(wc -l < "$stderr_file31")
state="$(_breaker_get "$S31" state)"; model="$(_breaker_get "$S31" currentModel)"
opened="$(_breaker_get "$S31" openedAt)"
if [[ "$sum_after31" == "$valid_sum31" && "$warn_lines31" -eq 0 && "$opened" == "777000" \
      && "$retry_sleep_calls31" -ge 1 ]]; then
  report PASS "31: retry-RECOVERY (deterministic, shadowed-sleep) -- torn file restored ATOMICALLY on the retry loop's FIRST sleep(0.05) invocation (retry_sleep_calls=$retry_sleep_calls31, proving the retry branch itself ran -- not merely the initial validity check) -> restored state preserved (checksum == valid source, state=$state, currentModel=$model, openedAt UNCHANGED=$opened -- itself proof the fail-safe path did not fire), NO stderr warning, NO fail-safe reseed"
else
  report FAIL "31: retry-RECOVERY (deterministic, shadowed-sleep)" \
    "sum_match=$([[ "$sum_after31" == "$valid_sum31" ]] && echo yes || echo no) state=$state model=$model opened=$opened stderr='$(cat "$stderr_file31")' warn_lines=$warn_lines31 retry_sleep_calls=$retry_sleep_calls31"
fi

# ---------------------------------------------------------------------------
# 32 (NEW, story-009 task-03 hardening): atomic write. Behavioral half: after
# a real breaker_record transition (CLOSED+RL -> OPEN, which writes), no
# `*.tmp.*` sibling of the state file remains and the resulting file still
# parses (_breaker_valid). Structural half: the canonical breaker.sh source
# itself is grepped -- _breaker_write's schema block redirects to `"$tmp"`,
# never a bare `> "$file"` (the pre-story non-atomic truncate-then-write this
# story closed).
# ---------------------------------------------------------------------------
S32="$TMP/atomic.json"
S32_dir="$(dirname "$S32")"; S32_base="$(basename "$S32")"
breaker_load "$S32" "$CHAIN" 30000000
tmp_before32=$(find "$S32_dir" -maxdepth 1 -name "${S32_base}.tmp.*" 2>/dev/null | wc -l)
breaker_record "$S32" 1 30000100
tmp_after32=$(find "$S32_dir" -maxdepth 1 -name "${S32_base}.tmp.*" 2>/dev/null | wc -l)
parses_ok32=0
_breaker_valid "$S32" && parses_ok32=1

write_func_body="$(sed -n '/^_breaker_write() {/,/^}/p' "$BREAKER_SH")"
structural_ok32=0
if grep -qF '} > "$tmp"' <<< "$write_func_body" && ! grep -qE '> "\$file"' <<< "$write_func_body"; then
  structural_ok32=1
fi

if [[ "$tmp_before32" -eq 0 && "$tmp_after32" -eq 0 && "$parses_ok32" -eq 1 && "$structural_ok32" -eq 1 ]]; then
  report PASS "32: atomic write -- no *.tmp.* sibling remains after breaker_record's OPEN transition (state still parses), and _breaker_write's source redirects the schema block to \"\$tmp\" (mv -f onto the target) with no stray '> \"\$file\"' bare redirect remaining"
else
  report FAIL "32: atomic write" "tmp_before=$tmp_before32 tmp_after=$tmp_after32 parses_ok=$parses_ok32 structural_ok=$structural_ok32"
fi

# ---------------------------------------------------------------------------
# 33 (NEW, story-009 task-03, routed addendum item a): 126/127 contract-clause
# parity. Extracts the appended 126/127 clause from BOTH canonical loop
# twins' exit-code contract blocks (marker-normalized: leading `# ` comment
# markers stripped before compare, since the twins otherwise differ in
# comment-marker convention on other lines) and requires the clause text be
# byte-identical, plus that both extracted blocks literally mention "126"
# and "127".
# ---------------------------------------------------------------------------
extract_126127_clause() { # extract_126127_clause <file>
  awk '/^# 126\/127 \(shell-propagated edge cases/{flag=1} flag{print} /\(the 126 case is Unix-host-only\)\.$/{if (flag) exit}' "$1"
}
clause_sh33="$(extract_126127_clause "$LOOP_SH")"
clause_ps133="$(extract_126127_clause "$LOOP_PS1")"
norm_sh33="$(sed 's/^# \{0,1\}//' <<< "$clause_sh33")"
norm_ps133="$(sed 's/^# \{0,1\}//' <<< "$clause_ps133")"

if [[ -z "$clause_sh33" || -z "$clause_ps133" ]]; then
  report FAIL "33 setup: extract 126/127 clause from canonical loop twins" \
    "clause_sh empty=$([[ -z "$clause_sh33" ]] && echo yes || echo no) clause_ps1 empty=$([[ -z "$clause_ps133" ]] && echo yes || echo no)"
elif [[ "$norm_sh33" == "$norm_ps133" && "$norm_sh33" == *"126"* && "$norm_sh33" == *"127"* \
        && "$norm_ps133" == *"126"* && "$norm_ps133" == *"127"* ]]; then
  report PASS "33: 126/127 contract-clause parity -- canonical loop.sh + loop.ps1 exit-code contract blocks carry a byte-identical (marker-normalized) appended clause, both mentioning 126 and 127"
else
  report FAIL "33: 126/127 contract-clause parity" "clause_sh='$clause_sh33' clause_ps1='$clause_ps133'"
fi

# ---------------------------------------------------------------------------
# 34 (NEW, story-009 task-03, cycle-1 MAJOR-3 / Check-G-parity-guard
# deviation landing site; FIX-CYCLE-1: t34_move_check re-scoped): ps1
# mechanics structural guard. The canonical breaker.ps1 is grepped for three
# mechanics, block-scoped per the assertion-18 coupling precedent (a
# line-window anchored at the relevant function/message, not independent
# file-wide greps a decoy could satisfy):
#   - ::Move( with the overwrite argument ($true), inside the
#     Write-BreakerState function body (fix-cycle-1: a file-wide grep was
#     mutation-proven decoy-satisfiable -- breaker.ps1:138 is a COMMENT
#     containing this exact literal; deleting the real :171 call left the
#     old check green, so it is now anchored at `function Write-BreakerState`
#     the same way the other two sub-checks below are already anchored);
#   - the terminator condition (-eq '}') inside Test-BreakerTerminatorOk;
#   - the fail-safe OPEN branch: the "failing SAFE to OPEN" warning coupled
#     (within a few lines) to the New-BreakerFailsafeOpen call, and that
#     function's own body in turn coupled to -State 'OPEN'.
# ---------------------------------------------------------------------------
t34_move_check() {
  local f="$1" ln window
  ln="$(grep -n 'function Write-BreakerState' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 35))p" "$f")"
  grep -qF '::Move($tmp, $Path, $true)' <<< "$window"
}
t34_term_check() {
  local f="$1" ln window
  ln="$(grep -n 'function Test-BreakerTerminatorOk' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 15))p" "$f")"
  grep -qE -- "-eq '\}'" <<< "$window"
}
t34_failsafe_msg_check() {
  local f="$1" ln window
  ln="$(grep -n 'failing SAFE to OPEN' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 5))p" "$f")"
  grep -qF 'New-BreakerFailsafeOpen' <<< "$window"
}
t34_failsafe_state_check() {
  local f="$1" ln window
  ln="$(grep -n 'function New-BreakerFailsafeOpen' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 30))p" "$f")"
  grep -qE -- "-State 'OPEN'" <<< "$window"
}
if t34_move_check "$BREAKER_PS1" && t34_term_check "$BREAKER_PS1" \
   && t34_failsafe_msg_check "$BREAKER_PS1" && t34_failsafe_state_check "$BREAKER_PS1"; then
  report PASS "34: ps1 mechanics structural guard -- canonical breaker.ps1 carries ::Move( with the overwrite arg (\$true), the terminator condition (-eq '}') inside Test-BreakerTerminatorOk, and the fail-safe OPEN branch (New-BreakerFailsafeOpen coupled to the 'failing SAFE to OPEN' warning, itself writing -State 'OPEN') -- not runtime-verified, pwsh absent"
else
  report FAIL "34: ps1 mechanics structural guard" \
    "move=$(t34_move_check "$BREAKER_PS1" && echo ok || echo FAIL) term=$(t34_term_check "$BREAKER_PS1" && echo ok || echo FAIL) failsafe_msg=$(t34_failsafe_msg_check "$BREAKER_PS1" && echo ok || echo FAIL) failsafe_state=$(t34_failsafe_state_check "$BREAKER_PS1" && echo ok || echo FAIL)"
fi

# ---------------------------------------------------------------------------
# 35 (NEW, story-009 task-03, routed addendum item b): CRLF prompt parity --
# bash behavioral. The read line (`p="$(cat "$PROMPT_FILE")"`) and the strip
# line (the both-CR/LF iterative while-loop) are extracted LIVE from the
# canonical loop.sh by CONTENT match (never a reimplementation, never line
# numbers -- the task pin explicitly warns these lines move), wrapped in a
# minimal script that repoints PROMPT_FILE at each fixture. All seven pinned
# tail vectors (\n, \r\n, \r\r\n, \r, \r\n\r\n, \n\r\n, \r\n\r\n\r\n) must
# yield exactly "text" -- the \r\n\r\n and \n\r\n tails are the discriminating
# cases a CR-only strip would fail (goal.md's empirically-disproven original
# pin).
# ---------------------------------------------------------------------------
read_ln_num35="$(grep -nF 'cat "$PROMPT_FILE"' "$LOOP_SH" | head -1 | cut -d: -f1)"
strip_ln_num35="$(grep -nF 'p%?' "$LOOP_SH" | head -1 | cut -d: -f1)"
read_line35="$( [[ -n "$read_ln_num35" ]] && sed -n "${read_ln_num35}p" "$LOOP_SH" )"
strip_line35="$( [[ -n "$strip_ln_num35" ]] && sed -n "${strip_ln_num35}p" "$LOOP_SH" )"

if [[ -z "$read_line35" || -z "$strip_line35" ]]; then
  report FAIL "35 setup: extract read+strip lines from canonical loop.sh" \
    "read_line='$read_line35' strip_line='$strip_line35' -- loop.sh structure changed?"
else
  crlf_script35="$TMP/35_crlf.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'PROMPT_FILE="$1"\n'
    printf '%s\n' "$read_line35"
    printf '%s\n' "$strip_line35"
    printf 'printf %%s "$p"\n'
  } > "$crlf_script35"

  declare -a tail_names35=('\n' '\r\n' '\r\r\n' '\r' '\r\n\r\n' '\n\r\n' '\r\n\r\n\r\n')
  declare -a tails35=($'\n' $'\r\n' $'\r\r\n' $'\r' $'\r\n\r\n' $'\n\r\n' $'\r\n\r\n\r\n')
  all_ok35=1
  declare -a fail_details35=()
  for i in "${!tails35[@]}"; do
    vec_file35="$TMP/35_vec_${i}.txt"
    printf 'text%s' "${tails35[$i]}" > "$vec_file35"
    result35="$(bash "$crlf_script35" "$vec_file35")"
    if [[ "$result35" != "text" ]]; then
      all_ok35=0
      fail_details35+=("tail='${tail_names35[$i]}' got='$result35'")
    fi
  done

  if [[ "$all_ok35" -eq 1 ]]; then
    report PASS "35: CRLF prompt parity (bash) -- all seven tail vectors (\\n, \\r\\n, \\r\\r\\n, \\r, \\r\\n\\r\\n, \\n\\r\\n, \\r\\n\\r\\n\\r\\n) yield 'text' through the LIVE-extracted canonical loop.sh read+strip lines"
  else
    report FAIL "35: CRLF prompt parity (bash)" "${fail_details35[*]}"
  fi
fi

# ---------------------------------------------------------------------------
# 36 (NEW, story-009 task-03, routed addendum item b; FIX-CYCLE-1: TrimEnd
# check re-scoped): CRLF prompt parity -- ps1 structural. The canonical
# loop.ps1 is grepped for the corrected comment (the original CR-only-strip
# pin was empirically disproven at cycle 1; the comment now accurately
# states both twins strip trailing CR/LF) and the TrimEnd("`r", "`n") line
# itself, which strips BOTH characters -- exact parity with the bash twin's
# iterative both-char strip loop verified behaviorally in 35. Fix-cycle-1: a
# file-wide grep for the TrimEnd(...) literal was mutation-proven
# decoy-satisfiable -- loop.ps1:168 applies the SAME TrimEnd("`r", "`n") call
# to the CLI OUTPUT (not the PROMPT.md read); deleting the prompt-side :153
# line left the old check green. Now block-scoped: anchored at the line that
# reads PROMPT.md into $raw (Get-Content -Raw -LiteralPath $PromptFile), a
# small window forward to the TrimEnd call that consumes that same $raw.
# ---------------------------------------------------------------------------
comment_ok36=0
grep -qF 'both twins strip trailing CR/LF from the prompt tail' "$LOOP_PS1" && comment_ok36=1

trimend_ok36=0
prompt_read_ln36="$(grep -nF 'Get-Content -Raw -LiteralPath $PromptFile' "$LOOP_PS1" | head -1 | cut -d: -f1)"
if [[ -n "$prompt_read_ln36" ]]; then
  prompt_window36="$(sed -n "${prompt_read_ln36},$((prompt_read_ln36 + 5))p" "$LOOP_PS1")"
  grep -qF 'TrimEnd("`r", "`n")' <<< "$prompt_window36" && trimend_ok36=1
fi

if [[ "$comment_ok36" -eq 1 && "$trimend_ok36" -eq 1 ]]; then
  report PASS "36: CRLF prompt parity (ps1 structural) -- canonical loop.ps1 carries the corrected comment ('both twins strip trailing CR/LF from the prompt tail') and the TrimEnd(\`r,\`n) line matching bash's iterative both-char strip -- not runtime-verified, pwsh absent"
else
  report FAIL "36: CRLF prompt parity (ps1 structural)" "comment_ok=$comment_ok36 trimend_ok=$trimend_ok36"
fi

# ===========================================================================
# STORY-010 slot-supervision coverage (assertions 37-53). Shared fixture
# helpers: sandbox_write_loop substitutes the three instance tokens
# ({{PROJECT_NAME}}/{{LOOP_MODEL_CHAIN}}/{{IDE_DIR}}) into COPIES of the
# CANONICAL loop.sh/breaker.sh BEFORE any run (pinned) -- these fixtures never
# drive the instance _loop/ files (that remains assertion 15's own lane, and
# the goal's extraction-survival requirement is already proven by assertions
# 13/14/13b/13c/16/33/35 above, which re-extract against these same canonical
# files on every run of this harness). make_sandbox wraps the substituted
# copy in a throwaway git repo under this run's mktemp workdir, with
# independently-controllable tracked/gitignored _goals and {{IDE_DIR}} state
# (needed by the two preflight-failure fixtures, 44/45).
# ===========================================================================
sandbox_write_loop() { # sandbox_write_loop <dest_dir> <ide_dir_name>
  local dest="$1" ide="$2"
  mkdir -p "$dest/_loop"
  sed -e 's/{{PROJECT_NAME}}/sandbox-project/g' \
      -e 's/{{LOOP_MODEL_CHAIN}}/sonnet/g' \
      -e "s/{{IDE_DIR}}/$ide/g" \
      "$LOOP_SH" > "$dest/_loop/loop.sh"
  chmod +x "$dest/_loop/loop.sh"
  sed -e 's/{{PROJECT_NAME}}/sandbox-project/g' \
      "$BREAKER_SH" > "$dest/_loop/breaker.sh"
  printf 'Fixture prompt: do the task; print the sentinel when done.\n' > "$dest/_loop/PROMPT.md"
}

make_sandbox() { # make_sandbox <dest_dir> <ide_dir_name> <track_goals:0|1> <track_ide:0|1>
  local dest="$1" ide="$2" track_goals="$3" track_ide="$4"
  rm -rf "$dest"
  mkdir -p "$dest"
  sandbox_write_loop "$dest" "$ide"
  (
    cd "$dest"
    git init -q
    git config user.email test@example.com
    git config user.name "story010-test"
    mkdir -p _goals "$ide"
    printf '# backlog\n' > _goals/backlog.md
    printf 'placeholder\n' > "$ide/.keep"
    : > .gitignore
    if [[ "$track_goals" != "1" ]]; then printf '_goals/\n' >> .gitignore; fi
    if [[ "$track_ide" != "1" ]]; then printf '%s/\n' "$ide" >> .gitignore; fi
    git add -A
    git commit -qm init
  )
}

# ---------------------------------------------------------------------------
# 37-40: LOOP_SLOTS clamp/guard/banner surface. The banner ("slots: N — ...")
# and the STORY-011 guard warning both print BEFORE the iteration loop body
# ever runs (loop.sh:85-94), so MAX_ITER=0 exercises them with ZERO CLI
# invocations -- no stub CLI, no git repo needed (nothing before the for-loop
# touches git).
# ---------------------------------------------------------------------------
CLAMP_DIR="$TMP/clamp-sandbox"
mkdir -p "$CLAMP_DIR/_goals"
sandbox_write_loop "$CLAMP_DIR" ".claude"

run_slots_probe() { # run_slots_probe <value|__UNSET__> -> sets slots_out/slots_err
  local val="$1" out err
  rm -f "$CLAMP_DIR/_goals/breaker-state.json"
  out="$TMP/slots_stdout_${RANDOM}.txt"; err="$TMP/slots_stderr_${RANDOM}.txt"
  if [[ "$val" == "__UNSET__" ]]; then
    ( cd "$CLAMP_DIR" && unset LOOP_SLOTS && bash ./_loop/loop.sh 0 ) >"$out" 2>"$err"
  else
    ( cd "$CLAMP_DIR" && LOOP_SLOTS="$val" bash ./_loop/loop.sh 0 ) >"$out" 2>"$err"
  fi
  slots_out="$(cat "$out")"; slots_err="$(cat "$err")"
}

# 37: LOOP_SLOTS=0 -> effective 1, NO warning.
run_slots_probe "0"
if grep -qF 'slots: 1 — dark launch; design default 2 activates in STORY-011' <<< "$slots_out" \
   && [[ -z "$slots_err" ]]; then
  report PASS "37: LOOP_SLOTS=0 -> effective 1, banner correct, stderr empty (no warning)"
else
  report FAIL "37: LOOP_SLOTS=0 -> effective 1, no warning" "stdout='$slots_out' stderr='$slots_err'"
fi

# 38: LOOP_SLOTS=5 -> internally clamped to 3 (structural, since the guard's
# collapse-to-1 makes the intermediate 3 behaviorally invisible on its own),
# THEN the >1 dark-launch guard holds effective at 1 WITH the STORY-011
# warning (explicitly set >1).
t38_clamp_check() { # t38_clamp_check <file> -> 0 if SLOTS>3 clamp-to-3 exists, block-scoped
  local f="$1" ln window
  ln="$(grep -n 'SLOTS="\${LOOP_SLOTS:-2}"' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 10))p" "$f")"
  grep -qE 'SLOTS > 3' <<< "$window" && grep -qE '^\s*SLOTS=3\s*$' <<< "$window"
}
run_slots_probe "5"
if t38_clamp_check "$LOOP_SH" \
   && grep -qF 'slots: 1 — dark launch; design default 2 activates in STORY-011' <<< "$slots_out" \
   && grep -qF 'LOOP_SLOTS>1 requires driver-owned dispatch (STORY-011); running with 1' <<< "$slots_err"; then
  report PASS "38: LOOP_SLOTS=5 -> structural clamp-to-3 present in canonical loop.sh, effective 1 WITH the STORY-011 warning"
else
  report FAIL "38: LOOP_SLOTS=5 -> clamp 3 -> guard 1 WITH warning" \
    "clamp_present=$(t38_clamp_check "$LOOP_SH" && echo yes || echo no) stdout='$slots_out' stderr='$slots_err'"
fi

# 39: LOOP_SLOTS=3 -> warning + effective 1 (in-range, no upper clamp needed,
# still >1 so the dark-launch guard applies).
run_slots_probe "3"
if grep -qF 'slots: 1 — dark launch; design default 2 activates in STORY-011' <<< "$slots_out" \
   && grep -qF 'LOOP_SLOTS>1 requires driver-owned dispatch (STORY-011); running with 1' <<< "$slots_err"; then
  report PASS "39: LOOP_SLOTS=3 -> effective 1 WITH the STORY-011 warning"
else
  report FAIL "39: LOOP_SLOTS=3 -> warning + effective 1" "stdout='$slots_out' stderr='$slots_err'"
fi

# 40: UNSET -> effective 1, PLAIN banner, stderr COMPLETELY warning-free (the
# anti-warning-fatigue contract: the default path never warns).
run_slots_probe "__UNSET__"
if grep -qF 'slots: 1 — dark launch; design default 2 activates in STORY-011' <<< "$slots_out" \
   && [[ -z "$slots_err" ]]; then
  report PASS "40: LOOP_SLOTS unset -> effective 1, plain banner, stderr entirely warning-free (anti-warning-fatigue)"
else
  report FAIL "40: LOOP_SLOTS unset -> effective 1, warning-free stderr" "stdout='$slots_out' stderr='$slots_err'"
fi

# 40-mutation-proof: delete the dark-launch guard (the SLOTS>1 collapse-to-1
# block) in a COPY, content-anchored (not by line number) -> with an in-range
# explicit value (3), the banner must now show >1 (i.e. 3, unclamped by the
# removed guard) -- proving the guard, not some other code path, is what
# holds the banner at 1 above.
MUT40_DIR="$TMP/clamp-sandbox-mut40"
rm -rf "$MUT40_DIR"; mkdir -p "$MUT40_DIR/_goals" "$MUT40_DIR/_loop"
awk '
  /^if \(\( SLOTS > 1 \)\); then$/ && !done {
    print "EFFECTIVE_SLOTS=$SLOTS   # mutation (test 40): dark-launch guard removed"
    skip=4; done=1; next
  }
  skip>0 { skip--; next }
  { print }
' "$CLAMP_DIR/_loop/loop.sh" > "$MUT40_DIR/_loop/loop.sh"
chmod +x "$MUT40_DIR/_loop/loop.sh"
cp "$CLAMP_DIR/_loop/breaker.sh" "$MUT40_DIR/_loop/breaker.sh"
mut40_guard_removed=0
grep -qF 'EFFECTIVE_SLOTS=$SLOTS   # mutation (test 40)' "$MUT40_DIR/_loop/loop.sh" && \
  ! grep -qE '^if \(\( SLOTS > 1 \)\); then$' "$MUT40_DIR/_loop/loop.sh" && mut40_guard_removed=1
mut40_out="$TMP/mut40_stdout.txt"
( cd "$MUT40_DIR" && LOOP_SLOTS=3 bash ./_loop/loop.sh 0 ) >"$mut40_out" 2>/dev/null
mut40_banner="$(grep -oE 'slots: [0-9]+' "$mut40_out" | head -1 | grep -oE '[0-9]+')"
if [[ "$mut40_guard_removed" -eq 1 && -n "$mut40_banner" && "$mut40_banner" -gt 1 ]]; then
  report PASS "40-mutation-proof: dark-launch guard deleted in a COPY -> banner shows $mut40_banner (>1) with LOOP_SLOTS=3, confirming the guard (not other code) holds it at 1 on the real driver"
else
  report FAIL "40-mutation-proof: guard deletion must show banner >1" "guard_removed=$mut40_guard_removed banner='$mut40_banner'"
fi

# ---------------------------------------------------------------------------
# 41 (goal's flag=0 equivalence contract, items a/b/c/e): LOOP_WORKTREE
# unset/0 (default) + LOOP_SLOTS unset -> (a) no worktree created, no
# .loop-worktrees/ path; (b) no new branch; (c) an identical stub run yields
# the identical exit code (same sandbox, invoked twice); (e) stderr free of
# the guard warning. Item (d) -- CB0/CB1/CB2 semantics/thresholds unchanged
# -- is covered by the CB fixtures below: 50-52 run at these SAME default
# flags (49 is the flag=1 CB0-scoped fixture, not a default-flags proof).
# Item (f) is assertion 42 (its own literal enumeration proof, below).
# ---------------------------------------------------------------------------
EQUIV_DIR="$TMP/equiv-sandbox"
make_sandbox "$EQUIV_DIR" ".claude" 1 1
cat > "$EQUIV_DIR/_loop/stub-sentinel.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Deterministic single-pass stub: no commit, prints the sentinel immediately.
echo "<promise>COMPLETE</promise>"
exit 0
STUBEOF
chmod +x "$EQUIV_DIR/_loop/stub-sentinel.sh"

equiv_out_a="$TMP/equiv_a_stdout.txt"; equiv_err_a="$TMP/equiv_a_stderr.txt"
( cd "$EQUIV_DIR" && LOOP_CLI="$EQUIV_DIR/_loop/stub-sentinel.sh" bash ./_loop/loop.sh 1 ) \
  >"$equiv_out_a" 2>"$equiv_err_a"
equiv_rc_a=$?

equiv_out_b="$TMP/equiv_b_stdout.txt"; equiv_err_b="$TMP/equiv_b_stderr.txt"
( cd "$EQUIV_DIR" && LOOP_CLI="$EQUIV_DIR/_loop/stub-sentinel.sh" bash ./_loop/loop.sh 1 ) \
  >"$equiv_out_b" 2>"$equiv_err_b"
equiv_rc_b=$?

no_worktree_dir=1; [[ -e "$EQUIV_DIR/.loop-worktrees" ]] && no_worktree_dir=0
no_new_branch=1
equiv_branch_count="$(git -C "$EQUIV_DIR" branch --list 'loop/*' | wc -l)"
[[ "$equiv_branch_count" -ne 0 ]] && no_new_branch=0
identical_exit=0
[[ "$equiv_rc_a" -eq "$equiv_rc_b" ]] && identical_exit=1
stderr_warning_free=1
grep -qF 'LOOP_SLOTS>1 requires driver-owned dispatch' "$equiv_err_a" && stderr_warning_free=0

if [[ "$no_worktree_dir" -eq 1 && "$no_new_branch" -eq 1 && "$identical_exit" -eq 1 \
      && "$stderr_warning_free" -eq 1 ]]; then
  report PASS "41: flag=0 equivalence contract (a)(b)(c)(e) -- no .loop-worktrees/ path, no new branch, identical stub run (same sandbox, invoked twice) -> identical exit code ($equiv_rc_a == $equiv_rc_b), stderr free of the guard warning"
else
  report FAIL "41: flag=0 equivalence contract (a)(b)(c)(e)" \
    "no_worktree_dir=$no_worktree_dir no_new_branch=$no_new_branch(count=$equiv_branch_count) identical_exit=$identical_exit(rc_a=$equiv_rc_a rc_b=$equiv_rc_b) stderr_warning_free=$stderr_warning_free"
fi

# ---------------------------------------------------------------------------
# 42 (flag=0 equivalence contract, item f): the ONLY new stdout line versus
# the pre-story driver is the slot banner -- the expected stdout line set is
# enumerated LITERALLY here (never derived from git/HEAD, per the goal pin,
# which would degrade into a self-comparison against the NEW driver), with
# the iteration banner's embedded $(date -Is) timestamp normalized to a
# placeholder (marker-normalization precedent: this file's own sed-based
# clause normalization at assertion 33, run.sh:1163-1164 pre-story).
# ---------------------------------------------------------------------------
expected_f42="slots: 1 — dark launch; design default 2 activates in STORY-011
=== iteration 1/1 <TS> ===
<promise>COMPLETE</promise>
=== backlog complete after 1 iteration(s) ==="
normalized_f42="$(sed -E 's/=== iteration ([0-9]+\/[0-9]+) [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} ===/=== iteration \1 <TS> ===/' "$equiv_out_a")"
if [[ "$normalized_f42" == "$expected_f42" ]]; then
  report PASS "42: flag=0 equivalence contract (f) -- normalized stdout exactly matches the literally-enumerated expected line set (banner + iteration + tail-25 CLI output + completion line), timestamp normalized"
else
  report FAIL "42: flag=0 equivalence contract (f)" "expected='$expected_f42' actual(normalized)='$normalized_f42'"
fi

# ---------------------------------------------------------------------------
# 43: worktree lifecycle, flag=1, TRACKED sandbox (both _goals/backlog.md and
# {{IDE_DIR}} tracked/committed, so the preflight passes). The stub probes
# its OWN cwd (the worktree, per the driver/child boundary pin) into a file
# OUTSIDE the repo, commits progress, then prints the sentinel so the run
# completes via the pinned ff-only-integrate -> worktree-remove -> branch -d
# ordering.
# ---------------------------------------------------------------------------
LIFECYCLE_DIR="$TMP/lifecycle-sandbox"
make_sandbox "$LIFECYCLE_DIR" ".claude" 1 1
lifecycle_probe="$TMP/lifecycle-wt-probe.txt"
rm -f "$lifecycle_probe"

cat > "$LIFECYCLE_DIR/_loop/stub-lifecycle.sh" <<STUBEOF
#!/usr/bin/env bash
pwd > "$lifecycle_probe"
echo "progress" > progress.txt
git add progress.txt
git commit -qm "lifecycle progress"
echo "<promise>COMPLETE</promise>"
exit 0
STUBEOF
chmod +x "$LIFECYCLE_DIR/_loop/stub-lifecycle.sh"
# Commit the stub CLI itself so it is not mistaken for post-run litter below.
( cd "$LIFECYCLE_DIR" && git add -A && git commit -qm "add stub CLI" )

lifecycle_log="$TMP/lifecycle-run.log"
( cd "$LIFECYCLE_DIR" && LOOP_WORKTREE=1 LOOP_CLI="$LIFECYCLE_DIR/_loop/stub-lifecycle.sh" \
    bash ./_loop/loop.sh 1 ) >"$lifecycle_log" 2>&1
lifecycle_rc=$?

expected_wt_path="$LIFECYCLE_DIR/.loop-worktrees/slot-1"
probed_pwd="$( [[ -f "$lifecycle_probe" ]] && cat "$lifecycle_probe" )"
worktree_existed=0
[[ "$probed_pwd" == "$expected_wt_path" ]] && worktree_existed=1

worktree_removed_after=1
[[ -e "$expected_wt_path" ]] && worktree_removed_after=0

branch_deleted=1
[[ -n "$(git -C "$LIFECYCLE_DIR" branch --list 'loop/iter-1')" ]] && branch_deleted=0

zero_stray_branches=1
[[ -n "$(git -C "$LIFECYCLE_DIR" branch --list 'loop/*')" ]] && zero_stray_branches=0

# zero_litter: `.loop-worktrees` itself is not removed by `git worktree
# remove` (only the slot-N entry under it is), so an empty parent is
# expected, not litter -- verified empirically before writing this check.
# breaker-state.json is likewise an expected, non-litter byproduct.
zero_litter=1
if [[ -d "$LIFECYCLE_DIR/.loop-worktrees" ]]; then
  [[ -z "$(ls -A "$LIFECYCLE_DIR/.loop-worktrees" 2>/dev/null)" ]] || zero_litter=0
fi
litter_status="$(git -C "$LIFECYCLE_DIR" status --porcelain -- . ':(exclude)_goals/breaker-state.json')"
[[ -n "$litter_status" ]] && zero_litter=0

worktree_list_count="$(git -C "$LIFECYCLE_DIR" worktree list | wc -l)"
main_only=1
[[ "$worktree_list_count" -ne 1 ]] && main_only=0

integrated=1
git -C "$LIFECYCLE_DIR" log --oneline | grep -qF "lifecycle progress" || integrated=0

if [[ "$lifecycle_rc" -eq 0 && "$worktree_existed" -eq 1 && "$worktree_removed_after" -eq 1 \
      && "$branch_deleted" -eq 1 && "$zero_stray_branches" -eq 1 && "$zero_litter" -eq 1 \
      && "$main_only" -eq 1 && "$integrated" -eq 1 ]]; then
  report PASS "43: worktree lifecycle (flag=1, tracked sandbox) -- worktree existed during the run (probed cwd=$probed_pwd), removed after, branch loop/iter-1 integrated ff-only into main (progress commit present) + deleted, zero litter, zero stray branches"
else
  report FAIL "43: worktree lifecycle" \
    "rc=$lifecycle_rc existed=$worktree_existed removed_after=$worktree_removed_after branch_deleted=$branch_deleted zero_stray=$zero_stray_branches zero_litter=$zero_litter(status='$litter_status') main_only=$main_only(count=$worktree_list_count) integrated=$integrated probe='$probed_pwd' expected='$expected_wt_path'"
  sed 's/^/    /' "$lifecycle_log" >&2
fi

# ---------------------------------------------------------------------------
# 44 (preflight failure, fixture i): _goals/ GITIGNORED (this repo's own
# shape). `git worktree add` SUCCEEDS (the branch does not pre-exist), so the
# failure is the PREFLIGHT's own exit 5, not git's add failing with its own
# status. Stub carries a marker so "stub never ran" is an assertable fact.
# ---------------------------------------------------------------------------
PREFLIGHT_I_DIR="$TMP/preflight-i-sandbox"
make_sandbox "$PREFLIGHT_I_DIR" ".claude" 0 1   # _goals GITIGNORED, IDE_DIR tracked
preflight_i_marker="$TMP/preflight-i-stub-ran.marker"
rm -f "$preflight_i_marker"

cat > "$PREFLIGHT_I_DIR/_loop/stub-never.sh" <<STUBEOF
#!/usr/bin/env bash
touch "$preflight_i_marker"
echo "<promise>COMPLETE</promise>"
exit 0
STUBEOF
chmod +x "$PREFLIGHT_I_DIR/_loop/stub-never.sh"

preflight_i_log="$TMP/preflight-i-run.log"
( cd "$PREFLIGHT_I_DIR" && LOOP_WORKTREE=1 LOOP_CLI="$PREFLIGHT_I_DIR/_loop/stub-never.sh" \
    bash ./_loop/loop.sh 1 ) >"$preflight_i_log" 2>&1
preflight_i_rc=$?

stub_never_ran_i=1
[[ -f "$preflight_i_marker" ]] && stub_never_ran_i=0
worktree_removed_i=1
[[ -e "$PREFLIGHT_I_DIR/.loop-worktrees/slot-1" ]] && worktree_removed_i=0
branch_removed_i=1
[[ -n "$(git -C "$PREFLIGHT_I_DIR" branch --list 'loop/iter-1')" ]] && branch_removed_i=0
names_requirement_i=0
grep -qF "must be committed (not gitignored) for LOOP_WORKTREE=1" "$preflight_i_log" \
  && grep -qF "_goals/backlog.md" "$preflight_i_log" && names_requirement_i=1

if [[ "$preflight_i_rc" -eq 5 && "$stub_never_ran_i" -eq 1 && "$worktree_removed_i" -eq 1 \
      && "$branch_removed_i" -eq 1 && "$names_requirement_i" -eq 1 ]]; then
  report PASS "44: preflight failure fixture (i, gitignored _goals/) -- exit 5, loud error naming the tracked-instance requirement + _goals/backlog.md, worktree removed, branch removed, stub never ran (no silent fallback)"
else
  report FAIL "44: preflight failure fixture (i, gitignored _goals/)" \
    "rc=$preflight_i_rc(expected 5) stub_never_ran=$stub_never_ran_i worktree_removed=$worktree_removed_i branch_removed=$branch_removed_i names_requirement=$names_requirement_i"
  sed 's/^/    /' "$preflight_i_log" >&2
fi

# ---------------------------------------------------------------------------
# 45 (preflight failure, fixture ii): _goals/ TRACKED but {{IDE_DIR}}
# GITIGNORED (the cycle-2 mirror case). Same assertions as 44, mirrored;
# `git worktree add` SUCCEEDS here too.
# ---------------------------------------------------------------------------
PREFLIGHT_II_DIR="$TMP/preflight-ii-sandbox"
make_sandbox "$PREFLIGHT_II_DIR" ".claude" 1 0   # _goals TRACKED, IDE_DIR gitignored
preflight_ii_marker="$TMP/preflight-ii-stub-ran.marker"
rm -f "$preflight_ii_marker"

cat > "$PREFLIGHT_II_DIR/_loop/stub-never.sh" <<STUBEOF
#!/usr/bin/env bash
touch "$preflight_ii_marker"
echo "<promise>COMPLETE</promise>"
exit 0
STUBEOF
chmod +x "$PREFLIGHT_II_DIR/_loop/stub-never.sh"

preflight_ii_log="$TMP/preflight-ii-run.log"
( cd "$PREFLIGHT_II_DIR" && LOOP_WORKTREE=1 LOOP_CLI="$PREFLIGHT_II_DIR/_loop/stub-never.sh" \
    bash ./_loop/loop.sh 1 ) >"$preflight_ii_log" 2>&1
preflight_ii_rc=$?

stub_never_ran_ii=1
[[ -f "$preflight_ii_marker" ]] && stub_never_ran_ii=0
worktree_removed_ii=1
[[ -e "$PREFLIGHT_II_DIR/.loop-worktrees/slot-1" ]] && worktree_removed_ii=0
branch_removed_ii=1
[[ -n "$(git -C "$PREFLIGHT_II_DIR" branch --list 'loop/iter-1')" ]] && branch_removed_ii=0
names_requirement_ii=0
grep -qF "must be committed (not gitignored) for LOOP_WORKTREE=1" "$preflight_ii_log" \
  && grep -qF ".claude" "$preflight_ii_log" && names_requirement_ii=1

if [[ "$preflight_ii_rc" -eq 5 && "$stub_never_ran_ii" -eq 1 && "$worktree_removed_ii" -eq 1 \
      && "$branch_removed_ii" -eq 1 && "$names_requirement_ii" -eq 1 ]]; then
  report PASS "45: preflight failure fixture (ii, tracked _goals/ + gitignored {{IDE_DIR}}=.claude) -- exit 5, loud error naming the tracked-instance requirement + .claude, worktree removed, branch removed, stub never ran (no silent fallback)"
else
  report FAIL "45: preflight failure fixture (ii, tracked _goals/ + gitignored IDE_DIR)" \
    "rc=$preflight_ii_rc(expected 5) stub_never_ran=$stub_never_ran_ii worktree_removed=$worktree_removed_ii branch_removed=$branch_removed_ii names_requirement=$names_requirement_ii"
  sed 's/^/    /' "$preflight_ii_log" >&2
fi

# ---------------------------------------------------------------------------
# 46: abnormal slot exit -- stub exits nonzero AND leaves an uncommitted
# (dirty) worktree -> quarantine-lite: NOT integrated, --force cleanup,
# branch RETAINED (never deleted) and named in the closing output (the
# EXIT-trap-printed retained-branches summary).
# ---------------------------------------------------------------------------
ABNORMAL_DIR="$TMP/abnormal-sandbox"
make_sandbox "$ABNORMAL_DIR" ".claude" 1 1
abnormal_main_head_before="$(git -C "$ABNORMAL_DIR" rev-parse HEAD)"

cat > "$ABNORMAL_DIR/_loop/stub-abnormal.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Leaves the worktree dirty (uncommitted change) and exits nonzero -- neither
# a recognized CB1/CB2 disposition (single iteration, thresholds 3/5 not
# reached) nor a clean tree, so the driver's abnormal-exit branch fires.
echo "dirty, uncommitted" > dirty.txt
echo "boom"
exit 7
STUBEOF
chmod +x "$ABNORMAL_DIR/_loop/stub-abnormal.sh"

abnormal_log="$TMP/abnormal-run.log"
( cd "$ABNORMAL_DIR" && LOOP_WORKTREE=1 LOOP_CLI="$ABNORMAL_DIR/_loop/stub-abnormal.sh" \
    bash ./_loop/loop.sh 1 ) >"$abnormal_log" 2>&1
abnormal_rc=$?

abnormal_main_head_after="$(git -C "$ABNORMAL_DIR" rev-parse HEAD)"
names_branch=0
grep -qF "retaining branch 'loop/iter-1'" "$abnormal_log" && names_branch=1
closing_summary=0
grep -qF "retained branches from quarantined slots (NOT integrated): loop/iter-1" "$abnormal_log" && closing_summary=1
worktree_cleaned=1
[[ -e "$ABNORMAL_DIR/.loop-worktrees/slot-1" ]] && worktree_cleaned=0
branch_retained=1
[[ -z "$(git -C "$ABNORMAL_DIR" branch --list 'loop/iter-1')" ]] && branch_retained=0
no_integration=1
[[ "$abnormal_main_head_before" != "$abnormal_main_head_after" ]] && no_integration=0

if [[ "$abnormal_rc" -eq 1 && "$names_branch" -eq 1 && "$closing_summary" -eq 1 \
      && "$worktree_cleaned" -eq 1 && "$branch_retained" -eq 1 && "$no_integration" -eq 1 ]]; then
  report PASS "46: abnormal slot exit -- dirty worktree + nonzero exit -> NOT integrated, --force cleanup, branch loop/iter-1 RETAINED (not deleted) and named in the closing retained-branches summary"
else
  report FAIL "46: abnormal slot exit" \
    "rc=$abnormal_rc names_branch=$names_branch closing_summary=$closing_summary worktree_cleaned=$worktree_cleaned branch_retained=$branch_retained no_integration=$no_integration"
  sed 's/^/    /' "$abnormal_log" >&2
fi

# ---------------------------------------------------------------------------
# 47: available_slots accounting + refill-on-exit, structural (block-scoped,
# each anchored at its own site, matching the assertion-18/34 coupling
# precedent). Behavioral coverage at N=1 is implicit throughout 41-46/50-52 --
# every one of those runs completes its dispatched iteration(s) via this
# exact accounting.
# ---------------------------------------------------------------------------
t47_accounting_check() { # available_slots expression + negative-clamp, block-scoped
  local f="$1" ln window
  ln="$(grep -n 'available_slots=\$(( EFFECTIVE_SLOTS - active_slots ))' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 4))p" "$f")"
  grep -qE 'available_slots < 0' <<< "$window"
}
t47_refill_check() { # refill-on-slot-exit, block-scoped at the decrement site
  local f="$1" ln window
  ln="$(grep -n 'active_slots=\$((active_slots - 1))' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "$((ln - 1)),$((ln + 1))p" "$f")"
  grep -qF 'refill trigger' <<< "$window"
}
if t47_accounting_check "$LOOP_SH" && t47_refill_check "$LOOP_SH"; then
  report PASS "47: available_slots/refill -- accounting expression (EFFECTIVE_SLOTS - active_slots) + negative-clamp, and refill-on-slot-exit (active_slots decrement + 'refill trigger' comment), both present in canonical loop.sh, block-scoped"
else
  report FAIL "47: available_slots/refill" \
    "accounting=$(t47_accounting_check "$LOOP_SH" && echo ok || echo FAIL) refill=$(t47_refill_check "$LOOP_SH" && echo ok || echo FAIL)"
fi

# ---------------------------------------------------------------------------
# 48 (mutation-prove by fixture): ff-only integration stop. The stub commits
# progress inside its OWN worktree, but ALSO makes an EXTERNAL commit
# directly against the sandbox's MAIN tree (simulating a concurrent
# modification landing on main while the slot was running) before it exits
# -- by the time the driver reaps the child and attempts
# `git merge --ff-only`, main has diverged, so the branch is no longer a
# fast-forward. Driver stops loudly at integration: exit 5, branch NOT
# force-merged (main's log never gains the slot's commit).
# ---------------------------------------------------------------------------
FFONLY_DIR="$TMP/ffonly-sandbox"
make_sandbox "$FFONLY_DIR" ".claude" 1 1

cat > "$FFONLY_DIR/_loop/stub-ffonly.sh" <<STUBEOF
#!/usr/bin/env bash
echo "slot progress" > slot-progress.txt
git add slot-progress.txt
git commit -qm "slot-side commit (never integrated)"
# Simulate an EXTERNAL, concurrent commit landing on the sandbox's MAIN tree
# (a separate checkout of the SAME repo, not this worktree) while the slot
# was running -- this is what makes the eventual ff-only merge non-fast-forward.
git -C "$FFONLY_DIR" commit --allow-empty -qm "external main-tree commit (concurrent)"
echo "no sentinel this iteration"
exit 0
STUBEOF
chmod +x "$FFONLY_DIR/_loop/stub-ffonly.sh"

ffonly_log="$TMP/ffonly-run.log"
( cd "$FFONLY_DIR" && LOOP_WORKTREE=1 LOOP_CLI="$FFONLY_DIR/_loop/stub-ffonly.sh" \
    bash ./_loop/loop.sh 1 ) >"$ffonly_log" 2>&1
ffonly_rc=$?

names_failure=0
grep -qF "integration failed: 'loop/iter-1' is not a fast-forward" "$ffonly_log" && names_failure=1
not_force_merged=1
git -C "$FFONLY_DIR" log --oneline 2>/dev/null | grep -qF "slot-side commit" && not_force_merged=0

if [[ "$ffonly_rc" -eq 5 && "$names_failure" -eq 1 && "$not_force_merged" -eq 1 ]]; then
  report PASS "48: ff-only integration stop (mutation-prove: external main-tree commit forces a non-fast-forward) -- exit 5, loud 'not a fast-forward' stop, worktree branch NOT force-merged into main"
else
  report FAIL "48: ff-only integration stop" "rc=$ffonly_rc(expected 5) names_failure=$names_failure not_force_merged=$not_force_merged"
  sed 's/^/    /' "$ffonly_log" >&2
fi

# ---------------------------------------------------------------------------
# 49: CB0 scoped revert (LOOP_WORKTREE=1). Stub commits a PROTECTED-path
# change (_loop/loop.sh itself) inside its own worktree -> CB0 fires: exit 4,
# the SANDBOX MAIN TREE's HEAD is unchanged (the revert + --force removal
# happen entirely on the worktree side), no integration, worktree cleaned up.
# ---------------------------------------------------------------------------
CB0_DIR="$TMP/cb0-sandbox"
make_sandbox "$CB0_DIR" ".claude" 1 1
cb0_main_head_before="$(git -C "$CB0_DIR" rev-parse HEAD)"

cat > "$CB0_DIR/_loop/stub-cb0.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Modifies a PROTECTED path (_loop/, per the CB0 path list) inside the
# worktree -- must trigger the run-fatal revert, never reach CB1/CB2.
echo "# protected-path tamper" >> _loop/loop.sh
git add _loop/loop.sh
git commit -qm "oops: touched protected _loop/"
echo "irrelevant output"
exit 0
STUBEOF
chmod +x "$CB0_DIR/_loop/stub-cb0.sh"

cb0_log="$TMP/cb0-run.log"
( cd "$CB0_DIR" && LOOP_WORKTREE=1 LOOP_CLI="$CB0_DIR/_loop/stub-cb0.sh" \
    bash ./_loop/loop.sh 1 ) >"$cb0_log" 2>&1
cb0_rc=$?

cb0_main_head_after="$(git -C "$CB0_DIR" rev-parse HEAD)"
main_head_unchanged=0
[[ "$cb0_main_head_before" == "$cb0_main_head_after" ]] && main_head_unchanged=1
cb0_worktree_cleaned=1
[[ -e "$CB0_DIR/.loop-worktrees/slot-1" ]] && cb0_worktree_cleaned=0
cb0_no_integration=1
git -C "$CB0_DIR" log --oneline | grep -qF "protected _loop/" && cb0_no_integration=0
cb0_named=0
grep -qF "protected-path modification detected" "$cb0_log" && cb0_named=1

if [[ "$cb0_rc" -eq 4 && "$main_head_unchanged" -eq 1 && "$cb0_worktree_cleaned" -eq 1 \
      && "$cb0_no_integration" -eq 1 && "$cb0_named" -eq 1 ]]; then
  report PASS "49: CB0 scoped revert (LOOP_WORKTREE=1) -- protected-path commit inside the worktree -> exit 4, sandbox MAIN TREE HEAD unchanged ($cb0_main_head_before), no integration, worktree cleaned up"
else
  report FAIL "49: CB0 scoped revert" \
    "rc=$cb0_rc(expected 4) main_head_unchanged=$main_head_unchanged(before=$cb0_main_head_before after=$cb0_main_head_after) worktree_cleaned=$cb0_worktree_cleaned no_integration=$cb0_no_integration named=$cb0_named"
  sed 's/^/    /' "$cb0_log" >&2
fi

# ---------------------------------------------------------------------------
# 50 (per-slot CB1 meaning-preserved proof): assertion 15 already covers the
# CB1 rate-limited carve-out end-to-end against the RE-EMITTED instance
# driver (pre-story until task 05); this proves the SAME CB1 threshold (3
# consecutive no-progress iterations) against the CANONICAL, newly
# -restructured (slot-table-based counters) driver directly, at the default
# flags (LOOP_WORKTREE=0). Stub never commits, never rate-limits -> exit 2
# after exactly 3 no-progress iterations.
# ---------------------------------------------------------------------------
CB1_CANON_DIR="$TMP/cb1-canonical-sandbox"
make_sandbox "$CB1_CANON_DIR" ".claude" 1 1

cat > "$CB1_CANON_DIR/_loop/stub-cb1.sh" <<'STUBEOF'
#!/usr/bin/env bash
# Deliberately avoids any wording detect_rate_limit's pattern could match
# (rate/limit/quota/429/too many requests) -- an earlier draft's own
# incidental phrasing false-positived the detector and OPENED the breaker,
# derailing this fixture into a 600s cooldown sleep.
echo "steady state, nothing new this pass"
exit 0
STUBEOF
chmod +x "$CB1_CANON_DIR/_loop/stub-cb1.sh"

cb1c_log="$TMP/cb1-canonical-run.log"
( cd "$CB1_CANON_DIR" && LOOP_CLI="$CB1_CANON_DIR/_loop/stub-cb1.sh" bash ./_loop/loop.sh 5 ) \
  >"$cb1c_log" 2>&1
cb1c_rc=$?

if [[ "$cb1c_rc" -eq 2 ]] && grep -qF -- '--- no progress (3/3)' "$cb1c_log" \
   && grep -qF 'circuit breaker: 3 iterations without a commit' "$cb1c_log"; then
  report PASS "50: per-slot CB1 (canonical driver, default flags) -- meaning preserved: exit 2 after exactly 3 no-progress iterations (slot-table counter reaches 3/3)"
else
  report FAIL "50: per-slot CB1 (canonical driver)" "rc=$cb1c_rc(expected 2)"
  sed 's/^/    /' "$cb1c_log" >&2
fi

# ---------------------------------------------------------------------------
# 51 (per-slot CB2 -- NEW, previously ZERO CB2 coverage): stub commits
# progress every iteration (so CB1's no-progress counter never fires) but
# prints an IDENTICAL 5-line failure signature and exits nonzero every time
# -> the per-slot same-error counter reaches 5 -> exit 3.
# ---------------------------------------------------------------------------
CB2_DIR="$TMP/cb2-sandbox"
make_sandbox "$CB2_DIR" ".claude" 1 1
cb2_counter_file="$TMP/cb2-counter.txt"
rm -f "$cb2_counter_file"

cat > "$CB2_DIR/_loop/stub-cb2.sh" <<STUBEOF
#!/usr/bin/env bash
counter_file="$cb2_counter_file"
n=0
[[ -f "\$counter_file" ]] && n="\$(cat "\$counter_file")"
n=\$((n + 1))
echo "\$n" > "\$counter_file"
echo "progress \$n" >> progress.txt
git add progress.txt
git commit -qm "progress \$n"
printf 'ERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\n'
exit 1
STUBEOF
chmod +x "$CB2_DIR/_loop/stub-cb2.sh"

cb2_log="$TMP/cb2-run.log"
( cd "$CB2_DIR" && LOOP_CLI="$CB2_DIR/_loop/stub-cb2.sh" bash ./_loop/loop.sh 6 ) >"$cb2_log" 2>&1
cb2_rc=$?

if [[ "$cb2_rc" -eq 3 ]] && grep -qF 'circuit breaker: same error 5 times' "$cb2_log" \
   && ! grep -qF 'no progress' "$cb2_log"; then
  report PASS "51: per-slot CB2 (NEW behavioral coverage) -- 5 identical failure outputs (each iteration still committing progress, so CB1 never fires) -> exit 3"
else
  report FAIL "51: per-slot CB2 behavioral" "rc=$cb2_rc(expected 3)"
  sed 's/^/    /' "$cb2_log" >&2
fi

# ---------------------------------------------------------------------------
# 52 (per-slot CB2 control): 4 identical failure outputs, then a DIFFERENT
# 5th -> the same-error counter resets on the 5th, never reaching 5 -> the
# run must NOT exit 3 (it exhausts MAX_ITER=5 and exits 1).
# ---------------------------------------------------------------------------
CB2_CTRL_DIR="$TMP/cb2-control-sandbox"
make_sandbox "$CB2_CTRL_DIR" ".claude" 1 1
cb2_ctrl_counter_file="$TMP/cb2-control-counter.txt"
rm -f "$cb2_ctrl_counter_file"

cat > "$CB2_CTRL_DIR/_loop/stub-cb2-control.sh" <<STUBEOF
#!/usr/bin/env bash
counter_file="$cb2_ctrl_counter_file"
n=0
[[ -f "\$counter_file" ]] && n="\$(cat "\$counter_file")"
n=\$((n + 1))
echo "\$n" > "\$counter_file"
echo "progress \$n" >> progress.txt
git add progress.txt
git commit -qm "progress \$n"
if [[ "\$n" -eq 5 ]]; then
  printf 'ERROR: a totally different failure on the 5th pass\n'
else
  printf 'ERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\nERROR: build failed\n'
fi
exit 1
STUBEOF
chmod +x "$CB2_CTRL_DIR/_loop/stub-cb2-control.sh"

cb2_ctrl_log="$TMP/cb2-control-run.log"
( cd "$CB2_CTRL_DIR" && LOOP_CLI="$CB2_CTRL_DIR/_loop/stub-cb2-control.sh" bash ./_loop/loop.sh 5 ) \
  >"$cb2_ctrl_log" 2>&1
cb2_ctrl_rc=$?

if [[ "$cb2_ctrl_rc" -eq 1 ]] && ! grep -qF 'circuit breaker: same error 5 times' "$cb2_ctrl_log" \
   && grep -qF 'max iterations (5) reached' "$cb2_ctrl_log"; then
  report PASS "52: per-slot CB2 control -- 4 identical + 1 DIFFERENT failure -> same-error counter resets, run does NOT exit 3 (exhausts MAX_ITER, exits 1)"
else
  report FAIL "52: per-slot CB2 control" "rc=$cb2_ctrl_rc(expected 1)"
  sed 's/^/    /' "$cb2_ctrl_log" >&2
fi

# ---------------------------------------------------------------------------
# 53: ps1 structural parity, block-scoped (assertion-18/34 coupling
# precedent) against the CANONICAL loop.ps1 -- not runtime-verified, pwsh
# absent, same disposition as this file's other ps1 structural guards.
# ---------------------------------------------------------------------------
t53_slots_check() { # $env:LOOP_SLOTS read + clamp, block-scoped
  local f="$1" ln window
  ln="$(grep -n '\$SlotsRaw = \$env:LOOP_SLOTS' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 10))p" "$f")"
  grep -qF '$Slots -lt 1' <<< "$window" && grep -qF '$Slots -gt 3' <<< "$window"
}
t53_worktree_check() { grep -qF '$env:LOOP_WORKTREE' "$1"; }
t53_guard_msg_check() { grep -qF 'LOOP_SLOTS>1 requires driver-owned dispatch' "$1"; }
t53_preflight_check() { # two-path preflight, block-scoped
  local f="$1" ln window
  ln="$(grep -n 'backlogOk = Test-Path' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 6))p" "$f")"
  grep -qF 'ideDirOk = Test-Path' <<< "$window" && grep -qF 'PathType Container' <<< "$window"
}
t53_startjob_wait_check() { # Start-Job/process wait, block-scoped
  local f="$1" ln window
  ln="$(grep -n 'Start-Job -ScriptBlock' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 30))p" "$f")"
  grep -qF 'Wait-Job' <<< "$window"
}
t53_removal_ordering_check() { # wait-then-remove comment + --force/prune fallback
  local f="$1" ln window
  ln="$(grep -n 'Windows removal ordering' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 12))p" "$f")"
  grep -qF 'Wait-Job' <<< "$window" || return 1
  grep -qF -- '--force' "$f" && grep -qF 'prune' "$f"
}
t53_abnormal_check() { # abnormal-exit branch, block-scoped
  local f="$1" ln window
  ln="$(grep -n 'slot exited abnormally' "$f" | head -1 | cut -d: -f1)"
  [[ -z "$ln" ]] && return 1
  window="$(sed -n "${ln},$((ln + 6))p" "$f")"
  grep -qF 'retainedBranches +=' <<< "$window"
}
t53_capacity_check() { grep -qF 'Capacity-contention rationale' "$1"; }
t53_exit5_check() { grep -qF 'Exit 5 = setup or integration failure' "$1"; }

if t53_slots_check "$LOOP_PS1" && t53_worktree_check "$LOOP_PS1" && t53_guard_msg_check "$LOOP_PS1" \
   && t53_preflight_check "$LOOP_PS1" && t53_startjob_wait_check "$LOOP_PS1" \
   && t53_removal_ordering_check "$LOOP_PS1" && t53_abnormal_check "$LOOP_PS1" \
   && t53_capacity_check "$LOOP_PS1" && t53_exit5_check "$LOOP_PS1"; then
  report PASS "53: ps1 structural parity -- \$env:LOOP_SLOTS+clamp, \$env:LOOP_WORKTREE, the STORY-011 guard message, the two-path preflight (backlogOk/ideDirOk, Container test), Start-Job/Wait-Job, removal ordering (wait-then-remove + --force/prune fallback), the abnormal-exit branch (retainedBranches +=), the capacity-contention comment, and the appended exit-5 sentence all present in canonical loop.ps1 -- not runtime-verified, pwsh absent"
else
  report FAIL "53: ps1 structural parity" \
    "slots=$(t53_slots_check "$LOOP_PS1" && echo ok || echo FAIL) worktree=$(t53_worktree_check "$LOOP_PS1" && echo ok || echo FAIL) guard_msg=$(t53_guard_msg_check "$LOOP_PS1" && echo ok || echo FAIL) preflight=$(t53_preflight_check "$LOOP_PS1" && echo ok || echo FAIL) startjob_wait=$(t53_startjob_wait_check "$LOOP_PS1" && echo ok || echo FAIL) removal_ordering=$(t53_removal_ordering_check "$LOOP_PS1" && echo ok || echo FAIL) abnormal=$(t53_abnormal_check "$LOOP_PS1" && echo ok || echo FAIL) capacity=$(t53_capacity_check "$LOOP_PS1" && echo ok || echo FAIL) exit5=$(t53_exit5_check "$LOOP_PS1" && echo ok || echo FAIL)"
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
