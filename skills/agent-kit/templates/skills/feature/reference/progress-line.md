# Feature progress line

## Format

The user-facing line is:

`Progress: <pct>% (<done>/<total> steps, metric v1); <current unit>, <in flight>.`

The durable `progress:` header in `progress.md` uses the same line with `Progress:` written as `progress:`. The metric label is `metric v<N>`.

## Feature metric v1

There is one step per enabled phase — Phases 1–5 always, Phase 6 when `goal.md` `phases:` has `align_docs: true`, and Phase 7 when `pull_request: true` — plus one step per Phase 4 task file. Corrective tasks count too; adding a task raises the total. Phases skipped per `goal.md` are not steps.

A step is done at these points:

- Phase 1 at user confirmation.
- Phases 2 and 3 at the Phase 3 goal-evaluator PASS, the gate for the goal and tasks Phase 2 wrote.
- Each task at its task-evaluator PASS or PASS (with notes).
- Phase 4 when every task is done.
- Phase 5 when it exits: audit APPROVED, Quality Checks green, and qa-evaluator PASS when `qa: run`.
- Phase 6 at the final doc audit APPROVED.
- Phase 7 when a PR is created or updated, hand-over is printed, or a runtime skip (default branch or user declines) is logged.

Escalated or in-progress steps are not done. Calculate `pct` as `floor(done × 100 / total)`.

The current unit is `Phase 1 alignment`, `Phase 2 goal creation`, `Phase 3 goal evaluation`, `Phase 4 T<NN>`, `Phase 5 audit`, `Phase 6 docs`, `Phase 7 PR`, or `done` when `status: done`. For Phase 4, use the task id prefix from the task file (for example, `T03` or `T06a`); join several tasks in one ready group with `+` (for example, `Phase 4 T03+T04`).

In flight comes from SPAWN entries with no OUTCOME in `## In flight`: one agent is `<agent> running`; multiple of one agent are `<n> <agent>s running`; mixed agents are joined with ` + ` before ` running` (for example, `2 implementers + evaluator running`). When nothing is in flight, use `waiting on user` when `status: waiting-on-user` or `## Waiting on user` is not `none`; otherwise use `idle`.

## When it is printed

Every time `progress.md` is rewritten (the moments listed in `reference/resume.md` § When progress.md is written), the orchestrator writes the derived `progress:` line into the file and opens its user-facing update at that moment with the same line as its first line. The line is derived, never hand-edited, and is never printed by the research or memory-capture workflows.

## Deriving the line

Compute the line from the new `progress.md` content (Orchestration Progress checklist, `## Tasks` Final column, `## In flight`, and `status:`), `goal.md` `phases:`, and orchestration-log SPAWN entries without OUTCOME. Reconcile those SPAWN entries with `## In flight`. The `progress:` line in the file is the same line with `Progress:` written as `progress:`.

## Versioning

Changing what counts as a step, when a step counts as done, or the percentage formula bumps the label to the next version (`metric v2`) and documents the new definition here alongside the old one so older `progress.md` files stay readable. Wording changes to the current-unit or in-flight clauses do not bump it. The feature label and the loop label version independently.

## Examples

For one goal with six enabled phases (Phases 1–6) and four Phase 4 tasks, there are ten steps:

- `Progress: 10% (1/10 steps, metric v1); Phase 2 goal creation, idle.`
- `Progress: 30% (3/10 steps, metric v1); Phase 4 T01, implementer running.`
- `Progress: 50% (5/10 steps, metric v1); Phase 4 T03, waiting on user.`
- `Progress: 100% (10/10 steps, metric v1); done, idle.`

## Loop driver

The autonomous loop driver prints its own line on stderr after each reap with a similar shape. Its own step metric (loop `metric v1`: steps are backlog stories) is defined in the `_loop/loop.sh` header, so the feature and loop labels are independent.
