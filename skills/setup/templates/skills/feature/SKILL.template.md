---
name: feature
description: Orchestrate a feature for {{PROJECT_NAME}} end-to-end — evaluator-gated goal, task, audit, docs, and PR phases, all execution delegated to fresh-context subagents. Invoke for any non-trivial feature.
---

# Feature (Feature Orchestrator)

You are the **orchestrator**. You coordinate; you never execute. Implementation goes
to `implementer`/`test-writer`; verification to `evaluator`. Read
`{{IDE_DIR}}/ORCHESTRATION.md` by **current-phase section**, never whole.

**Iron rules:**
- You never write or edit product code yourself.
- Every subagent gets a complete context package.
- No phase advances without evaluator PASS / PASS (with notes) / APPROVED.
- Fixes and revisions are ALWAYS re-evaluated. No exception.
- Max 3 evaluation cycles per phase/task; on Phase 4 cycle-3 exhaustion, read
  `phases.ladder` (`escalate` default or key absent → escalate with "Run the
  continuation ladder" as option 1; `auto` → continuation ladder). Other phases escalate.
- Every spawn passes its model explicitly (the model map's resolved ID for the agent's
  tier); the log records requested vs self-reported. `inherit` only for a tier the
  install left unpinned.
- Transient subagent-launch failure: retry the same subagent up to 3 times (backoff
  2s/4s/8s). Never substitute a different agent type.

### Terminal spawn rule

Spawn `terminal` for **any Bash or PowerShell command** whose raw output should not
land here — pass the exact command, shell (`bash` or `pwsh`), and the result needed;
it returns **only** that result. Never run `{{FULL_TEST_COMMAND}}` yourself — spawn
`terminal` for rung 3. Rungs 1–2 stay with `implementer`/`test-writer` when output is
small; they may spawn `terminal` for noisy commands where the harness allows (not
Copilot — only this L1 session spawns there). Exception: `_kit/log-spawn.*` is run
inline by the orchestrator (single-line output), never via `terminal`.

### Resume policy

Re-evaluations (Phase 3 revisions, Phase 4 fix cycles, Phase 5 re-audits) RESUME the
same evaluator with a delta prompt listing only the applied fixes. The implementer MAY
be resumed for fix cycle 1; cycles 2–3 are fresh spawns (model rotation applies).

Update the architecture doc's Orchestration Progress block after each step.

## Phase 1 — Alignment (no files)

Ask the user 5–20 structured multiple-choice questions covering: the problem, which
layer/lane is affected ({{EXECUTION_LAYERS}}), external surfaces touched,
auth/permissions, error behavior, interface shape, existing patterns to follow, and
priority — plus run Phase 6 docs alignment? (default **no** — yes when user-facing docs
change) and open a Phase 7 PR? (default yes). Present a "My Understanding" summary and
**wait for explicit confirmation** before Phase 2. Record Phase 6/7 answers and
`ladder:` in `goal.md`'s `phases:` block (interactive goals: `escalate` unless asked).

## Phase 2 — Goal creation

Create `_goals/[goal-name]/` containing:
- `goal.md` from `templates/goal.md` (Phase 1 Q&A + `phases:` block)
- One `NN-task-name.md` per task from `templates/task.md`, in dependency order along
  {{EXECUTION_LAYERS}}, then a final test task.

Every task file carries the ownership contract (`writes`/`reads`/`depends_on`/`owner`/
`rewrite_semantics` — see `templates/task.md`), `## Acceptance Criteria` (criterion +
verification method each; Phase 3 validates once), and disjoint `writes` sets for every
pair of tasks without a `depends_on` ordering. `eval_depth`
default is `light`; set `full` with reason for contract tasks / tasks with interface
consumers (mirroring, documenting, or testing the output does not count) / tasks writing
agents, criteria, drivers, shared infra. Contract-first: a shared boundary gets a
dedicated contract/scaffold task FIRST, a `depends_on` prerequisite of every consumer.

Decision gate: multiple viable approaches → present tradeoffs and **wait**.

### Supporting skills routing

`test-ladder` in **every** implement/test package — executors climb rungs 1–2; rung 3
**authority** is this orchestrator at cycle end, **execution** a spawned `terminal`,
never `{{FULL_TEST_COMMAND}}` inline here.

<!-- BOOTSTRAP[layer-skill-map]: map layers → skills, e.g.
| Layer touched | Skills to include in context package |
|---------------|--------------------------------------|
| Backend module | TDD workflow skill |
| API routes | api-smoke-testing |
| Frontend | frontend best-practices, visual-qa-testing |
Plus domain skill + ground-truth ({{GROUND_TRUTH_DOC}}) for any domain task. -->

## Phase 3 — Goal evaluation (loop until PASS)

Launch `evaluator` with goal.md, all task files, Phase 1 Q&A, and
`{{IDE_DIR}}/skills/goal-criteria/SKILL.md`; it validates every task's
`## Acceptance Criteria` once.

- **PASS** → Phase 4. **NEEDS REVISION** → revise flagged items, re-evaluate (max 3).
- **REJECT** → escalate. The ONLY exit to Phase 4 is evaluator PASS on the current revision.

## Phase 4 — Task execution (each task loops until PASS)

For each task in dependency order:

1. Launch `implementer` (`test-writer` for the test task) with a full context package.
2. **Silent-success check**: empty/missing report ⇒ verify artifacts: present ⇒
   completed ("report lost, files verified"); absent ⇒ failed, respawn once. Never
   re-run when expected artifacts already exist.
3. Launch `evaluator` with the task file, report, and
   `{{IDE_DIR}}/skills/task-criteria/SKILL.md`.
4. **PASS** or **PASS (with notes)** → next task (notes go into the log entry via `--note`). **NEEDS FIXES** → fix cycle + re-evaluate (max 3). **REJECT** → escalate.

   **Bypass at detection (every verdict, cycles 1–3).** Verdicts tagged `destructive`,
   `security`, or `infra` stop all cycles immediately and escalate — from cycle 1.

   **On cycle-3 exhaustion**, read `goal.md`'s `phases.ladder`: `escalate` (default, or
   key absent) → escalate with "Run the continuation ladder" as option 1 (log "ladder:
   escalate per goal.md"); `auto` → Read `reference/continuation-ladder.md` and follow
   it. Every ladder fix attempt is re-evaluated; no exception.

   **Fix-cycle model rotation**: cycle 1 re-runs normally; cycle 2 pins a **different
   model family** at comparable tier; cycle 3 pins **frontier tier** (model map). Log
   each rotation.

Ladder rungs 1–2 only (`test-ladder`); never rung 3. The headless loop inherits this.

## Phase 5 — Final audit (loop until APPROVED)

Launch `evaluator` in audit mode: every task's requirements, cross-task integration,
regressions. **APPROVED** → Quality Checks (rung 3: full suite + lint/type) via spawned
`terminal` with `{{FULL_TEST_COMMAND}}`. **ISSUES** → fix via executor + re-evaluate
(rungs 1–2), re-audit (max 3).

**Quality Checks failure**: non-zero exit with truncated excerpt ⇒ **Read** the log path
(failure section or last ≤80 lines), route to `implementer`, re-spawn `terminal`
with a **narrower** command — never dump the full suite here.

Optional QA: after approval, capture evidence and launch `qa-evaluator`.

Then read `goal.md`'s `phases:` block: `align_docs: false` skips Phase 6 (log "Phase 6
skipped per goal.md"); `pull_request: false` skips Phase 7 likewise.

## Phase 6 — Align docs (loop until doc audit APPROVED)

Read `{{IDE_DIR}}/skills/align-docs/SKILL.md` and execute. Docs-only — never code;
`_research/` and `_goals/` read-only. Complete only at doc audit APPROVED.

## Phase 7 — Pull request (gated on user approval)

Read `{{IDE_DIR}}/skills/ship-pr/SKILL.md` and execute: analyze commits/diff, draft PR,
**show draft and wait for approval**, push if needed. Report PR URL or hand-over
artifact. Skip on the default branch (say so), if the user declines, or on
`pull_request: false`.

## Orchestration log (append-only spawn ledger)

`_goals/[goal]/orchestration-log.md` is written ONLY through `_kit/log-spawn.sh`
(`pwsh _kit/log-spawn.ps1` on Windows; same flags — see `--help` or ORCHESTRATION.md).
**Before** each spawn: write the full context package to
`_goals/[goal]/spawns/NN-context.md` (NN = next free number), then
`_kit/log-spawn.sh spawn --goal [goal] --agent [agent] --phase "…" --model-requested [id] --context [that file] [--writes --why --expect]`
(measures `context_chars`). **After** return: save the verbatim report to
`spawns/NN-report.md`, then `_kit/log-spawn.sh outcome --goal [goal] --spawn NN --report [that file] --verdict "…" --model-reported "…"`
(appends `report_chars`, `io_est_tokens` — orchestrator I/O proxy, chars/4 — and
`work_est_tokens` from the agent's `### Footprint` (`n/a` = block missing: flag it to
the evaluator), plus both running totals). Phase completions, ladder transitions (with
the **rung name**), guard trips, skips: `_kit/log-spawn.sh note --goal [goal] --text "…"`.
No placeholder lines ("TBD"). Append-only — rejections and respawns are new entries.

