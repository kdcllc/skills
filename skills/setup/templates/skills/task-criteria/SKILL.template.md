---
name: task-criteria
description: Criteria the evaluator applies when evaluating a completed task in {{PROJECT_NAME}}. Reference skill — not invoked directly.
disable-model-invocation: true
---

# Task Evaluation Criteria

Evaluate the executor's work against the task file, not against the report's claims.

**Hard-threshold rule**: the dimensions below are gates, not averages — one failing
dimension caps the verdict at NEEDS FIXES no matter how strong the rest are.

## 1. Requirements Completeness

Walk the task's requirements checklist item by item. Verify each against the actual code
(file:line) or test output — never against the executor's report alone — and mark each
on the confidence ladder (✅ Verified / ⚠️ Unverified / ❌ Contradicted / 🔍 Needs
investigation) per the evaluator's existence-check rules. One ⚠️ Unverified requirement
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

## Acceptance Criteria verification

Every task file carries an `## Acceptance Criteria` section (validated at Phase 3).
Verify the implementation against the task's Requirements **and** Acceptance Criteria.
Walk each numbered acceptance criterion and verify it using the verification method
stated on that line — file:line, test output, or command run, marked on the confidence
ladder the same way as requirements. An unaddressed or unverified acceptance criterion
caps the verdict at NEEDS FIXES.

## Light evaluation rubric (`eval_depth: light`)

Only when the task file's `eval_depth` is `light` (orchestrator-set, stated reason —
see `goal-criteria`). Shortened, never skipped:
1. Requirements walk (dimension 1), Test Evidence (dimension 4), and the write fence
   (dimension 5) run in full — these gate the verdict.
2. Correctness (dimension 2) and Reuse & Patterns (dimension 3) deep review is skipped.
3. Still ends in a real verdict (PASS / NEEDS FIXES / REJECT); auto-fail triggers apply.
4. Acceptance Criteria verification also runs in full under `light` — it is a hard gate,
   not a depth-scaled dimension, so every acceptance criterion is still checked regardless
   of `eval_depth`.

## Auto-fail triggers

Apply the auto-fail list in `{{IDE_DIR}}/agents/evaluator.md`.

## Failure-class taxonomy

Every non-PASS task verdict carries `failure_class:` from this closed set (see the
evaluator's Verdict format section for output shape and bypass consequence).

**Failure-class taxonomy (closed set):** `implementation` (default) · `criteria-defect` · `destructive` · `security` · `infra`.

- **`implementation`** — default when the work is wrong or incomplete but the criteria
  themselves are sound; fix and retry.
- **`criteria-defect`** — the acceptance criteria are defective; route to arbitration
  (ladder rung 5) or human escalation, not blind retry.
- **`destructive`** — would corrupt data, delete irrecoverable state, or cause
  irreversible harm; bypass — stop all retrying at detection, escalate.
- **`security`** — credential exposure, auth bypass, injection, or other security
  violation; bypass — stop all retrying at detection, escalate.
- **`infra`** — environment, tooling, or external dependency failure outside the
  implementer's control; bypass — stop all retrying at detection, escalate.

### Arbitration rubric

When ladder rung 5 invokes arbitration, the arbiter applies these defect types to the
**criteria** (never the implementation):

- **contradiction** — two or more acceptance criteria are mutually contradictory and
  cannot all be true at once.
- **Unsatisfiable** — no implementation could satisfy the criterion as written, even
  with perfect code.
- **Untestable** — the criterion has no verifiable check (no command, test, or observable
  outcome named).
- **Ambiguous** — reasonable engineers would interpret the criterion differently and
  reach conflicting PASS/FAIL verdicts.

Example — **contradiction**: AC 2 requires "all errors return 400" and AC 5 requires
"auth failures return 401"; both cannot hold for the same auth-error path.

Example — **unsatisfiable**: AC 3 demands "response time under 1 ms" on a network-bound
endpoint with no caching allowance stated in the task file.

Example — **untestable**: AC 4 says "code must be elegant" with no named linter, rubric
dimension, or command output verification.

Example — **ambiguous**: AC 7 says "match existing patterns" without naming which module
or convention file is the reference — two evaluators could disagree on PASS.

## Severity: minor

`minor` is wording, formatting, comment text, log phrasing, or non-normative prose that
(a) no requirement or acceptance criterion names and (b) changes no behavior, exit code,
or output. Anything named by a requirement or AC, anything that alters behavior, and
anything on the auto-fail list is never `minor`.

## Verdicts

- **PASS**: every requirement and acceptance criterion verified, ladder rungs 1–2 green,
  no auto-fails.
- **PASS (with notes)**: every requirement and acceptance criterion verified, rungs
  1–2 green, no auto-fails; the only issues found are `minor` and are listed under
  `### Notes (non-blocking)`. Counts as PASS for phase advancement.
- **NEEDS FIXES**: exhaustive required-fixes list (task loops back at most 3 times).
  Requires at least one `major` or `blocker`.
- **REJECT**: approach wrong or auto-fail fired; escalation needed.
