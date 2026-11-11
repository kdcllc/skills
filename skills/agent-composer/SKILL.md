---
name: agent-composer
description: "Design a custom multi-agent crew from an interview, write a YAML crew spec, and generate validated Claude Code and Cursor agent files plus an orchestrator skill. Use when you want custom agents, a designed agent team or crew, a generated orchestration workflow, or subagents for Claude Code or Cursor."
license: MIT
metadata:
  version: "0.2.1"
---

# Agent Composer

## What this produces

From one interview you get:

- A crew spec at `.agent-composer/<name>.crew.yaml` (single source of truth)
- Per targeted harness: agent files, an orchestrator skill at `.claude/skills/<name>/SKILL.md` or `.cursor/skills/<name>/SKILL.md`, and optionally `.cursor/rules/<name>.mdc`
- A manifest at `.agent-composer/<name>.manifest.json` for safe re-runs

Schema, validation codes, generated layout, manifest states, and runtime protocol: [references/spec-schema.md](references/spec-schema.md). Role prompts and boundaries: [references/writing-agents.md](references/writing-agents.md).

## When to use / when not to use

**Use** when you need distinct roles, explicit handoffs in a run workdir, and an orchestrator that schedules steps (pipeline, router, parallel merge, evaluator loop, or planner dispatch).

**Do not use** when one agent or a single skill is enough — say so during the interview. Use **`agent-kit`** instead when you want the standard orchestrator/worker/evaluator kit (seven fixed agents, `/feature` and `/research`, evaluator gates).

**Not sure a crew is needed?** Run the **`orchestration-advisor`** skill first. It inspects the repository, asks about the workload, and recommends a shape; come back here when it recommends custom roles.

**Patterns** (pick one dominant `pattern` in the spec; details in [references/patterns.md](references/patterns.md)): `pipeline`, `router`, `fan-out`, `evaluator-optimizer`, `orchestrator-workers`.

**Example specs** to adapt: [assets/examples/coding-crew.crew.yaml](assets/examples/coding-crew.crew.yaml) (coding), [assets/examples/content-crew.crew.yaml](assets/examples/content-crew.crew.yaml) (content), [assets/examples/triage-crew.crew.yaml](assets/examples/triage-crew.crew.yaml) (triage).

## Requirements

- **bash**, **python3**, and **PyYAML** for [scripts/validate.sh](scripts/validate.sh) and [scripts/manifest.sh](scripts/manifest.sh) (override interpreter with `AGENT_COMPOSER_PYTHON`).
- If those scripts exit **3**, show `python3 -m pip install pyyaml`, offer to install; if the user declines, run the **manual validation checklist** in Step 5 and state that validation was manual.
- In commands below, **`<skill-dir>`** is the directory containing this `SKILL.md` (the published `skills/agent-composer/` folder in the pack, or your installed copy).

## Step 1 — Detect

1. Detect harness folders: `.claude/` (Claude Code), `.cursor/` (Cursor). Ask which to target (v1: either or both).
2. Enumerate existing files:
   - `.claude/agents/`, `.cursor/agents/` (including agent-kit’s seven agents when installed)
   - `.claude/skills/`, `.cursor/skills/`
   - `.agent-composer/*.crew.yaml`
3. Report **name collisions** (agent ids, skill names, spec basenames) before the interview.
4. Report **how many agent files already exist** and the rough combined size of their `description` values (characters divided by 4 as a token estimate). Claude Code warns when custom subagent descriptions together exceed 15,000 tokens (Claude Code subagents documentation, checked 2026-11-10); say how close the existing agents are before adding more.

## Step 2 — Interview

One round at a time; prefer multiple-choice. Cover:

- Crew goal in one sentence
- Work type: coding, general (research, writing, ops, analysis), or domain-specific
- Inputs and final deliverable
- **Before roles:** for each agent beyond the first, which of the four reasons justifies it — context pollution, independent parallel units, tool or prompt conflict, or need for an independent verifier ([references/patterns.md](references/patterns.md) § Do you need a crew at all?). A split by type of work (plan, build, test, review) is not a reason. When no reason holds, offer one agent or a skill instead.
- Roles, handoffs, quality gates (who judges, what PASS means, max cycles, behavior on exhaustion)
- Tools per role; model tiers (`frontier`, `light`, `fast`, `inherit`)

