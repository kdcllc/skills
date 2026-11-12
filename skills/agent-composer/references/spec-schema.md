# Crew spec schema

This document is the frozen contract for the YAML crew spec, validation error codes, script CLIs, generated-file layout, manifest format, and crew runtime protocol. Generators, validators, and orchestrator templates must match it verbatim.

## Spec file location

One crew per file: `.agent-composer/<name>.crew.yaml` in the user's project (repo-relative). The `<name>` must match the spec's top-level `name` field (mismatch → **S029**).

### Documented rules and error codes

Rules below name the stable code the validator uses. Wrong type, enum, string length, or list length (including `schema` ≠ `1`, `description` outside 1–1024 characters, an empty `harnesses` list, and an empty `steps` list) → **S006**. Missing required key (including `gate.on_fail`, `gate.max_cycles`, `dispatch.workers`, or `dispatch.max_tasks` when the parent map is present) → **S005**.

| Rule | Code |
| --- | --- |
| Spec basename `<name>` ≠ top-level `name` | S029 |
| Duplicate value in `harnesses` | S033 |
| Agent count not in 1–8 | S032 |
| Step sets both `agent` and `parallel`, or neither | S030 |
| `parallel` list has fewer than two agent ids | S031 |
| Unknown key inside `gate` | S035 |
| Unknown key inside `dispatch` | S036 |
| Unknown key inside `models.<harness>` | S037 |
| Placeholder string in `models.<harness>.<tier>` (contains `<` and `>`) | S040 |
| Unknown top-level / agent / step key | S002 / S003 / S004 |
| Agent declares `outputs` without `edit` in `tools` (including `kind: planner` without `edit`) | S039 |

## Top-level keys

| Key | Required | Type | Default | Rules |
| --- | --- | --- | --- | --- |
| `schema` | yes | integer | — | Must be `1`. |
| `name` | yes | string | — | Regex `^[a-z0-9]+(-[a-z0-9]+)*$`, 1–64 characters. Becomes the orchestrator skill name and the `/name` command. |
| `description` | yes | string | — | 1–1024 characters; states what the crew does and when to use it. |
| `pattern` | yes | enum | — | One of `pipeline`, `router`, `fan-out`, `evaluator-optimizer`, `orchestrator-workers`. |
| `harnesses` | yes | list | — | Non-empty; each value is `claude-code` or `cursor`; no duplicates. |
| `invocation` | no | enum | `manual` | `manual` or `auto`. `manual` means the orchestrator skill gets `disable-model-invocation: true`. |
| `workdir` | no | string | `_crew/<name>` | Repo-relative path; each run writes under `<workdir>/<run-id>/`. |
| `cursor_rule` | no | boolean | `false` | When `true`, generate a Cursor `.mdc` pointer rule. |
| `models` | no | map | none (absent) | Keys: harness (`claude-code`, `cursor`). Values: maps with optional `frontier`, `light`, `fast` (model ID strings) and optional `verified` (date and source of the live check; default absent). Required for every listed harness when any agent's `tier` is not `inherit`; only tiers actually used by agents must be present. |
| `on_exhaustion` | no | enum | `ask-user` | `ask-user` or `stop`; applied after evaluator `max_cycles` FAIL verdicts. |
| `agents` | yes | list | — | 1–8 agent objects (see below). |
| `steps` | yes | list | — | At least one step object (see below). |

Unknown top-level keys are errors.

## Agent object

| Key | Required | Type | Default | Rules |
| --- | --- | --- | --- | --- |
| `id` | yes | string | — | Same regex as `name`; unique within `agents`. |
| `description` | yes | string | — | 1–1024 characters. |
| `kind` | no | enum | `worker` | `worker`, `evaluator`, `router`, or `planner`. |
| `tier` | no | enum | `inherit` | `frontier`, `light`, `fast`, or `inherit`. |
| `tools` | no | list | `[read, search]` | Values from `read`, `search`, `edit`, `shell`, `web`. The tool `spawn` does not exist — subagents never spawn subagents; the orchestrator skill does all spawning. |
| `instructions` | yes | string | — | Non-empty role prompt body. |
| `inputs` | no | list | `[]` | Workdir-relative file names this agent reads. |
| `outputs` | no | list | `[]` | Workdir-relative file names this agent writes. Must be empty when `edit` is not in `tools` (**S039**); the orchestrator persists the agent report instead. |
| `run` | no | enum | `subagent` | `subagent` or `inline`. `subagent` generates an agent file and the orchestrator spawns it. `inline` generates a role file inside the orchestrator skill folder instead of an agent file, and the orchestrator performs that agent's steps itself by following the role file. |

