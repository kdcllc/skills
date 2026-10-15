---
title: "Research: Autonomous Fix-Cycle Escalation (continuation ladder)"
topic: autonomous-escalation
date: 2026-08-24
status: shipped
shipped_in: ["1.0.0"]
goals: [autonomous-escalation-ladder]
supersedes: []
memory: [20260824T120004Z-46bf9116]
---

# Research: Autonomous Fix-Cycle Escalation (continuation ladder)

**Method**: `research` skill — self-contained prompt
(`_memory/work/research/autonomous-escalation/prompt.md`) → external deep-research report
(saved at `_memory/work/research/autonomous-escalation/report.md`, scratch) → critical
ingestion against primary sources cited in the report. Scratch lives under
`_memory/work/research/`; **this brief is canonical.**

**Trigger**: After three implement→evaluate fix cycles with model rotation, the kit
previously escalated to a human. Research asked whether bounded, strategy-changing
autonomous continuation could reduce low-value interruptions without runaway cost.

---

## Part 1 — Findings

### 1.1 Retry convergence — same strategy exhausts by round 3–4

The published repair-loop record is unusually clear: **attempts 4+ with the same strategy
do not meaningfully converge.** Gains concentrate in the first 1–2 repair rounds and are
exhausted by round 3–4; a **strategy change** (not just a model swap) is required to make
further attempts worthwhile.

- "How Many Tries Does It Take? Iterative Self-Repair in LLM Code Generation"
  (arXiv:2604.10508v1, 2026): "most gains concentrate in the first two rounds"; "two
  repair rounds capture the majority (76–95%) of achievable gains." For several models,
  R4 yields no additional improvement over R3; R4 fixes 0–1 problems for every model in
  the "first solved at round" breakdown.
- "Is Three the Magic Number? An Empirical Evaluation of LLM-Based Repair Loops"
  (arXiv:2607.05197v1, 2026): "the first three to four repair iterations account for
  most achievable gains, while later iterations contribute only marginal improvements";
  per-step relative improvement falls from +266.7% (step 1) to ~0% by step 9. The same
  paper finds repair behavior is influenced more by **workflow orchestration and feedback
  design** than by the underlying model — switching the repair prompt adds gains
  "comparable to an additional 1–2 repair rounds."

**Bottom line:** Because the kit already rotates models across cycles 1–3, a plain
cycle 4 with the same approach has near-zero expected gain. The next move must change
the *approach* — diagnosis-first, criteria arbitration, or decomposition — not the model
alone.

*Caveat:* both anchor studies are recent single-version arXiv preprints on relatively
easy benchmarks; treat exact percentages as directional.

### 1.2 Unanimous-failure heuristic

When every agent fails the same way, suspect the task or evaluator — not the
implementer. The Power Systems Agent Benchmark (arXiv:2606.20950) documents the rule:
**"treat a unanimous failure as a likely defect in the specification or the evaluator,
then confirm or dismiss it."** When agents fail differently, the disagreement is signal;
when they fail on the *same* required-fix item across cycles already on different model
families, that item is a criteria-defect candidate.

This maps directly to rung 5: spawn the evaluator in **arbitration mode** on a different
frontier model family when cycles 1–3 all failed on the same required-fix item.

### 1.3 Judge instability and the dual-judge escalation rule

LLM judges are useful but noisy. Zheng et al., "Judging LLM-as-a-Judge with MT-Bench
and Chatbot Arena" (arXiv:2306.05685, NeurIPS 2023), found strong judges match human
preferences well while naming position, verbosity, and self-enhancement bias. The "Coin
Flip Judge" study (arXiv:2606.13685) adds that **the same judge can change its verdict
across repeated trials** and different judge models disagree on a non-trivial fraction of
items.

**Dual-judge rule:** a second-opinion evaluator can catch wrong-criteria cases, but
**disagreement must escalate — never auto-resolve.** A tie or arbiter/primary disagreement
routes to the human carrying the specific defect, not to another fix attempt.

### 1.4 Guard evidence and kit hard guards

Continuing past a fixed cap without guards is repeatedly reported to cause catastrophic
cost. Documented failure modes include runaway sessions with thousands of identical
failing tool calls (community reports cite figures such as **$437 overnight** and
**$12,000 in a single session** — **design references only**, not independently
verified in this kit). Effective guards, in priority order (external design reference —
not enforceable in this kit): step count + wall-clock timeout + token limits "cover 90%
of runaway scenarios"; consecutive-identical-failure detection;
failure-signature matching.

