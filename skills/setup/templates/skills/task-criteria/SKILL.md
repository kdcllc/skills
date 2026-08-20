---
name: task-criteria
description: Criteria the judge applies when judging a completed task in {{PROJECT_NAME}}. Reference skill — not invoked directly.
disable-model-invocation: true
---

# Task Judgment Criteria

Judge the executor's work against the task file, not against the report's claims.

## 1. Requirements Completeness

Walk the task's requirements checklist item by item. Verify each against the actual code
(file:line) or test output — never against the executor's report alone — and mark each
on the confidence ladder (✅ Verified / ⚠️ Unverified / ❌ Contradicted / 🔍 Needs
investigation) per the judge's existence-check rules. One ⚠️ Unverified requirement
caps the verdict at NEEDS FIXES; any ❌ Contradicted claim does too.

## 2. Correctness

- Error paths behave as specified (auth failures surfaced cleanly, no swallowed
  exceptions, correct exit/status codes).
- Edge cases: empty results, pagination, malformed input.
- No regressions in the files touched.

## 3. Reuse & Patterns

Shared core modules are reused, not re-implemented. New code matches the conventions of
the neighboring code and the domain skill's non-negotiables.

## 4. Test Evidence

Require evidence of `test-ladder` rungs 1–2 (new tests, then impacted tests).
Do **not** fail a task for skipping rung 3 — the full suites run once at cycle end,
after the final audit. The task's tests must exist, be meaningful (assert outcomes, would fail on
regression), pass, and mock all external services. Run them yourself
(`{{TARGETED_TEST_COMMAND}}`-style rung 1–2 run) — do not trust reported output.

## 5. Scope Discipline

Only the task's declared files changed. Unrequested refactoring or drive-by edits are
flagged.

**Write fence — execution.** The task's ownership block declares a `writes` set; that set
is the executor's fence. Verify it from the repository, never from the report:
`git status` / `git diff --name-only` must show every change confined to the declared
paths. Where declared paths lie outside git's view (gitignored install artifacts,
generated state), `git status` proves nothing — verify those by content hash against a
recorded baseline or by an mtime window covering the executor's run, and state which
method you used. A file changed outside the fence is ❌ Contradicted scope whatever the
justification. The healthy opposite is a reported escalation — the executor naming the
exact out-of-fence path it needed and stopping instead of editing it; score that as a
correct outcome that routes back to the orchestrator for re-planned ownership, not as a
scope failure.

**Write fence — delivery.** Confirm the fence actually reached the executor: the context
package carried a `## Write fence` section, cross-checked against the `writes` claim the
orchestration-log entry recorded for this task. If the orchestrator omitted the fence,
the fault is the orchestrator's — route the fix there (re-dispatch with the fence in the
package). Never fail the executor for a fence it was never given.

## Auto-fail triggers

Apply the auto-fail list in `{{IDE_DIR}}/agents/judge.md`.

## Verdicts

- **PASS**: every requirement verified, ladder rungs 1–2 green, no auto-fails.
- **NEEDS FIXES**: exhaustive required-fixes list (task loops back at most 3 times).
- **REJECT**: approach wrong or auto-fail fired; escalation needed.