Unknown agent keys are errors.

Agent ids and step ids are **separate namespaces**: **S008** applies within the `agents` list and within the `steps` list separately, and a step may reuse its agent's id.

### Agent kind constraints

- `kind: evaluator` — must not list `edit` (error). Listing `shell` is a warning. An evaluator that lists `outputs` without `edit` is **S039** (the general `outputs` rule; an evaluator listing `edit` is **S024**).
- `kind: planner` — must list `edit` to write `<workdir>/<run-id>/tasks.yaml`; a planner without `edit` is **S039**.
- Every agent must appear in at least one step via `agent`, `parallel`, or `dispatch.workers`.
- Agents referenced in a step's `parallel` list or in `dispatch.workers` must have `kind: worker` (**S038**).
- More than six agents in the crew is a warning.

### Inline agents (run: inline)

- `run: inline` is allowed only on `kind: worker` (**S041**).
- `run: inline` requires `tier: inherit` (**S042**). The step runs in the main session on the main session's model, so no per-agent model applies.
- A `run: inline` agent must not appear in a step's `parallel` list or in `dispatch.workers`, because an inline step cannot run concurrently (**S043**).
- `tools`, `inputs`, `outputs` and `instructions` keep their meaning and rules (**S026** and **S039** still apply). The tools are the main-session tools the step uses and are listed in the role file body.
- Choose `inline` when the role has no distinct tools, model tier or isolation need of its own (a knowledge-only role). Evaluator, router and planner roles stay subagents. An inline step shares the orchestrator's context, so when a gate re-runs it, it sees the evaluator's findings and its earlier attempts.
- A `kind: worker` agent that looks knowledge-only but still runs as a subagent gets the warning **S044**: `run` absent or `subagent`, `tier: inherit`, tools a subset of `[read, search]` (the default included), no `outputs`, not in any step's `parallel` list or `dispatch.workers`, not the agent of any step a gate re-runs (the gate's `on_fail` step, and every step that transitively needs the `on_fail` step and is transitively needed by the gated step), not an agent id that appears more than once in `agents` (**S008** already reports it), and the crew has more than one agent (a one-agent crew is better as a plain skill, so the hint does not apply). The message suggests `run: inline`. Warnings do not change the exit code.
- **S027** is not reported for an agent that gets **S042**: the fix S042 asks for (`tier: inherit`) needs no `models` entry.

## Step object

| Key | Required | Type | Default | Rules |
| --- | --- | --- | --- | --- |
| `id` | yes | string | — | Same regex as `name`; unique within `steps`. |
| `agent` | conditional | string | — | Agent id for this step. Required unless `parallel` is set. Mutually exclusive with `parallel`. |
| `parallel` | conditional | list | none (absent) | At least two agent ids run concurrently. Mutually exclusive with `agent`. |
| `needs` | no | list | `[]` | Step ids that must finish before this step runs. Empty means no prerequisites — absence never means "the previous step". |
| `routes` | conditional | map | — | Keys are route labels; values are step ids. Required when the step's agent has `kind: router`; forbidden elsewhere. |
| `gate` | conditional | map | — | `{on_fail: <step id>, max_cycles: <int 1–5>}`. Both `on_fail` and `max_cycles` are required inside `gate`; either missing → **S005**. Required when the step's agent has `kind: evaluator`; forbidden elsewhere. |
| `dispatch` | conditional | map | — | `{workers: [agent ids], max_tasks: <int 1–20>}`. Both `workers` and `max_tasks` are required inside `dispatch`; either missing → **S005**. Required when the step's agent has `kind: planner`; forbidden elsewhere. |

