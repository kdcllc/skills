---
name: orchestration-advisor
description: "Inspect a project and its workload and either recommend an agent orchestration shape (a single agent plus skills by default, or generator-verifier, orchestrator-subagent, agent teams, message bus, shared state) or audit an existing orchestration system, hooks and other enforcers included, and produce a current-vs-recommended comparison. Read-only: it counts harness folders, agents, skills, hooks, rules, MCP servers, tests and CI, asks six workload questions, and reports evidence, a cost note, and a next step. Use when you ask which orchestration pattern fits, do I need multiple agents, should I add subagents, agent-kit or agent-composer, or audit my agents, orchestrators or hooks for overlap."
license: MIT
metadata:
  version: "0.3.0"
---

# Orchestration Advisor

Inspects a project and asks about the workload. It runs in one of two modes. **Design mode** recommends one orchestration shape for a project with little or no orchestration, with the evidence behind it, the shapes it ruled out, and the next step. **Audit mode** reviews an existing orchestration system: it maps each system, accounts for what enforces each gate, and produces a current-vs-recommended comparison.

**Read-only.** This skill creates or changes no file in the user's project. The one exception: it saves its report to a file when the user asks for that. It installs nothing and generates no agents.

**About the figures.** Every number below names its source and that source's date. These figures move as models improve. They are guidance for a recommendation, not pass/fail rules, and none of them was measured by this skill or its authors.

## When to use

- **Design mode:** you are starting agent work on a project with little or no orchestration and want to know whether one agent is enough.
- **Audit mode:** the project already has an orchestration system (agents, an `agent-kit` install, crews, orchestrator skills, hooks) and you want it reviewed: what each flow does, what enforces its gates, and what to change or leave alone.
- You ask "which orchestration pattern", "do I need multiple agents", or "single agent or multi-agent".
- You already have subagents or a crew and want them audited for overlap, or want to know whether to fold some back into the main agent.
- You are choosing between `agent-kit`, `agent-composer`, and installing nothing.

## When not to use

- You already have a router-plus-subagents system **and** an eval for it, and you want measured fold-in work. Use Anthropic's [`single-agent-loop-kit`](https://github.com/anthropics/single-agent-loop-kit) instead. It is a reference implementation; its README describes it as not maintained (checked 2026-11-10), so read it as a worked method, not a supported tool.
- You have already decided on the shape and want it built. Go straight to `agent-kit` (evaluator-gated feature work) or `agent-composer` (custom roles).
- You want a measured answer. This skill triages from signals and answers; only an eval on your own tasks decides (see "How to check this" in the report).

## Requirements

- **bash** for [scripts/inspect.sh](scripts/inspect.sh). The script needs `find`, `awk`, `sort`, `wc` and `tr` on `PATH`. `git` and `jq` are optional; without them three keys (`mcp_servers`, `tracked_files`, `harness_hook_entries`) can report `unknown`. When bash or one of the required tools is unavailable, use the manual fallback in Step 2.
- In commands below, **`<skill-dir>`** is the directory containing this `SKILL.md`, and **`<project-root>`** is the root of the user's project.

## Step 1 — Detect

1. Find which harness folders exist at the project root: `.claude/` or `CLAUDE.md` (Claude Code), `.cursor/` (Cursor), `.github/copilot-instructions.md` or `.github/agents/` (GitHub Copilot), `.codex/` or `AGENTS.md` (Codex; `AGENTS.md` alone is weak evidence because several harnesses read it).
2. List what already exists, by name:
   - Agents: files directly inside `.claude/agents/`, `.cursor/agents/`, `.github/agents/`, `.codex/agents/`.
   - Skills: folders containing `SKILL.md` under `.claude/skills/`, `.cursor/skills/`, `.github/skills/`, `.agents/skills/`, `.codex/skills/`.
   - MCP configuration: `.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`.
   - Existing orchestration: `orchestration-kit.manifest.json` (an `agent-kit` install) and `.agent-composer/*.crew.yaml` (`agent-composer` crews).
   - Hook configs: `.claude/settings.json`, `.claude/settings.local.json`, `.cursor/hooks.json`.
   - Git hooks: `.git/hooks`, `.husky/`, lefthook and pre-commit configs.
   - Rules: `.cursor/rules/`, `.claude/rules/`, `.github/instructions/`.
   - Rubric or criteria folders.
   - Command and prompt files: `.claude/commands/`, `.cursor/commands/`, `.github/prompts/`.
   - Other harness config files (model routing, Codex config).
   - Entry-point skills that launch agents, and the state folders those entry points read and write (found by reading them).
3. For each existing agent, read its description and note two things for Step 5: whether its description overlaps another agent's, and whether it only carries knowledge (no distinct tools, model tier, or isolation need).

Tell the user what you found before going on. This step does not choose a mode; Step 2 asks.

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
- The seven enforcement and orchestration signals (`harness_hook_entries`, `git_hook_files`, `rule_files`, `rubric_files`, `command_files`, `harness_config_files`, `orchestrator_skills`), counted per their definitions in signals.md. `orchestrator_skills` leaves out this skill itself.
- Test directories near the root, CI workflow files, lint and type-check configuration files at the root, and package manifests.

