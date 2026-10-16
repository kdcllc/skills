# Pre-flight (before Phase 3 evaluation attempt 1)

The orchestrator runs this checklist **once** after Phase 2 goal and task files exist
and **before Phase 3 evaluation attempt 1**. Never run it between evaluation attempts.
Pre-flight is **read-only** toward product code: it reads goal/task files and the workspace, and changes only goal/task files.
It produces **no score or verdict** and **never replaces** the evaluator.

<!-- BOOTSTRAP[preflight-extra]: List project-specific pre-flight checks here, one bullet each (e.g. "migration file paired with its model change"), or answer "" when there are none. -->

## Checks (stack-agnostic)

Run every check below, plus any project-specific checks listed above (if any).
Count all of them when forming the log line (N in `Pre-flight: N/N pass`).

### 1. Acceptance criteria and paths

For each task, confirm every acceptance criterion's verification method can run in
this workspace — no live service, credential, or unshipped feature required.

For every path in the task's `reads` list and every path in `writes` that the task
**modifies** rather than creates, run `test -e <path>`. Skip paths that are
placeholders containing `<`, `>`, `[`, `]`, or `*`.

**Failure:** a criterion cannot be verified locally, or `test -e` fails for a
non-placeholder path the task depends on or modifies.

### 2. Missed callers

For every symbol a task renames or re-signs, search the repo with
`rg -n '\b<symbol>\b'` (fallback `grep -rnw '<symbol>' .` when `rg` is unavailable).

**Failure:** any file with a hit is **not** inside some task's `writes` set (every
caller must be owned by a task that updates it).

### 3. Scope drift

Every task requirement must trace to a Success Criterion or a Phase 1 Q&A row in
`goal.md`. Nothing listed under `## Out of Scope` in `goal.md` may be required by any
task.

**Failure:** an orphan requirement, or a task that requires out-of-scope work.

### 4. Default-value semantics

Every new optional input, flag, or parameter a task introduces must state its default
explicitly in the task requirements.

**Failure:** a default is missing, or "absent" is treated as meaning "all" without
saying so.

## On failure

The orchestrator **fixes the goal/task files itself** (planning bookkeeping under
`_memory/work/goals/`, not product code), then launches the evaluator. Never escalate
for a pre-flight failure alone.

A fix that would change a **Phase 1 decision** is not a pre-flight fix — route it
through the user like any decision gate.

## Running commands

Commands whose output is short (`test -e`, a scoped search) may run **inline**.

Anything with long output goes through a **`terminal` spawn** per the feature skill's
**Terminal spawn rule** (exact command, shell, and the result needed back — not the
full stream).

## Logging

Record exactly **one** line via `_kit/log-spawn.sh note --goal <g> --text "..."`:

- All checks pass: `Pre-flight: N/N pass` (N = checks run, including project-specific).
- One or more fixes applied: `Pre-flight: fixed K: <one line per fix, semicolon-separated>`.
