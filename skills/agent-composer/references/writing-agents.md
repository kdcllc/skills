# Writing agent roles and crew boundaries

This guide defines how to write `instructions`, `description`, `inputs`, `outputs`, `tools`, and `tier` fields in the crew spec. Generated agent files embed `instructions` verbatim; the orchestrator skill schedules steps and reads workdir handoffs per [spec-schema.md](spec-schema.md).

## Role-prompt structure

Every agent’s `instructions` should read as a standalone subagent brief. Include these sections in prose or headings:

1. **Role** — What this agent is responsible for in one sentence; how it fits the crew.
2. **Inputs it reads** — Match spec `inputs` (workdir-relative filenames). Say where to find them (`<workdir>/<run-id>/`).
3. **Outputs it writes** — Match spec `outputs` only when `edit` is in `tools` (**S039**). Agents without `edit` (evaluators, routers, read-only reviewers) declare **no** `outputs`; their findings and protocols live in the orchestrator-saved `<step-id>.report.md` (see **File handoffs**).
4. **Steps** — Ordered actions the agent performs; keep them checkable.
5. **Stop conditions** — When to finish with `STATUS: done` vs `STATUS: blocked — <reason>`.
6. **Must never do** — Scope limits (tools not granted, no spawning subagents, evaluators never fix).
7. **Report format** — End every run with `STATUS: done` or `STATUS: blocked — <reason>`; list workdir files written (empty when `outputs` is `[]`). Routers add `ROUTE:`; evaluators add `VERDICT:` (see **Runtime protocol** in spec-schema.md).

Align `inputs` / `outputs` in the spec with what the prompt names so the validator and orchestrator stay consistent.

## Evaluators stay independent

Agents with `kind: evaluator`:

- **Never fix** upstream work — no `edit` in `tools` (**S024**); prefer `read` and `search` only.
- Return **PASS or FAIL** with findings: exactly one line `VERDICT: PASS` or `VERDICT: FAIL`, then bullets on FAIL.
- Use **read-only** tools in practice; `shell` is discouraged (**S025**).
- Tie the evaluator step to `gate.on_fail` and `gate.max_cycles` on the same step.

The orchestrator applies FAIL by re-running upstream producers, not by asking the evaluator to patch files.

Evaluators (and any agent without `edit`) must **not** list `outputs` in the spec (**S039**). Put PASS/FAIL findings, checklist results, and evidence in the agent report; the orchestrator persists it as `<workdir>/<run-id>/<step-id>.report.md` and later steps (or the orchestrator on re-run) read that file — not a separate artifact the evaluator wrote with `edit`.

## File handoffs through the workdir

- Default run root: `<workdir>/<run-id>/` from the spec (`workdir` defaults to `_crew/<name>`).
- Declare every cross-agent artifact in `inputs` and `outputs` (outputs only when the agent has `edit`). Agents read and write **only** declared paths under the run folder unless the orchestrator passes extra context in the spawn prompt.
- Agents without `edit` hand off through **reports**: the orchestrator saves each step’s final report to `<workdir>/<run-id>/<step-id>.report.md` (or `<step-id>.<agent-id>.report.md` for `parallel` members). Downstream steps read prior artifacts from `inputs` and may receive report excerpts in the spawn prompt; evaluators never write a parallel “findings file” in the workdir.
- Use stable filenames across steps (`notes.md`, `draft.md`) so gates and parallel merges stay predictable.
- The orchestrator creates the run folder; agents must not assume paths outside the declared lists.
- Agent ids and step ids are **separate namespaces** (**S008** applies within each list only). A step may reuse its agent’s id (for example step `triage` with `agent: triage`) when that keeps the graph readable.

## Inline or subagent

Set `run: inline` when the role needs no tools, model tier or isolation of its own and only brings knowledge: a style guide, a glossary, a domain checklist. The orchestrator reads its role file and performs the step in the main session, so the agent costs no extra context window and no agent file. An inline role uses `tier: inherit` and is not scheduled in `parallel` or `dispatch`.

Keep a role a subagent when it is:

- an evaluator, router or planner;
- in need of its own model tier or isolation (a separate context, restricted tools);
- scheduled in a `parallel` step or as a `dispatch` worker;
- a gated producer whose re-runs should not see its earlier attempts or the evaluator's findings (an inline step shares the orchestrator's context).

## Choosing tiers