**What 1.0.0 shipped (markdown policy — no driver change):**

- At most **3 additional implementation attempts** after cycle 3, summed across rungs 4
  and 6.
- A **repeated failure signature** stops the ladder immediately (required-fixes list
  identical item-for-item to an earlier cycle after normalizing whitespace).
- Every rung transition is an **orchestration-log** entry recording agent, model, rung,
  and trigger.

The external report recommended per-task token/cost budgets and wall-clock caps — not enforceable here; **NOT a guard in this kit** — no harness exposes token counts to markdown policy (see §2.3).

### 1.5 Risk-class rationale and always-escalate bypass

**Keep autonomous:** semantic/contract failures — evaluator-FAIL cases where the
implementation may be wrong but the surface is safe to retry.

**Route to a human regardless of remaining budget:** destructive/irreversible operations,
security-sensitive surfaces, and production/infra changes. The OWASP Top 10 for Agentic
Applications 2026 (OWASP GenAI Security Project, Dec 2025) enumerates agentic risk
categories grounded in real incidents (e.g., tool misuse, privilege abuse, rogue agents).

**Requirement ambiguity** is NOT a bypass class — it routes through rung 5 arbitration, not
immediate human escalation. The bypass subset is closed: `destructive`, `security`,
`infra`.

**Oversight capacity:** "Oversight Has a Capacity" (arXiv:2606.08919) shows
over-escalation is itself a failure mode — a more-escalating oversight policy can be the
*less* safe one because human attention is finite. This supports bounded autonomous
continuation for safe failure classes while preserving human attention for genuinely
high-risk cases.

**Claude Code auto mode** (reported 0.4% false-positive and 17% false-negative rates;
937 of 1,053 planted dangerous commands blocked in a controlled study) is the most
directly relevant shipping precedent for numeric backstops — **design reference only**;
statistics not independently verified here.

### 1.6 Deferred stages — not shipped

The external report recommended a fuller ladder including **deferred** high-effort pin and best-of-N rungs. After critique against kit constraints:

- **High-effort pin (deferred)** — evidence-marginal for routine coding (medium reasoning effort
  already peaks for refactor tasks; high adds little per multiple 2026 sources). No
  procedure defined in shipped templates.
- **Best-of-N parallel attempts** — powerful but conflicts with the kit's **disjoint
  write-set admission** design (driver-owned dispatch assigns one writer per file; parallel
  independent attempts cannot be merged without violating ownership fences). **Deferred**
  — no procedure defined here.

The headless loop inherits the Phase 4 ladder because each iteration runs the phased
flow; loop drivers' per-story attempt cap and circuit breakers stay the **unchanged outer
backstop** — the continuation ladder does not apply to Phase 3, Phase 5, or Phase 6
retry loops.

---

## Part 2 — What the kit adopted (1.0.0)

Shipped behavior lives in the canonical template source. After `/agent-kit`, the emitted
`ORCHESTRATION.md` and agent files carry the ladder.

### 2.1 Continuation ladder (Phase 4 task execution only)

When Task Execution (Phase 4) exhausts its 3 implement→evaluate fix cycles, the
orchestrator runs this ladder before terminal human escalation. Order:

1. **Bypass check (every verdict, every cycle).** A verdict tagged with a bypass failure
   class (`destructive`, `security`, `infra`) stops all retrying immediately — including
   cycles 1–3 — and escalates to the human. Requirement ambiguity routes through rung 5,
   not the bypass — it is not a bypass class.
2. **Rung 5 — arbitration** — if cycles 1–3 all failed on the *same* required-fix item,
   spawn the evaluator in arbitration mode on an alternate frontier model family.
   Outcomes: `criteria-defective` → escalate with the specific defect; arbiter/primary
   **disagreement → escalate (never auto-resolve)**; `criteria-sound` → continue to
   rung 4.
3. **Rung 4 — diagnosis-first** — spawn the `diagnostician` (frontier tier, no code
   writes) with task file, signed contract, and all three fix-cycle histories. If its
   Signature Declaration matches a previously tried fix signature → skip to rung 6 if it
   recommended a split, else escalate. Otherwise run **ONE** diagnosis-driven
   implementation attempt (fresh implementer on frontier tier, using the diagnostician's
   rewritten required-fixes list) and re-evaluate.
4. **Rung 6 — decomposition + selective retry** — only on a diagnostician split
   recommendation; subtasks with write sets ⊆ the parent task's, retrying **failing
   pieces only**.
5. **Terminal** — human escalation with full ladder history.