Unknown step keys are errors.

References in `agent`, `parallel`, `needs`, `routes`, `gate.on_fail`, and `dispatch.workers` must name existing agents or steps.

## Pattern rules

| Pattern | Rules |
| --- | --- |
| `pipeline` | No `routes`, `parallel`, or `dispatch` on any step. Steps form one linear chain through `needs` (exactly one step has empty `needs`; every other step needs exactly one step; no step is needed by more than one step). |
| `router` | Exactly one step has `routes`. Every route target exists and lists the router step in its `needs`. |
| `fan-out` | At least one step has `parallel`, and a later step's `needs` includes that parallel step's id. |
| `evaluator-optimizer` | At least one step has `gate`. |
| `orchestrator-workers` | Exactly one step has `dispatch`. |

## General graph rules

- The `needs` graph is acyclic.
- `gate.on_fail` names a step the gated step transitively needs (upstream).
- Every route target lists its router step in `needs` (in any pattern that uses routes).
- Pattern-specific rules above must hold.
- Agents in `parallel` or `dispatch.workers` must have `kind: worker` (**S038**).

## Minimal example (evaluator–optimizer)

```yaml
schema: 1
name: research-write-check
description: "Research a topic, draft content, and fact-check in a loop until the checker passes or cycles exhaust."
pattern: evaluator-optimizer
harnesses:
  - claude-code
  - cursor
invocation: manual
workdir: _crew/research-write-check
cursor_rule: false
on_exhaustion: ask-user
models:
  claude-code:
    light: "<light-model-id>"
  cursor:
    light: "<light-model-id>"
agents:
  - id: researcher
    description: "Gather sources and notes for the assigned topic."
    kind: worker
    tier: inherit
    tools: [read, search, web, edit]
    instructions: |
      Research the user's topic and write structured notes to the run workdir.
    outputs: [notes.md]
  - id: writer
    description: "Turn research notes into a draft article."
    kind: worker
    tier: inherit
    tools: [read, search, edit]
    instructions: |
      Read notes.md and write draft.md in the run workdir.
    inputs: [notes.md]
    outputs: [draft.md]
  - id: checker
    description: "Verify factual claims in the draft against the notes."
    kind: evaluator
    tier: light
    tools: [read, search]
    instructions: |
      Compare draft.md to notes.md. Print exactly one line VERDICT: PASS or VERDICT: FAIL, followed by findings on FAIL.
    inputs: [notes.md, draft.md]
steps:
  - id: research
    agent: researcher
    needs: []
  - id: draft
    agent: writer
    needs: [research]
  - id: review
    agent: checker
    needs: [draft]
    gate:
      on_fail: draft
      max_cycles: 3
```

## Runtime protocol

Run id format: UTC `YYYYMMDDTHHMMSSZ`. Run folder: `<workdir>/<run-id>/` (repo-relative base from `workdir`).

### Step scheduling

A step runs when every step listed in its `needs` has finished.

A step is **skipped** when any step it needs was skipped, or when it is a route target its router did not select. Skipped steps are listed in the run report.

### Root inputs

A **root input** is a file name listed in any agent's `inputs` that no agent in the crew lists in `outputs`. (`tasks.yaml` is never a root input.)

After creating `<workdir>/<run-id>/` and before the first step, the orchestrator writes the user's request — the text the user gave with `/<name>`; when that text is empty, it asks the user for it first — into each root input at `<workdir>/<run-id>/<file>` (every root input receives the full request). The request is also always passed in the spawn context of every step whose `needs` is empty, whether or not the crew has root inputs. When `inputs` is absent on every agent, there are no root inputs.

### Agent reports

Every agent's report ends with a line `STATUS: done` or `STATUS: blocked — <reason>` and lists the output files it wrote.

The orchestrator saves every agent's final report verbatim:

- Single-agent step: `<workdir>/<run-id>/<step-id>.report.md`
- `parallel` step: one file per member `<workdir>/<run-id>/<step-id>.<agent-id>.report.md`
- `dispatch` step: one file per task item `<workdir>/<run-id>/<step-id>.<task-id>.report.md`

