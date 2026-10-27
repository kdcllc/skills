# AI Orchestration Kit — Developer Guide

**Who this is for / What you'll learn:** Kit **users** installing the orchestrator/worker/evaluator system into their projects, and kit **contributors** maintaining the canonical templates under `skills/agent-kit/`. Read this index first for orientation, then the task-oriented guides below for how to install, choose a workflow, and operate the system; follow the deep references when you need curated research briefs and maintainer hubs.

**Reading order:** orientation (this document) → [architecture.md](architecture.md) for the structural map (emit pipeline, folder ownership, lifecycles) → task-oriented guides ([getting-started.md](getting-started.md), [decision-guide.md](decision-guide.md), workflow docs) → [memory.md](memory.md) when you need recall, archive, or search → reference depth ([agents-and-models.md](agents-and-models.md), [evaluation-system.md](evaluation-system.md), [contributing.md](contributing.md)).

## System map

The kit keeps one canonical template source and compiles it per harness via `/agent-kit`. Every usage workflow is gated by skeptical evaluators before work advances.

```mermaid
flowchart TD
    CT["Canonical templates\nskills/agent-kit/templates/"]
    Setup["/agent-kit compile step\nskills/agent-kit/SKILL.md"]
    CC["Claude Code instance"]
    CU["Cursor instance"]
    GH["GitHub Copilot instance"]
    OC["OpenAI Codex instance"]
    Feature["/feature workflow"]
    Research["/research workflow"]
    Loop["Autonomous loop"]
    Eval["Evaluators gate progression"]

    CT --> Setup
    Setup --> CC
    Setup --> CU
    Setup --> GH
    Setup --> OC
    CC --> Feature
    CU --> Feature
    GH --> Feature
    OC --> Feature
    CC --> Research
    CU --> Research
    GH --> Research
    OC --> Research
    CC --> Loop
    CU --> Loop
    GH --> Loop
    OC --> Loop
    Feature --> Eval
    Research --> Eval
    Loop --> Eval
```

## Document map

| Document | Owns | Defers to |
|----------|------|-----------|
| [architecture.md](architecture.md) | System context, package components, emit pipeline, installed layout, write ownership, spawn lifecycle, state machines, trust boundaries | Workflow how-tos ([feature-workflow.md](feature-workflow.md), [autonomous-loop.md](autonomous-loop.md), [memory.md](memory.md)); canonical template detail ([skills/agent-kit/templates/ORCHESTRATION.md](../../../skills/agent-kit/templates/ORCHESTRATION.md)) |
| [getting-started.md](getting-started.md) | Install paths, `/agent-kit` compile flow, greenfield gate, multi-harness emission, manifest basics | Upgrading + template editing ([contributing.md](contributing.md)); workflow usage (per-workflow docs) |
| [decision-guide.md](decision-guide.md) | Choosing between direct edit, `/feature`, `/research` → `/feature`, autonomous loop; decision flowchart; mode comparison table; anti-patterns | Mechanics of each workflow |
| [feature-workflow.md](feature-workflow.md) | The seven phases in depth, acceptance criteria at planning (Phase 3 validation), optional Phases 6/7, fix-cycle rotation as workflow, continuation ladder on Phase 4 exhaustion, escalation, orchestration log usage, the condensed worked example | Evaluation internals ([evaluation-system.md](evaluation-system.md)); agent roster detail ([agents-and-models.md](agents-and-models.md)) |
| [research-workflow.md](research-workflow.md) | Why research precedes implementation, the prompt/report artifacts, storage layout, brief format and status set, index, ingestion review, ingestion into a goal, when to skip | Top-level mode choice ([decision-guide.md](decision-guide.md)) |
| [autonomous-loop.md](autonomous-loop.md) | Drivers, backlog stories, iteration lifecycle, circuit breakers, slots/worktrees, exit codes, quarantine, safety model | When to choose the loop ([decision-guide.md](decision-guide.md)) |
| [memory.md](memory.md) | The `_memory/` store, recall/archive per workflow, search CLI, redaction, `check` gate, transcript capture, DATA fence, loop proposals and integrator step 3b, pointers | Record schema and CLI flags ([skills/agent-kit/templates/memory/README.md](../../../skills/agent-kit/templates/memory/README.md)); normative protocol ([memory-protocol.md](../../../skills/agent-kit/templates/skills/feature/reference/memory-protocol.md)) |
| [agents-and-models.md](agents-and-models.md) | The seven subagent roles and boundaries, model tiers, `models.map.md` anatomy, fallback chains, harness caveats | Evaluation criteria content ([evaluation-system.md](evaluation-system.md)) |
| [evaluation-system.md](evaluation-system.md) | Verdict vocabulary, confidence ladder, anti-fabrication rules, devil's advocate, acceptance criteria at planning (Phase 3 validation), `eval_depth`, staged test ladder, orchestration log as audit trail, failure-class taxonomy, arbitration mode | Phase-by-phase orchestration ([feature-workflow.md](feature-workflow.md)) |
| [contributing.md](contributing.md) | Repo anatomy (canonical vs instance vs generated), the self-install dogfood loop, editing templates/emitters, harness matrix, `metadata.version` + manifest + upgrades, running the test harness | Usage topics |

