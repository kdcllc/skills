# Candidates

This directory holds candidate changes to agent-kit, one folder per candidate (`<name>/patch.diff` and `<name>/README.md`). The format, the marker rule, the size budget and the four candidates are defined in the sections "Candidates" and "compare.sh" of [../README.md](../README.md). That README wins when the two disagree.

Candidates are temporary. A later goal adopts each one (moves the change into `skills/agent-kit/` with a version bump) or deletes it. Nothing here is shipped to kit users.

To regenerate a candidate when the kit changes:

1. Copy `skills/agent-kit/` twice to scratch (outside the repository).
2. Re-apply the intended change to one of the copies.
3. Run `diff -ruN` on the two copies and save the output as `patch.diff` (paths relative to the kit directory, `a/templates/...`). Run `diff -ruN a b > patch.diff` from the scratch parent folder, with the two copies named `a` and `b` (relative names), so paths read `a/templates/...`; absolute paths produce a patch `git apply -p1` rejects.
4. Run `bash tests/agent-kit/evals/compare.sh --check --cand <name>`.
