---
name: orchestration-advisor
description: "Inspect a project and its workload and recommend an agent orchestration shape: a single agent plus skills, generator-verifier, orchestrator-subagent, agent teams, message bus, or shared state. Read-only: it counts harness folders, agents, skills, MCP servers, tests and CI, asks six workload questions, and writes a report with evidence, ruled-out shapes, a cost note, and a next step. Use when you ask which orchestration pattern fits, do I need multiple agents, single agent or multi-agent, should I add subagents, should I use agent-kit or agent-composer, or audit my subagents for overlap before adding or removing agents."
license: MIT
metadata:
  version: "0.1.0"
---

# Orchestration Advisor

Inspects a project, asks about the workload, and recommends one orchestration shape with the evidence behind it, the shapes it ruled out, and the next step.

**Read-only.** This skill creates or changes no file in the user's project. The one exception: it saves its report to a file when the user asks for that. It installs nothing and generates no agents.

**About the figures.** Every number below names its source and that source's date. These figures move as models improve. They are guidance for a recommendation, not pass/fail rules, and none of them was measured by this skill or its authors.

## When to use

- You are starting agent work on a project and want to know whether one agent is enough.
- You ask "which orchestration pattern", "do I need multiple agents", or "single agent or multi-agent".
- You already have subagents or a crew and want them audited for overlap, or want to know whether to fold some back into the main agent.
- You are choosing between `agent-kit`, `agent-composer`, and installing nothing.

## When not to use

- You already have a router-plus-subagents system **and** an eval for it, and you want measured fold-in work. Use Anthropic's [`single-agent-loop-kit`](https://github.com/anthropics/single-agent-loop-kit) instead. It is a reference implementation; its README describes it as not maintained (checked 2026-11-10), so read it as a worked method, not a supported tool.
- You have already decided on the shape and want it built. Go straight to `agent-kit` (evaluator-gated feature work) or `agent-composer` (custom roles).
- You want a measured answer. This skill triages from signals and answers; only an eval on your own tasks decides (see "How to check this" in the report).

## Requirements

- **bash** for [scripts/inspect.sh](scripts/inspect.sh). The script needs `find`, `awk`, `sort`, `wc` and `tr` on `PATH`. `git` and `jq` are optional; without them two keys report `unknown`. When bash or one of the required tools is unavailable, use the manual fallback in Step 2.
- In commands below, **`<skill-dir>`** is the directory containing this `SKILL.md`, and **`<project-root>`** is the root of the user's project.

## Step 1 — Detect

1. Find which harness folders exist at the project root: `.claude/` or `CLAUDE.md` (Claude Code), `.cursor/` (Cursor), `.github/copilot-instructions.md` or `.github/agents/` (GitHub Copilot), `.codex/` or `AGENTS.md` (Codex; `AGENTS.md` alone is weak evidence because several harnesses read it).
2. List what already exists, by name:
   - Agents: files directly inside `.claude/agents/`, `.cursor/agents/`, `.github/agents/`, `.codex/agents/`.
   - Skills: folders containing `SKILL.md` under `.claude/skills/`, `.cursor/skills/`, `.github/skills/`, `.agents/skills/`, `.codex/skills/`.
   - MCP configuration: `.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`.
   - Existing orchestration: `orchestration-kit.manifest.json` (an `agent-kit` install) and `.agent-composer/*.crew.yaml` (`agent-composer` crews).
3. For each existing agent, read its description and note two things for Step 4: whether its description overlaps another agent's, and whether it only carries knowledge (no distinct tools, model tier, or isolation need).

Tell the user what you found before going on.

## Step 2 — Inspect

Run:

```bash
bash <skill-dir>/scripts/inspect.sh <project-root>
```

It prints one `key=value` line per signal and changes nothing. The argument is optional and defaults to the current directory; this skill passes it explicitly. Read the lines per [references/signals.md](references/signals.md), which defines every key, how it is computed, how it bears on the decision, and its known undercounts. Exit code 1 means the description text could not be counted; in that case use the manual fallback below. Exit code 2 means the argument was not an existing directory or more than one argument was given. Exit code 3 means a required tool (`find`, `awk`, `sort`, `wc` or `tr`) is missing; in that case use the manual fallback below.

A value of `unknown` means the signal could not be computed. Report it as unknown; do not guess a number.

