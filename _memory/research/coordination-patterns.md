---
title: "Research: Choosing an orchestration pattern from a codebase and a workload"
topic: coordination-patterns
date: 2026-11-10
status: shipped
recheck_by: 2027-02-10
goals: [orchestration-advisor]
supersedes: []
memory: [20261110T222412Z-9e7ce62d]
---

# Research: Choosing an orchestration pattern from a codebase and a workload

**Method**: two passes on 2026-11-10. Pass 1: the orchestrator read four Anthropic
articles through a summarizing fetch. Pass 2: an external deep-research report against a
19-question prompt, then an ingest review that spot-checked seven claims against live
pages and checked the rest against `skills/agent-kit/` and `skills/agent-composer/`.
Scratch: `_memory/work/research/coordination-patterns/` (`prompt.md`, `report.md`,
`report-pass1.md`, `review.md`).

**Legend**: ✅ documented by an official source · 📊 measured (by whom stated) ·
🔬 re-checked by the orchestrator on 2026-11-10 · 💬 community or search excerpt ·
🤔 inferred.

## Question

Do agent-kit or agent-composer gain anything from current guidance on multi-agent
coordination patterns, folding subagents into one loop, and skills? Is there room for a
skill that reads a codebase and a workload and recommends the orchestration shape?

## Load-bearing conclusions

- A single agent plus skills is the default across Anthropic, OpenAI and Cognition ✅.
  More agents need one concrete reason: context pollution, independent parallel units,
  tool or prompt conflict, or black-box verification.
- Anthropic reports multi-agent runs use roughly 3–10x the tokens of a single agent for
  equivalent tasks ✅ [3] (2026-01-23). Its ~15x figure is a different comparison, against
  chat.
- Splitting by type of work (plan / build / test / review) is the documented
  anti-pattern ✅. Anthropic reports one such experiment spent more tokens coordinating
  than working 📊 (Anthropic, no effect size).
- A separate test author helps only when it works from the spec without the
  implementation in context: 25% fault detection for independent tests against 14% for
  tests written after seeing faulty code 📊🔬 (arXiv 2607.05139). agent-kit's
  `test-writer` and agent-composer's `coding-crew` test-writer both read the
  implementation first, so they pay the handoff cost without the independence 🔬.
- Black-box verification is the best-supported multi-agent pattern, and agent-kit
  already implements it, including cross-family rotation.
- No tool with published results infers a topology from a repository 💬. The closest
  prior art is Anthropic's unmaintained `single-agent-loop-kit` 🔬 and the community
  skill `multi-agent-system-architect-v2` (not inspected).
- The only documented decision method is eval-first: about 10 golden tasks, change one
  thing, repeat runs, inspect which tasks flipped ✅. An advisor can triage; an eval
  decides.
- Thresholds are moving toward fewer agents ✅: tool-count guidance rose from 15–20+
  to 30–50 definitions with tool search, and stronger orchestrators evaluate subagent
  work directly.

## Per-question findings

Confidence: **high** = documented by an official source · **medium** = several
independent sources agree · **low** = inferred or single community source.

### Q1: Does agent-kit benefit?

The design is confirmed [1][3][5] — confidence: high. Candidates:

- **K1** `test-writer` reads the modules under test, so it is neither context-preserving
  nor independent 🔬. Options: fold it into `implementer`, or re-point it at the task
  spec. Evidence on which is better for this kit: none — confidence: low.
- **K2** no right-sizing gate before the seven phases. Sources favor a deterministic,
  logged rubric over an LLM classifier 🤔 — confidence: low.
- **K3** no outcome eval set. Starting size 10 tasks ✅; a 24-task, three-arm, three-run
  design is a screening experiment that hides differences under about 10 points 🤔.
- **K4** verifier additions with support: per-criterion structured verdicts (31.5%
  average reduction in judge self-preference, arXiv 2604.22891 📊, unchecked) and a
  "no new findings for N cycles" stop ✅ — confidence: medium.

### Q2: Does agent-composer benefit?

Yes [1][2][3][4] — confidence: medium.

- **C1** the role-first interview and the `coding-crew` example steer toward
  type-of-work crews 🔬.
- **C2** the crew-or-not test should require one of the four reasons and warn on
  pipelines whose stages are phases of the same work.
