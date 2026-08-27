# AI Orchestration Kit — Developer Guide

**Who this is for / What you'll learn:** Kit **users** installing the orchestrator/worker/evaluator system into their projects, and kit **contributors** maintaining the canonical templates under `skills/setup/`. Read this index first for orientation, then the task-oriented guides below for how to install, choose a workflow, and operate the system; follow the deep references when you need research-level detail on harness design, evaluation hardening, or parallel dispatch.

**Reading order:** orientation (this document) → task-oriented guides ([getting-started.md](getting-started.md), [decision-guide.md](decision-guide.md), workflow docs) → reference depth ([agents-and-models.md](agents-and-models.md), [evaluation-system.md](evaluation-system.md), [contributing.md](contributing.md)).

## System map

The kit keeps one canonical template source and compiles it per harness via `/setup`. Every usage workflow is gated by skeptical evaluators before work advances.

```mermaid
flowchart TD
    CT["Canonical templates\nskills/setup/templates/"]
    Setup["/setup compile step\nskills/setup/SKILL.md"]
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
| [getting-started.md](getting-started.md) | Install paths, `/setup` compile flow, greenfield gate, multi-harness emission, manifest basics | Upgrading + template editing ([contributing.md](contributing.md)); workflow usage (per-workflow docs) |
| [decision-guide.md](decision-guide.md) | Choosing between direct edit, `/feature`, `/research` → `/feature`, autonomous loop; decision flowchart; mode comparison table; anti-patterns | Mechanics of each workflow |
| [feature-workflow.md](feature-workflow.md) | The seven phases in depth, acceptance criteria at planning (Phase 3 validation), optional Phases 6/7, fix-cycle rotation as workflow, continuation ladder on Phase 4 exhaustion, escalation, orchestration log usage, the condensed worked example | Evaluation internals ([evaluation-system.md](evaluation-system.md)); agent roster detail ([agents-and-models.md](agents-and-models.md)) |
| [research-workflow.md](research-workflow.md) | Why research precedes implementation, the prompt/report artifacts, ingestion into a goal, when to skip | Top-level mode choice ([decision-guide.md](decision-guide.md)) |
| [autonomous-loop.md](autonomous-loop.md) | Drivers, backlog stories, iteration lifecycle, circuit breakers, slots/worktrees, exit codes, quarantine, safety model | When to choose the loop ([decision-guide.md](decision-guide.md)) |
| [agents-and-models.md](agents-and-models.md) | The six subagent roles and boundaries, model tiers, `models.map.md` anatomy, fallback chains, harness caveats | Evaluation criteria content ([evaluation-system.md](evaluation-system.md)) |
| [evaluation-system.md](evaluation-system.md) | Verdict vocabulary, confidence ladder, anti-fabrication rules, devil's advocate, acceptance criteria at planning (Phase 3 validation), `eval_depth`, staged test ladder, orchestration log as audit trail, failure-class taxonomy, arbitration mode | Phase-by-phase orchestration ([feature-workflow.md](feature-workflow.md)) |
| [contributing.md](contributing.md) | Repo anatomy (canonical vs instance vs generated), the self-install dogfood loop, editing templates/emitters, harness matrix, VERSION + manifest + upgrades, running the test harness | Usage topics |

## Conventions

Every document in this suite follows these rules. As of v0.20.0, they apply to all new and revised guide content.

### (a) Mermaid

- Use core GitHub-renderable diagram types only: `flowchart`, `sequenceDiagram`, `stateDiagram-v2`.
- Default orientation for flowcharts: `flowchart TD`.
- No Mermaid init blocks or theme directives (for example `%%` configuration fences).
- Quote node labels that contain punctuation.

### (b) Links

- Cross-document links **inside the suite** are relative and file-level only — no `#anchor` fragments across files (same-file anchors are allowed).
- **All link targets** are written as paths resolved from the **linking file's directory**. From `docs/guide/`, `../` reaches `docs/` and `../../` reaches the repo root (for example `../../skills/setup/SKILL.md`). Never use GitHub-root-style paths without the `../` prefix.
- Targets **outside** the suite must resolve on disk at writing time.
- Links to the eight frozen sibling filenames in the document map above are valid once they match this map. Whole-suite resolve-on-disk is verified only at the end by the suite checker (`tests/docs-link-check.sh`), never during a parallel sibling task's evaluation.

### (c) Opener block

Every guide document opens with a **"Who this is for / What you'll learn"** block before its first heading's body.

### (d) Sources section

Every guide document ends with a **Sources** section listing the canonical files its claims derive from.

### (e) Version anchoring

Version-sensitive claims are anchored at the kit version where the behavior shipped (for example **"as of v0.19.0"** or **"as of v0.20.0"**).

### (f) Canonical shipped behavior