Evaluator verdicts and router labels are read from these saved reports (not from live session output alone).

On FAIL at a gate, the orchestrator counts the verdict as gate cycle *n* (first FAIL is 1, second is 2, and so on). When *n* equals `max_cycles`, it applies `on_exhaustion` and does not rename reports or re-run steps. When *n* is below `max_cycles`, before re-running it renames the gated step's current report and the current report of every step it will re-run (`<base>.report.md`) to `<base>.cycle-<n>.report.md`, so `<base>.report.md` always holds the latest run and earlier `.cycle-*` files are never renamed again. The run report lists every cycle's evaluator verdict from those saved files.

### Router agents

Router agents print exactly one line `ROUTE: <label>` where `<label>` is a key of the step's `routes`. An unknown label stops the run with a failure report.

### Evaluator agents

Evaluator agents print exactly one line `VERDICT: PASS` or `VERDICT: FAIL`, followed by a findings list on FAIL. On FAIL, the orchestrator counts the verdict as gate cycle *n* (matching the FAIL verdict number). When *n* equals `max_cycles`, it applies `on_exhaustion` and does not rename reports or re-run steps. When *n* is below `max_cycles`, it renames reports as in **Agent reports**, then re-runs `gate.on_fail` (and the steps between it and the gate) with the findings, then re-runs the gate.

### Planner agents

Planner agents write `<workdir>/<run-id>/tasks.yaml`: a YAML list of at most `dispatch.max_tasks` items, each `{id, title, worker, inputs, outputs}` where `worker` is one of `dispatch.workers`. The orchestrator spawns one worker per item and runs items with disjoint `outputs` in parallel.

### Inline steps

At a step whose agent has `run: inline`, the orchestrator does not spawn. It reads `roles/<agent-id>.md` in its own skill folder and performs the step itself, then saves its report verbatim and writes the outputs exactly as **Agent reports** says for a spawned agent. A gate's `on_fail` re-run of an inline step is performed inline again, using the evaluator's findings directly in the orchestrator's context. An inline step whose `needs` is empty uses the user's request directly, because there is no spawn context.

### Orchestrator role

The orchestrator never does a worker's, router's, planner's, or evaluator's job itself, except a step whose agent has `run: inline`, which it performs by following that agent's role file (§ Inline steps).

### Run report

When a run ends (success, user stop, exhaustion, or a blocked step), the orchestrator writes the run report to `<workdir>/<run-id>/run-report.md`, listing every step id, whether it ran or was skipped, verdicts or route labels read (if any), output paths, saved report paths, and every gate cycle's verdict. `run-report.md` is a reserved file name in the run folder; agents should not list it in `outputs`.

## Validation error codes

Findings use stable codes. Spec-mode validation uses `S###`; generated-tree validation uses `T###`.

