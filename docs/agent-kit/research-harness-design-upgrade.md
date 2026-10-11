# Research: Harness Design Upgrade (judge → evaluator)

**Date**: 2026-08-21 · **Method**: `research` skill — self-contained prompt
(`_research/prompts/harness-design-upgrade.md`) → external deep-research report
(user-provided, saved at `_research/harness-design-upgrade/report.md`, untracked) →
critical ingestion against the primary sources, which were also read in full in-session.
An agent-generated pre-read (`internal-baseline.md`, untracked) was used only as a
comparison baseline.

**Status**: findings promoted 2026-08-21. Phase 3 decisions approved by the user
2026-08-21: naming pair **`evaluator` + `qa-evaluator`** (kept separate); migration
**clean one-shot rename** (no alias shims — installs regenerate via `/agent-kit` +
manifest); v0.18.0 scope **Phases 0–2** (rename + evaluator hardening + contracts with
`eval_depth` routing); Phases 3–5 follow as separate goals. Implementation still gated
on the `feature` skill's goal judgment — nothing below is shipped yet.

**Trigger**: Anthropic Labs, [Harness design for long-running application
development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
(Prithvi Rajasekaran, 24 Mar 2026), plus every post it references. User direction:
adopt **evaluator** in place of **judge**, and produce a clear harness-upgrade guide.

---

## Part 1 — Findings

### 1.1 Lineage of the Anthropic harness line

| Date | Post | What it establishes |
|------|------|---------------------|
| 2024-12-19 | [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) | The primitives: **orchestrator-workers** and **evaluator-optimizer** ("one LLM call generates a response while another provides evaluation and feedback in a loop"). Simplicity doctrine: "find the simplest solution possible, and only increasing complexity when needed." |
| 2025-06-13 | [Multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) | Orchestrator-worker in production: Opus 4 lead + Sonnet 4 subagents beat single-agent Opus 4 by 90.2% at ~15× tokens; subagents never talk to each other; read-heavy work only. (Already ground truth via `research-designing-conflict-free-multi-agents.md`.) |
| 2025-09-29 | [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) | Context rot, attention budget, and the three long-horizon levers: **compaction** / **structured notes** / **sub-agent isolation** (distilled 1–2k-token returns). |
| 2025-11-26 | [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) | **Initializer** + **coding agent**; `feature_list.json` all `passes: false`; `claude-progress.txt`; `init.sh`; git as memory; browser-MCP E2E ("do all testing as a human user would"); **context resets** between sessions because compaction alone was insufficient. |
| 2026-02-05 | [Opus 4.6 launch](https://www.anthropic.com/news/claude-opus-4-6) | "Plans more carefully, sustains agentic tasks for longer… better code review and debugging skills to catch its own mistakes." MRCR v2 8-needle 1M: 76% vs Sonnet 4.5's 18.5%. Motivation to *strip* scaffolding. |
| 2026-03-24 | [Harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) | GAN-inspired **generator + evaluator**, extended to **planner + generator + evaluator**. Sprint contracts negotiated before code; evaluator drives the live app via Playwright MCP; hard per-criterion thresholds; few-shot calibration. On Opus 4.5 they dropped context resets (one continuous SDK session); on 4.6 they removed sprints and made the end-run evaluator conditional. The planner was always kept ("Without the planner, the generator under-scoped"). |

Key quote for maintenance policy: "every component in a harness encodes an assumption
about what the model can't do on its own, and those assumptions are worth stress
testing… because they can quickly go stale as models improve."

### 1.2 Role vocabulary and the rename map

"Evaluator" is Anthropic's stable term across Dec 2024 and Mar 2026 (the Mar 2026 post
uses "evaluator" and "QA" interchangeably for the same agent). Approved direction:

| Current | Action | New name | Why |
|---------|--------|----------|-----|
| `judge` | rename | `evaluator` | Anthropic's exact term for the never-edits, verdict-returning grader; user preference. |
| `qa-judge` | rename, keep separate | `qa-evaluator` | Grading the artifact vs driving the product are two jobs; Copilot/CLI-only installs can't always run a browser MCP, so the split is load-bearing. |
| `implementer` | keep | — | Anthropic's "generator" is a whole-app builder in a continuous session; this role is a fenced one-task worker. Renaming would misdescribe it. |
| `test-writer` | keep | — | Nov 2025 left specialized test agents as an open question; merging test author into code author reintroduces self-grading bias. |
| `terminal` | keep | — | ACI primitive; no Anthropic analogue. |
| orchestrator (`feature` skill) | keep | — | Dec 2024 orchestrator-workers is the ancestor. The Mar 2026 *planner* (autonomous spec expansion from 1–4 sentences, no user Q&A) is NOT this kit's Phase 1/2 — document the duality, do not rename, do not add a `planner` subagent. |

Names are valid in all four harnesses (lowercase + hyphen: Claude Code `name:`, Cursor
agents, Copilot `.agent.md`, Codex `[agents.<name>]`).

Prose shift: "orchestrator/worker/judge" → "orchestrator/worker/evaluator";
"judgment / re-judge" → "evaluation / re-evaluate". **Verdict tokens are stable**:
PASS / NEEDS FIXES / NEEDS REVISION / REJECT / APPROVED keep their exact spellings
(logs, tests, and loop drivers grep them).

### 1.3 Mechanisms to adopt (the actual upgrade content)

1. **Per-task contracts with two-party sign-off** (Mar 2026 sprint contracts). The
   contract exists to bridge "user stories → testable implementation" and to stop
   goalpost-moving in both directions: the worker proposes what "done" looks like and
   how it will be verified; the evaluator counter-signs *before code is written*.
   Kit shape: `_goals/[goal]/contracts/NN-task-name.contract.md` with `task_id`,
   `done_definition`, numbered `acceptance_criteria` each carrying a verification
   method, `verification_environment` (CLI / API / browser), `out_of_scope`, and
   `signoff.worker` / `signoff.evaluator`. Orchestrator refuses to dispatch
   implementation until both sign-offs are true. Negotiation is file-based and bounded
   (1–2 rounds; on Copilot each round is one stateless spawn). Complementary to
   `task.md` — the contract is the testable expansion, never a second source of scope.
2. **Execute-before-score** (generalization of Playwright-before-score). The evaluator
   must ground its verdict in *executing* the artifact, not reading about it: run the
   targeted tests itself (already required), invoke the CLI / hit the API for
   behavioral checks (via `terminal`), drive the browser where a Playwright-class MCP
   exists. Screenshots/logs alone pass the exact bug class the design targets —
   features that render but don't function ("audio recording is still stub-only").
3. **Evaluator calibration levers** (all transfer to code/spec except aesthetics):
   named criteria over vibes; **hard per-criterion thresholds** (one failing criterion
   fails the task — no averaging away); **few-shot verdict exemplars** with score
   breakdowns (the most portable lever; reduces drift); skeptical-by-default stance;
   an explicit anti-pattern rule against "identify the issue, then talk yourself into
   approving anyway"; and a **log-driven prompt-tuning ritual** — read evaluator
   traces, find divergence from the maintainer's judgment, patch the criteria/prompt.
4. **Tier the evaluation, not the gate.** Anthropic's "the evaluator is not a fixed
   yes-or-no decision… worth the cost when the task sits beyond what the current model
   does reliably solo" is adopted as *intensity routing*, never a skip: every task
   still ends in a verdict; the **orchestrator** (never the worker) routes low-risk
   tasks to a lightweight evaluator pass and high-risk tasks to the full pass +
   optional live QA. Evaluation is cheap relative to build in Anthropic's own numbers
   (DAW run: QA ≈ $10.39 total vs ≈ $113.85 build — ≈9%), so the default stays "at
   least the lightweight pass, always."
5. **Copilot degradation is explicit, not silent.** Where the qa-evaluator cannot
   drive the surface (nesting off, no MCP), orchestrator-captured evidence remains the
   input and the verdict is marked `evidence: secondary`.
6. **Optional `frontend-design` skill routing.** Emit the official Anthropic skill as
   an optional supporting skill; route it into UI tasks' context packages (generator
   side); bake the four grading criteria (design quality, originality, craft,
   functionality) into the qa-evaluator's UI rubric block only. Never applied to the
   kit's own docs.