Docs describe canonical shipped behavior — what `skills/setup/templates/` emits via `/setup`. Instance-specific notes (for example this repo's gitignored `.claude/` tree) are labeled as such.

## Terminology

Definitions trace to the kit's canonical sources. Version references use v0.20.0 where behavior changed recently.

| Term | Definition |
|------|------------|
| **Kit** | The AI Orchestration Kit: a portable orchestrator/worker/evaluator multi-agent system packaged as one installable `setup` skill that compiles a single canonical template source into each harness's native format. |
| **Harness** | An AI coding environment the kit targets: Claude Code, Cursor, GitHub Copilot (VS Code), or OpenAI Codex. `/setup` detects and emits per harness via emitters. |
| **Canonical templates** | The single source tree under `skills/setup/templates/` (Claude Code format). All project-specific content is resolved here before emission; edits belong in templates, not in emitted instance files. |
| **Emitter** | A per-harness compile instruction file under `skills/setup/emitters/` (for example `cursor.md`, `claude-code.md`) that maps resolved templates into that harness's native layout. |
| **Instance (emitted install)** | The generated orchestration tree `/setup` writes into a target project — agents, skills, `ORCHESTRATION.md`, optional `_loop/`, and `orchestration-kit.manifest.json`. In this repo the instance is gitignored and is not source of truth. |
| **Orchestrator** | The main session (feature or research coordinator) that prepares context, makes decisions, and spawns subagents — it coordinates and never executes implementation itself. |
| **Worker (implementer / test-writer)** | Fresh-context subagents on the light model tier that execute tasks: `implementer` for implementation and fixes, `test-writer` for outcome-verifying tests with external services mocked. |
| **Evaluator** | Skeptical frontier-tier subagents (`evaluator`, `qa-evaluator`) that verify goals, tasks, code, and user-facing behavior. No phase or task advances without an evaluator PASS (or APPROVED for audits). |
| **Goal** | A scoped body of work under `_goals/<name>/` with a `goal.md` file, task files, contracts, and an append-only `orchestration-log.md`. Created in Phase 2 of `/feature`. |
| **Task** | A single implementable unit within a goal (`NN-name.md`), with an ownership-contract block declaring `writes`, `reads`, `depends_on`, and `eval_depth`, plus `## Acceptance Criteria` (criterion + verification method each). Executed in Phase 4 after Phase 3 goal evaluation **PASS** validates those criteria. |
| **Ownership contract (`writes` / `reads` / `depends_on`)** | Per-task YAML declarations of write fence, read-only inputs, and task ordering. Disjointness is verified at goal evaluation; workers may modify only paths in `writes`. |
| **Pre-code contract (removed v0.23.0)** | Historical only — v0.18.0–v0.22.0 per-task `contracts/NN-name.contract.md` with two-party worker/evaluator sign-off before dispatch. v0.23.0 folded acceptance criteria into task files at Phase 2; Phase 3 validates them once; no separate sign-off gate. |
| **Backlog story** | A prioritized entry in `_goals/backlog.md` consumed by the autonomous loop — one story per fresh-context iteration, with `passes: false` until an evaluator-gated commit lands. |
| **Circuit breaker** | Structural guards in the loop drivers (`_loop/loop.sh` / `_loop/loop.ps1`) that stop unproductive runs — no-progress retirement, repeated-error signatures, protected-path violations (exit 4), and model rate-limit breakers. |
| **Test ladder rung** | Staged test execution: **rung 1** — new tests for the current change; **rung 2** — impacted tests mid-cycle; **rung 3** — full suite(s) once at cycle end (Phase 5 Quality Checks or a goal's designated closer task). Workers run rungs 1–2 only; rung 3 is a `terminal` spawn. |
| **Diagnostician** | Frontier-tier diagnosis-only subagent spawned at continuation-ladder rung 4 after fix-cycle 3 exhaustion; reads the task file (including its `## Acceptance Criteria`) and all three fix-cycle histories; returns a frozen five-section diagnosis report; never edits code. |
| **Continuation ladder** | The Phase 4 post-exhaustion sequence (rung 5 arbitration → rung 4 diagnosis-first → rung 6 decomposition + selective retry → terminal human escalation) run before escalating to the user, under hard guards (max 3 additional implementation attempts, repeated-failure-signature stop, logged rung transitions). |
| **Failure class** | Closed-set tag (`implementation` default · `criteria-defect` · `destructive` · `security` · `infra`) carried by every non-PASS task verdict; the bypass subset (destructive, security, infra) stops all retrying at detection — any cycle — and escalates. |

## Deep references

Research and design documents linked from this suite (paths relative to `docs/guide/`):

- [Multi-harness upgrade research](../research-multi-harness-upgrade.md)
- [Squad study and adopted ideas](../research-squad-ideas.md)
- [Harness design upgrade (evaluator vocabulary + contracts)](../research-harness-design-upgrade.md)
- [Token-efficient skills](../research-token-efficient-skills.md)
- [Conflict-free multi-agent design](../research-designing-conflict-free-multi-agents.md)
- [Parallel dispatch design](../design-parallel-dispatch.md)
- [Autonomous escalation research (continuation ladder)](../research-autonomous-escalation.md)
- [Repository README](../../README.md) — install story, layout, feature list
- [Orchestration architecture pointer](../../ORCHESTRATION.md) — summary with link to the canonical template

## Sources

- [`README.md`](../../README.md) — kit overview, layout, install paths, feature list, model tiers, upgrade story
- [`ORCHESTRATION.md`](../../ORCHESTRATION.md) — v0.18.0–v0.21.0 capability summary
- [`skills/setup/SKILL.md`](../../skills/setup/SKILL.md) — `/setup` workflow, greenfield gate, emit steps, manifest
- [`skills/setup/templates/ORCHESTRATION.md`](../../skills/setup/templates/ORCHESTRATION.md) — canonical architecture: workflows, agents, evaluation, contracts, test ladder, autonomous loop guards