**Manual fallback (no bash, or exit code 1 or 3).** Count by hand, using the definitions in [references/signals.md](references/signals.md):

- Which of the four harnesses are present (Step 1 already did this).
- Whether `orchestration-kit.manifest.json` exists, and how many `.agent-composer/*.crew.yaml` files exist.
- Distinct agent names across the four agent folders (the same name in two harness folders counts once).
- For Claude Code only: the `.md` files in `.claude/agents/` and the total length of their `description:` values, divided by 4 for a token estimate.
- Distinct skill names across the five skill roots.
- Server entries in the three MCP configuration files.
- Test directories near the root, CI workflow files, lint and type-check configuration files at the root, and package manifests.

Say in the report that the signals were counted by hand.

## Step 3 — Ask about the workload

The repository cannot answer these. Ask one round at a time, multiple-choice where possible, and wait for each answer:

1. **Is the work one-off or recurring?** (one-off / recurring / both)
2. **Can it split into units with disjoint files and their own tests?** (yes / no / not sure) If yes, which units?
3. **Does each step need what the previous step discovered?** (yes, steps build on each other / no, steps are independent / mixed)
4. **Is there an executable acceptance check, and how long does it run?** (none / seconds / minutes / longer)
5. **Do events or people start the work?** (a person asks / an event such as a webhook, schedule or queue triggers it / both)
6. **What cost multiple over a single agent is acceptable?** (none / a few times / cost is not the constraint)

Skip a question only when the user already answered it. Record each answer; the report's Evidence section lists them.

## Step 4 — Decide

### The default

**The default recommendation is a single agent plus skills.** Put project knowledge and procedures into skills and keep one agent loop.

Any other shape needs **at least one** of these four reasons, and each reason you rely on must be backed by a signal value from Step 2 or a workload answer from Step 3:

| Reason | What backs it |
| --- | --- |
| **Context pollution** — a subtask produces large output the main agent does not need afterwards | Workload answer 3 says steps are independent, plus a named subtask with noisy output (searches, logs, long test runs) |
| **Independent parallel units** — units that do not share files and can be checked separately | Workload answer 2 is yes with named units; `package_manifests` and `test_paths` point the same way (direction only, see signals.md) |
| **Tool or prompt conflict** — two jobs need tool sets or instructions that interfere with each other | A named pair of conflicting tool sets or instructions; `mcp_servers` shows how much tooling is loaded (a proxy, not a tool count) |
| **Need for an independent verifier** — the result must be judged by something that did not produce it | Workload answer 4 says there is an acceptance check, or the user needs review the author cannot give itself; `test_paths`, `ci_workflows`, `lint_configs` and `typecheck_configs` show what can be checked by a command |

If none of the four holds, recommend the default and stop looking for a reason.

### What is not a reason

- **A split by type of work is not a reason.** Separate plan, build, test and review agents are phases of the same work; each handoff loses context the next phase needs. Workload answer 3 ("each step needs what the previous step discovered") argues against splitting.
- **A separate test author helps only when it works from the spec without reading the implementation.** One study found independent tests detected 25% of faults against 14% for tests written after seeing faulty code (arXiv 2607.05139, 2026-07-06). A test agent that reads the implementation first pays the handoff cost without that independence.
- **A code-ownership file is not a reason.** Agents mirroring an org chart are a known failure mode; treat such a file as a warning sign.
- **Repository size, coupling and package count** have no validated metric. Use them for direction only.

### Reading two signals correctly

- **`claude_agent_description_tokens_est`** is compared with one thing only: Claude Code's 15,000-token warning for combined custom subagent descriptions (Claude Code subagents documentation, checked 2026-11-10). It is a rough estimate (characters divided by 4, an approximation and not a tokenizer count). Do not compare it with any other limit or apply it to another harness.
- **`agent_files`** counts distinct agents, not files. A project that mirrors the same agents into two harness folders has that many agents once, not twice.

### Existing agents

When Step 1 found agents whose descriptions overlap, or agents that only carry knowledge, recommend folding them: move the knowledge into skills and keep the agents that have one of the four reasons. This holds even when the overall recommendation stays multi-agent.

### The six shapes

Pick one. [references/patterns.md](references/patterns.md) has the table: when to use and avoid each, the codebase and workload signals, the main failure mode, and harness support.