7. **A written simplification policy** (Mar 2026 method + Dec 2024 doctrine): on each
   new model generation, re-examine the harness by ablating **one component at a
   time**; components map to problem classes, and a component is removed only when its
   problem class demonstrably no longer occurs. Write-set disjointness and the
   separate `test-writer` are recorded as non-candidates absent primary-source
   evidence that parallel writers became safe.

### 1.4 What NOT to copy (would hurt this kit)

1. One continuous session as the architecture — the kit's portability across four
   harnesses rests on fresh-context spawns + file handoffs; three of four targets lack
   SDK auto-compaction.
2. All-frontier workers — breaks the cheap-executor economics (frontier lead + light
   workers) and Copilot's cost ceiling handling.
3. Replacing Phase 1 alignment with a 1–4-sentence autonomous planner — Anthropic's
   own planner-less runs under-scoped, and their planner replaces the *written spec*,
   not stakeholder decisions.
4. High-level specs without ownership contracts — greenfield single-writer luxury;
   this kit exists for multi-task, one-writer-per-file work.
5. Merging `test-writer` into the implementer.
6. Making per-task evaluation optional — greenfield-boundary evidence doesn't transfer
   to regression-risk codebases; vary depth, never skip.
7. JSON-only feature lists replacing markdown task files (Nov 2025's JSON preference
   was a narrow anti-overwrite finding; consider JSON only for a status ledger if loop
   stories ever get destructively edited).