- **C3** emit a skill in place of an agent when a role has no distinct tools, tier or
  isolation need ✅. Contract-shaped procedures stay subagents (arXiv 2609.09233 📊,
  unchecked).
- **C4** agent teams are native only in Claude Code and experimental ✅💬; message bus
  and shared state are native nowhere 🤔. Document, do not generate.
- **C5** `on_exhaustion` has `ask-user` and `stop` 🔬; "best attempt with caveats" is
  missing. A warning as combined descriptions approach Claude Code's 15,000-token
  limit ✅🔬 is cheap to add.

### Q3: Is a codebase-driven recommender a separate need?

Yes — confidence: medium on need, low on signal validity.

- Supported signals ✅: overlapping agent descriptions, knowledge-only agents, tool
  counts against the 15–20+ and 30–50 bands, a fast executable acceptance check.
- Direction only, no validated metric 🤔: package independence, coupling, repo size.
- Warning only ✅: code-ownership files (org-chart architectures are a failure mode).
- Workload questions that map to a pattern 🤔: once or recurring; separable units with
  their own tests; whether each step needs the previous step's discoveries; an
  executable acceptance check and its run time; event- or person-triggered; acceptable
  cost multiple.

### Q4: What changed in the harnesses?

- Cursor: per-subagent worktrees or cloud environments on request ✅🔬. Conflicts with
  `harness-matrix.md`.
- Claude Code: 20 concurrent subagents and three nesting layers by default ✅🔬 (the
  report doubted the first; the matrix is right). `isolation: worktree` branches from
  the default branch, not the parent HEAD ✅🔬.
- Copilot: parallel subagents reported since VS Code 1.109 💬, unchecked.
- Codex: concurrency key name still uncertain 💬.

## Decisions

- **Adopted:** a read-only `orchestration-advisor` skill plus `agent-composer` guidance
  and example changes (goal `orchestration-advisor`); an agent-kit outcome eval set as
  the next goal. agent-kit candidates K1, K2 and K4 wait for that eval set.
- **Rejected:** hard-coded thresholds as pass/fail rules (they move with models);
  worktree isolation for ready groups as a simple switch (worktrees branch from the
  default branch); a `model_family` field in the crew spec (thin evidence for code);
  a three-agent cap for chat-style crews (the composer has no such pattern).

## Open questions

- Fold `test-writer`, or re-point it at the spec? Blocked on K3 or a user decision.
- Resolved 2026-11-10: a skills.sh search and a read of
  `multi-agent-system-architect-v2` found no skill that inspects a repository and
  recommends a coordination shape 🔬. The Cursor marketplace was not searched.
- Google, LangGraph, AutoGen and CrewAI criteria were not researched.
- Copilot parallelism and Codex concurrency keys need a live check before
  `harness-matrix.md` changes.

## Sources

1. [Multi-agent coordination patterns](https://claude.com/resources/articles/multi-agent-coordination-patterns) — Anthropic, 2026-04-10, accessed 2026-11-10
2. [When to fold subagents into your main agent loop](https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop) — Anthropic, 2026-10-22, accessed 2026-11-10
3. [Building multi-agent systems: when and how to use them](https://claude.com/resources/articles/building-multi-agent-systems-when-and-how-to-use-them) — Anthropic, 2026-01-23, accessed 2026-11-10
4. [Building agents with skills](https://claude.com/resources/articles/building-agents-with-skills-equipping-agents-for-specialized-work) — Anthropic, 2026-01-22, accessed 2026-11-10
5. [On the risk of coding before testing](https://arxiv.org/abs/2607.05139) — Konstantinou, Tambon, Papadakis, 2026-07-06, accessed 2026-11-10
6. [anthropics/single-agent-loop-kit](https://github.com/anthropics/single-agent-loop-kit) — Anthropic, accessed 2026-11-10
7. [Claude Code subagents](https://code.claude.com/docs/en/sub-agents) — Anthropic, accessed 2026-11-10
8. [Cursor subagents](https://cursor.com/docs/subagents) — Cursor, accessed 2026-11-10
9. [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams) — Anthropic, accessed 2026-11-10 ("Agent teams are experimental and disabled by default"; the "about 10 golden examples" eval starting size is in source 2)
10. External deep-research report with further sources (Cognition, Kim et al., MAST, arXiv 2609.09233, 2604.22891): `_memory/work/research/coordination-patterns/report.md` (scratch, not re-checked)
