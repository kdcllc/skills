#!/usr/bin/env bash
# Autonomous feature loop for {{PROJECT_NAME}} — drives one `auto-loop` iteration per
# fresh-context CLI run. State lives in _goals/backlog.md + git, never in memory.
#
# Twin: loop.ps1 (PowerShell 7+) — behaviorally identical —
# same defaults, guards, and exit codes; any divergence is a bug.
#
# Usage:   _loop/loop.sh [max-iterations]        (default 10)
# CLI:     override with LOOP_CLI, e.g. LOOP_CLI="codex exec" or LOOP_CLI="claude -p"
# SLOTS:   override with LOOP_SLOTS (default 2, clamped [1,3]) — a dark-launch guard (STORY-010) holds effective concurrency at 1 regardless of this value until STORY-011.
# WORKTREE: override with LOOP_WORKTREE=1 to run each iteration in its own git worktree under .loop-worktrees/ (default 0 = main tree, today's behavior).
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
# Exit 5 = setup or integration failure: the LOOP_WORKTREE=1 tracked-instance
# preflight failing after `git worktree add`, or the interim ff-only
# integration step hitting a non-fast-forward -- both are loud, driver-level
# stops that never silently fall back to the main tree (the preflight path
# removes its worktree; the non-ff path retains worktree and branch for
# inspection).
set -euo pipefail

MAX_ITER="${1:-10}"   # total iterations dispatched ACROSS slots (today: the
                       # one slot the dark-launch guard below permits)
LOOP_CLI="${LOOP_CLI:-claude -p}"
LOOP_MODEL_FLAG="${LOOP_MODEL_FLAG:-}"
# Absolute paths, resolved BEFORE any `cd` happens anywhere below (the child
# subshell dispatched per-iteration cd's into the slot's worktree at
# LOOP_WORKTREE=1) -- both were relative and depended on the invocation cwd.
PROMPT_FILE="$(cd "$(dirname "$0")" && pwd)/PROMPT.md"
SENTINEL='<promise>COMPLETE</promise>'
STATE_FILE="$PWD/_goals/breaker-state.json"

# shellcheck source=./breaker.sh
source "$(dirname "$0")/breaker.sh"
breaker_load "$STATE_FILE" "{{LOOP_MODEL_CHAIN}}"

# --- LOOP_SLOTS: read, clamp, dark-launch guard -----------------------------
# LOOP_SLOTS_EXPLICIT captures the RAW value (pre-clamp) so the guard below
# can tell "explicitly requested >1" apart from the unset default -- the
# stderr warning fires only in the former case (no warning fatigue on every
# default run).
LOOP_SLOTS_EXPLICIT="${LOOP_SLOTS:-}"
SLOTS="${LOOP_SLOTS:-2}"
if (( SLOTS < 1 )); then
  SLOTS=1
fi
if (( SLOTS > 3 )); then
  SLOTS=3
fi

# Capacity-contention rationale (why the design default is 2, not 3+): (1) one
# iteration fans out many subagents (implementer/test-writer execute, judge
# verifies every task, fixes are always re-judged), and that per-iteration
# fan-out multiplies by N against a shared ~20-concurrent subagent-spawn
# ceiling; (2) all N slots would authenticate through the same LOOP_CLI as one
# provider account, so they would share ONE rate-limit budget -- more slots
# raise request rate against an unchanged quota rather than adding real
# throughput; (3) the circuit breaker is provider-global (one state file, one
# 600s cooldown) -- a single OPEN trip stalls ALL N slots at once, so more
# slots raise the odds of a full-run stall without shortening it. N=3 crowds
# fact (1) hardest, which is why 2 (not 3) is the design default.
#
# LOOP_SLOTS dark launch (STORY-010): this story ships the slot-supervision
# STRUCTURE only (slot table, available_slots accounting, poll supervision,
# per-slot breakers) -- driver-owned dispatch, admission, and the real
# integrator arrive in STORY-011. Until then EFFECTIVE_SLOTS is held at 1
# regardless of the clamped SLOTS value above, so the machinery below always
# drives exactly one concurrent child -- the same structure STORY-011
# activates for N>1 without restructuring it.
if (( SLOTS > 1 )); then
  EFFECTIVE_SLOTS=1