8. Dropping context resets because "Opus 4.5 removed context anxiety" — model- and
   runtime-specific; the kit runs pinned/fallback models on four harnesses.
9. 5–15 GAN-style iterations as the default fix loop — keep max 3 + escalate; a higher
   cap only ever as an explicit design-iteration task type.
   *[Superseded for Phase 4 task execution in v0.20.0: on cycle-3 exhaustion the
   orchestrator now enters the continuation ladder (rungs 5→4→6 — arbitration,
   diagnosis-first, decomposition) before terminal human escalation; other phases keep
   max 3 + escalate. See [research-autonomous-escalation.md](research-autonomous-escalation.md).]*
10. Taste-steering phrases ("museum quality") in the *code* evaluator's criteria —
    Mar 2026 observed criteria wording steering output character.

### 1.5 Corrections & flags on the external report (2026-08-21 ingestion)

The external report (`_research/harness-design-upgrade/report.md`) is high quality;
spot-checks against the primary sources read in-session confirmed its load-bearing
quotes (MRCR 76%/18.5%; the DAW cost table; sprint-contract and evaluator quotes; the
writing-tools post's "contract between deterministic systems and non-deterministic
agents", 25,000-token default, and Ken Aizawa authorship — all verified verbatim).
Flags a future reader must carry:

1. **"Make sprints/decomposition optional, gated on model tier" (its Q8) is rejected.**
   Task decomposition is the substrate of the ownership contracts — `writes` fences and
   pairwise-disjointness checks only exist because work is decomposed into tasks.
   Making decomposition optional would silently delete write-set verification. What may
   vary with model tier is task *granularity* (fewer, larger tasks), never the
   existence of the decomposition + per-task contract.
2. **Arithmetic**: its "QA ≈ ~4% of build cost" understates the DAW numbers — QA
   totals $10.39 vs $113.85 build ≈ **9%** (≈8% of the $124.70 total). The conclusion
   (evaluation is cheap relative to build) stands.
3. **Codex naming-rule quote** ("simple ASCII names… `name` is the source of truth")
   is plausible but **not yet in the kit's verified harness matrix** — re-verify
   against the live Codex config reference during the rename emit. `evaluator` /
   `qa-evaluator` are safe under any plausible rule, so the conclusion is unaffected.
4. **Unsourced capability claim**: "Opus 4.6 can ask clarifying questions upfront and
   then build a user-editable plan" is not in the Opus 4.6 launch post (likely
   conflates Claude Code plan mode). Do not cite it.
5. **Community-grade numbers it already flags**: Copilot cloud-agent ~64K prompt
   ceiling (one community discussion); the Ralph "iterate destructively" quote is
   unattributed paraphrase; Opus 4.5 launch figures are via InfoWorld/The Decoder
   (secondary). Chroma Research's "Context Rot" (July 2025) is real but was not
   independently re-verified in this session.