| Tier | Use for |
| --- | --- |
| `frontier` | Judging quality, planning decomposition, ambiguous tradeoffs, security-sensitive review. |
| `light` | Routine professional work — drafting, summarizing, standard code changes. |
| `fast` | Mechanical transforms, formatting, simple lookups, high-volume worker items. |
| `inherit` | Default when unsure; harness uses session default. |

When any agent uses a non-`inherit` tier, the spec’s `models` map must list that tier for each harness (**S027**). Verify live model IDs at generation time; do not hard-code IDs in reference docs — record optional `verified` on the harness map.

## Writing `description` fields

Crew and agent `description` strings (1–1024 characters) must state **what** the role or crew does and **when** to use it — same spirit as Agent Skills spec descriptions. The orchestrator skill and harness agent pickers surface these strings; avoid internal jargon and placeholder TODOs.

## Worked role prompt: coding implementer

Spec fragment:

```yaml
  - id: implementer
    description: "Implements one task from tasks.yaml in the run workdir; edits only allowed paths."
    kind: worker
    tier: light
    tools: [read, search, edit, shell]
    inputs: [task-brief.md, context-package.md]
    outputs: [implementation-report.md, changed-files.txt]
    instructions: |
      You are the coding implementer for this crew run.

      Read `<workdir>/<run-id>/task-brief.md` and `context-package.md`. Implement exactly the scoped task; do not expand scope.

      Steps:
      1. Confirm inputs exist; if missing, end with STATUS: blocked — missing inputs.
      2. Edit only files allowed in the brief; run targeted tests named in the brief.
      3. Write `implementation-report.md` (summary, commands run, results) and `changed-files.txt` (one repo-relative path per line).

      Never spawn subagents, never commit unless the brief requires it, never touch secrets.

      End with STATUS: done and list output files.
```

## Worked role prompt: non-coding researcher

Spec fragment:

```yaml
  - id: researcher
    description: "Collects cited notes on an assigned topic into the run workdir."
    kind: worker
    tier: light
    tools: [read, search, web, edit]
    inputs: [topic.md]
    outputs: [notes.md]
    instructions: |
      You are the research agent for this content crew.

      Read `<workdir>/<run-id>/topic.md` for the question, scope, and any source constraints.

      Steps:
      1. If `topic.md` is missing or empty, end with STATUS: blocked — missing or empty topic brief.
      2. Gather facts from allowed sources; prefer primary references.
      3. Write `notes.md` with sections: Summary, Key claims, Sources (title, URL, date accessed).
      4. Flag gaps or conflicts in a final **Open questions** section.

      Do not draft final prose for publication; do not edit files outside `notes.md`.

      End with STATUS: done and list notes.md.
```

## Worked role prompt: domain-specific reviewer

Spec fragment (compliance-style reviewer; adjust domain in `description`):

```yaml
  - id: compliance-reviewer
    description: "Reviews draft.md against policy checklist; PASS/FAIL only, no edits."
    kind: evaluator
    tier: frontier
    tools: [read, search]
    inputs: [draft.md, policy-checklist.md, notes.md]
    instructions: |
      You are the domain compliance reviewer. You judge; you do not rewrite draft.md.

      Read `<workdir>/<run-id>/draft.md`, `policy-checklist.md`, and supporting `notes.md`.

      Steps:
      1. If any required input file is missing, end with STATUS: blocked — missing inputs (name the files).
      2. For each checklist item, record met / not met with evidence citations in your report (structured bullets).
      3. Print exactly one line: VERDICT: PASS or VERDICT: FAIL.
      4. On FAIL, after the verdict line, list blocking findings only.

      Never use edit or shell; never fix wording in the draft. Do not declare workdir output files — the orchestrator saves this report as `<step-id>.report.md`.

      End with STATUS: done (no workdir files written).
```

Pair this agent with a gated step (`gate.on_fail` pointing at the draft step) when the crew pattern is `evaluator-optimizer`.

## Crew boundaries (coding, general, domain)

| Crew type | Boundaries |
| --- | --- |
| **Coding** | Workers may use `edit` and `shell`; keep tasks file-scoped; evaluators read artifacts and logs, no direct fixes. Prefer `evaluator-optimizer` or `orchestrator-workers` for multi-file efforts. |
| **General (non-coding)** | Favor `read`, `search`, `web`; outputs are Markdown or structured text in the workdir; routers for intake, fan-out for multi-source research. |
| **Domain-specific** | Encode policy in workdir inputs (`policy-checklist.md`, rubrics); frontier tier on evaluators; workers stay inside domain tools listed in the spec. |

When interview answers imply a single session skill can cover the work, say so — see [patterns.md](patterns.md) (**Do you need a crew at all?**).
