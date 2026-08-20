#!/usr/bin/env bash
# Autonomous feature loop for {{PROJECT_NAME}} — drives one `auto-loop` iteration per
# fresh-context CLI run. State lives in _goals/backlog.md + git, never in memory.
#
# Twin: loop.ps1 (PowerShell 7+) — behaviorally identical —
# same defaults, guards, and exit codes; any divergence is a bug.
#
# Usage:   _loop/loop.sh [max-iterations]        (default 10)
# CLI:     override with LOOP_CLI, e.g. LOOP_CLI="codex exec" or LOOP_CLI="claude -p"
#
# SAFETY: run inside a sandbox (worktree/container) with minimal credentials.
# This script never pushes and never bypasses permission prompts by itself.
#
# Breaker: sources breaker.sh (functions: breaker_load, breaker_should_skip,
# breaker_record, breaker_current_model); state file: _goals/breaker-state.json.
#
# Exit codes: 0 = backlog complete (sentinel found); 1 = max iterations reached without
# completion; 2 = circuit breaker — no commit for 3 consecutive iterations; 3 = circuit
# breaker — same failure signature 5 times consecutively; 4 = protected-path
# modification detected (iteration reverted).
# 126/127 (shell-propagated edge cases, not loop-owned codes): command-not-found
# propagates as exit 127 and found-but-not-executable as exit 126 (bash) —
# standard shell convention, distinct from the four codes above. The
# PowerShell twin's Get-Command guard does not attempt to distinguish the two
# and exits 127 for both — a stated, knowingly-accepted platform difference
# (the 126 case is Unix-host-only).
set -euo pipefail

MAX_ITER="${1:-10}"
LOOP_CLI="${LOOP_CLI:-claude -p}"
LOOP_MODEL_FLAG="${LOOP_MODEL_FLAG:-}"
PROMPT_FILE="$(dirname "$0")/PROMPT.md"
SENTINEL='<promise>COMPLETE</promise>'
STATE_FILE="_goals/breaker-state.json"

# shellcheck source=./breaker.sh
source "$(dirname "$0")/breaker.sh"
breaker_load "$STATE_FILE" "{{LOOP_MODEL_CHAIN}}"

# detect_rate_limit <output> -> return 0 iff any SINGLE line of <output> matches the
# pinned rate-limit pattern (case-insensitive), 1 otherwise. Deliberately line-oriented
# (grep matches within one line at a time — it never merges text across newlines) —
# never `[[ output =~ pattern ]]` on the whole multi-line capture, whose `.` can cross
# line boundaries and falsely join unrelated lines (e.g. a bare token count on one line
# and the word "error" on another).
# Herestrings (`<<<`), not `printf | grep`, and a SINGLE grep per stage (no
# inter-grep pipe at all): under `set -o pipefail`, any pipeline whose
# downstream `grep -q` matches and exits early can SIGPIPE an upstream process
# still writing a large capture — pipefail then reports the pipeline's status
# as that upstream process's non-zero (SIGPIPE, 141, the rightmost NON-ZERO
# exit), not the downstream grep's own successful 0, silently flipping a real
# match into "no match". A herestring feeds data via a pre-materialized temp
# file with no live producer to SIGPIPE, closing that path for stage 1. Stage
# 2's "429 co-occurring with a keyword on the same line" no longer pipes one
# grep into another either: the co-occurrence is folded into ONE bidirectional
# alternation (`429.*(keyword)|(keyword).*429`) so a single process decides
# the whole stage — no process boundary for a downstream match to SIGPIPE
# across, at any capture size. Still strictly line-oriented (grep's `.` never
# crosses a newline), so a bare `429` on one line and a keyword on another
# never falsely co-occur.
detect_rate_limit() {
  local output="$1"
  grep -qiE 'rate.?limit|too many requests|quota (exceeded|reached|hit)' <<< "$output" && return 0
  grep -qiE '429.*(error|status|http|rate|too many)|(error|status|http|rate|too many).*429' <<< "$output" && return 0
  return 1
}

no_progress=0
same_error=0
last_error_sig=""

