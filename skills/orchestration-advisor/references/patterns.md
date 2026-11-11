# Orchestration shapes

The six shapes [../SKILL.md](../SKILL.md) Step 4 chooses between. Signal names are defined in [signals.md](signals.md); "Q1" to "Q6" are the workload questions in SKILL.md Step 3.

Figures move as models improve; they are guidance, not pass/fail rules. Bracketed numbers refer to Sources at the end.

## Marks used for harness statements

Every statement about what a harness supports carries one of these:

- **matrix** — backed by agent-kit's harness capability matrix, [`skills/agent-kit/reference/harness-matrix.md`](https://github.com/kdcllc/skills/blob/master/skills/agent-kit/reference/harness-matrix.md), with the date that file gives for the row.
- **[n]** — backed by the numbered entry in Sources.
- `inferred` — no documentation was found either way; a conclusion, not a checked fact.
- `not checked` — a claim exists but was not verified against a live page.

## The six shapes

Harness support is as of 2026-11-10.

| Shape | Use when | Avoid when | Codebase signals | Workload signals | Main failure mode | Harness support (2026-11-10) |
| --- | --- | --- | --- | --- | --- | --- |
| **Single agent plus skills** | The default. None of the four reasons in SKILL.md Step 4 holds | One of the four reasons clearly holds and is backed by a signal or an answer | Any. Overlapping or knowledge-only agents (read from the `agent_files` set) point back here; `skill_files` shows knowledge already in skills | Q3: each step needs what the previous one discovered. Q6: no cost multiple acceptable | The context fills with output from noisy subtasks; conflicting instructions pile up in one prompt | Skills: Claude Code, Cursor, GitHub Copilot — matrix (Skills row, verified 2026-08-18; Copilot 2026-08-20). Codex: per-skill enablement via `skills.config` — matrix (spot-verified 2026-08-18) |
| **Generator-verifier** | The result needs a judge that did not produce it, and "pass" can be written as explicit criteria or a command | No acceptance criteria exist; or the verifier would see the same context and reasoning as the generator | `test_paths`, `ci_workflows`, `lint_configs`, `typecheck_configs` above 0: something can be checked by a command. `agent_kit_installed=1`: already in place | Q4: an executable check exists, ideally fast. Q1: recurring | The verifier is only as good as its criteria; the loop repeats without converging unless it has a cycle limit | Needs fresh-context subagents: Claude Code, Cursor, GitHub Copilot — matrix (Fresh-context subagents row, verified 2026-08-18); Codex — matrix (spot-verified 2026-08-18). `agent-kit` emits this for all four; `agent-composer` for Claude Code and Cursor (each per its own SKILL.md) |
| **Orchestrator-subagent** | Bounded subtasks whose output the lead needs only as a summary (context pollution), or independent units that can run in parallel | Each step needs the previous step's discoveries; or the split is by type of work (plan, build, test, review) | `package_manifests` above 1 and several `test_paths`: possible separable units (direction only) | Q2: yes, with named units. Q3: steps are independent. Q6: a few times the cost is acceptable | The lead becomes a bottleneck and detail is lost at each handoff; subagents sharing a checkout overwrite each other's edits | Fresh-context subagents: all four — matrix (as above). Running them in parallel: Claude Code, default limit 20 running at once — matrix (Concurrent subagent spawns row, spot-checked 2026-10-16) and [7]; Cursor — matrix (same row, spot-checked 2026-10-16) and [8]. GitHub Copilot parallel subagents: `not checked`. Codex concurrency: `not checked` |
| **Agent teams** | Several long, independent units of work that benefit from peers coordinating directly, and cost is not the constraint | Units share files; work is short; or the harness is not Claude Code | Clearly separate packages with their own tests (direction only; no validated metric) | Q2: yes. Q1: recurring or long-running. Q6: cost is not the constraint | Coordination overhead; conflicting edits when the units turn out not to be independent | Claude Code: experimental and disabled by default (Source 9, accessed 2026-11-10). Cursor, GitHub Copilot, Codex: no native equivalent — `inferred`. Neither `agent-kit` nor `agent-composer` generates it |
| **Message bus** | Events start the work, the set of handlers grows over time, and no single agent should schedule the rest | A person starts each task and waits for the answer; or the flow is a fixed sequence | None in the repository; this is decided by the workload | Q5: events trigger the work. Q1: recurring | Hard to trace what happened; a misrouted or dropped event fails silently | Native in none of Claude Code, Cursor, GitHub Copilot, Codex — `inferred`. Needs glue the user writes (a queue or event router outside the harness) |
| **Shared state** | Agents build on each other's findings over a long run and no coordinator should sit in the middle | The work has a clear sequence or a natural lead; or there is no stop condition | None in the repository; this is decided by the workload | Q3: agents need each other's findings continuously, not in order. Q6: cost is not the constraint | Duplicate work and agents reacting to each other without end; needs an explicit termination condition | Native in none of Claude Code, Cursor, GitHub Copilot, Codex — `inferred`. Needs glue the user writes (a store and a convention for reading and writing it) |