1. **Single agent plus skills** — the default.
2. **Generator-verifier** — one agent produces, an independent one judges against explicit criteria.
3. **Orchestrator-subagent** — a lead agent delegates bounded subtasks to fresh-context subagents and combines the results.
4. **Agent teams** — long-running peer agents that work independent units in parallel and coordinate among themselves.
5. **Message bus** — agents react to published events; nothing schedules them centrally.
6. **Shared state** — agents read and write a common store and build on each other's findings without a coordinator.

### From recommendation to next step

| Recommendation | Next step |
| --- | --- |
| Single agent plus skills | Install nothing. Move knowledge and procedures into skills. |
| Evaluator-gated feature work on a codebase (generator-verifier with an orchestrator) | Install [`agent-kit`](https://github.com/kdcllc/skills/tree/master/skills/agent-kit): `npx skills add kdcllc/skills --skill agent-kit`. It compiles for Claude Code, Cursor, GitHub Copilot and Codex (per its own SKILL.md). |
| Custom roles (generator-verifier or orchestrator-subagent with roles you define) | Use [`agent-composer`](https://github.com/kdcllc/skills/tree/master/skills/agent-composer) and name one of its five patterns: `pipeline`, `router`, `fan-out`, `evaluator-optimizer`, `orchestrator-workers`. It generates for Claude Code and Cursor (per its own SKILL.md). The mapping from shapes to these patterns is in [references/patterns.md](references/patterns.md). |
| Overlapping or knowledge-only existing agents | Fold them into skills. For the measured method, point to [`single-agent-loop-kit`](https://github.com/anthropics/single-agent-loop-kit) (reference implementation, not maintained per its README, checked 2026-11-10). |
| Agent teams | A Claude Code feature that is experimental and disabled by default (per Anthropic's Claude Code agent teams documentation, accessed 2026-11-10; see `[9]` in the Sources of [references/patterns.md](references/patterns.md)). Neither `agent-kit` nor `agent-composer` generates it. |
| Message bus or shared state | Not native in Claude Code, Cursor, GitHub Copilot or Codex (`inferred`: no documentation found, none of the four was checked exhaustively). It needs glue the user writes. |

## Step 5 — Report

Give the report in chat. Save it to a file only when the user asks. Use exactly these headings, in this order:

```markdown
## Recommendation
## Evidence
## Ruled out
## Harness notes
## Cost note
## Next step
## How to check this
```

- **Recommendation** — one shape, named as in the list above, in one or two sentences. When the default applies, say so plainly.
- **Evidence** — the signal values and the workload answers you used, each on its own line (`agent_files=7`, "Q2: yes — api and web packages"). Include `unknown` values and say when signals were counted by hand. For any non-default shape, name which of the four reasons applies and which line backs it.
- **Ruled out** — one line per shape not recommended, with the reason it does not fit here.
- **Harness notes** — what the detected harnesses support for the recommended shape, from [references/patterns.md](references/patterns.md). Keep its `inferred` and `not checked` marks; do not restate an unchecked claim as fact. When today's date is after the re-check date given in `references/patterns.md`, say in the report that the harness statements may be out of date.
- **Cost note** — Anthropic reports multi-agent runs use roughly 3–10x the tokens of a single agent for equivalent tasks (Anthropic, "Building multi-agent systems: when and how to use them", 2026-01-23). Set that against workload answer 6. For the default shape, say no multiple applies.
- **Next step** — the matching row of the routing table.
- **How to check this** — a small experiment the user can run: pick about 10 representative tasks (the starting size Anthropic gives in "When to fold subagents into your main agent loop", 2026-10-22), run each more than once on the current setup and on the recommended one, and compare task completion, tokens and wall time. Change one thing at a time and look at which tasks flipped. This recommendation is triage; the experiment decides.

## Quality checklist

- [ ] No file in the user's project was created or changed (other than a report the user asked to save).
- [ ] All six workload questions were asked or already answered.
- [ ] A non-default recommendation names at least one of the four reasons, each backed by a signal value or a workload answer.
- [ ] No recommendation rests on a split by type of work.
- [ ] `claude_agent_description_tokens_est` was compared only with Claude Code's 15,000-token warning.
- [ ] The report has the seven headings in order, one "Ruled out" line per other shape, and every figure with its source and date.
- [ ] Harness statements keep their `inferred` and `not checked` marks.
