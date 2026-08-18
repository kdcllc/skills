#!/usr/bin/env bash
# Autonomous feature loop for {{PROJECT_NAME}} — drives one `auto-loop` iteration per
# fresh-context CLI run. State lives in _goals/backlog.md + git, never in memory.
#
# Twin: skills/setup/templates/loop/loop.ps1 (PowerShell 7+) — behaviorally identical —
# same defaults, guards, and exit codes; any divergence is a bug.
#
# Usage:   _loop/loop.sh [max-iterations]        (default 10)
# CLI:     override with LOOP_CLI, e.g. LOOP_CLI="codex exec" or LOOP_CLI="claude -p"
#
# SAFETY: run inside a sandbox (worktree/container) with minimal credentials.
# This script never pushes and never bypasses permission prompts by itself.
#
# Exit codes: 0 = backlog complete (sentinel found); 1 = max iterations reached without
# completion; 2 = circuit breaker — no commit for 3 consecutive iterations; 3 = circuit
# breaker — same failure signature 5 times consecutively; 4 = protected-path
# modification detected (iteration reverted).
set -euo pipefail

MAX_ITER="${1:-10}"
LOOP_CLI="${LOOP_CLI:-claude -p}"
PROMPT_FILE="$(dirname "$0")/PROMPT.md"
SENTINEL='<promise>COMPLETE</promise>'

no_progress=0
same_error=0
last_error_sig=""

for ((i = 1; i <= MAX_ITER; i++)); do
  echo "=== iteration $i/$MAX_ITER $(date -Is) ==="
  head_before="$(git rev-parse HEAD)"

  set +e
  output="$($LOOP_CLI "$(cat "$PROMPT_FILE")" 2>&1)"
  status=$?
  set -e
  printf '%s\n' "$output" | tail -n 25

  if printf '%s' "$output" | grep -qF "$SENTINEL"; then
    echo "=== backlog complete after $i iteration(s) ==="
    exit 0
  fi

  # Circuit breaker 0: protected paths — the loop must never modify its own machinery
  if ! git diff --quiet "$head_before" HEAD -- _loop/ '{{IDE_DIR}}/agents/' '{{IDE_DIR}}/skills/' orchestration-kit.manifest.json .gitattributes 2>/dev/null; then
    echo "!!! protected-path modification detected — reverting iteration and stopping" >&2
    git reset --hard "$head_before"
    exit 4
  fi

  # Circuit breaker 1: no new commit for 3 consecutive iterations
  if [[ "$(git rev-parse HEAD)" == "$head_before" ]]; then
    no_progress=$((no_progress + 1))
    echo "--- no progress ($no_progress/3)"
    if ((no_progress >= 3)); then
      echo "!!! circuit breaker: 3 iterations without a commit — stopping" >&2
      exit 2
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
