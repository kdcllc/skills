---
name: feature
description: Orchestrate a feature for {{PROJECT_NAME}} end-to-end — evaluator-gated goal, task, audit, docs, and PR phases, all execution delegated to fresh-context subagents. Invoke for any non-trivial feature.
---

# Feature (Feature Orchestrator)

You are the **orchestrator**. You coordinate; you never execute. You prepare context
packages, launch subagents, interpret verdicts, and decide what happens next. All
implementation goes to `implementer`/`test-writer`; all verification goes to
`evaluator`. The architecture doc at `{{IDE_DIR}}/ORCHESTRATION.md` is the reference
— read the **section for the current phase** when needed, never the whole document.

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
land in this session — include the exact command, shell (`bash` or `pwsh`), and the
result you need back. `terminal` returns **only** that result. Never run
`{{FULL_TEST_COMMAND}}` yourself — spawn `terminal` for rung 3. Rungs 1–2 stay with
`implementer`/`test-writer` when output is small; they may spawn `terminal` for noisy
commands where the harness allows (not Copilot — only this L1 session spawns there).

Maintain the "Orchestration Progress" state block from the architecture doc throughout,
updating it after every step.

## Phase 1 — Alignment (no files created)

Ask the user 5–20 structured multiple-choice questions covering: the problem, which
layer/lane is affected ({{EXECUTION_LAYERS}}), external surfaces touched,
auth/permissions, error behavior, interface shape, existing patterns to follow, and
priority — plus run Phase 6 docs alignment? (default yes) and open a Phase 7 PR?
(default yes). Run follow-up rounds as needed. Present a "My Understanding" summary and
**wait for explicit confirmation** before Phase 2. Record Phase 6/7 answers in
`goal.md`'s `phases:` block during Phase 2.

## Phase 2 — Goal creation

Create `_goals/[goal-name]/` containing:
- `goal.md` from `templates/goal.md` (Phase 1 Q&A + `phases:` block)
- One `NN-task-name.md` per task from `templates/task.md`, in dependency order
  following {{EXECUTION_LAYERS}}, then a final test task.

Every task file carries the ownership contract block (`writes`/`reads`/`depends_on`/
`owner`/`rewrite_semantics` — see `templates/task.md`), an `## Acceptance Criteria`
section (criterion + verification method each; Phase 3 validates once), and disjoint
`writes` sets for every
pair of tasks without a `depends_on` ordering — verify before Phase 3. Contract-first:
if the goal touches a shared boundary, define a dedicated contract/scaffold task FIRST
and make it a `depends_on` prerequisite of every consumer.

Decision gate: if a task has multiple viable approaches, present them with tradeoffs and
**wait** — do not pick silently.

### Supporting skills routing

`test-ladder` goes into **every** implement/test context package — executors climb
rungs 1–2; rung 3's **authority** is this orchestrator at cycle end, **execution** is a
spawned `terminal`, never this session running `{{FULL_TEST_COMMAND}}` inline.

<!-- BOOTSTRAP: map layers → additional skills, e.g.
| Layer touched | Skills to include in context package |
|---------------|--------------------------------------|
| Backend module | TDD workflow skill |
| API routes | api-smoke-testing |
| Frontend | frontend best-practices skill, visual-qa-testing |
Plus the domain skill + ground-truth doc ({{GROUND_TRUTH_DOC}}) for any domain task. -->

## Phase 3 — Goal evaluation (loop until PASS)

Launch `evaluator` with goal.md, all task files, Phase 1 Q&A, and
`{{IDE_DIR}}/skills/goal-criteria/SKILL.md`. The evaluator validates every task's
`## Acceptance Criteria` once for all tasks.

- **PASS** → Phase 4. **NEEDS REVISION** → revise flagged items, re-evaluate (max 3).
- **REJECT** → escalate. The ONLY exit to Phase 4 is evaluator PASS on the current revision.

## Phase 4 — Task execution (each task loops until PASS)

For each task in dependency order:

1. Launch `implementer` (`test-writer` for the test task) with the full context package.
2. **Silent-success check**: empty/missing report ⇒ verify artifacts before failure —
   files/tests as specified ⇒ completed ("report lost, files verified"); no artifacts ⇒
   failed, respawn once. Never re-run when expected artifacts already exist.
