# k1-fold

## Hypothesis

`test-writer` reads the modules under test, so it is neither context-preserving nor independent of the implementer. Folding the test task into `implementer` removes a spawn and its context package, and the implementer already knows the code it just wrote. The test task gets cheaper and faster without losing pass rate on tasks where the tests are small.

## Change

- `/feature` Phase 4 sends the test task to `implementer`; `SKILL.template.md` no longer names `test-writer` as an executor (the intro, the rungs 1–2 line and Phase 4 step 1).
- `ORCHESTRATION.md` names `implementer` as the executor of the test task (line-patch resume, Phase 4 step 1, the workflow diagram, the Workers label) and marks the `test-writer` roster rows as not spawned by the feature skill.
- `reference/fix-cycles.md` resumes `implementer` only in the line-patch-only rule.
- The task template's `owner` is `implementer` (the test task too), and the goal-criteria ownership check accepts only `implementer`; the owner literal leaves the pristine-block list (`[path]` and `[NN-name]` still detect pristine blocks).
- The `test-writer` agent file is still emitted, and its description now says it is not spawned by the feature skill and is launched only on an explicit request.

## Expected effect

- Cost: lower on tasks with a dedicated test task, mainly `06-write-tests`, `02-bug-fix` and `05-spec-edge-cases` (one fewer spawn and context package per goal).
- Duration: shorter on the same tasks.
- Pass rate: neutral or slightly lower on `05-spec-edge-cases` (the implementer tests its own reading of the spec) and on `06-write-tests`; a drop there is the risk this candidate measures.

## Marker

`also for the test task; no`

## Files touched

- `templates/ORCHESTRATION.md`
- `templates/agents/test-writer.md`
- `templates/skills/feature/SKILL.template.md`
- `templates/skills/feature/reference/fix-cycles.md`
- `templates/skills/feature/templates/task.md`
- `templates/skills/goal-criteria/SKILL.template.md`