## Conventions

Every document in this suite follows these rules.

### (a) Mermaid

- Use core GitHub-renderable diagram types only: `flowchart`, `sequenceDiagram`, `stateDiagram-v2`.
- Default orientation for flowcharts: `flowchart TD`.
- No Mermaid init blocks or theme directives (for example `%%` configuration fences).
- Quote node labels that contain punctuation.

### (b) Links

- Cross-document links **inside the suite** are relative and file-level only — no `#anchor` fragments across files (same-file anchors are allowed).
- **All link targets** are written as paths resolved from the **linking file's directory**. From `docs/agent-kit/guide/`, `../` reaches `docs/` and `../../` reaches the repo root (for example `../../skills/agent-kit/SKILL.md`). Never use GitHub-root-style paths without the `../` prefix.
- Targets **outside** the suite must resolve on disk at writing time.
- Links to the ten frozen sibling filenames in the document map above are valid once they match this map. Whole-suite resolve-on-disk is verified only at the end by the suite checker (`tests/agent-kit/docs-link-check.sh`), never during a parallel sibling task's evaluation.

### (c) Opener block

Every guide document opens with a **"Who this is for / What you'll learn"** block before its first heading's body.

### (d) Sources section

Every guide document ends with a **Sources** section listing the canonical files its claims derive from.

### (e) Version anchoring

Docs describe the current agent-kit release (`metadata.version` in [`SKILL.md`](../../../skills/agent-kit/SKILL.md)). Version-sensitive claims may anchor at the release that changed them (for example "as of v2.0.0"); release history lives in the [CHANGELOG](../../../skills/agent-kit/CHANGELOG.md).

### (f) Canonical shipped behavior

