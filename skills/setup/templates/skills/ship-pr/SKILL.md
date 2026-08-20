---
name: ship-pr
description: Summarize all commits on the current branch into a rich GitHub pull request — an executive (manager-facing) summary plus a technical breakdown — then create the PR with the gh CLI. Phase 7 of the {{PROJECT_NAME}} orchestration lifecycle; also usable standalone when the user says "open a PR" or "ship this branch".
disable-model-invocation: true
---

# Ship PR (Phase 7)

Turn the commits on the current branch into a polished GitHub pull request. The PR body
has two audiences: a **manager-facing executive summary** (what was accomplished and why
it matters) and a **technical breakdown** (what changed, grouped by area). The PR
description is **drafted and shown for approval before the PR is created**.

Uses the `gh` CLI for all GitHub operations. Never update git config, never force-push,
never skip hooks, and only push/commit work the user expects.

## Workflow

```
- [ ] Step 1: Gather branch + commit context
- [ ] Step 2: Detect the base branch
- [ ] Step 3: Analyze the diff and commits
- [ ] Step 4: Draft the PR title + body
- [ ] Step 5: Show the draft and get approval
- [ ] Step 6: Push the branch (only if needed)
- [ ] Step 7: Create the PR with gh
- [ ] Step 8: Return the PR URL
```

### Step 1: Gather branch + commit context

```bash
git rev-parse --abbrev-ref HEAD          # current branch
git status --short                       # uncommitted changes?
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
```

If the current branch IS the default branch, stop and tell the user — a PR needs a
feature branch. If there are uncommitted changes, surface them and ask whether to
include them (do not silently commit).

### Step 2: Detect the base branch

```bash
BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch origin "$BASE" --quiet
git log --oneline origin/"$BASE"..HEAD
```

If that range is empty, stop — there is nothing to open a PR for.

### Step 3: Analyze the diff and commits

```bash
git log origin/"$BASE"..HEAD --pretty=format:'%h %s%n%b' --reverse
git diff origin/"$BASE"...HEAD --stat
```

Inspect the actual changes in the most-changed files. Group changes by area so the
technical breakdown reflects real structure — use the project's layers:
{{EXECUTION_LAYERS}}.

### Step 4: Draft the PR title + body

**Title**: one concise line in the repo's commit style (imperative, no trailing period).

**Body** template:

```markdown
## Summary
<2–4 sentence executive summary for a manager/stakeholder: what was accomplished,
the user/business impact. No jargon, no file names.>

## What changed
- **<Area>** — <plain-language outcome>

## Technical details
<Grouped breakdown for reviewers: design decisions, new dependencies,
schema/contract changes, anything risky.>

## Testing
- <How it was verified. Cycle-end gate is rung 3 of the test-ladder:
  {{FULL_TEST_COMMAND}}.>

## Notes for reviewers
<Optional: call-outs, follow-ups, open questions. Omit if empty.>
```

Drafting rules: the Summary is outcomes and impact, never a commit log; derive content
from the diff, not just commit subjects; omit empty sections; match the repo's tone.

### Step 5: Show the draft and get approval

Present the title and full body and wait for approval or edits. Do not create the PR
yet.

### Step 6: Push the branch (only if needed)

```bash
git status -sb            # ahead/behind + upstream
git push -u origin HEAD   # only if no upstream or local is ahead
```

Never force-push. If the push is rejected, report it instead of forcing.

### Step 7: Create the PR with gh

```bash
gh pr create --base "$BASE" --title "<approved title>" --body "$(cat <<'EOF'
<approved body>
EOF
)"
```

If a PR already exists for the branch, `gh pr edit` it instead of creating a duplicate.

### Step 8: Return the PR URL

Print the URL and note whether a PR was created or updated.

## Guardrails

- **Approval first** — always show the drafted description and wait before creating.
- If `gh` fails with an auth error, tell the user to run `gh auth login`.
- **Never** update git config, force-push, or use `--no-verify`.
- Don't commit uncommitted work without explicit approval.
- Cite the base branch you targeted.
