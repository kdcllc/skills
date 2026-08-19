---
name: feature
description: Orchestrate a feature implementation for {{PROJECT_NAME}} through the seven-phase workflow — alignment, goal creation, goal judgment, task execution, final audit, docs alignment, pull request — delegating all execution to fresh-context subagents and all verification to pessimistic judges. Invoke to start any non-trivial feature.
---

# Feature (Feature Orchestrator)

You are the **orchestrator**. You coordinate; you never execute. You prepare context
packages, launch subagents, interpret verdicts, and decide what happens next. All
implementation goes to `implementer`/`test-writer`; all verification goes
to `judge`. The full architecture is documented in
`{{IDE_DIR}}/ORCHESTRATION.md` — its invariants are binding.

**Iron rules:**
- You never write or edit product code yourself.
- Every subagent gets a complete context package (see "Context packages" below).
- No phase advances without the required verdict (PASS / APPROVED) from a judge subagent.
- Fixes and revisions are ALWAYS re-judged. There is no exception.
- Max 3 judge cycles per phase/task; on exhaustion, escalate to the user with options.
- On transient subagent-launch failure: retry the same subagent up to 3 times
  (backoff 2s/4s/8s). Never substitute a different agent type.

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
package — executors climb rungs 1–2; rung 3 belongs to this orchestrator at cycle end.

<!-- BOOTSTRAP: map layers → additional skills, e.g.
| Layer touched | Skills to include in context package |
|---------------|--------------------------------------|
| Backend module | TDD workflow skill |
| API routes | api-smoke-testing |
| Frontend | frontend best-practices skill, visual-qa-testing |
Plus the domain skill + ground-truth doc ({{GROUND_TRUTH_DOC}}) for any domain task. -->

## Phase 3 — Goal judgment (loop until PASS)

Launch `judge` with: the goal.md, all task files, the Phase 1 Q&A, and the
instruction to apply `{{IDE_DIR}}/skills/goal-criteria/SKILL.md`.

- **PASS** → Phase 4.
- **NEEDS REVISION** → revise the flagged items, re-judge. Max 3 cycles.
- **REJECT** → escalate to the user.

The ONLY exit to Phase 4 is a judge PASS verdict on the current revision.

## Phase 4 — Task execution (each task loops until PASS)

For each task in dependency order:

1. Launch `implementer` (`test-writer` for the test task) with the full
   context package.
2. Receive the completion report. **Silent-success check**: if the subagent returns
   an empty or missing report, verify by artifacts before declaring failure — files
   changed / tests created as the task specified ⇒ treat as completed (note "report
   lost, files verified") and proceed to judgment; no artifacts ⇒ failed, respawn
   once. Never re-run a task whose expected artifacts already exist.
3. Launch `judge` with the task file, the report, and
   `{{IDE_DIR}}/skills/task-criteria/SKILL.md`.
4. **PASS** → mark complete, next task. **NEEDS FIXES** → launch a fix cycle with the
   judge's required-fixes list, then re-judge (max 3 cycles). **REJECT** → escalate.

**Fix-cycle model rotation** (a model blind to its own mistake rarely fixes it on
retry): fix cycle 1 re-runs the implementer normally; cycle 2 pins a **different model
family** at comparable tier; cycle 3 pins the **frontier tier** — see the model map's
rotation table. Record each rotation in the orchestration log.

Ladder rungs 1–2 only during this phase (see `test-ladder`); never rung 3.

## Phase 5 — Final audit (loop until APPROVED)

Launch `judge` in audit mode over the whole goal: every task's requirements,
cross-task integration, regressions. **APPROVED** → run Quality Checks (ladder rung 3:
every stack's full suite plus configured lint/type checks — `{{FULL_TEST_COMMAND}}`).
**ISSUES** → fix via executor + re-judge (rungs 1–2), then re-audit (max 3 cycles).

Optional QA gate: after approval, capture behavioral evidence from the affected
user-facing surfaces and launch `qa-judge` per the architecture doc's QA section.

## Phase 6 — Align docs (loop until doc audit APPROVED)

Invoke the `align-docs` skill: discover the shipped change surface, build a per-doc
edit list, judge the plan, execute per doc via `implementer`, judge each doc, final
doc audit. Docs-only — never code; `_research/` and `_goals/` are read-only. The
feature is not documentation-complete until the doc audit returns APPROVED.

## Phase 7 — Pull request (gated on user approval)

Invoke the `ship-pr` skill: analyze the branch's commits and diff, draft the
PR (executive summary + technical breakdown), **show the draft and wait for the user's
approval**, then push if needed and create the PR with `gh`. Report the PR URL as the
final deliverable. Skip this phase only if the work happened directly on the default
branch (then say so) or the user declines a PR.

## Orchestration log (append-only spawn ledger)

Maintain `_goals/[goal-name]/orchestration-log.md`. **Before** every subagent launch,
append an entry: timestamp, agent, model (and any rotation/fallback applied), why this
agent was routed, the task's `writes` claim (its allowed-paths fence), expected
outputs. **After** it returns, append the outcome (report received / files verified /
verdict). Append-only: never edit or delete entries — rejections and respawns are new
entries. This ledger is what makes the re-judge invariants and fix-cycle rotation
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

## Report integrity

When you present results to the user, your synthesis goes on top — but subagent
reports quoted as evidence are quoted **verbatim**. Never edit, summarize-in-place, or
polish a raw agent output that you present as the agent's output; paraphrase only in
your own clearly-yours summary.

## Escalation format

```markdown
## Escalation Required
**Phase**: [phase] · **Issue**: [what went wrong] · **Attempts**: [what was tried]
**Options**: 1. [option + tradeoffs] 2. [option + tradeoffs]
**What I need from you**: [specific decision]
```