Cost applies to every row but the first: Anthropic reports multi-agent runs use roughly 3–10x the tokens of a single agent for equivalent tasks ([3], 2026-01-23).

Two points hold across the table:

- A split by type of work is the documented anti-pattern ([3], 2026-01-23; [2], 2026-10-22). It is not a reason for any row.
- A separate test author is a case of generator-verifier only when it works from the spec without the implementation in context: one study found 25% fault detection for independent tests against 14% for tests written after seeing faulty code ([5], 2026-07-06).

## agent-composer patterns mapped onto the shapes

`agent-composer` generates crews in five patterns. All five are forms of the second and third shapes; none produces agent teams, a message bus or shared state.

| `agent-composer` pattern | Shape | Note |
| --- | --- | --- |
| `pipeline` | Orchestrator-subagent, run in sequence | When the stages are phases of the same work (plan, build, test, review), the better answer is usually a single agent plus skills |
| `router` | Orchestrator-subagent | A classifier step picks one specialist. Justified by tool or prompt conflict between the specialists |
| `fan-out` | Orchestrator-subagent, run in parallel | Justified by independent parallel units; a later step merges the results |
| `evaluator-optimizer` | Generator-verifier | A producer and an evaluator with a gate and a cycle limit |
| `orchestrator-workers` | Orchestrator-subagent | A planner writes a task list and the orchestrator dispatches workers; tasks with disjoint outputs may run in parallel |

`agent-kit` is a fixed generator-verifier system with an orchestrator: workers execute and evaluators gate each step.

## Sources

1. [Multi-agent coordination patterns](https://claude.com/resources/articles/multi-agent-coordination-patterns) — Anthropic, published 2026-04-10
2. [When to fold subagents into your main agent loop](https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop) — Anthropic, published 2026-10-22
3. [Building multi-agent systems: when and how to use them](https://claude.com/resources/articles/building-multi-agent-systems-when-and-how-to-use-them) — Anthropic, published 2026-01-23
4. [Building agents with skills](https://claude.com/resources/articles/building-agents-with-skills-equipping-agents-for-specialized-work) — Anthropic, published 2026-01-22
5. [On the risk of coding before testing](https://arxiv.org/abs/2607.05139) (arXiv 2607.05139) — Konstantinou, Tambon, Papadakis; arXiv, published 2026-07-06
6. [anthropics/single-agent-loop-kit](https://github.com/anthropics/single-agent-loop-kit) — Anthropic (GitHub), accessed 2026-11-10. A reference implementation; its README describes it as not maintained
7. [Claude Code subagents](https://code.claude.com/docs/en/sub-agents) — Anthropic (Claude Code documentation), accessed 2026-11-10
8. [Cursor subagents](https://cursor.com/docs/subagents) — Cursor (documentation), accessed 2026-11-10
9. [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams) — Anthropic (Claude Code documentation), accessed 2026-11-10
