---
name: goal-criteria
description: Criteria the judge applies when judging a goal (goal.md + task files) for {{PROJECT_NAME}}. Reference skill — not invoked directly.
---

# Goal Judgment Criteria

Score each dimension; the verdict starts at 2/5 and must be earned.

## 1. Discovery Coverage

Every decision recorded in the Phase 1 Q&A summary is reflected somewhere in the goal or
a task. An answered question that no task honors is a NEEDS REVISION.

## 2. Success Criteria Quality

Criteria are observable outcomes ("`command X` returns Y with exit code 0"), not
activities ("implement module X"). Each is verifiable by a judge without asking the user.

## 3. Task Decomposition

- Tasks follow the project's layer order ({{EXECUTION_LAYERS}}) and declare dependencies.
- Each task is completable by a fresh-context subagent from its file alone: exhaustive
  requirements, explicit files-to-read, explicit constraints, a targeted test command.
- A dedicated test task exists and covers every implementation task's output.

## 4. Scope Discipline

Out-of-scope section exists; no task smuggles in unrelated refactoring; no requirement
contradicts the constraints or the ground-truth doc ({{GROUND_TRUTH_DOC}}).

## 5. Risk Coverage

Error paths (auth failures, empty/malformed data, pagination), migration/compatibility
concerns, and rollback are addressed by some task where relevant.

## 6. Devil's Advocate (required section of every goal judgment)

Before the verdict, produce all five — informative, **never a veto** on its own:

1. **Steelman the strongest alternative approach** — the strongest version, not a
   strawman that's easy to defeat.
2. **Load-bearing assumptions** — things the goal treats as fixed that are actually
   choices.
3. **30-day pre-mortem** — "it's a month later and this shipped and failed; what
   happened?"
4. **At least one concrete alternative** sketch, so the chosen direction is a *chosen*
   direction.
5. **Risk acceptance** — which surfaced risks the goal implicitly accepts.

A DA finding forces NEEDS REVISION only when it reveals an unaddressed risk that a
success criterion or task should cover.

## Verdicts

- **PASS**: all six dimensions solid; a fresh executor could run task 01 right now.
- **NEEDS REVISION**: fixable gaps — list every one (goal loops back at most 3 times).
- **REJECT**: the decomposition or approach is wrong; the user must decide.