6. **Contract filename**: its "`contract.md`, one per task, sibling to `task.md`"
   collides in a goal directory holding N tasks — use
   `contracts/NN-task-name.contract.md` (adopted in §1.3).
7. **Its alias-shim migration** (emit deprecated `judge.md` stubs for one version) has
   unverified harness behavior: Cursor may list both agents in the picker, and prior
   kit research observed possible same-name dedup on Copilot dual trees. A clean
   one-shot rename with a manifest-driven re-emit (`/agent-kit` regenerates installs) is
   the safer default; see Part 2 Phase 0 decision.

### 1.6 Failure-mode → lever table (evidence-graded)

| Failure mode | Lever | Evidence |
|--------------|-------|----------|
| One-shotting the build | Feature list + one-feature-per-session | Nov 2025, practitioner-observed |
| Premature victory | All-`passes: false` ledger read at session start | Nov 2025, observed |
| Done-without-testing | Browser/E2E before flipping `passes` | Nov 2025, observed ("dramatically improved") |
| Context rot | Compaction / notes / sub-agent isolation | Sep 2025 + externally measured (MRCR; Chroma) |
| Context anxiety | Context resets + structured handoff | Mar 2026, observed on Sonnet 4.5; gone on Opus 4.5+ |
| Self-praise on own work | Separate evaluator, tuned skeptical | Mar 2026, observed on subjective *and* verifiable tasks |
| Talking-itself-into-approval | Hard thresholds; log-driven prompt tuning | Mar 2026, observed in early QA runs |
| Superficial QA | Drive the live artifact; contract criteria as rubric | Mar 2026, observed |
| Stubbed / display-only features | End-run evaluator still catches on 4.6 | Mar 2026, observed (DAW rounds 1–2) |
| Under-scoping | Planner/spec expansion kept | Mar 2026, observed |
| Spec cascade errors | Plan stays high-level; detail lives in the contract | Mar 2026, believed (stated concern, no ablation) |

None of the harness claims are controlled benchmarks; the measured quantities are
model-capability metrics only. Adopt mechanisms, not ablation verdicts.

---

## Part 2 — Upgrade plan (proposed; pending Phase 3 approval + goal judgment)

### Phase 0 — Vocabulary rename (breaking; target v0.18.0)

`judge` → `evaluator`, `qa-judge` → `qa-evaluator`, prose "orchestrator/worker/judge" →
"orchestrator/worker/evaluator". Verdict tokens unchanged.

Concrete blast radius in this repo (grep-verified 2026-08-21; `judge|qa-judge`
appears in ~35 files):

- `skills/agent-kit/templates/agents/judge.md`, `qa-judge.md` → renamed files + `name:`
  frontmatter; `models.map.md` tier-role rows and rotation table.
- `skills/agent-kit/templates/ORCHESTRATION.md` — diagrams ("pessimistic-judge"), subagent
  table, phase prose, QA section.
- `skills/agent-kit/templates/skills/*` — `feature` (iron rules, phases, spawn text),
  `goal-criteria` / `task-criteria` / `qa-criteria` (descriptions + owner cross-checks),
  `align-docs`, `research`, `ship-pr`, `test-ladder`; `templates/loop/` (SKILL.md,
  PROMPT.md, loop.sh/ps1 comments).
- `skills/agent-kit/emitters/*` — Claude Code spawn allowlist
  `tools: Agent(implementer, test-writer, judge, qa-judge, terminal)`; Cursor pointer
  rule text + translated-agent rows; Copilot `judge.agent.md` example, `agents:`
  arrays, verify checklist ("all five roles"); Codex `[agents.judge]` /
  `[agents.qa-judge]` tables + `agents/judge.toml` layers.
- `skills/agent-kit/SKILL.md`, `reference/harness-matrix.md` (incl. empirical-validation
  notes that name `judge` fixtures).
- Root `README.md`, `ORCHESTRATION.md`, `.cursor/rules/orchestration.mdc` (this repo's
  own alwaysApply rule says "judge PASS").
