# Contract: [NN-task-name]

<!-- Instance naming: _goals/[goal]/contracts/NN-task-name.contract.md — one contract
     file per task, filed in a `contracts/` subdirectory of the goal, named after the
     task file it expands (e.g. `_goals/checkout-v2/contracts/03-payment-webhook.contract.md`).
     Created during the Phase 4 contract gate, before implementation dispatch — see
     `feature/SKILL.md` Phase 4. The contract is the testable expansion of the task
     file, never a second source of scope. -->

## task_id

[NN-task-name — must match the corresponding task file's id exactly]

## done_definition

[Prose, one paragraph: what "done" looks like for this task, precise enough that
someone who did not write the task file could verify it unaided.]

## acceptance_criteria

1. [Specific, verifiable criterion] — verification: [unit test | integration test | command output | live interaction | screenshot]
2. [Specific, verifiable criterion] — verification: [unit test | integration test | command output | live interaction | screenshot]
3. [...]

## verification_environment

[CLI | API | browser | library]

## out_of_scope

- [Explicitly excluded from this contract, even if adjacent to the task]

```yaml
# --- contract sign-off ---
signoff:
  worker:              # the task's owner agent (implementer|test-writer), proposing
    agreed: [true|false]
    timestamp: [ISO 8601 timestamp]
    note: [one-line note]
  evaluator:           # evaluator, spawned in contract mode to review/counter-sign
    agreed: [true|false]
    timestamp: [ISO 8601 timestamp]
    note: [one-line note]
revision: [0-2]        # bumped once per revision round; max 2 rounds — a 3rd round is
                       # never attempted, the orchestrator tiebreaks or escalates to
                       # the user instead
```
