# Orchestration patterns

Use this guide during the agent-composer interview to pick a `pattern` value for the crew spec. Step scheduling, skipped steps, `ROUTE:` / `VERDICT:` lines, and `tasks.yaml` behavior are defined in [spec-schema.md](spec-schema.md) under **Runtime protocol** — this document applies those rules to each pattern without redefining them.

## Decision guide

Ask in order; the first strong match usually wins. When several apply, see **Combining patterns** below.

1. **Is the work one fixed sequence** (always step A → B → C with no branching)? → `pipeline`.
2. **Must the first step choose among different specialists** based on the input (triage, intent, category)? → `router`.
3. **Can independent workers run at once** and a later step merges their outputs? → `fan-out`.
4. **Does quality require a review loop** (draft → check → revise until pass or cycle limit)? → `evaluator-optimizer`.
5. **Does a planner break work into many similar tasks** for a pool of workers? → `orchestrator-workers`.

If none of the above is clearly true, read **Do you need a crew at all?** before adding agents.

## Do you need a crew at all?

Not every workflow needs a generated crew.

| Situation | Better answer |
| --- | --- |
| One role, one pass, no handoffs between specialists | A **single agent file** (or the main session) plus an existing **skill** for the procedure |
| The user only needs a checklist or template, not runtime spawning | **No subagents** — document the steps in a skill or runbook |
| Two steps but the second always runs and never branches | Often still a **pipeline**, but a **two-agent pipeline** may be overkill if one agent with clear sections in `instructions` suffices |

The skill **must tell the user** when a crew is unnecessary and recommend the simpler option. A crew spec is justified when there are distinct roles, explicit handoffs in the run workdir, and an orchestrator that schedules steps (including gates, routes, parallel blocks, or dispatch).

## Combining patterns

Real crews can embed one pattern inside another (for example, a `pipeline` whose last step is an evaluator `gate`). The spec allows only **one** top-level `pattern` enum — it names the **dominant** shape. The validator applies that pattern’s rule set from [spec-schema.md](spec-schema.md) (**Pattern rules**). Name the dominant behavior: a linear research → write → review loop is `evaluator-optimizer` even if research and draft are sequential; a triage step followed by parallel research is `router` if routing is the defining behavior, or `fan-out` if every path runs the same parallel merge.

## pipeline

### When to use it

Interview signals: fixed stages, each output feeds the next, no branching, no quality loop, no dynamic task list. Examples: ingest → transform → summarize; scrape → normalize → report.

### When not to use it

Branching on content, parallel independent work, review-until-pass loops, or a planner fanning out variable tasks. Do not use `parallel`, `routes`, or `dispatch` on any step.

### Typical roles

| Role | `kind` | Notes |
| --- | --- | --- |
| Stage workers | `worker` | One agent per step (or reuse one agent in multiple steps only if the spec intentionally repeats the same id). |
| Optional final reviewer | `evaluator` | Only if you add a `gate`; then the dominant pattern is usually `evaluator-optimizer`, not pure pipeline. |

### Gate shape

Pure pipelines have **no** `gate`. If the last step is an evaluator with `gate`, treat the crew as `evaluator-optimizer` for the top-level `pattern`.

### How the spec expresses it

Linear chain via `needs`: exactly one step has `needs: []`; every other step lists exactly one predecessor in `needs`; no step is needed by more than one successor. Use `agent` on each step only (no `parallel`, `routes`, or `dispatch`).

```yaml
steps:
  - id: collect
    agent: collector
    needs: []
  - id: refine
    agent: refiner
    needs: [collect]
  - id: publish
    agent: publisher
    needs: [refine]
```

### Runtime behavior

Steps run in dependency order per **Runtime protocol**. Agents with `edit` write declared `outputs` under `<workdir>/<run-id>/`; read-only agents declare no `outputs` and deliver findings via the orchestrator-saved step report. Every agent ends with `STATUS: done` or `STATUS: blocked — …`.

### Anti-patterns

Using empty `needs` on multiple steps (breaks single-chain rule). Assuming list order implies execution order. Hiding a router or parallel block inside a spec labeled `pipeline`.

## router

### When to use it

Interview signals: first step classifies input and only **one** downstream path should run (support vs billing, bug vs feature, language or domain branch).

### When not to use it

Every path must run (use `fan-out` or `pipeline`). Multiple routing decisions in series without a dominant single router step. Need to merge all branches into one final artifact in the same run.

### Typical roles

| Role | `kind` | Notes |
| --- | --- | --- |
| Classifier | `router` | Prints `ROUTE: <label>` matching a key in the step’s `routes`. |
| Specialists | `worker` | One step per route target; each lists the router step in `needs`. |

### Gate shape

Routers do not use `gate` on the router step. Evaluator gates belong on downstream paths only if that path is an optimizer loop (unusual in pure routers).

### How the spec expresses it

Exactly one step has `routes` (map of label → target step id). Each target step’s `needs` includes the router step id. Step ids and agent ids are separate namespaces, but a step **may reuse** its agent’s id (below, step `triage` and agent `triage`).

```yaml
steps:
  - id: triage
    agent: triage
    needs: []
    routes:
      billing: handle-billing
      tech: handle-tech
  - id: handle-billing
    agent: billing-specialist
    needs: [triage]
  - id: handle-tech
    agent: tech-specialist
    needs: [triage]
```

### Runtime behavior