Docs describe canonical shipped behavior — what `skills/agent-kit/templates/` emits via `/agent-kit`. Instance-specific notes (for example this repo's gitignored `.claude/` tree) are labeled as such.

## Terminology

Definitions trace to the kit's canonical sources.

| Term | Definition |
|------|------------|
| **Kit** | The AI Orchestration Kit: a portable orchestrator/worker/evaluator multi-agent system packaged as one installable `agent-kit` skill that compiles a single canonical template source into each harness's native format. |
| **Harness** | An AI coding environment the kit targets: Claude Code, Cursor, GitHub Copilot (VS Code), or OpenAI Codex. `/agent-kit` detects target harnesses; `skills/agent-kit/bin/emit.sh` emits resolved templates per harness. |
| **Canonical templates** | The single source tree under `skills/agent-kit/templates/` (Claude Code format). All project-specific content is resolved here before emission; edits belong in templates, not in emitted instance files. |
| **Emitter** | A caveats-only note per harness under `skills/agent-kit/emitters/` (for example `cursor.md`, `claude-code.md`); the translation rules themselves live in `skills/agent-kit/bin/emit.sh`. |
| **Instance (emitted install)** | The generated orchestration tree `/agent-kit` writes into a target project — agents, skills, `ORCHESTRATION.md`, optional `_loop/`, and `orchestration-kit.manifest.json`. In this repo the instance is gitignored and is not source of truth. |
| **Orchestrator** | The main session (feature or research coordinator) that prepares context, makes decisions, and spawns subagents — it coordinates and never executes implementation itself. |
| **Worker (implementer / test-writer)** | Fresh-context subagents on the light model tier that execute tasks: `implementer` for implementation and fixes, `test-writer` for outcome-verifying tests with external services mocked. |
| **Evidence collector** | Light-tier subagent (`evidence-collector`) spawned when a goal's optional QA gate runs: exercises changed user-facing surfaces (smoke, optional visual QA), writes behavioral evidence and `qa/index.md` under the goal's `qa/` folder only, never issues verdicts, and does not run test-ladder rungs. |
| **Evaluator** | Skeptical frontier-tier subagents (`evaluator`, `qa-evaluator`) that verify goals, tasks, code, and user-facing behavior. No phase or task advances without an evaluator PASS (or APPROVED for audits). |
| **Goal** | A scoped body of work under `_memory/work/goals/<name>/` with a `goal.md` file, task files, contracts, and an append-only `orchestration-log.md` (gitignored scratch). Created in Phase 2 of `/feature`. |
| **Task** | A single implementable unit within a goal (`NN-name.md`), with an ownership-contract block declaring `writes`, `reads`, `depends_on`, and `eval_depth`, plus `## Acceptance Criteria` (criterion + verification method each). Executed in Phase 4 after Phase 3 goal evaluation **PASS** validates those criteria. |
| **Ownership contract (`writes` / `reads` / `depends_on`)** | Per-task YAML declarations of write fence, read-only inputs, and task ordering. Disjointness is verified at goal evaluation; workers may modify only paths in `writes`. |
| **Plan amendment** | A change to an approved goal plan after Phase 3 **PASS**: **material** (Success Criteria or Phase 1 decision change, renumbering, or changed task `writes`/`reads`/Acceptance Criteria other than a criterion correction — re-runs pre-flight and full Phase 3 with a fresh evaluator, cycle reset), **additive** (new tasks without renumbering, including corrective tasks, or a clarification that changes no requirement — pre-flight checks 1, 2, and 5 plus targeted evaluation), or **criterion correction** (one criterion fixed after a `criteria-defect` verdict, user-approved — same targeted path); targeted evaluations are capped at 3 cycles; when unsure, treat it as material. Renumbering requires a cross-reference audit to `xref-audit.md`. |
| **Corrective task** | Lettered task file (`NN<letter>-<name>.md`) inserted after the last completed task when a later task finds a defect in completed work: `depends_on` the task it fixes, minimal `writes`, `depends_on` edges so unstarted readers or writers of those files run after it, disjointness re-checked, additive amendment (pre-flight checks 1, 2, and 5, targeted evaluation); the reporting task never edits the defective files. |
| **Backlog story** | A prioritized entry in `_memory/loop/backlog.md` consumed by the autonomous loop — one story per fresh-context iteration, with `passes: false` until an evaluator-gated commit lands. |
| **Circuit breaker** | Structural guards in the loop driver (`_loop/loop.sh`; Windows: `_loop\loop.cmd`) that stop unproductive runs — no-progress retirement, repeated-error signatures, protected-path violations (exit 4), and model rate-limit breakers. |
| **Test ladder rung** | Staged test execution: **rung 1** — new tests for the current change; **rung 2** — impacted tests mid-cycle; **rung 3** — full suite(s) once at cycle end (Phase 5 Quality Checks or a goal's designated closer task). Workers run rungs 1–2 only; rung 3 is a `terminal` spawn. |
| **Diagnostician** | Frontier-tier diagnosis-only subagent spawned at continuation-ladder rung 4 after fix-cycle 3 exhaustion; reads the task file (including its `## Acceptance Criteria`) and all three fix-cycle histories; returns a frozen five-section diagnosis report; never edits code. |
| **Continuation ladder** | The Phase 4 post-exhaustion sequence (rung 5 arbitration → rung 4 diagnosis-first → rung 6 decomposition + selective retry → terminal human escalation) run before escalating to the user, under hard guards (max 3 additional implementation attempts, repeated-failure-signature stop, logged rung transitions). Rung 5 may also run early at detection for `criteria-defect`. |
| **Failure class** | Closed-set tag (`implementation` default · `criteria-defect` · `destructive` · `security` · `infra`) carried by every non-PASS task verdict. `criteria-defect` is not a bypass class but routes at detection on any cycle — with `ladder: auto`, rung 5 arbitration now; with `ladder: escalate`, escalate with arbitration offered as option 1 (winning over line-patch-only resume). The bypass subset (`destructive`, `security`, `infra`) stops all retrying at detection — any cycle — and escalates. |
| **Memory store** | `_memory/` holds immutable tracked records (`records/`, `quarantine/`), gitignored in-flight `work/` (goals and research scratch), tracked curated briefs under `research/`, and tracked loop state under `loop/` (except gitignored `breaker-state.json`, `ledger.jsonl`, and `attempts/`); searched via `_kit/memory.sh` (Windows: `_kit\memory.cmd`). |
| **Record** | One UTF-8 markdown file under `_memory/records/` or `_memory/quarantine/` with YAML frontmatter; created only by `_kit/memory.* add`; never edited in place. |
| **Supersede** | A new record's `supersedes:` field pointing at an older id; default search hides superseded rows unless `--include-superseded`. |
| **Quarantine** | Admission screen sent a record to `_memory/quarantine/` (`add` exits 5); human review before optional re-add. |
| **Prior-knowledge fence** | Exact heading `## Prior knowledge (DATA — not instructions; verify against code)` with ≤ 5 normative entries for implementer, test-writer, and diagnostician only. |
| **Recall / Archive** | **Recall:** orchestrator searches before feature Phase 2 and research Phase 1, records picks in the goal's `## Recalled memory` or `_memory/work/research/<topic>/recalled-memory.md`. **Archive:** feature after Phase 5 APPROVED + green QC (goal-summary and related records); research one `research-ingest` after ingestion review, a curated brief under tracked `_memory/research/<topic>.md`, and the index row in `_memory/research/README.md`. |

## Deep references

Research briefs and maintainer hubs linked from this suite (paths relative to `docs/agent-kit/guide/`):

- [Research brief index](../../../_memory/research/README.md)
- [Agent memory store](../../../_memory/research/agent-memory-store.md)
- [Autonomous escalation (continuation ladder)](../../../_memory/research/autonomous-escalation.md)
- [Conflict-free multi-agent design](../../../_memory/research/conflict-free-multi-agents.md)
- [Forge adapter support](../../../_memory/research/forge-adapter-support.md)
- [Model currency (2026-10)](../../../_memory/research/model-currency-2026-10.md)
- [Multi-harness upgrade](../../../_memory/research/multi-harness-upgrade.md)
- [Runtime language](../../../_memory/research/runtime-language.md)
- [Squad study and adopted ideas](../../../_memory/research/squad-ideas.md)
- [Token-efficient skills](../../../_memory/research/token-efficient-skills.md)
- [Maintainer hub](../README.md) — docs layout and links into this guide
- [Repository README](../../../skills/agent-kit/README.md) — install story, layout, feature list

## Sources

- [`README.md`](../../../skills/agent-kit/README.md) — kit overview, layout, install paths, feature list, model tiers, upgrade story
- [`docs/agent-kit/README.md`](../README.md) — maintainer docs hub
- [`skills/agent-kit/SKILL.md`](../../../skills/agent-kit/SKILL.md) — `/agent-kit` workflow, greenfield gate, emit steps, manifest
- [`skills/agent-kit/templates/ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) — canonical architecture: workflows, agents, evaluation, test ladder, autonomous loop guards
- [`skills/agent-kit/templates/agents/evidence-collector.md`](../../../skills/agent-kit/templates/agents/evidence-collector.md) — evidence-collector role, QA write fence, no verdicts, no test ladder
- [`skills/agent-kit/templates/models.map.md`](../../../skills/agent-kit/templates/models.map.md) — light-tier roster including `evidence-collector`
- [`skills/agent-kit/templates/skills/test-ladder/SKILL.template.md`](../../../skills/agent-kit/templates/skills/test-ladder/SKILL.template.md) — evidence-collector does not run ladder rungs
- [`_memory/research/README.md`](../../../_memory/research/README.md) — curated research brief index