| Code | Severity | Meaning | Example |
| --- | --- | --- | --- |
| S001 | error | YAML parse failure | `error: S001 .agent-composer/foo.crew.yaml: invalid YAML at line 12` |
| S002 | error | Unknown top-level key | `error: S002 name: unknown key 'crew'` |
| S003 | error | Unknown agent key | `error: S003 agents[0]: unknown key 'model'` |
| S004 | error | Unknown step key | `error: S004 steps[1]: unknown key 'when'` |
| S005 | error | Missing required key | `error: S005 agents[0]: missing required key 'instructions'` |
| S006 | error | Wrong type or enum value (including an invalid `run` value) | `error: S006 pattern: must be one of pipeline, router, ...` |
| S007 | error | Bad name or id regex | `error: S007 name: must match ^[a-z0-9]+(-[a-z0-9]+)*$` |
| S008 | error | Duplicate id within `agents` or within `steps` (separate namespaces) | `error: S008 agents: duplicate id 'writer'` |
| S009 | error | Unknown agent reference | `error: S009 steps[0].agent: unknown agent 'missing'` |
| S010 | error | Unknown step reference | `error: S010 steps[1].needs[0]: unknown step 'nope'` |
| S011 | error | `needs` cycle | `error: S011 steps: needs graph contains a cycle` |
| S012 | error | `gate` missing on evaluator step | `error: S012 steps[2]: evaluator step requires gate` |
| S013 | error | `gate` on non-evaluator step | `error: S013 steps[0]: gate forbidden for non-evaluator agent` |
| S014 | error | `routes` missing on router step | `error: S014 steps[0]: router step requires routes` |
| S015 | error | `routes` present on non-router step | `error: S015 steps[1]: routes forbidden for non-router agent` |
| S016 | error | `dispatch` missing on planner step | `error: S016 steps[0]: planner step requires dispatch` |
| S017 | error | `dispatch` on non-planner step | `error: S017 steps[1]: dispatch forbidden for non-planner agent` |
| S018 | error | `max_cycles` out of range | `error: S018 steps[2].gate.max_cycles: must be 1–5` |
| S019 | error | `max_tasks` out of range | `error: S019 steps[0].dispatch.max_tasks: must be 1–20` |
| S020 | error | `on_fail` not upstream | `error: S020 steps[2].gate.on_fail: gated step must transitively need on_fail step` |
| S021 | error | Route target missing router in `needs` | `error: S021 steps[3].needs: route target must list router step` |
| S022 | error | Pattern-rule violation | `error: S022 pattern: pipeline must not use parallel steps` |
| S023 | error | Unused agent | `error: S023 agents[2]: agent 'orphan' is never used` |
| S024 | error | Evaluator with `edit` tool | `error: S024 agents[1].tools: evaluator must not list edit` |
| S025 | warn | Evaluator with `shell` tool | `warn: S025 agents[1].tools: shell on evaluator is discouraged` |
| S026 | error | Unknown tool (including `spawn`) | `error: S026 agents[0].tools[2]: unknown tool 'spawn'` |
| S027 | error | Missing `models` entry for used tier (not reported for an agent that gets **S042**) | `error: S027 models.claude-code: missing tier 'light' used by agent checker` |
| S028 | warn | More than six agents | `warn: S028 agents: crew has 7 agents (warning above 6)` |
| S029 | error | Spec filename ≠ crew `name` | `error: S029 .agent-composer/foo.crew.yaml: basename must match name 'bar'` |
| S030 | error | Step `agent` / `parallel` invalid | `error: S030 steps[1]: set exactly one of agent or parallel` |
| S031 | error | `parallel` too few agents | `error: S031 steps[0].parallel: must list at least two agents` |
| S032 | error | Agent count outside 1–8 | `error: S032 agents: must have 1–8 agents` |
| S033 | error | Duplicate harness | `error: S033 harnesses[1]: duplicate value 'cursor'` |
| S035 | error | Unknown key in `gate` | `error: S035 steps[2].gate: unknown key 'retry'` |
| S036 | error | Unknown key in `dispatch` | `error: S036 steps[0].dispatch: unknown key 'queue'` |
| S037 | error | Unknown key in `models.<harness>` | `error: S037 models.claude-code: unknown key 'default'` |
| S038 | error | Non-worker in `parallel` or `dispatch.workers` | `error: S038 agents[1]: agent 'checker' used in parallel must be kind worker` |
| S039 | error | Agent declares `outputs` without `edit` in `tools` (including `kind: planner` without `edit`) | `error: S039 agents[0].outputs: outputs require edit in tools` |
| S040 | warn | Placeholder model ID under `models.<harness>` | `warn: S040 models.claude-code.light: placeholder value; verify the model ID live and replace it` |
| S041 | error | `run: inline` on an agent that is not `kind: worker` | `error: S041 agents[1].run: run inline is allowed only on kind worker` |
| S042 | error | `run: inline` on an agent whose `tier` is not `inherit` | `error: S042 agents[0].run: run inline requires tier inherit` |
| S043 | error | `run: inline` agent used in a step's `parallel` list or in `dispatch.workers` | `error: S043 agents[0].run: inline agent 'glossary' cannot be used in parallel or dispatch.workers` |
| S044 | warn | Knowledge-only worker that runs as a subagent (hint to use `run: inline`) | `warn: S044 agents[0]: agent 'glossary' looks knowledge-only; consider run: inline` |