Recommend a **pattern** from [references/patterns.md](references/patterns.md) by name with a one-line reason. Push back if a crew is unnecessary: if one agent or a single skill would do, say so and offer that instead; **warn above six agents**.

## Step 3 — Spec

1. Write `.agent-composer/<name>.crew.yaml` per [references/spec-schema.md](references/spec-schema.md).
2. **Models:** fill `models:` only with IDs verified live now — Cursor: `agent models` or **Settings → Models** (empty CLI list is OK); Claude Code: model configuration docs in [references/claude-code.md](references/claude-code.md). Record date and source in `verified`. Placeholder model values (strings containing `<` and `>` under `models.<harness>`) raise **`S040`** warnings — replace them before generating.
3. Run `bash <skill-dir>/scripts/validate.sh spec <spec>`; fix every `error:` line and re-run until exit **0** (warnings alone still exit 0).
4. Show the spec to the user. **Do not generate any file until the user confirms the spec.**

## Step 4 — Generate

For each target harness, fill [assets/templates/](assets/templates/) per [assets/templates/README.md](assets/templates/README.md) and [references/claude-code.md](references/claude-code.md) / [references/cursor.md](references/cursor.md). Compute `{{root_inputs}}` and `{{steps_procedure}}` per the README and apply the blank-line rule to every generated file. Write exactly the paths in spec-schema **Generated layout**. Cursor `model` values stay **unquoted**. Emit the generated-by marker verbatim.

- Ask before adding the crew `workdir` to `.gitignore`.
- Never overwrite a path not listed for this crew’s manifest, or where `manifest.sh status` shows **`edited`**, without asking.

## Step 5 — Validate

1. `bash <skill-dir>/scripts/validate.sh tree <project-root> <spec>` — fix every error, re-run until exit **0**.
2. `bash <skill-dir>/scripts/manifest.sh write <project-root> <spec>`.

**Script behavior:** exit **2** = usage or I/O (wrong args, unreadable file) — fix invocation or files. Any line starting `error: internal:` = validator bug — stop, show the user, do not “fix” the tree to hide it.

**Exit 3 (no python3/PyYAML):** install hint above; if declined, walk the manual checklist below and say validation was **manual**.

### Manual validation checklist (exit 3 fallback)

Check spec rules first, then generated tree rules. Each item names its code; full definitions are in [references/spec-schema.md](references/spec-schema.md).

**Spec (`validate.sh spec`) — S codes**

- **S001** — YAML does not parse.
- **S002** — Unknown top-level key.
- **S003** — Unknown agent key.
- **S004** — Unknown step key.
- **S005** — Missing required key (including inside `gate` or `dispatch`).
- **S006** — Wrong type, enum, or length (including empty `harnesses` or `steps`).
- **S007** — `name` or id fails regex.
- **S008** — Duplicate id within `agents` or within `steps` (separate namespaces).
- **S009** — Step references unknown agent.
- **S010** — Reference to unknown step id.
- **S011** — Cycle in `needs`.
- **S012** — Evaluator step missing `gate`.
- **S013** — `gate` on non-evaluator step.
- **S014** — Router step missing `routes`.
- **S015** — `routes` on non-router step.
- **S016** — Planner step missing `dispatch`.
- **S017** — `dispatch` on non-planner step.
- **S018** — `gate.max_cycles` not 1–5.
- **S019** — `dispatch.max_tasks` not 1–20.
- **S020** — `gate.on_fail` not upstream of gated step.
- **S021** — Route target missing router in `needs`.
- **S022** — Top-level `pattern` rules violated.
- **S023** — Agent never used in any step.
- **S024** — Evaluator lists `edit`.
- **S025** — Evaluator lists `shell` (warning).
- **S026** — Unknown tool (including `spawn`).
- **S027** — Missing `models` tier mapping for a used non-inherit tier.
- **S028** — More than six agents (warning).
- **S029** — Spec basename ≠ top-level `name`.
- **S030** — Step must set exactly one of `agent` or `parallel`.
- **S031** — `parallel` lists fewer than two agents.
- **S032** — Agent count not 1–8.
- **S033** — Duplicate harness entry.
- **S035** — Unknown key inside `gate`.
- **S036** — Unknown key inside `dispatch`.
- **S037** — Unknown key inside `models.<harness>`.
- **S038** — Non-worker in `parallel` or `dispatch.workers`.
- **S039** — `outputs` without `edit` in `tools` (including planner without `edit`).
- **S040** — Placeholder value under `models.<harness>` (contains `<` and `>`).

