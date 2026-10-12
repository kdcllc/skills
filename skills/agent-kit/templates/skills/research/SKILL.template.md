---
name: research
description: Research → Plan workflow for {{PROJECT_NAME}} topics needing external investigation — produces a research prompt, ingests the report, and yields an evaluated goal/task structure.
---

# Research (Deep Research → Plan Orchestrator)

For domain topics an external research agent must investigate **without codebase
access**. You coordinate four phases; the output feeds `feature` Phase 4.

## Phase 1 — Generate the research prompt

**Recall:** search `--kind research-ingest,decision` (≤ 5) per
`{{IDE_DIR}}/skills/feature/reference/memory-protocol.md`; write ids or `none` to
`_research/<topic>/recalled-memory.md` (avoid re-researching settled questions).

Write `_research/prompts/[topic].md` from `templates/research-prompt.md`. The prompt must
be self-contained (the researcher cannot see this repo): include the relevant facts from
{{GROUND_TRUTH_DOC}} and the domain skill, the exact questions to answer, and the
required report structure. The user copy-pastes it to their external research tool.

## Phase 2 — Ingest the report

Save the returned report as `_research/[topic]/report.md` (structure per
`templates/research-report.md`). Read it critically: flag claims that contradict
{{GROUND_TRUTH_DOC}} or the codebase, and list open questions back to the user.
Promote durable findings into {{GROUND_TRUTH_DOC}}; `_research/` stays scratch.

**Archive:** one `research-ingest` after ingestion review per
`{{IDE_DIR}}/skills/feature/reference/memory-protocol.md`.

## Phase 3 — High-level plan

Collaborative planning with the user (use Plan Mode if available): approach options with
tradeoffs, chosen direction, affected layers ({{EXECUTION_LAYERS}}).

## Phase 4 — Low-level tasks

Create `_goals/[goal-name]/` using the `feature` skill's `goal.md`/`task.md`
templates; copy Phase 1 picks (or `none`) from `recalled-memory.md` into the goal's
`## Recalled memory` and log the note per
`{{IDE_DIR}}/skills/feature/reference/memory-protocol.md`. Hand off: the goal enters
`feature` at Phase 3 (goal evaluation) — it still must PASS the evaluator before execution.