| Code | Severity | Meaning | Example |
| --- | --- | --- | --- |
| T001 | error | Generated file missing (an agent file, a role file, an orchestrator skill file, or the Cursor rule) | `error: T001 .claude/skills/foo/roles/glossary.md: expected file missing` |
| T002 | error | Frontmatter parse failure | `error: T002 .cursor/agents/writer.md: invalid frontmatter` |
| T003 | error | Frontmatter `name` mismatch: an agent file's `name` differs from its file stem, or the orchestrator `SKILL.md`'s `name` differs from the crew `name` | `error: T003 .claude/agents/writer.md: name must match file stem 'writer'` |
| T004 | error | Disallowed or missing frontmatter key (including a Claude Code agent file without `model:`) | `error: T004 .claude/agents/writer.md: missing required frontmatter key 'model'` |
| T005 | error | Quoted Cursor `model` value | `error: T005 .cursor/agents/writer.md: Cursor model must be unquoted` |
| T006 | error | Cursor agent file contains `tools:` | `error: T006 .cursor/agents/writer.md: Cursor agents must not declare tools:` |
| T007 | error | `model` differs from spec tier mapping (every tier, including `inherit`) | `error: T007 .claude/agents/checker.md: model does not match spec tier mapping` |
| T008 | error | Evaluator agent grants write tools | `error: T008 .claude/agents/checker.md: evaluator must not grant edit/write tools` |
| T009 | error | Leftover template syntax in a generated file (including a role file): a `{{` token anywhere, or a line starting with `<!-- block:` or `<!-- /block:` | `error: T009 .claude/skills/foo/SKILL.md: contains {{ or block delimiter comment` |
| T010 | error | Generated-by marker missing in a generated file (including a role file, where it is the first line) | `error: T010 .claude/agents/writer.md: missing generated-by marker line` |
| T011 | error | Cursor rule invalid | `error: T011 .cursor/rules/foo.mdc: requires alwaysApply true and .mdc extension` |
| T012 | error | Name collision (applies to role files too): an expected path exists, is not listed in this crew's manifest, and does not carry this crew's generated-by marker | `error: T012 .claude/agents/writer.md: collides with existing file not in manifest and without this crew's marker` |
| T013 | error | Orchestrator skill too long | `error: T013 .claude/skills/foo/SKILL.md: exceeds 500 lines` |
| T014 | error | An agent file `.claude/agents/<agent-id>.md` or `.cursor/agents/<agent-id>.md` exists for a `run: inline` agent and carries this crew's generated-by marker (left over from a subagent run; delete it) | `error: T014 .claude/agents/glossary.md: stale agent file for inline agent 'glossary'; delete it` |
| T015 | error | Role file is not valid UTF-8 (its other role-file checks are skipped) | `error: T015 .claude/skills/foo/roles/glossary.md: not valid UTF-8` |

T002–T008, T011 and T013 do not apply to role files, which have no frontmatter. A file at an agent path without this crew's marker is not reported by T014.

## CLI contract

Implementation lives in `scripts/composer.py`; `validate.sh` and `manifest.sh` are thin wrappers.

Environment: `AGENT_COMPOSER_PYTHON` overrides the interpreter; default `python3`. When `python3` or PyYAML is missing, scripts exit `3` and print `python3 -m pip install pyyaml` on stderr.

### validate.sh

```bash
bash scripts/validate.sh spec <spec.crew.yaml>
bash scripts/validate.sh tree <project-root> <spec.crew.yaml>
```

- `spec` — validates the YAML crew spec only.
- `tree` — validates generated files for that spec (runs spec checks first).

Exit codes (both scripts): `0` no errors; `1` one or more errors (validate) or any non-`unchanged` line (manifest status); `2` usage error (wrong arguments, unreadable file); `3` missing dependency (python3 or PyYAML).

Output format: one line per finding:

```text
error: <CODE> <location>: <message>
warn: <CODE> <location>: <message>
```