The router agent emits one `ROUTE:` line; non-selected route targets are **skipped**, and any step that **needs** a skipped step is skipped as well (**Runtime protocol**). Therefore a router crew **cannot** have a join step after the specialists that merges all branches — skipped predecessors would skip the join. Each specialist delivers its **own** final output for the run; the orchestrator reports which routes ran and which steps were skipped.

### Anti-patterns

A shared “finalize” step that `needs` all specialists (invalid for router semantics). Missing router step in a target’s `needs` (**S021**). Using `routes` on a non-router agent.

## fan-out

### When to use it

Interview signals: several workers can proceed **in parallel** after a shared setup, then one step combines or decides using all partial results.

### When not to use it

Only one worker ever runs (use `pipeline` or `router`). Workers must not share merge timing (use sequential `pipeline`). Variable number of tasks from a planner (use `orchestrator-workers`).

### Typical roles

| Role | `kind` | Notes |
| --- | --- | --- |
| Optional setup | `worker` | Single step before the parallel block. |
| Parallel workers | `worker` | Listed together in one step’s `parallel` (at least two ids). |
| Merge / synthesize | `worker` | Step whose `needs` includes the parallel step id. |

### Gate shape

Optional: add a later step whose agent has `kind: evaluator` and carries `gate` (a `gate` on the worker merge step is forbidden, **S013**), with `on_fail` naming the merge step or another upstream step; if the loop dominates, set `pattern: evaluator-optimizer`.

### How the spec expresses it

At least one step uses `parallel` (mutually exclusive with `agent` on that step). A later step lists that parallel step in `needs`.

```yaml
steps:
  - id: brief
    agent: lead
    needs: []
  - id: research-parallel
    parallel: [researcher-a, researcher-b]
    needs: [brief]
  - id: synthesize
    agent: editor
    needs: [research-parallel]
```

### Runtime behavior

The orchestrator runs all agents in `parallel` concurrently; when the parallel step completes, merge steps run. Agents in `parallel` must be `kind: worker` (**S038**). Skipped-step rules apply if an upstream step was skipped.

### Anti-patterns

Only one agent in `parallel` (**S031**). Merge step that does not list the parallel step in `needs`. Putting an evaluator or router in `parallel`.

## evaluator-optimizer

### When to use it

Interview signals: produce a draft or implementation, then **independent review**; on failure, revise upstream work and re-review until `VERDICT: PASS` or `max_cycles` exhausts.

### When not to use it

One-shot review with no revision loop (use `pipeline` with a final worker, not an evaluator gate). Review that should edit the artifact directly (evaluators must not use `edit` — use a worker for fixes).

### Typical roles

| Role | `kind` | Notes |
| --- | --- | --- |
| Producers | `worker` | Steps between `gate.on_fail` and the gate (re-run on FAIL). |
| Reviewer | `evaluator` | Step that carries `gate`; prints `VERDICT: PASS` or `VERDICT: FAIL` plus findings. |

### Gate shape

On the evaluator step only: `gate: { on_fail: <step-id>, max_cycles: 1–5 }`. `on_fail` must be an **upstream** step the gated step transitively needs (**S020**). After `max_cycles` FAIL verdicts, the orchestrator applies spec `on_exhaustion` (`ask-user` or `stop`).

### How the spec expresses it

At least one step has `gate`. Often chained with `needs` from producer to evaluator.

```yaml
steps:
  - id: draft
    agent: writer
    needs: []
  - id: review
    agent: checker
    needs: [draft]
    gate:
      on_fail: draft
      max_cycles: 3
```

### Runtime behavior

On `VERDICT: FAIL`, the orchestrator re-runs the `gate.on_fail` step and the steps between it and the gate with the findings, then re-runs the gate. See **Runtime protocol** in [spec-schema.md](spec-schema.md).

### Anti-patterns

Evaluator with `edit` in `tools` (**S024**). `on_fail` pointing downstream. `gate` on a non-evaluator step. Expecting the evaluator to implement fixes.

## orchestrator-workers

### When to use it

Interview signals: one planner decomposes work into **many similar tasks** (up to `dispatch.max_tasks`), each assigned to a worker from a fixed pool; tasks may run in parallel when outputs do not collide.

### When not to use it

Fixed small sequence (use `pipeline`). Classify-then-one-path (use `router`). Known small parallel set (use `fan-out`).

### Typical roles

| Role | `kind` | Notes |
| --- | --- | --- |
| Planner | `planner` | Writes `tasks.yaml` under the run workdir; step uses `dispatch`. |
| Workers | `worker` | Ids listed in `dispatch.workers`; spawned per task item. |

### Gate shape

Optional evaluator on aggregated results after workers finish; dominant loop may justify `evaluator-optimizer` instead.

### How the spec expresses it

Exactly one step has `dispatch: { workers: [...], max_tasks: 1–20 }` on the planner’s step.

```yaml
steps:
  - id: plan
    agent: planner
    needs: []
    dispatch:
      workers: [implementer, implementer-b]
      max_tasks: 10
  - id: integrate
    agent: integrator
    needs: [plan]
```

### Runtime behavior

The planner writes `<workdir>/<run-id>/tasks.yaml` (YAML list of `{id, title, worker, inputs, outputs}`). The orchestrator spawns one worker per item; items with disjoint `outputs` may run in parallel (**Runtime protocol**). Workers must be `kind: worker`.

### Anti-patterns

Multiple `dispatch` steps (**S022** / pattern rules). Non-worker ids in `dispatch.workers`. Planner step without `dispatch` (**S016**). Subagents spawning subagents (forbidden in v1 — orchestrator spawns all workers).
