# Task NN: [name]

## Objective

[One paragraph: what exists when this task is done.]

## Dependencies

- [Tasks that must be complete first, or "none"]

```yaml
# --- task ownership contract ---
writes:              # [the ONLY paths this task may create or modify]
  - [path]           # [explicit paths by default; use a glob only when this task owns
                     #  the whole directory — two globs that overlap count as
                     #  intersecting, same as two identical paths]
reads:               # [interface briefs this task depends on, read-only]
  - [path]           # [exported symbols and signatures only, never edited here]
depends_on:          # [task ids that must land before this one, or [] for none]
  - [NN-name]
owner: [implementer|test-writer]     # [one writer for every path above]
rewrite_semantics: [whole-file|targeted-insertion]
# [whole-file is the default — small single-owner source files: the owner rewrites
#  them wholesale and never assumes another agent will reconcile the result.
#  targeted-insertion is for large shared documents: surgical edits that leave every
#  unrelated line untouched.]
```

## Requirements (exhaustive — the judge verifies every item)

- [ ] [Specific, verifiable requirement]
- [ ] [Error handling requirement — what happens on failure X]
- [ ] [...]

## Files to Read

- [path] — [why]

## Files to Create / Change

- [path] — [what]
- [Exactly the paths in the ownership contract's write-set above — no extras, no
  omissions; this section is the prose view of that machine block.]

## Constraints

- Must: [reuse shared module X, follow pattern in Y, ...]
- Must NOT: [re-implement Z, touch live services, modify files outside this list, ...]

## Verification

- Targeted test command: `[exact command]`
- [Any manual verification evidence to capture]