Then a final summary line:

```text
validate: <N> error(s), <M> warning(s)
```

Warnings never change the exit code.

### manifest.sh

```bash
bash scripts/manifest.sh write <project-root> <spec.crew.yaml>
bash scripts/manifest.sh status <project-root> <spec.crew.yaml>
```

`write` records the manifest for currently generated files.

`status` may print a leading line `spec-changed <spec>` when a manifest exists and its stored `spec_sha256` differs from the current spec file bytes (or the key is absent or not a string). `<spec>` is the spec path relative to the project root (or the path given when outside the root). This line is not a per-path state; it precedes the per-path lines below. It forces exit `1` like any non-`unchanged` per-path state.

`status` then prints one line per path, sorted by path, with exactly one state each:

| State | Meaning |
| --- | --- |
| `unchanged <path>` | Expected by the spec, present on disk, listed in the manifest, sha256 matches. |
| `edited <path>` | Expected, present, listed, sha256 differs. |
| `missing <path>` | Expected by the spec and absent from disk (whether or not the manifest lists it). |
| `new <path>` | Expected, present on disk, not listed in the manifest (every present expected file is `new` when no manifest exists). |
| `orphan <path>` | Listed in the manifest but no longer expected by the spec (present or absent on disk). |

Exit `0` only when every line is `unchanged`; otherwise `1`.

## Generated layout

Paths are relative to the project root.

| Harness | Generated paths |
| --- | --- |
| Claude Code | `.claude/agents/<agent-id>.md` (subagent agents), `.claude/skills/<name>/roles/<agent-id>.md` (inline agents), `.claude/skills/<name>/SKILL.md` |
| Cursor | `.cursor/agents/<agent-id>.md` (subagent agents), `.cursor/skills/<name>/roles/<agent-id>.md` (inline agents), `.cursor/skills/<name>/SKILL.md`, and `.cursor/rules/<name>.mdc` only when `cursor_rule: true` |

An agent with `run: inline` produces the role file and no `.claude/agents/<agent-id>.md` / `.cursor/agents/<agent-id>.md`. Agents with `run: subagent` (the default) are unchanged.

### Role files

A role file has no frontmatter. Its first line is the generated-by marker. It then holds the agent's `instructions`, the tools it uses, its `inputs` and `outputs` under `<workdir>/<run-id>/`, and the report protocol of **Agent reports**. It is a reference file of the orchestrator skill, not a skill and not a command.

### Generated-by marker

Every generated file carries, on the first line after its frontmatter, exactly:

```text
<!-- generated by agent-composer from .agent-composer/<name>.crew.yaml — edit the spec and re-run; manual edits are detected -->
```

Replace `<name>` with the crew `name`. Templates and the validator use this text verbatim. In a file without frontmatter (a role file) the marker is the first line.

### Tier to model mapping

| Agent `tier` | Claude Code | Cursor |
| --- | --- | --- |
| `inherit` | `model: inherit` | `model: inherit` |
| `frontier`, `light`, `fast` | ID from `models.claude-code.<tier>` | ID from `models.cursor.<tier>` |

A Claude Code agent file without `model:` is **T004** (missing frontmatter key). Tree validation **T007** checks that `model` matches the spec tier mapping for every tier, including `inherit`.

Concrete per-harness frontmatter key sets are defined in [claude-code.md](claude-code.md) and [cursor.md](cursor.md); this document links to them and does not duplicate them.

Use placeholders such as `<frontier-model-id>` in specs and docs; verify live model IDs at generation time and record optional `verified` metadata on the `models` map.

## Manifest format

Path: `.agent-composer/<name>.manifest.json`

| Field | Type | Description |
| --- | --- | --- |
| `schema` | integer | Must be `1`. |
| `crew` | string | Crew `name`. |
| `generator` | string | `agent-composer <version>` (space-separated). |
| `spec_sha256` | string | SHA-256 of the spec file bytes. |
| `harnesses` | list | Harness ids from the spec. |
| `files` | map | Repo-relative generated path → sha256 of file bytes. The spec file itself is not listed in `files`. |
