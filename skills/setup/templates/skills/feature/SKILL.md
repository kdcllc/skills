---
name: feature
description: Orchestrate a feature implementation for {{PROJECT_NAME}} through the seven-phase workflow — alignment, goal creation, goal evaluation, task execution, final audit, docs alignment, pull request — delegating all execution to fresh-context subagents and all verification to pessimistic evaluators. Invoke to start any non-trivial feature.
---

# Feature (Feature Orchestrator)

You are the **orchestrator**. You coordinate; you never execute. You prepare context
packages, launch subagents, interpret verdicts, and decide what happens next. All
implementation goes to `implementer`/`test-writer`; all verification goes
to `evaluator`. The full architecture is documented in
`{{IDE_DIR}}/ORCHESTRATION.md` — its invariants are binding.

**Iron rules:**
- You never write or edit product code yourself.
- Every subagent gets a complete context package (see "Context packages" below).
- No phase advances without the required verdict (PASS / APPROVED) from an evaluator subagent.
- Fixes and revisions are ALWAYS re-evaluated. There is no exception.
- Max 3 evaluation cycles per phase/task; on exhaustion, Phase 4 task execution enters
  the continuation ladder (all other phases escalate to the user with options).
- On transient subagent-launch failure: retry the same subagent up to 3 times
  (backoff 2s/4s/8s). Never substitute a different agent type.

### Terminal spawn rule

Spawn `terminal` for **any Bash or PowerShell command** whose raw output should not
land in this session. The spawn prompt must include (1) the exact command, (2) the
shell (`bash` or `pwsh`), (3) the result you need back (exit code, last N lines, a
match, pass/fail, a path, …). `terminal` runs that command and returns **only** that
result. You must **never** run `{{FULL_TEST_COMMAND}}` yourself — always spawn
`terminal` for rung 3. Rungs 1–2 stay with `implementer`/`test-writer` when the output
is small enough to keep inline; they may spawn `terminal` for a noisy command where
the harness lets workers spawn (not Copilot — nesting stays off, so only this L1
session spawns there). Spawning `terminal` is coordination, not you executing product
code.

Maintain the "Orchestration Progress" state block from the architecture doc throughout,
updating it after every step.

## Phase 1 — Alignment (no files created)

Ask the user 5–20 structured multiple-choice questions covering: the problem, which
layer/lane is affected ({{EXECUTION_LAYERS}}), external surfaces touched,
auth/permissions, error behavior, interface shape, existing patterns to follow, and
priority. Run follow-up rounds as needed. Then present a "My Understanding" summary and
**wait for explicit confirmation** before Phase 2.

## Phase 2 — Goal creation

Create `_goals/[goal-name]/` containing:
- `goal.md` from `templates/goal.md` (include the Phase 1 Q&A summary)
- One `NN-task-name.md` per task from `templates/task.md`, in dependency order
  following the project's layer chain: {{EXECUTION_LAYERS}}, then a final test task.

Every task file carries the ownership contract block (`writes`/`reads`/`depends_on`/
`owner`/`rewrite_semantics` — see `templates/task.md`), and you verify that the `writes`
sets of every pair of tasks without a `depends_on` ordering between them are disjoint
before Phase 3. Contract-first: if the goal touches a shared boundary or interface,
define a dedicated contract/scaffold task that creates and freezes it FIRST, and make
that task a `depends_on` prerequisite of every consumer task rather than letting two
tasks write the boundary in parallel.

Decision gate: if a task has multiple viable approaches, present them to the user with
tradeoffs and **wait** — do not pick silently.

### Supporting skills routing

Include in each task's context package the skills relevant to its layer:

`test-ladder` is routed into **every** implementation and test task's context
package — executors climb rungs 1–2; rung 3's **authority** (when it runs) belongs to
this orchestrator at cycle end, but its **execution** is a spawned `terminal`, never
this session running `{{FULL_TEST_COMMAND}}` inline.

<!-- BOOTSTRAP: map layers → additional skills, e.g.
| Layer touched | Skills to include in context package |
|---------------|--------------------------------------|
| Backend module | TDD workflow skill |
| API routes | api-smoke-testing |
| Frontend | frontend best-practices skill, visual-qa-testing |
Plus the domain skill + ground-truth doc ({{GROUND_TRUTH_DOC}}) for any domain task. -->

## Phase 3 — Goal evaluation (loop until PASS)

Launch `evaluator` with: the goal.md, all task files, the Phase 1 Q&A, and the
instruction to apply `{{IDE_DIR}}/skills/goal-criteria/SKILL.md`.

- **PASS** → Phase 4.
- **NEEDS REVISION** → revise the flagged items, re-evaluate. Max 3 cycles.
- **REJECT** → escalate to the user.

The ONLY exit to Phase 4 is an evaluator PASS verdict on the current revision.

## Phase 4 — Task execution (each task loops until PASS)

For each task in dependency order:

**Contract gate** (runs once per task, before step 1 — implementation dispatch):