else
  EFFECTIVE_SLOTS=$SLOTS
fi

if [[ -n "$LOOP_SLOTS_EXPLICIT" ]] && (( LOOP_SLOTS_EXPLICIT > 1 )); then
  echo "LOOP_SLOTS>1 requires driver-owned dispatch (STORY-011); running with 1" >&2
fi
echo "slots: $EFFECTIVE_SLOTS — dark launch; design default 2 activates in STORY-011"

# LOOP_WORKTREE: 0 (default) runs every iteration in the main tree -- today's
# behavior, unchanged. 1 activates the worktree lifecycle below (loud
# tracked-instance preflight, per-slot HEAD/CB0-2, pinned ff-only
# integration, quarantine-lite on abnormal exit).
WORKTREE="${LOOP_WORKTREE:-0}"

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

# --- Slot table --------------------------------------------------------------
# bash-3.2-safe parallel indexed arrays (no associative arrays -- same floor
# breaker.sh:172-174 documents for `local -n`: bash 3.2 on stock macOS has
# neither). One row per slot, indexed 0..EFFECTIVE_SLOTS-1; STORY-011 raises
# EFFECTIVE_SLOTS past 1 by looping over more rows, not by changing this shape.
slot_pid=()
slot_tree=()
slot_branch=()
slot_no_progress=()
slot_last_error_sig=()
slot_same_error=()
slot_state=()   # "idle" | "running"

SLOT=0   # the dark-launch guard means every iteration dispatches into (and
         # reaps) this one row; STORY-011 turns this into a loop 0..EFFECTIVE_SLOTS-1.
slot_pid[SLOT]=0
slot_tree[SLOT]=""
slot_branch[SLOT]=""
slot_no_progress[SLOT]=0
slot_last_error_sig[SLOT]=""
slot_same_error[SLOT]=0
slot_state[SLOT]="idle"

# _loop_integrate_slot <tree> <branch> -- interim integration (flag=1 only).
# ORDERING PINNED: merge --ff-only (from the MAIN tree, i.e. this process's
# own cwd, never the worktree) -> worktree remove -> branch -d. That order is
# load-bearing: `git branch -d` fails while the branch is still checked out
# in a worktree, so the worktree must be removed first. Non-ff -> loud
# stderr + exit 5, never merge -- a plain function call (not a subshell), so
# this `exit` terminates the whole script, i.e. stays driver-level.
# STORY-011 replaces this interim, slot-called integrator with the real one
# (single integrator, never a slot, per the design's integrator-not-slots
# rule).
_loop_integrate_slot() {
  local tree="$1" branch="$2"
  if ! git merge --ff-only "$branch"; then
    echo "!!! integration failed: '$branch' is not a fast-forward of the current tree — stopping (worktree and branch retained for inspection: $tree)" >&2
    exit 5
  fi
  git worktree remove "$tree"
  git branch -d "$branch"
}

active_slots=0
retained_branches=()   # quarantine-lite: branches from abnormally-exited
                        # slots, retained (not integrated) for inspection --
                        # named again in the driver's closing output below.

