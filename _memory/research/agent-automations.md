---
title: "Unattended-run rules from Anthropic's agent automations guide: what the loop already does and candidate follow-ups"
topic: agent-automations
date: 2026-10-30
status: ingested
shipped_in: []
goals: []
supersedes: []
memory: []
---

# Unattended-run rules from Anthropic's agent automations guide: what the loop already does and candidate follow-ups

**Method**: direct review (no `/research` prompt or external report). One primary source,
Anthropic's [Building effective agent automations](https://claude.dev/blog/building-effective-agent-automations/)
(Lance Martin and CJ Avilla, 2026-10-08), read against the canonical loop driver
(`skills/agent-kit/templates/loop/loop.sh`), the `auto-loop` skill template, the memory
protocol and the emitter. Every gap below was confirmed by reading code at the time of
writing; none was reproduced with a failing test yet. **This brief is canonical.** The rules
the loop already follows are documented for users in
[autonomous-loop.md § Unattended-run rules](../../docs/agent-kit/guide/autonomous-loop.md#unattended-run-rules)
(shipped in agent-kit 2.2.0 as documentation only).

## Question

The article builds a scheduled background agent (a daily brief over Slack and GitHub) on
Claude Managed Agents and distills six rules for agents that run with nobody watching:

1. Read each source from a bookmark, not a fixed time window.
2. Report a failed read as unreadable, never as a quiet day.
3. Re-check every item right before posting.
4. Count a post as sent only when the destination confirms it, then update bookmarks and
   ledger.
5. Re-read preferences every run, from a store the agent can't edit.
6. Give the agent read-only access wherever it only reads, and cap what each run can spend.

It also recommends a run record per run, a ledger of reported items with stable ids and
last-known status, a heartbeat someone watches, and budgets set from real runs (three to
five times a normal run). Which of these does agent-kit's autonomous loop already apply,
and which would be worth building?

## Load-bearing conclusions

- The loop already applies all six rules in its own terms (backlog state as the bookmark,
  driver-owned transitions, fresh-context iterations, protected paths, budgets). The
  mapping is in the guide, not repeated here.
- The article's rule 4 failure ("records a post that never landed, the bookmarks move on")
  has a direct analogue in the driver: a story can be marked `passes: true` before its work
  is confirmed on the main tree (C1). This is the highest-value follow-up.
- The article warns that agent-kept notes between runs are a channel for planted
  instructions. Loop outbox learnings and escalations reach tracked files without the
  redaction and admission screen that memory records get (C2).
- "Failed read is not a quiet day" applies to memory recall: a failed search and an empty
  one both become `none` (C3).
- Scheduling, a run-end heartbeat and budget calibration are small, optional additions
  (C5–C7). Nothing in the article argues for replacing the bash driver with a
  harness-native scheduler; that was rejected for other reasons in
  [orchestration-loop-review.md](orchestration-loop-review.md).

## Candidates

Ranked by value. Effort: **S** = one function or doc section plus a test case;
**M** = several functions, new knob or new ledger outcome, docs and goldens.

### C1. Mark a story passed only after its commit is confirmed on the main tree — value: high, effort: S–M

**Evidence.** In `_loop_reap_slot`, integrator step 2 applies the slot's
`ITERATION: <id> passed` verdict with `_loop_backlog_set_field … passes true` and clears the
attempt dossier (`_loop_dossier_clear_story`). That runs before two later checks:

- the `head_after == head_before` comparison, which today only feeds CB1's no-progress
  counter, so a slot that reports `passed` without committing still marks the story done;
- `_loop_integrate_slot`'s rebase and `git merge --ff-only`; on a non-fast-forward the driver
  logs `nonff` and exits **5**, but the backlog already says `passes: true` and the dossier
  is gone, so the next run skips a story whose work never reached the main tree.

`tests/agent-kit/templates/loop-guards.sh` case 18 (`nonff`) asserts exit 5, the ledger
line and the summary, not the backlog state. The sequence diagram in the autonomous-loop
guide also shows step 2 before the merge.

**Proposal.** Move the `passes` transition and the dossier clear after disposal. Apply them
only when a new commit exists, and in worktree mode only when `_loop_integrate_slot`
succeeded. Decide whether a `passed` verdict without a commit is `failed` or a new ledger
outcome (for example `unconfirmed`, the article's "maybe posted"); either way no backlog
transition. `blocked` stays as today, since it needs no commit.

**Tests.** Extend case 18 to assert `passes: false` after a non-ff exit; add a case whose
stub prints `passed` without committing. Update the guide's sequence diagram and the
emitted ORCHESTRATION.md loop text if they state the order. Goldens regenerate for
`loop.sh`.

### C2. Screen outbox learnings and escalations before appending them — value: high, effort: S–M

**Evidence.** Integrator step 3 appends `<outbox>/learnings.md` and
`<outbox>/escalations.md` with plain `cat >>` into the tracked
`_memory/loop/LEARNINGS.md` and `_memory/loop/ESCALATIONS.md`. Every `auto-loop` iteration
reads `ESCALATIONS.md` at load time, so it is a channel back into later agent context. Both files
are committed. Decision record `20261013T204955Z-87ce3a3c` puts secret stopping at
`memory add` and the `check` gate; these two files pass through neither, so a token or an
injection phrase a slot copied from a tool result lands in git unscreened.

**Proposal.** Pipe each outbox file through `_kit/memory.sh redact` (the driver runs in the
main tree, where `_kit/` exists) and through the frozen admission patterns, line by line.
On an admission match, append a one-line placeholder naming the story and the matched
class instead of the text, keep the original in a gitignored file for human review, and
print a `!!!` line. When `_kit/memory.sh` is missing, append as today with a warning (fail
open, like step 3b). This needs a stdin admission check: either a new `memory.sh screen`
subcommand or an `--admission` flag on `redact`.

**Tests.** Stub slot writing a fake GitHub token and `ignore previous instructions` into
both outbox files; assert the tracked files hold the redaction marker and the placeholder.
Memory CLI tests for the new subcommand or flag.

### C3. Distinguish "recall unavailable" from "no prior knowledge" — value: medium, effort: S (marker) or M (driver recall)

**Evidence.** The memory protocol's failure handling treats any non-zero exit, a missing
tool and `memory: 0 results` the same way: the goal's `## Recalled memory` gets `none`, and
the failure is logged only as an orchestration-log note. Worktree slots have no `_kit/`,
so every worktree iteration plans with recall empty by design.

**Proposal.** Small: write `unavailable (<reason>)` instead of `none` when search failed or
`_kit/` is absent, so the goal evaluator and the reader can tell the two apart. Larger:
have the driver, which does have `_kit/`, run recall for the story's title and `writes:`
paths and inject up to five records as a DATA-fenced block, the same way it injects the
attempt dossier.

### C4. Verify after integrating, not only before — value: medium, effort: M

**Evidence.** The article's rule 3 re-checks live state just before acting. The driver's
pre-merge checks (CB0, subset, tamper) are structural; the tests ran inside the slot
against the pre-rebase base. `_loop_integrate_slot` rebases onto the current main HEAD and
fast-forwards without re-running anything. Disjoint `writes:` rule out textual conflicts,
not semantic ones between two stories integrated in the same run.

**Proposal.** Opt-in `LOOP_POST_MERGE_CHECK="<command>"` run in the main tree after each
integration. On failure, reset to the pre-merge HEAD, leave `passes: false`, and retain the
branch with a new quarantine reason (for example `postmerge`). Independently, `ship-pr`
could re-run test-ladder rung 3 once over the whole run's branch before drafting the PR.

### C5. Run-end notification hook — value: medium-low, effort: S

**Evidence.** The article's guardrails include "a heartbeat that someone watches." The loop
prints its run summary to stderr and writes a local ledger; an unattended or scheduled run
tells nobody it ended or why.

**Proposal.** Opt-in `LOOP_NOTIFY_CMD`, invoked once from the existing EXIT trap with the
exit code as an argument and the run summary on stdin. It must fail open, never change the
exit code, run with a short timeout, and receive only the summary (no prompts, outbox text,
or paths outside the repo).

### C6. Scheduling recipes — value: low, effort: S (docs only)

**Proposal.** A guide section on running the loop and `_kit/memory.sh capture` on a
schedule: cron or a systemd timer, a scheduled CI job, Cursor Automations, or a Claude
Managed Agents deployment. `capture` already behaves like a scheduled job (idle-hours
cutoff, hashed ledger). Each recipe must repeat the sandbox rules, state that the loop
never pushes (a scheduled run ends with a local branch and a summary), and pair with C5.
Verify each scheduler's current behavior before documenting it.

### C7. Budget suggestions from the ledger — value: low, effort: S

**Evidence.** 2.2.0 documents the article's "three to five times a normal run" guidance;
users still compute it by hand from `_memory/loop/ledger.jsonl`.

**Proposal.** A read-only `loop.sh --suggest-budget [ledger]` (jq required, like usage
parsing) that prints median and high per-story cost and tokens over `passed` reaps, and the
3× and 5× values as candidate `LOOP_STORY_BUDGET_*` settings. No side effects, never in a
normal run.

### C8. Tool allowlists for verdict agents on Claude Code — value: low, effort: S

**Evidence.** Cursor installs emit `readonly: true` for `evaluator`, `qa-evaluator` and
`diagnostician` (`emit.sh`, `cursor-agent` filter). On Claude Code only `terminal`
(`Bash, Read`) and `diagnostician` (`Bash, Read, Grep, Glob`) carry `tools:` lists; the
evaluator templates rely on prose ("You never edit files").

**Proposal.** Add `tools: Bash, Read, Grep, Glob` to the evaluator and qa-evaluator
templates for Claude Code. Bash stays because evaluators execute checks, so this removes
the edit tools without making the role fully read-only. Confirm first that no evaluator
mode writes a file itself, and check the Copilot and Codex emitters' handling of `tools:`.

### C9. Age open escalations in the run summary — value: low, effort: S

**Evidence.** The article's ledger carries open items forward as "still waiting, day 3"
instead of letting them go stale. Open entries in `_memory/loop/ESCALATIONS.md` (no
`- resolved:` line) are not mentioned at run end.

**Proposal.** One run-summary line: the count of open escalations and the oldest one's
story id and age.

## Decisions

- **Adopted (2.2.0, documentation only):** the six-rule mapping in
  [autonomous-loop.md § Unattended-run rules](../../docs/agent-kit/guide/autonomous-loop.md#unattended-run-rules),
  the budget-calibration paragraph there, and the README pointer. No behavior changed.
- **Not adopted:** the article's time-zone rule (kit ids and ledgers are UTC; escalation
  resolution dates are human-written); the destination idempotency check (the loop has no
  external destination, and its only delivery is a human-approved PR); vault-based
  credential injection (a harness and sandbox concern, covered by the sandbox guidance);
  Managed Agents memory-store mounts (the git-tracked `_memory/` store is the kit's
  design).

## Open questions

- C1: should a `passed` verdict with no commit simply be `failed` (the attempt was already
  counted at claim, and CB1 already counts the no-commit reap), or a distinct outcome that
  blocks the story at once for human review?
- C2: where should a screened-out outbox line be kept so a human can review it without it
  being tracked? A gitignored `_memory/loop/screened/` folder is one option.
- C3: does driver-side recall belong in the driver, or should the tracked-instance preflight
  instead require `_kit/` in worktrees?
- C4: which quarantine reason name, and does a post-merge failure retire the slot?

## Sources

1. [Building effective agent automations](https://claude.dev/blog/building-effective-agent-automations/) — Anthropic (Lance Martin, CJ Avilla), published 2026-10-08, accessed 2026-10-30
2. [`skills/agent-kit/templates/loop/loop.sh`](../../skills/agent-kit/templates/loop/loop.sh) — `_loop_reap_slot` integrator steps 2 and 3, `_loop_integrate_slot`, `_loop_print_run_summary`
3. [`skills/agent-kit/templates/loop/SKILL.template.md`](../../skills/agent-kit/templates/loop/SKILL.template.md) — dispatch modes, outbox contract, manual-mode load state
4. [`skills/agent-kit/templates/skills/feature/reference/memory-protocol.md`](../../skills/agent-kit/templates/skills/feature/reference/memory-protocol.md) — recall failure handling
5. [`skills/agent-kit/bin/emit.sh`](../../skills/agent-kit/bin/emit.sh) — Cursor `readonly: true` for verdict agents
6. `tests/agent-kit/templates/loop-guards.sh` — case 18 (`nonff`)