for ((i = 1; i <= MAX_ITER; i++)); do
  echo "=== iteration $i/$MAX_ITER $(date -Is) ==="

  # Mechanism B: single machine, no loop restructure. If OPEN and cooldown has not
  # elapsed, log + sleep, then ask again — the second call performs OPEN->HALF-OPEN
  # and returns 0 — and proceed with this SAME iteration.
  skip="$(breaker_should_skip "$STATE_FILE" "$(date +%s)")"
  if ((skip > 0)); then
    echo "breaker OPEN — sleeping ${skip}s before HALF-OPEN trial"
    sleep "$skip"
    skip="$(breaker_should_skip "$STATE_FILE" "$(date +%s)")"
  fi

  head_before="$(git rev-parse HEAD)"

  model="$(breaker_current_model "$STATE_FILE")"
  # Plain string (not an array): kept consistent with $LOOP_CLI's own unquoted,
  # naive whitespace-splitting expansion below — and avoids the pre-4.4 bash bug
  # where an empty array referenced via "${arr[@]}" trips `set -u` as unbound.
  model_arg=""
  if [[ -n "$LOOP_MODEL_FLAG" && -n "$model" ]]; then
    model_arg="$LOOP_MODEL_FLAG $model"
  fi

  set +e
  p="$(cat "$PROMPT_FILE")"
  # CRLF parity (twin: loop.ps1's TrimEnd): strip BOTH trailing CR and LF, not CR alone
  # — command substitution above already strips trailing newlines, so a \n before a \r
  # (e.g. a CRLF file ending "text\r\n\r\n") would otherwise re-expose a trailing \r
  # that a CR-only strip misses.
  while [[ "$p" == *$'\r' || "$p" == *$'\n' ]]; do p="${p%?}"; done
  output="$($LOOP_CLI $model_arg "$p" 2>&1)"
  status=$?
  set -e
  printf '%s\n' "$output" | tail -n 25

  if detect_rate_limit "$output"; then
    detected=1
  else
    detected=0
  fi
  breaker_record "$STATE_FILE" "$detected" "$(date +%s)"

  # Herestring, not `printf | grep`: same pipefail+SIGPIPE false-negative class as
  # detect_rate_limit above — no live producer here for a downstream match to SIGPIPE.
  if grep -qF "$SENTINEL" <<< "$output"; then
    echo "=== backlog complete after $i iteration(s) ==="
    exit 0
  fi

  # Circuit breaker 0: protected paths — the loop must never modify its own machinery
  if ! git diff --quiet "$head_before" HEAD -- _loop/ '{{IDE_DIR}}/agents/' '{{IDE_DIR}}/skills/' orchestration-kit.manifest.json .gitattributes 2>/dev/null; then
    echo "!!! protected-path modification detected — reverting iteration and stopping" >&2
    git reset --hard "$head_before"
    exit 4
  fi

  # Circuit breaker 1: no new commit for 3 consecutive iterations.
  # CB1 carve-out (amended scope): a rate-limited pass never counts against this
  # counter — the breaker owns recovery for it instead. Non-rate-limited no-commit
  # passes increment no_progress exactly as before.
  if [[ "$(git rev-parse HEAD)" == "$head_before" ]]; then
    if ((detected == 1)); then
      echo "rate-limited pass — CB1 exempt (breaker owns it)"
    else
      no_progress=$((no_progress + 1))
      echo "--- no progress ($no_progress/3)"
      if ((no_progress >= 3)); then
        echo "!!! circuit breaker: 3 iterations without a commit — stopping" >&2
        exit 2
      fi
    fi
  else
    no_progress=0
  fi

  # Circuit breaker 2: same failure signature 5 times in a row
  if ((status != 0)); then
    error_sig="$(printf '%s' "$output" | tail -n 5 | sha256sum | cut -d' ' -f1)"
    if [[ "$error_sig" == "$last_error_sig" ]]; then
      same_error=$((same_error + 1))
      if ((same_error >= 5)); then
        echo "!!! circuit breaker: same error 5 times — stopping" >&2
        exit 3
      fi
    else
      same_error=1
      last_error_sig="$error_sig"
    fi
  else
    same_error=0
    last_error_sig=""
  fi
done

echo "=== max iterations ($MAX_ITER) reached; backlog not complete ==="
exit 1
