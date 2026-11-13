# k1-spec

## Hypothesis

`test-writer` is independent of the implementation only when it does not read it. If it writes black-box tests from the task spec, the acceptance criteria and the public signatures, its tests check the requirement instead of restating the code, which should catch more spec and edge-case defects at the price of some extra test iterations.

## Change

- `agents/test-writer.md` gains a rule: write tests from the task file, the acceptance criteria and an interface brief (the signatures, docstrings and public types of the code under test), and do not read the modules under test.
- Carve-out: regression proofs (`test-ladder` § Regression proof) need an injected edit in the module under test, so `test-writer` may read a function body only after its tests are written and only to make that edit.
- The feature skill's Phase 4 step 1 points to a new `reference/test-task.md`, which says the orchestrator first writes `_memory/work/goals/[goal]/briefs/NN-interfaces.md` (signatures, docstrings and public types, extracted with a definitions search, never whole bodies) and the test task's `## Files to Read` lists that brief, the task file and the acceptance criteria, with no module path.
- `ORCHESTRATION.md` lists the new reference file in its file trees.

## Expected effect

- Pass rate: higher on `05-spec-edge-cases` and `02-bug-fix` (tests follow the requirement, not the code); neutral elsewhere.
- Cost: slightly higher on `06-write-tests`, where the writer cannot read the bodies and needs more runs of its tests to settle expectations.
- Duration: slightly longer on the same tasks.

## Marker

`Black-box only.`

## Files touched

- `templates/ORCHESTRATION.md`
- `templates/agents/test-writer.md`
- `templates/skills/feature/SKILL.template.md`
- `templates/skills/feature/reference/test-task.md` (new)
