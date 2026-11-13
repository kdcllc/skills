# k4-criteria

## Hypothesis

A task verdict that must list every acceptance criterion with its own result (met, unmet or unverified) and evidence cannot skip a criterion without the gap showing, so the evaluator misses fewer unmet criteria and returns fewer false PASS verdicts. The candidate changes the verdict's shape (one row per criterion), not the gate: PASS and PASS (with notes) still need every criterion verified, an `unmet` row is cited by a blocking issue, and `unverified` rows block, as the stock task-criteria "Acceptance Criteria verification" section and the evaluator's stance already require. Goal evaluations and audits are unchanged.

Not covered: K4's "no new findings for N cycles" stop. "Early ladder entry" (`reference/fix-cycles.md`, line 135) ends fix cycles early under `ladder: auto` when a `[structural]` key repeats, and then starts the continuation ladder, which is more work, not a stop. A "no new findings" stop is therefore not covered by the kit and is left for a later candidate.

## Change

- The evaluator's verdict format gains a required `### Criteria` table before `### Issues found` for Phase 4 task evaluations and ladder re-evaluations: one row per acceptance criterion, columns `# | Criterion (short) | Result (met / unmet / unverified) | Evidence (command output, file:line or report section)`. A short paragraph states the rule: every row `met` for PASS, `unmet` cited by a blocking issue, `unverified` blocks, every other mode omits the table.
- The task-criteria skill's "Acceptance Criteria verification" section says the same in one short paragraph.
- No change to `templates/skills/feature/SKILL.template.md`, so the 11264-byte budget is untouched.

## Expected effect

- Pass rate: equal or higher, and only on tasks where an earlier stock verdict would have passed work that missed a criterion. The tasks most likely to show it are the ones with several separate requirements: `05-spec-edge-cases`, `10-error-handling`, `09-signature-change` and `04-multi-file-rename`. Tasks with one obvious criterion (`01-trivial-fix`) should tie.
- Cost: slightly higher, because the evaluator writes and backs a row per criterion.
- Duration: slightly longer for the same reason; a further fix cycle appears only when the table exposes a real gap.

## Marker

`The table changes the verdict's shape, not the gate.`

## Files touched

- `templates/agents/evaluator.md`
- `templates/skills/task-criteria/SKILL.template.md`