Say in the report that the signals were counted by hand.

**Ask the mode question.** Once the signals are known, ask the user one question and wait for the answer: "Recommend a setup, or audit the existing one?" Pre-select the suggested answer: **audit** when `agent_files` > 0, `agent_kit_installed` = 1, `composer_crews` > 0 or `orchestrator_skills` > 0; otherwise **design**. Show those four values as the reason. The signals are evidence, not the decider; the user's answer is. With plain project subagents and no orchestrator skill or command, audit mode treats the main session that delegates to them as the entry point of one system. The chosen mode and the values behind the suggestion go in the report.

## Step 3 — Ask about the workload

The repository cannot answer these. Ask one round at a time, multiple-choice where possible, and wait for each answer:

1. **Is the work one-off or recurring?** (one-off / recurring / both)
2. **Can it split into units with disjoint files and their own tests?** (yes / no / not sure) If yes, which units?
3. **Does each step need what the previous step discovered?** (yes, steps build on each other / no, steps are independent / mixed)
4. **Is there an executable acceptance check, and how long does it run?** (none / seconds / minutes / longer)
5. **Do events or people start the work?** (a person asks / an event such as a webhook, schedule or queue triggers it / both)
6. **What cost multiple over a single agent is acceptable?** (none / a few times / cost is not the constraint)

Skip a question only when the user already answered it. In audit mode, ask per system when the answers differ between systems. Record each answer; the report lists them.

## Step 4 — Map

Audit mode only; design mode skips this step. Follow [references/audit.md](references/audit.md) for the procedure. In short:

- Find each separate orchestration system and its entry point.
- Detect tiers by pattern: a system whose workers are themselves orchestration systems is a higher tier. Map it at its boundary only (what it launches, what it gates) and keep it as its own system.
- For each system record the phases, the gates, the agents with their role per flow, the shared state, and the loop control (cycle or stuck rules).
- For each gate record its enforcer: hooks, rubrics, CI, model routing, git hooks, cycle or stuck rules, or "prompt-only" when nothing but the prompt enforces it.
- Describe each system as a composition of shapes, not one label.
- On large systems, when the harness supports subagents, launch one read-only subagent per system to build its map section, then merge the results (per audit.md).

## Step 5 — Decide

**Design mode: everything below in this step. Audit mode: skip to the last subsection and apply [references/audit.md](references/audit.md) § Decide.**

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

### Audit mode

Apply these six rules; [references/audit.md](references/audit.md) § Decide has the full text of each.

- **Shapes compose.** A system is a composition of shapes; a shape already in use is never listed as ruled out or proposed as new.
- **Tier rule.** Never change a higher tier, or fold, merge or re-architect across a tier boundary, unless the user opts in.
- **Per-flow overlap.** Two agents overlap only when the same flow launches them for the same job; judge it from the map, not from descriptions.
- **Enforcer rule.** Every suggested change names the enforcer that covers the affected gate afterwards; when none does, the change cannot be recommended.
- **Honesty rule.** When no material change is found, the headline says the current design fits and lists the small fixes; a fold of one or two agents is never the headline unless it is the only material change and is labeled as small.
- **Material change.** A suggestion is material only when it fixes a failure the owner can see (gate escapes, loops that do not converge, cost, context lost at handoffs, rules enforced only by prompt) and names that failure with evidence; "fewer agents" or "cleaner design" is not a failure.

## Step 6 — Report

**Design mode.** Give the report in chat. Save it to a file only when the user asks. Use exactly these headings, in this order:

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

**Audit mode.** Chat gets the short summary defined in [references/report-audit.md](references/report-audit.md) (headline, top suggestions, what was left alone), followed by an offer to save the full report as a markdown file. Write nothing without the user's yes. The full report's structure is in report-audit.md.

## Quality checklist

- [ ] No file in the user's project was created or changed (other than a report the user asked to save).
- [ ] The mode question was asked and answered, with the suggested answer and its signal values shown.
- [ ] All six workload questions were asked or already answered.
- [ ] Design mode: a non-default recommendation names at least one of the four reasons, each backed by a signal value or a workload answer.
- [ ] Design mode: no recommendation rests on a split by type of work.
- [ ] `claude_agent_description_tokens_est` was compared only with Claude Code's 15,000-token warning.
- [ ] Design mode: the report has the seven headings in order, one "Ruled out" line per other shape, and every figure with its source and date.
- [ ] Harness statements keep their `inferred` and `not checked` marks.
- [ ] Audit mode: each system was mapped separately.
- [ ] Audit mode: every gate has a named enforcer or is marked prompt-only.
- [ ] Audit mode: higher tiers were mapped at the boundary only and not changed without opt-in.
- [ ] Audit mode: no shape already in use is listed as ruled out or proposed as new.
- [ ] Audit mode: every suggestion names its enforcer, evidence, effort and risk.
- [ ] Audit mode: the Honesty rule was applied.
- [ ] Audit mode: hook configs counted by Step 2 appear in the map.