# _loop_report_retained -- prints the retained-branches list (if any) exactly
# once, in the driver's closing output, on EVERY run-ending path (0/1/2/3/4/5),
# not just the max-iterations path. An EXIT trap (bash 3.2-safe; no `wait -n`
# or associative-array trick involved) is the right primitive here: it fires
# once as the shell is about to terminate, on any exit reason, and — because
# it never calls `exit` itself — cannot alter the pending exit status, so it
# does not touch (and cannot hide) any of the literal `exit N` statements
# above (check G's greps still see them; this trap runs strictly after them).
_loop_report_retained() {
  if (( ${#retained_branches[@]} > 0 )); then
    echo "=== retained branches from quarantined slots (NOT integrated): ${retained_branches[*]} ==="
  fi
}
trap _loop_report_retained EXIT

for ((i = 1; i <= MAX_ITER; i++)); do
  echo "=== iteration $i/$MAX_ITER $(date -Is) ==="

  # available_slots accounting (design pin, trivially exercised at N=1): the
  # structure STORY-011 activates for real concurrency.
  available_slots=$(( EFFECTIVE_SLOTS - active_slots ))
  if (( available_slots < 0 )); then
    available_slots=0
  fi

  # Mechanism B: single machine, no loop restructure. If OPEN and cooldown has not
  # elapsed, log + sleep, then ask again — the second call performs OPEN->HALF-OPEN
  # and returns 0 — and proceed with this SAME iteration.
  skip="$(breaker_should_skip "$STATE_FILE" "$(date +%s)")"
  if ((skip > 0)); then
    echo "breaker OPEN — sleeping ${skip}s before HALF-OPEN trial"
    sleep "$skip"
    skip="$(breaker_should_skip "$STATE_FILE" "$(date +%s)")"
  fi

  # --- worktree lifecycle (LOOP_WORKTREE=1 only) ----------------------------
  # Interim `loop/iter-<i>` branch naming: the real story id is unknown at
  # spawn time until STORY-011's claim table exists.
  branch="loop/iter-$i"
  if (( WORKTREE == 1 )); then
    wt="$PWD/.loop-worktrees/slot-1"
    git worktree add -b "$branch" "$wt" HEAD >/dev/null

    # Loud preflight (cycle-3 correction): BOTH probes are built from the SAME
    # resolved worktree-path variable ($wt) just passed to `git worktree add`
    # above — never a second hardcoded literal. The second probe is a
    # DIRECTORY test on {{IDE_DIR}}, deliberately NOT a skill-FILE path: that
    # file exists only on Claude-Code installs (this template's own loop
    # skill) -- codex emits no loop skill file at all, copilot may inline its
    # instructions instead of a file, and a Cursor+Claude install keeps the
    # file under .claude/ while {{IDE_DIR}} resolves to .cursor. A directory
    # probe on {{IDE_DIR}} is true on all four harnesses whenever the
    # instance is tracked, and false in exactly the gitignored-instance case
    # -- the iteration needs that whole directory (it is sent to
    # ORCHESTRATION.md and _goals/ESCALATIONS.md), not just one file in it.
    if [[ ! -f "$wt/_goals/backlog.md" || ! -d "$wt/{{IDE_DIR}}" ]]; then
      echo "!!! worktree preflight failed: '$wt' is missing a tracked _goals/backlog.md and/or a tracked {{IDE_DIR}} directory — a worktree checks out TRACKED files only, so this repo's loop instance must be committed (not gitignored) for LOOP_WORKTREE=1 — stopping, no fallback to the main tree" >&2
      git worktree remove --force "$wt" 2>/dev/null || true
      git worktree prune
      # The `-b "$branch"` on `git worktree add` above already created this
      # branch even though the preflight then failed -- without deleting it
      # here, a rerun's `git worktree add -b "$branch"` dies at git's own
      # exit 128 ("branch already exists"), not a loop-owned code.
      git branch -D "$branch" 2>/dev/null || true
      exit 5
    fi
    tree="$wt"
  else
    tree="$PWD"
  fi
  slot_tree[SLOT]="$tree"
  slot_branch[SLOT]="$branch"

  # DRIVER-owned HEAD capture, before dispatch (after reap: see head_after
  # below). Unified for both flags via `-C`: at LOOP_WORKTREE=0, tree is
  # $PWD, so this is identical to a plain `git rev-parse HEAD`.
  head_before="$(git -C "$tree" rev-parse HEAD)"

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

  # --- driver/child boundary (the pin) --------------------------------------
  # The child is a background subshell that runs ONLY the CLI invocation, cwd
  # = the slot's tree (worktree at LOOP_WORKTREE=1, main tree otherwise),
  # stdout+stderr redirected to a driver-created per-slot output file (mktemp,
  # outside the repo — no gitignore concern; removed after evaluation below).
  # The ONLY things that cross child->driver are the CLI exit status (via
  # `wait "$pid"` after the kill -0 poll, below) and that output file. Every
  # exit 2/3/4/5 statement in this script lives OUTSIDE this subshell, at
  # driver level: an `exit` inside a subshell only ends the subshell, and
  # check G's grep cannot see that distinction, so keeping every exit
  # statement out here is a discipline this comment is the only guard for.
  out_file="$(mktemp)"
  (
    cd "$tree"
    $LOOP_CLI $model_arg "$p" > "$out_file" 2>&1
  ) &
  pid=$!
  slot_pid[SLOT]="$pid"
  slot_state[SLOT]="running"
  active_slots=$((active_slots + 1))

  # Supervision: a `kill -0` poll loop, then `wait "$pid"` for the real exit
  # status -- the portable bash-3.2-floor primitive (`wait -n` needs bash
  # 4.3+, which the kit does not require anywhere else either). `kill -0`
  # only tests whether a signal COULD be delivered; a child that has already
  # exited but not yet been collected by this shell (a zombie) still answers
  # it, so this loop's true termination condition is "`wait` below has
  # collected the real status," not "the process is gone." This is the poll
  # loop even at this story's N=1 so STORY-011 activates N>1 by iterating
  # more pids here, not by restructuring this shape.
  while kill -0 "$pid" 2>/dev/null; do
    sleep 0.2
  done
  wait "$pid"
  status=$?
  set -e

  slot_state[SLOT]="idle"
  active_slots=$((active_slots - 1))   # refill trigger: slot exit, not merge

  # Identifier preservation (cycle-3): `output` is populated, verbatim, from
  # the per-slot output file the child wrote to -- never a reimplementation.
  output="$(cat "$out_file")"
  rm -f "$out_file"

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
    if (( WORKTREE == 1 )); then
      _loop_integrate_slot "$tree" "$branch"
    fi
    exit 0
  fi

  # Circuit breaker 0: protected paths — the loop must never modify its own machinery.
  # Evaluated over the slot's own head_before..HEAD (its worktree at
  # LOOP_WORKTREE=1, the main tree at 0 — today's behavior); run-fatal,
  # meaning preserved. At this story's N=1 there are no OTHER concurrent slot
  # children to kill (this slot's own child is already reaped via `wait`
  # above) -- STORY-011 kills the other active slots' children here too.
  if ! git -C "$tree" diff --quiet "$head_before" HEAD -- _loop/ '{{IDE_DIR}}/agents/' '{{IDE_DIR}}/skills/' orchestration-kit.manifest.json .gitattributes 2>/dev/null; then
    echo "!!! protected-path modification detected — reverting iteration and stopping" >&2
    git -C "$tree" reset --hard "$head_before"
    if (( WORKTREE == 1 )); then
      git worktree remove --force "$tree" 2>/dev/null || true
      git worktree prune
    fi
    exit 4
  fi

  # DRIVER-owned HEAD capture, after reap.
  head_after="$(git -C "$tree" rev-parse HEAD)"

  # cb_disposition/cb_exit defer CB1/CB2's exit so the worktree lifecycle
  # (integrate-or-quarantine, below) runs first even on a terminal iteration —
  # the underlying evaluation order (record -> sentinel -> CB0 -> CB1 -> CB2)
  # is unchanged; only WHERE the exit statement executes moves.
  cb_disposition=0
  cb_exit=0

  # Circuit breaker 1: no new commit for 3 consecutive iterations (per-slot
  # counter, unchanged threshold).
  # CB1 carve-out (amended scope): a rate-limited pass never counts against this
  # counter — the breaker owns recovery for it instead. Non-rate-limited no-commit
  # passes increment no_progress exactly as before.
  if [[ "$head_after" == "$head_before" ]]; then
    if ((detected == 1)); then
      echo "rate-limited pass — CB1 exempt (breaker owns it)"
    else
      slot_no_progress[SLOT]=$(( slot_no_progress[SLOT] + 1 ))
      echo "--- no progress (${slot_no_progress[SLOT]}/3)"
      if (( slot_no_progress[SLOT] >= 3 )); then
        echo "!!! circuit breaker: 3 iterations without a commit — stopping" >&2
        cb_disposition=1
        cb_exit=2
      fi
    fi
  else
    slot_no_progress[SLOT]=0
  fi

  # Circuit breaker 2: same failure signature 5 times in a row (per-slot
  # counter, thresholds unchanged; CB2's signature reads the same output
  # file/variable the driver already captured above). Skipped entirely once
  # CB1 has already assigned a disposition this iteration — matches the
  # original ordering, where CB1's `exit 2` would have prevented this code
  # from ever running.
  if (( cb_disposition == 0 )) && (( status != 0 )); then
    error_sig="$(printf '%s' "$output" | tail -n 5 | sha256sum | cut -d' ' -f1)"
    if [[ "$error_sig" == "${slot_last_error_sig[SLOT]}" ]]; then
      slot_same_error[SLOT]=$(( slot_same_error[SLOT] + 1 ))
      if (( slot_same_error[SLOT] >= 5 )); then
        echo "!!! circuit breaker: same error 5 times — stopping" >&2
        cb_disposition=1
        cb_exit=3
      fi
    else
      slot_same_error[SLOT]=1
      slot_last_error_sig[SLOT]="$error_sig"
    fi
  elif (( cb_disposition == 0 )); then
    slot_same_error[SLOT]=0
    slot_last_error_sig[SLOT]=""
  fi

  # --- slot disposal: quarantine-lite (abnormal) vs normal integration -----
  if (( WORKTREE == 1 )); then
    dirty=0
    if [[ -n "$(git -C "$tree" status --porcelain 2>/dev/null)" ]]; then
      dirty=1
    fi
    abnormal=0
    # Abnormal slot exit (quarantine-lite, pinned): a nonzero CLI status that
    # did NOT earn a recognized CB1/CB2 disposition this iteration, OR a
    # dirty worktree left behind either way. Full quarantine (markers,
    # retirement bookkeeping) is STORY-012's; this is an explicit deferral.
    if (( status != 0 )) && (( cb_disposition == 0 )); then
      abnormal=1
    fi
    if (( dirty == 1 )); then
      abnormal=1
    fi

    if (( abnormal == 1 )); then
      echo "!!! slot exited abnormally (status=$status dirty=$dirty) — quarantine-lite: NOT integrating; retaining branch '$branch' for inspection ($tree)" >&2
      git worktree remove --force "$tree" 2>/dev/null || true
      git worktree prune
      retained_branches+=("$branch")
    else
      _loop_integrate_slot "$tree" "$branch"
    fi
  fi

  # Literal `exit 2`/`exit 3` statements (not a variable exit, per check G's
  # greps at .claude/checks.sh:295-297, which require the literal digit on a
  # driver-level exit line): cb_exit only SELECTS between them, it never
  # substitutes for them.
  if (( cb_disposition == 1 )); then
    if (( cb_exit == 2 )); then
      exit 2
    fi
    exit 3
  fi
done

# (Retained-branches summary, if any, is printed by the _loop_report_retained
# EXIT trap installed above -- it fires here too, after this exit statement.)
echo "=== max iterations ($MAX_ITER) reached; backlog not complete ==="
exit 1