Canonical prose: [`skills/agent-kit/templates/ORCHESTRATION.md`](../../skills/agent-kit/templates/ORCHESTRATION.md)
(Continuation ladder subsection).

### 2.2 Agents, arbitration, and feature-skill integration

| Component | Canonical file | Role |
|-----------|----------------|------|
| Continuation ladder policy | [`skills/agent-kit/templates/ORCHESTRATION.md`](../../skills/agent-kit/templates/ORCHESTRATION.md) | Rungs 5→4→6, guards, taxonomy |
| `diagnostician` agent | [`skills/agent-kit/templates/agents/diagnostician.md`](../../skills/agent-kit/templates/agents/diagnostician.md) | Root-cause analysis, no code writes |
| Evaluator arbitration | [`skills/agent-kit/templates/agents/evaluator.md`](../../skills/agent-kit/templates/agents/evaluator.md) | Second-opinion / criteria-defect detection |
| Phase 4 orchestration | [`skills/agent-kit/templates/skills/feature/SKILL.template.md`](../../skills/agent-kit/templates/skills/feature/SKILL.template.md) | Ladder dispatch after cycle 3 |
| Model tiers | [`skills/agent-kit/templates/models.map.md`](../../skills/agent-kit/templates/models.map.md) | `diagnostician` on frontier tier |

**Failure-class taxonomy (closed set):** `implementation` (default) · `criteria-defect` ·
`destructive` · `security` · `infra`. Bypass subset: destructive, security, infra.

### 2.3 Report-critique corrections (ground truth)

The external report (`_memory/work/research/autonomous-escalation/report.md`) recommended
items the kit **explicitly rejected or deferred**:

1. **Per-task token/cost budgets are NOT enforceable in this kit.** No harness exposes
   token counts to markdown policy; token/cost budget guards cannot adopt as shipped
   behavior. The report's dollar figures ($437, $12,000, frontier-vs-light multipliers)
   are **design references only** — not independently verified here.
2. **Best-of-N conflicts with disjoint write-set admission.** Parallel independent
   attempts require N writers on overlapping paths; the kit's driver-owned dispatch and
   write-set admission design admit one writer per file. Best-of-N is **deferred** — no
   procedure defined.
3. **Arbitration complements the 1.0.0 contract gate**, not a parallel criteria
   mechanism. The arbiter reviews the **signed contract** and unanimous-failure context;
   it does not replace per-task contracts or add a second criteria source.

### 2.4 Externally unverified statistics (design references only)

Treat as directional design references, not kit telemetry:

- Claude Code auto-mode statistics (0.4% false-positive, 17% false-negative, 937/1053
  blocked commands).
- Community runaway-cost anecdotes ($437 overnight, $12,000 single session).
- Frontier-vs-light cost multipliers and per-token pricing spreads from vendor blogs.

---

## Open questions (carried from ingestion)

1. No published ladder for exactly this architecture (frontier orchestrator + light
   workers + pessimistic evaluator, cap-3 with model rotation already done).
2. Quantified success rate of diagnosis-first vs. plain cycle-4 in a fix-loop context
   is not published.
3. Cursor silent model substitution may defeat tier pins — verify via evaluator, not the
   pin.

## Sources

Primary (from the external report; arXiv anchors verified present):

- [How Many Tries Does It Take?](https://arxiv.org/abs/2604.10508) (arXiv:2604.10508v1, 2026)
- [Is Three the Magic Number?](https://arxiv.org/abs/2607.05197) (arXiv:2607.05197v1, 2026)
- [Power Systems Agent Benchmark — unanimous failure heuristic](https://arxiv.org/abs/2606.20950) (arXiv:2606.20950)
- [Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena](https://arxiv.org/abs/2306.05685) (arXiv:2306.05685, NeurIPS 2023)
- [Coin Flip Judge — judge instability](https://arxiv.org/abs/2606.13685) (arXiv:2606.13685)
- [Oversight Has a Capacity](https://arxiv.org/abs/2606.08919) (arXiv:2606.08919)
- OWASP Top 10 for Agentic Applications 2026 (OWASP GenAI Security Project, Dec 2025)

Scratch report: `_memory/work/research/autonomous-escalation/report.md`

Related kit ground truth: [evaluation-system.md](../../docs/agent-kit/guide/evaluation-system.md) ·
[autonomous-loop.md](../../docs/agent-kit/guide/autonomous-loop.md) ·
[multi-harness-upgrade.md](multi-harness-upgrade.md)