**Generated tree (`validate.sh tree`) — T codes** — check each target harness against its own list: [references/claude-code.md](references/claude-code.md) and [references/cursor.md](references/cursor.md) (§ Validator rules); T005, T006, T011 apply to Cursor only.

- **T001** — Expected generated file missing.
- **T002** — Frontmatter does not parse.
- **T003** — Frontmatter `name` mismatch (agent stem or orchestrator skill name).
- **T004** — Disallowed or missing frontmatter key (Claude Code agents: exactly `name`, `description`, `tools`, `model`; Cursor agents: `name`, `description`, `model`, optional `readonly`; orchestrator skill: `name`, `description`, optional `disable-model-invocation`).
- **T005** — Cursor `model` value is quoted.
- **T006** — Cursor agent file declares `tools:`.
- **T007** — `model` does not match spec tier mapping (including `inherit`).
- **T008** — Evaluator grants write tools (Claude Code: `Edit` or `Write` in `tools`; Cursor: missing `readonly: true` when the spec's tools omit `shell`).
- **T009** — Leftover `{{` or block delimiter comments.
- **T010** — Missing generated-by marker line.
- **T011** — Cursor rule invalid (`.mdc`, `alwaysApply`).
- **T012** — Path collides with foreign file (not in manifest, no marker).
- **T013** — Orchestrator skill exceeds 500 lines.

## Step 6 — Report

- List every file written.
- Walk through one run: “When you run `/<name>`, …” — describe only behavior present in the generated orchestrator skill: run id and run folder, writing the user's request into each root input (and empty-request handling), passing that request in spawn context for steps with empty `needs`, each step in scheduling order with its agent (and parallel/dispatch/gate behavior only when the generated files include those sections), report paths, gate cycle report renaming when applicable, and where the orchestrator writes the run report (`<workdir>/<run-id>/run-report.md`).
- When the crew targets both harnesses, tell the user Cursor may list two identical `/<name>` skills (the `.cursor/skills/` and `.claude/skills/` copies have identical bodies); see [references/cursor.md](references/cursor.md).
- Tell the user how to change the crew: edit `.agent-composer/<name>.crew.yaml`, then re-run this skill.

## Re-running after a spec change

1. Read the existing spec; apply the user’s edits.
2. Re-validate: `bash <skill-dir>/scripts/validate.sh spec <spec>`.
3. `bash <skill-dir>/scripts/manifest.sh status <project-root> <spec>`:
   - **`spec-changed`** — the spec file changed since the last `manifest.sh write`; generated files are stale. Regenerate every file the spec produces (still ask before overwriting **`edited`** files).
   - **`unchanged`** / **`missing`** — regenerate safely.
   - **`edited`** — show the user; choose keep, overwrite, or merge before writing.
   - **`new`** — run collision checks like Step 1.
   - **`orphan`** — list paths the new spec no longer produces; delete only after user agrees.
4. Regenerate, then `validate.sh tree` until exit **0**, then `manifest.sh write`.

## Quality checklist

- Spec validates with zero errors; tree validates with zero errors (or manual checklist if exit 3).
- No leftover template tokens; Cursor models unquoted; orchestrator matches [references/writing-agents.md](references/writing-agents.md) report protocols (`STATUS:`, `ROUTE:`, `VERDICT:`).
- Dominant pattern matches [references/patterns.md](references/patterns.md); coding and non-coding crews both supported via examples above.
