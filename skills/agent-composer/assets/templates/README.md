# Generation templates

Fill these templates when generating a crew from `.agent-composer/<name>.crew.yaml`. Substitute every token listed below and keep or delete each optional block (see **Block ids**). Generated files must contain **no** remaining `{{` tokens and **no** lines that start with `<!-- block:` or `<!-- /block:` — those delimiters are stripped during generation.

## Tokens

| Token | Source | Templates |
| --- | --- | --- |
| `{{agent_id}}` | Agent `id` | claude-agent.md.tmpl, cursor-agent.md.tmpl |
| `{{agent_description}}` | Agent `description`, emitted inside double quotes with `\` and `"` escaped | claude-agent.md.tmpl, cursor-agent.md.tmpl |
| `{{claude_tools}}` | Agent `tools` mapped to comma-separated Claude Code tool names | claude-agent.md.tmpl |
| `{{claude_model}}` | Agent `tier` → `models.claude-code.<tier>` or `inherit` | claude-agent.md.tmpl |
| `{{cursor_model}}` | Agent `tier` → unquoted `models.cursor.<tier>` or `inherit` | cursor-agent.md.tmpl |
| `{{instructions}}` | Agent `instructions` (role-prompt body) | claude-agent.md.tmpl, cursor-agent.md.tmpl |
| `{{crew_name}}` | Spec `name` | all `.tmpl` files |
| `{{step_id}}` | Step `id` for this agent's scheduled step | claude-agent.md.tmpl, cursor-agent.md.tmpl |
| `{{workdir}}` | Spec `workdir` (default `_crew/<name>`) | orchestrator-skill.md.tmpl; referenced in agent bodies |
| `{{max_dispatch_tasks}}` | Step `dispatch.max_tasks` for the planner step | claude-agent.md.tmpl, cursor-agent.md.tmpl (planner block only) |
| `{{crew_description}}` | Spec `description`, emitted inside double quotes with `\` and `"` escaped | orchestrator-skill.md.tmpl |
| `{{on_exhaustion}}` | Spec `on_exhaustion` (`ask-user` or `stop`) | orchestrator-skill.md.tmpl |
| `{{root_inputs}}` | Comma-separated backticked root-input file names per [spec-schema.md](../../references/spec-schema.md) **Root inputs** (inputs never listed in any agent's `outputs`; `tasks.yaml` excluded), or the literal `none` when there are none | orchestrator-skill.md.tmpl |
| `{{steps_procedure}}` | Generated per-step procedure (see **{{steps_procedure}} outline** below) | orchestrator-skill.md.tmpl |

## {{steps_procedure}} outline

Emit a numbered list with **one entry per step** in topological order of `needs` (ties broken by spec order). Each entry must name:

- the step `id`
- its agent id, or `parallel` member ids, or the dispatch planner and `dispatch.workers`
- `needs` (or `none`)
- input files and output files under `<workdir>/<run-id>/` (from the scheduled agent(s)' `inputs` / `outputs`)
- the report path (single-agent, parallel per-member, or dispatch per-task form)
- when present: the gate (`on_fail`, `max_cycles`), the `routes` map, or `dispatch.max_tasks`

### Worked example (`content-crew.crew.yaml`)

1. **`research`** — agent `researcher`; needs `none`; inputs `<workdir>/<run-id>/topic.md`; outputs `<workdir>/<run-id>/notes.md`; report `<workdir>/<run-id>/research.report.md`.
2. **`draft`** — agent `writer`; needs `research`; inputs `<workdir>/<run-id>/notes.md`, `<workdir>/<run-id>/topic.md`; outputs `<workdir>/<run-id>/draft.md`; report `<workdir>/<run-id>/draft.report.md`.
3. **`fact-check`** — agent `fact-checker`; needs `draft`; inputs `<workdir>/<run-id>/notes.md`, `<workdir>/<run-id>/draft.md`; outputs none; report `<workdir>/<run-id>/fact-check.report.md`; gate `on_fail: draft`, `max_cycles: 3`.

(`topic.md` is the only root input — listed in agent `inputs` but not in any agent `outputs`.)

## Block ids

Optional sections use HTML comment delimiters in the template sources only. The generator **keeps** a block (and removes the delimiter lines) when the condition holds; otherwise it deletes the whole block including delimiters.

| Block id | Keep when | Templates |
| --- | --- | --- |
| `disable_model_invocation` | Spec `invocation` is `manual` (default) | orchestrator-skill.md.tmpl |
| `readonly` | Agent `tools` lists neither `edit` nor `shell` | cursor-agent.md.tmpl |
| `shell_without_edit` | Agent has `shell` but not `edit` | cursor-agent.md.tmpl |
| `no_edit` | Agent `tools` omits `edit` | claude-agent.md.tmpl, cursor-agent.md.tmpl |
| `router` | Agent templates: agent `kind` is `router`. orchestrator-skill.md.tmpl: spec `pattern` is `router` | claude-agent.md.tmpl, cursor-agent.md.tmpl, orchestrator-skill.md.tmpl (pattern notes) |
| `routes` | Any step declares `routes` | orchestrator-skill.md.tmpl (step-scheduling skip clause, agent-report `ROUTE:` read, router steps protocol) |
| `evaluator` | Agent templates: agent `kind` is `evaluator`. orchestrator-skill.md.tmpl: any step declares `gate` | claude-agent.md.tmpl, cursor-agent.md.tmpl, orchestrator-skill.md.tmpl |
| `planner` | Agent `kind` is `planner` | claude-agent.md.tmpl, cursor-agent.md.tmpl |
| `parallel` | Any step declares `parallel` | orchestrator-skill.md.tmpl |
| `dispatch` | Any step declares `dispatch` | orchestrator-skill.md.tmpl |
| `pipeline` | Spec `pattern` is `pipeline` | orchestrator-skill.md.tmpl |
| `fan-out` | Spec `pattern` is `fan-out` | orchestrator-skill.md.tmpl |
| `evaluator-optimizer` | Spec `pattern` is `evaluator-optimizer` | orchestrator-skill.md.tmpl |
| `orchestrator-workers` | Spec `pattern` is `orchestrator-workers` | orchestrator-skill.md.tmpl |

## Blank-line rule

After tokens are substituted and optional blocks are kept or removed, apply this rule to **every** generated file. A *blank line* is empty or whitespace-only; lines inside fenced code blocks are never changed.

1. Collapse every run of two or more blank lines to a single blank line.
2. Remove any blank line directly after the opening `---` of frontmatter and any blank line directly before the closing `---` of frontmatter.
3. End the file with exactly one newline.

## Generated-by marker

Immediately after frontmatter in every generated file, emit the generated-by marker exactly as defined in [spec-schema.md](../../references/spec-schema.md) (Generated-by marker section), with the crew `name` in place of `<name>`. Every `.tmpl` file embeds that line using the `{{crew_name}}` token.