## Context packages

Every launch (= the `spawns/NN-context.md` file) uses this structure:

```
You are the [subagent-name] subagent. Read: {{IDE_DIR}}/agents/[subagent-name].md

CURRENT_DATETIME: [literal ISO timestamp — never guess dates]

## Task
[what to accomplish]

## Requirements
[exhaustive list from the task file]

## Files to Read
[explicit paths: code, skills, ground-truth docs]

## Write fence
[the task's `writes` list — the ONLY paths this subagent may create or modify]

## Model
requested: [resolved ID from the model map for this agent's tier] · tier: [light|frontier] · rotation: [cycle N or n/a]

## Rules
[must-do / must-not-do constraints for this task]

## Output
[the exact report/verdict format expected]
```

## Report integrity

The verbatim report lives at `spawns/NN-report.md` — never edit or polish it; the log
references it. Paraphrase only in your own summary.

## Escalation format

```markdown
## Escalation Required
**Phase**: [phase] · **Issue**: [what went wrong] · **Attempts**: [what was tried]
**Ladder**: [rungs attempted + outcomes]
**Options**: 1. [option + tradeoffs] 2. [option + tradeoffs]
**What I need from you**: [specific decision]
```

For `criteria-defective` (rung 5), quote the criterion **verbatim** in **Issue**.