- `tests/agent-kit/loop-harness/run.sh` (`j_target_path=".claude/agents/judge.md"` and judge-named
  assertions), `tests/agent-kit/templates/invocation-flags.sh`.
- The self-install emitted instance (`.claude/`, gitignored) regenerates via
  `scripts/agent-kit/self-install.sh`.

Migration decision (Phase 3 question): clean one-shot rename + re-emit vs one-version
deprecated `judge.md` alias stubs. Alias behavior in Cursor's picker and Copilot's
dual-tree dedup is unverified (see §1.5.7 and the open questions).

### Phase 1 — Evaluator hardening (non-breaking)

Few-shot verdict exemplars (PASS vs NEEDS FIXES vs REJECT with reasoning); explicit
"never talk yourself into a PASS" anti-pattern; hard per-criterion thresholds in the
criteria skills; execute-before-score requirement; log-driven prompt-tuning ritual
documented for maintainers. Optional: persist verdicts/reports as files in the goal dir
(`NN-task.verdict.md`) to complete the file-based-communication pattern.

### Phase 2 — Contracts (additive)

`contracts/NN-task-name.contract.md` per §1.3.1, contract-mode evaluator sign-off
before implementation dispatch, bounded negotiation, orchestration-log entries for both
sign-offs. Evaluation-intensity routing (§1.3.4) rides in with it: the task file gains
an orchestrator-set `eval_depth` field (`full` default | `light`), never worker-set.

### Phase 3 — Live QA (routed capability)

qa-evaluator executes CLI/API surfaces itself (via `terminal`); drives a browser where
a Playwright-class MCP is present (a `/agent-kit` interview question decides per-project);
Copilot keeps the captured-evidence path with `evidence: secondary` marking. Route by
the contract's `verification_environment`.

### Phase 4 — Optional frontend-design skill

Vendored/linked official skill; routed into UI-layer tasks; four criteria in the
qa-evaluator UI rubric only.

### Phase 5 — Simplification policy (docs)

The per-model-generation ablation ritual (§1.3.7) added to the architecture doc;
non-candidates recorded.

---

## Open questions (carried from ingestion)

1. Cursor/Copilot behavior with deprecated same-role alias agent files — blocks the
   alias-shim migration option; a clean rename avoids it. Empirical.
2. Codex agent-name rule + `name`-as-identity — re-verify at emit time (§1.5.3).
3. Source of few-shot verdict exemplars (kit dogfood traces vs synthetic). Blocks
   Phase 1 quality.
4. Risk-tiering signal for `eval_depth` (diff size? ownership-graph touch? coverage
   delta?) — needs kit-side data before `light` gets objective routing rules.
5. Whether one negotiation round suffices for contracts (Anthropic iterated "until
   they agree"; Copilot statelessness favors 1 round + orchestrator tiebreak).
6. Whether Copilot's `evidence: secondary` verdicts should require a human check for
   phase advance. Policy decision.

## Sources

Primary (read in full this session): [harness-design-long-running-apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) ·
[effective-harnesses-for-long-running-agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) ·
[effective-context-engineering-for-ai-agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) ·
[building-effective-agents](https://www.anthropic.com/engineering/building-effective-agents) ·
[writing-tools-for-agents](https://www.anthropic.com/engineering/writing-tools-for-agents) ·
[claude-opus-4-6](https://www.anthropic.com/news/claude-opus-4-6) ·
[anthropics/skills frontend-design](https://github.com/anthropics/skills/blob/HEAD/skills/frontend-design/SKILL.md)

Secondary (via the external report; not independently re-verified): InfoWorld / The
Decoder (Opus 4.5 launch figures) · Chroma Research "Context Rot" (July 2025) ·
Cognition (Yan) 2025/2026 posts (consistent with
[research-designing-conflict-free-multi-agents.md](research-designing-conflict-free-multi-agents.md)) ·
community notes on Copilot cloud-agent limits and Ralph failure modes.

Related kit ground truth: [research-multi-harness-upgrade.md](research-multi-harness-upgrade.md) ·
[research-squad-ideas.md](research-squad-ideas.md) ·
[research-designing-conflict-free-multi-agents.md](research-designing-conflict-free-multi-agents.md)
