# Goal: [name]

## Problem Statement

[What is broken/missing, for whom, and why it matters. 2–5 sentences.]

## Discovery Summary (Phase 1 Q&A)

[Condensed record of the alignment questions and the user's answers. The goal judge
checks tasks against this — every answered decision must be reflected in a task.]

## Success Criteria

- [ ] [Observable, verifiable outcome — behavior, not activity]
- [ ] [...]

## Constraints

- [Must reuse / must not touch / performance / compatibility constraints]

## Out of Scope

- [Explicitly excluded work, so the judge can flag scope creep]

## Tasks (dependency order)

| # | Task file | Layer | Depends on |
|---|-----------|-------|------------|
| 01 | `01-[name].md` | [layer] | — |
| 02 | `02-[name].md` | [layer] | 01 |
| NN | `NN-tests.md` | tests | all |

**Contract first.** If this goal touches a shared boundary or interface, the first task
is a dedicated contract/scaffold task — it defines the types, schemas, and port
interfaces and creates the empty file skeletons — and every task that consumes them
lists it in `depends_on`. Consumers then build against a frozen contract instead of
each other's files.
