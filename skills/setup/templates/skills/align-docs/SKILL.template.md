---
name: align-docs
description: Align all repository documentation to shipped code after a feature is implemented — Phase 6 of the {{PROJECT_NAME}} orchestration lifecycle. Updates every markdown surface (READMEs, docs/, agent/skill files) EXCEPT _research/ and _goals/ (orchestrator-managed, read-only). Runs after the final audit and Quality Checks pass, or when the user asks to sync documentation with recent changes.
disable-model-invocation: true
---

# Align Docs (Phase 6)

Bring repository **documentation** back in sync with shipped **code** after a feature
lands. Same evaluator-gated subagent workflow as the `feature` skill (discover → plan →
evaluate → execute-per-doc → final audit), but the deliverable is **accurate Markdown,
never code**.

## Core guardrails (NON-NEGOTIABLE — repeat in every subagent context package)

1. **HARD EXCLUSION — `_research/` and `_goals/`.** Never create, edit, or delete
   anything under these paths. You **may READ** them as source-of-truth for what
   shipped; you must **never WRITE** to them.
2. **DOCS-ONLY.** Never modify code, infra, tests, or config. If a doc claims behavior
   that does not exist, **fix the doc** — never change code to match the doc.
3. **ANTI-INVENTION.** Every documented claim must trace to a file you actually read
   this run. If a detail is unconfirmed, **omit it** — do not guess routes, flags,
   names, or behavior.
4. **SCOPE DISCIPLINE.** Update only **stale or missing** content. Preserve
   already-accurate prose **verbatim**. Prefer surgical edits over rewrites; a
   justified no-op for an already-correct doc is a valid outcome.
5. **HISTORICAL LOGS.** Dated notes under `_research/` are append/annotate territory,
   not rewrite-history. Promote only implemented ground truth into {{GROUND_TRUTH_DOC}}.
<!-- BOOTSTRAP[rendered-siblings]: if this project keeps rendered siblings of any markdown doc (e.g. a
     hand-styled .html mirror), add a guardrail here naming the exact pair(s) and
     requiring surgical same-edit syncing — never wholesale regeneration. Otherwise
     delete this comment. -->

## Documentation surface map

In scope: **everything markdown EXCEPT `_research/` and `_goals/`** — READMEs, docs
under `docs/`, per-directory instruction files, and `{{IDE_DIR}}/`
skill/agent files.

<!-- BOOTSTRAP[doc-buckets]: list this project's actual doc buckets and the code-area → doc mapping
     (e.g. "API routes → docs/api.md + README endpoints table"), so Phase 2 can map
     shipped changes to affected docs without guessing. -->

## Subagents

Uses the standard kit subagents: `evaluator` (plan evaluation, per-doc evaluation, final
audit) and `implementer` (per-doc editing). Standard retry rules apply (same subagent,
3 attempts, backoff — never substitute).

## Workflow

### Phase 6.0: Preconditions
Identify the shipped feature (explicit goal name, or the newest completed
`_goals/<goal>/goal.md`). Confirm the implementation actually landed (`git` shows the
code changes). If nothing shipped, stop and say so.

### Phase 6.1: Discover the change surface (READ-ONLY)
Read the goal + task files (read-only) and the diff
(`git diff --stat <base>...HEAD`, then targeted per-file diffs). Distill a **"what
shipped"** fact list — new/changed routes, modules, CLIs, config keys, UI surfaces,
auth behavior, renames, removals — each fact with its source file.

### Phase 6.2: Map changes to affected docs
Using the surface map above, (1) **grep every in-scope doc** for each shipped fact's
identifiers — old and new names, flags, paths, and stale markers ("TODO", "planned",
"not yet"); (2) build the **per-doc edit list** from ONLY docs with at least one hit.
A doc with zero hits is out of the edit list — it is not evaluated and not reported as
"already accurate". Confirm `_research/` and `_goals/` are excluded.

### Phase 6.3: Evaluate the edit plan (`evaluator`)
**Small-change fold.** When the edit list has ≤ 3 docs, skip 6.3 as a separate spawn:
execute 6.4 directly and have the 6.5 final audit ALSO verify the edit-list criteria
(coverage, scope, anti-invention) in the same spawn. Log 'Phase 6.3 folded into 6.5
(edit list ≤ 3)'. With > 3 docs, 6.3 runs as today.

Criteria: coverage (every stale doc caught?), scope (zero excluded-path or code edits
planned?), anti-invention (every planned edit cites its source file?). Mandatory
re-evaluate loop: PASS → 6.4; NEEDS REVISION → revise + re-evaluate (3 max); REJECT →
escalate.

### Phase 6.4: Execute per doc (`implementer` + `evaluator`)
Docs are independent — executors may run in parallel. Context package per doc: its
edit-list entry, the relevant shipped facts, exact files to READ FIRST, and the full
guardrails. Evaluate each result: accuracy, completeness, scope (only this doc changed),
preserved prose intact, links resolve. Re-evaluate loop, 3 cycles max per doc.

### Phase 6.5: Final audit (`evaluator`)
The whole change set: every affected doc accurate and **mutually consistent**; no
stale claims remain; `git status` shows **only** documentation files changed. When the
small-change fold applied, this audit also verifies the 6.3 edit-list criteria (coverage,
scope, anti-invention).
APPROVED → lint markdown if a linter is configured, report which docs changed; ISSUES →
remediate + re-audit (3 max).

## Escalation

Escalate when: an evaluator fails to PASS/APPROVED after 3 cycles; any REJECT; no shipped
feature found; or a guardrail conflict (the only accurate fix would require a code
change — which this skill must not make).