a. Launch the task's owner agent (`implementer` or `test-writer`, per its `owner`
   field) in **contract mode** to propose
   `_goals/[goal]/contracts/NN-task-name.contract.md` from `templates/contract.md`,
   expanding the task file's requirements into `acceptance_criteria` with an explicit
   verification method each. For a trivial task, you (the orchestrator) may draft the
   contract directly instead of spawning the owner.
b. Launch `evaluator` in **contract mode** to review the proposal: it either
   counter-signs (`signoff.evaluator.agreed: true`) or returns exactly one revision
   request. Bounded to max 2 rounds; each round is a single stateless spawn — no
   cross-spawn memory required, so this is Copilot-safe. Contract mode never reviews
   code — the contract precedes any implementation.
c. You refuse to dispatch implementation (step 1 below) until both
   `signoff.worker.agreed` and `signoff.evaluator.agreed` are `true`. If round 2 ends
   without agreement, you tiebreak the open point yourself or escalate to the user —
   never proceed on an unresolved contract.
d. Append both sign-offs to the orchestration log as their own entries (timestamp,
   agent, contract-mode verdict).

1. Launch `implementer` (`test-writer` for the test task) with the full
   context package.
2. Receive the completion report. **Silent-success check**: if the subagent returns
   an empty or missing report, verify by artifacts before declaring failure — files
   changed / tests created as the task specified ⇒ treat as completed (note "report
   lost, files verified") and proceed to evaluation; no artifacts ⇒ failed, respawn
   once. Never re-run a task whose expected artifacts already exist.
3. Launch `evaluator` with the task file, the report, and
   `{{IDE_DIR}}/skills/task-criteria/SKILL.md`.
4. **PASS** → mark complete, next task. **NEEDS FIXES** → launch a fix cycle with the
   evaluator's required-fixes list, then re-evaluate (max 3 cycles). **REJECT** → escalate.

   **Bypass at detection (every verdict, cycles 1–3).** Any verdict tagged
   `destructive`, `security`, or `infra` stops all cycles immediately and escalates
   to the user — from cycle 1, not only after exhaustion.

   **On cycle-3 exhaustion** (NEEDS FIXES after three implement→evaluate cycles without
   PASS), enter the **continuation ladder** before terminal escalation. Every ladder fix
   attempt is re-evaluated; there is no exception. Apply in this order:

   1. **Rung 5 — arbitration (unanimity check).** If all three evaluator verdicts in
      the orchestration log flagged the same required-fix item (unanimous-failure
      heuristic), spawn `evaluator` in
      **arbitration mode** on `{{MODEL_FRONTIER_ALT_FAMILY}}` with the task file,
      signed contract, all three verdicts, and all three implementer reports. Outcomes:
      `criteria-defective` → escalate to the user carrying the named defective criterion
      **verbatim**; arbiter/primary disagreement → escalate (never auto-resolve);
      `criteria-sound` → continue to rung 4.

   2. **Rung 4 — diagnosis-first.** Spawn `diagnostician` with the task file,
      signed contract, all three implementer reports and evaluator verdicts, and the
      targeted verification command. If its **Signature Declaration** matches a
      previously tried fix signature → skip to rung 6 if it recommended a split,
      else escalate. Otherwise run **ONE** diagnosis-driven implementation attempt:
      fresh `implementer` on `{{MODEL_FRONTIER}}` using the diagnostician's
      **Rewritten Required-Fixes** list; then mandatory re-evaluation.

   3. **Rung 6 — decomposition + selective retry** (only on a diagnostician
      split recommendation). Derive subtask files with ownership contracts whose write sets
      are subsets of the parent task's, from the **failing pieces only** — unflagged work
      from earlier cycles stays as-is, is not re-run, and gets no separate evaluation.
      Each derived subtask gets one implement→evaluate cycle; the parent task completes
      when every derived subtask has an evaluator PASS; evaluator spawns never consume
      the attempt budget — only implementation attempts do.

   4. **Terminal.** Escalate to the user with the full ladder history.

   **Hard guards** (character-consistent with `{{IDE_DIR}}/ORCHESTRATION.md`):

   - At most **3 additional implementation attempts** after cycle 3, summed across rungs 4
     and 6.
   - The diagnosis-driven implementation attempt costs 1 of the 3. Each rung-6 subtask
     implement→evaluate cycle costs 1 of the 3. Before splitting, compare the
     failing-subtask count against the remaining budget — if the count exceeds the
     remaining budget, escalate instead of splitting.
   - A **repeated failure signature** stops the ladder immediately: the evaluator's
     required-fixes list as recorded in the orchestration log, identical to an earlier
     cycle's list item-for-item after normalizing whitespace and list numbering.
   - Every rung transition, spawn, and guard trip is an orchestration-log entry recording
     the rung name.

   token/cost budgets are NOT a guard in this kit — no harness exposes token counts to
   markdown policy.

**Fix-cycle model rotation** (a model blind to its own mistake rarely fixes it on
retry): fix cycle 1 re-runs the implementer normally; cycle 2 pins a **different model
family** at comparable tier; cycle 3 pins the **frontier tier** — see the model map's
rotation table. Record each rotation in the orchestration log.

Ladder rungs 1–2 only during this phase (see `test-ladder`); never rung 3.

The headless loop inherits this ladder because each iteration runs this skill; the loop
drivers' per-story attempt cap and circuit breakers stay the unchanged outer backstop.

## Phase 5 — Final audit (loop until APPROVED)

Launch `evaluator` in audit mode over the whole goal: every task's requirements,
cross-task integration, regressions. **APPROVED** → run Quality Checks (ladder rung 3:
every stack's full suite plus configured lint/type checks) by spawning `terminal`
with `{{FULL_TEST_COMMAND}}` — never run that command yourself.
**ISSUES** → fix via executor + re-evaluate (rungs 1–2), then re-audit (max 3 cycles).

**Quality Checks failure path**: if `terminal` returns a non-zero exit and its
excerpt is truncated, the log path is required in its report — **Read** that log's
failure section, or its last ≤80 lines if it is large, never the whole file. Use
that to route a fix to `implementer`; never dump the full suite into this session.
Re-spawn `terminal` only with a **narrower** command (one failing test / one stack),
not the full suite again, to confirm the fix. Inline shell in this session is
allowed only for small read-only inspection (e.g. `git status`) — never for
`{{FULL_TEST_COMMAND}}`.

Optional QA gate: after approval, capture behavioral evidence from the affected
user-facing surfaces and launch `qa-evaluator` per the architecture doc's QA section.

## Phase 6 — Align docs (loop until doc audit APPROVED)

Read `{{IDE_DIR}}/skills/align-docs/SKILL.md` and execute that workflow in this
session: discover the shipped change surface, build a per-doc edit list, evaluate the
plan, execute per doc via `implementer`, evaluate each doc, final doc audit. Docs-only —
never code; `_research/` and `_goals/` are read-only. The feature is not
documentation-complete until the doc audit returns APPROVED.

## Phase 7 — Pull request (gated on user approval)

Read `{{IDE_DIR}}/skills/ship-pr/SKILL.md` and execute that workflow in this
session: analyze the branch's commits and diff, draft the PR (executive summary +
technical breakdown), **show the draft and wait for the user's approval**, then push
if needed and create the PR with `gh`. Report the PR URL as the final deliverable.
Skip this phase only if the work happened directly on the default branch (then say
so) or the user declines a PR.

## Orchestration log (append-only spawn ledger)

Maintain `_goals/[goal-name]/orchestration-log.md`. **Before** every subagent launch,
append an entry: timestamp, agent, model (and any rotation/fallback applied), why this
agent was routed, the task's `writes` claim (its allowed-paths fence), expected
outputs. **After** it returns, append the outcome (report received / files verified /
verdict) as a new line under that entry. For continuation-ladder transitions, spawns,
and guard trips, include the **rung name** in the entry. Never write placeholder status lines
("Outcome: (pending)", "TBD") — under append-only they can never be resolved in place
and rot into permanently stale text; an entry with no outcome line yet IS the pending
state. Append-only: never edit or delete entries — rejections and respawns are new
entries. This ledger is what makes the re-evaluation invariants and fix-cycle rotation
auditable.

## Context packages

Every subagent launch uses this structure (see the architecture doc's protocol section):

```
You are the [subagent-name] subagent. Read: {{IDE_DIR}}/agents/[subagent-name].md

CURRENT_DATETIME: [literal ISO timestamp — use this for any date; never guess]

## Task
[what to accomplish]

## Requirements
[exhaustive list from the task file]

## Files to Read
[explicit paths: code, skills, ground-truth docs]

## Write fence
[the task's `writes` list — the ONLY paths this subagent may create or modify]

## Rules
[must-do / must-not-do constraints for this task]

## Output
[the exact report/verdict format expected]
```

For the implementation spawn (Phase 4 step 1 onward), the context package additionally
includes the task's signed contract (`_goals/[goal]/contracts/NN-task-name.contract.md`)
— both `signoff.worker.agreed` and `signoff.evaluator.agreed` already `true` from the
contract gate above.

## Report integrity

When you present results to the user, your synthesis goes on top — but subagent
reports quoted as evidence are quoted **verbatim**. Never edit, summarize-in-place, or
polish a raw agent output that you present as the agent's output; paraphrase only in
your own clearly-yours summary.

## Escalation format

```markdown
## Escalation Required
**Phase**: [phase] · **Issue**: [what went wrong] · **Attempts**: [what was tried]
**Ladder**: [rungs attempted and their outcomes]
**Options**: 1. [option + tradeoffs] 2. [option + tradeoffs]
**What I need from you**: [specific decision]
```

For `criteria-defective` escalations (from rung 5 arbitration), state the defective
criterion **verbatim** in the **Issue** line.