3. Launch `evaluator` with the task file, report, and
   `{{IDE_DIR}}/skills/task-criteria/SKILL.md`.
4. **PASS** → next task. **NEEDS FIXES** → fix cycle + re-evaluate (max 3). **REJECT** → escalate.

   **Bypass at detection (every verdict, cycles 1–3).** Verdicts tagged `destructive`,
   `security`, or `infra` stop all cycles immediately and escalate — from cycle 1.

   **On cycle-3 exhaustion**, Read `reference/continuation-ladder.md` (relative to this
   skill) and follow it. Every ladder fix attempt is re-evaluated; no exception.

   **Fix-cycle model rotation**: cycle 1 re-runs normally; cycle 2 pins a **different
   model family** at comparable tier; cycle 3 pins **frontier tier** — see the model map.
   Record each rotation in the orchestration log.

Ladder rungs 1–2 only (see `test-ladder`); never rung 3. The headless loop inherits
this ladder; loop drivers' attempt cap and circuit breakers stay the outer backstop.

## Phase 5 — Final audit (loop until APPROVED)

Launch `evaluator` in audit mode: every task's requirements, cross-task integration,
regressions. **APPROVED** → Quality Checks (rung 3: full suite + lint/type) via spawned
`terminal` with `{{FULL_TEST_COMMAND}}` — never run it yourself. **ISSUES** → fix via
executor + re-evaluate (rungs 1–2), re-audit (max 3).

**Quality Checks failure**: non-zero exit with truncated excerpt ⇒ **Read** the log path
from the report (failure section or last ≤80 lines), route fix to `implementer`, re-spawn
`terminal` with a **narrower** command to confirm — never dump the full suite here.

Optional QA gate: after approval, capture behavioral evidence and launch `qa-evaluator`
per the architecture doc's QA section.

After APPROVED + Quality Checks, read `goal.md`'s `phases:` block: `align_docs: false`
skips Phase 6 ("Phase 6 skipped per goal.md" in the log); `pull_request: false` skips
Phase 7 likewise.

## Phase 6 — Align docs (loop until doc audit APPROVED)

Read `{{IDE_DIR}}/skills/align-docs/SKILL.md` and execute: discover shipped change
surface, per-doc edit list, evaluate plan, execute via `implementer`, evaluate each doc,
final doc audit. Docs-only — never code; `_research/` and `_goals/` read-only. Not
documentation-complete until doc audit APPROVED.

## Phase 7 — Pull request (gated on user approval)

Read `{{IDE_DIR}}/skills/ship-pr/SKILL.md` and execute: analyze commits/diff, draft PR,
**show draft and wait for approval**, push if needed. Report PR URL or hand-over artifact.
Skip if work was on the default branch (say so), the user declines a PR, or
`goal.md` has `pull_request: false`.

## Orchestration log (append-only spawn ledger)

Maintain `_goals/[goal-name]/orchestration-log.md` with a running `est_tokens` total in
the header. **Before** each spawn: timestamp, agent, model (rotation/fallback), routing
reason, task `writes` fence, expected outputs, `context_chars`. **After** return: outcome
line with `report_chars` and `est_tokens` (= (context_chars + report_chars)/4, labeled
estimate — proxies only; no harness exposes true token counts). Ladder transitions and
guard trips include the **rung name**. No placeholder lines ("Outcome: (pending)", "TBD").
Append-only — rejections and respawns are new entries. Auditable re-evaluation and rotation.

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

Subagent reports quoted as evidence are **verbatim** — never edit, summarize-in-place, or
polish raw output presented as the agent's. Paraphrase only in your own summary. A full
report may be referenced by its orchestration-log entry instead of dumped inline when only
the verdict/summary is presented.

## Escalation format

```markdown
## Escalation Required
**Phase**: [phase] · **Issue**: [what went wrong] · **Attempts**: [what was tried]
**Ladder**: [rungs attempted and their outcomes]
**Options**: 1. [option + tradeoffs] 2. [option + tradeoffs]
**What I need from you**: [specific decision]
```

For `criteria-defective` escalations (rung 5 arbitration), state the defective criterion
**verbatim** in **Issue**.
