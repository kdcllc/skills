---
title: "Hardening evaluator gates: consumer trace, cite-or-backlog, repeat signatures, failure classes, hook field notes"
topic: gate-hardening
date: 2026-10-27
status: adopted
recheck_by: 2027-01-27
shipped_in: []
goals: [evaluator-gate-hardening]
supersedes: []
memory: [20261028T002222Z-81ed0485]
---

# Hardening evaluator gates: consumer trace, cite-or-backlog, repeat signatures, failure classes, hook field notes

**Method**: `research` skill. A self-contained prompt
(`_memory/work/research/gate-hardening/prompt.md`) went to an external deep-research tool.
Its report is saved at `_memory/work/research/gate-hardening/report.md` (scratch). The
critical ingestion review (`review.md`, scratch) spot-checked four load-bearing sources.
**This brief is canonical.**

## Question

A sibling orchestration system ("Project A") of the same orchestrator/worker/evaluator shape
uses five patterns agent-kit lacks. Should agent-kit adopt them, and how, given its settled
decisions?

1. A blind goal-level contract with a consumer trace.
2. Cite-or-backlog, "the first cycle sets the blocking list", and "a PASS is final".
3. A fixed issue-line format with normalized keys and progress-based loop termination (no
   cycle cap).
4. Classifying quality-check failures as introduced, pre-existing or caused by local edits.
5. Field observations of Cursor hook behavior.

The settled decisions in play:
- per-task contracts were removed in v0.23.0 for cost;
- strict mode and orchestrator-side list diffing were rejected on 2026-10-23;
- the 3-cycle cap plus continuation ladder rests on repair-loop research;
- the kit installs no hooks by default.

## Load-bearing conclusions

- **Missed consumers are a common failure, and thoroughness is the bottleneck, not the
  search tool.** In a controlled study, call-site recall was about 0.66 with both grep and
  LSP; the paper blames the agent stopping early [1]. Incomplete fixes are the largest
  failure bucket in several 2025–2026 taxonomies [2][3].
- **No evidence shows that a *blind* criteria writer beats a planner-written trace.**
  Anthropic's harness post supports separating the judge from the builder, which the kit
  already does. Its contract was negotiated, not blind, and later removed on Opus 4.6 [4].
  That supports the v0.23.0 removal.
- **LLM judges are unstable on identical inputs.** 7–17% of verdicts flip across identical
  replications at temperature 0 [5]. Some late findings are therefore re-sampling noise,
  which supports "a PASS is final" and demoting late findings outside changed code to a
  backlog.
- **Keep the cap; add a progress signal inside it.** Repair gains concentrate in rounds 1–4
  [6][7]. The strongest progress-based paper shows loops *degrading* under stress, and its
  own method still keeps a round budget [8].
- **Failure classification needs a base-branch baseline**, one flake retry and a
  start-of-run snapshot of dirty files. Report and backlog is the safe default for
  pre-existing failures.
- **Cursor hooks are unreliable enough to be telemetry, not enforcement.** Staff confirm that
  a deny's `agent_message` never reaches the agent [9]. Hooks do not run during a cloud
  agent's read-only early turns [10]. Cursor and Copilot both also run repository
  `.claude/settings.json` hooks, so one hook can run in three harnesses [10][11].

## Per-question findings

Confidence: **high** = documented by an official source · **medium** = several
independent sources agree · **low** = inferred or single community source.

### Item 1: consumer trace

- A planner-written `## Consumers` section in `goal.md`, built from literal `rg` searches
  that `terminal` executes, with verbatim hit lists and every hit classified, beats a
  separate blind spawn on cost. There is no evidence for blindness itself. Confidence:
  medium.
- Text search fails toward false positives (it also finds comments, strings, config and
  docs). Semantic references miss strings and comments, and fail renames [1]. Confidence:
  medium (one preliminary study plus practitioner reports).
- Sound "unaffected" evidence, strongest first: a covering test that ran; an unchanged
  interface shown by diff; a zero-hit search for *every* name variant. Confidence: low
  (inference).
- Estimated cost: 15k–75k tokens of search output per goal, with no extra spawn.
  Confidence: low.

### Item 2: cite or backlog, first cycle sets the list, PASS is final

- No study measures the recall cost of requiring each finding to cite a rubric item, or of
  restricting late findings. Confidence: low.
- Practice is severity-gated. Google's review guidance uses "Nit:"/"FYI" labels and approves
  changes that "definitely improve the overall code health … even if the CL isn't perfect".
  Production AI reviewers tune for precision. Confidence: medium.
- Recommended reconciliation: after cycle 1, a blocking `[new]` finding is allowed only in
  code changed since the last cycle, or in a severe list (the bypass classes plus
  authorization bypass, cross-tenant access, secret exposure, wrong-target mutation, data
  loss and hangs). Every other late finding goes to a goal backlog with its evidence, never
  dropped. Confidence: low (no comparative evidence).

### Item 3: issue-line format and termination

- No published measurement exists of how faithfully models reproduce issue wording across
  fresh calls, or of false-repeat rates for exact versus fuzzy matching. Confidence: low.
- Harnesses combine fingerprint-based loop detection *with* iteration caps [12]. Cursor's
  `stop`/`subagentStop` `loop_limit` defaults to 5; Copilot ignores blocks after 8 in a row
  [10][11]. Confidence: high.
- Recommended: compute normalized keys as instrumentation. Use the same key in two
  consecutive cycles only as an early exit into the ladder, inside the existing cap. Use
  exact keys only, never fuzzy or embedding matching, as a gate. Confidence: medium.

### Item 4: failure classes

- Vendors detect flakes from history (a test that passes and fails on the same commit) and
  quarantine flaky tests; a rerun is the cheap detector. Confidence: medium.
- No agent vendor documents a policy for pre-existing failures. Confidence: high (absence,
  per the report).

### Item 5: hook field notes (Cursor, October 2026)

- **Confirmed by Cursor staff:** only `user_message` reaches the agent on a `preToolUse` or
  `beforeShellExecution` deny [9]. Confidence: high (desktop; cloud unverified).
- **Documented:**
  - hooks do not run during a cloud agent's read-only early turns, the likely cause of
    first-turn subagents firing no hooks [10];
  - Cursor loads Claude Code hooks, with `loop_limit` `null` for them [10];
  - Copilot reads repository `.claude/settings.json` and runs hooks from every source
    together [11].
  Confidence: high.
- **Community-reported:** a Task launch without a model runs on the parent's model; an
  unrecognized frontmatter model silently falls back to the parent model;
  `subagentStop.summary` and `agent_transcript_path` are often empty. Confidence: medium.
- **Unconfirmed:** `failClosed` on `stop` crashes; `loop_count` resetting per prompt; hooks
  in multi-root named environments; resumed Tasks skipping `subagentStart`. Confidence: low.

## Decisions

- **Adopted (2026-10-27, user planning answers):** goal `evaluator-gate-hardening` (items 2, 3, 4, 5). Its plan passed Phase 3 on 2026-10-27:
  - **Late findings:** severe-class restriction. A late finding stays blocking in changed files, or when it cites `F1`, `F3`, `F4`, `F7` or an acceptance criterion, or when it is a reversal; every other late finding becomes `[backlog] [late]`.
  - **Repeat keys:** logged under `ladder: escalate`. Under `ladder: auto`, an initial early-ladder-entry implementation triggers on a repeated `[structural]` key, with the cap and budget unchanged.
  - **Pre-existing failures:** reported and backlogged, backlog-only in loop runs.
  - **Release:** ships in the same agent-kit 2.2.0 release as the concurrent `agent-kit-opt-in` goal, as local commits on `feat/agent-kit-opt-in` with no pull request. Its Phase 4 starts after that goal finishes Phases 4–6.

  A later goal A covers item 1: a planner-written consumer trace, plus a read-only spawn for bypass-class goals.
- **Recommended for planning**, pending user decisions:
  - Item 1: the planner-written trace, checked by `goal-criteria` and the Phase 5 audit;
  - Item 2: cite-or-backlog plus the backlog file and PR-body section;
  - Item 3: keys as instrumentation plus an early exit inside the cap;
  - Item 4: baseline classification with a backlog-only default in loop mode;
  - Item 5: harness-matrix rows, added only when implemented.
- **Rejected by the evidence:**
  - removing the cycle cap;
  - fuzzy or embedding repeat matching as a gate;
  - a blind contract spawn for every goal;
  - per-task traces;
  - putting kit hooks in `.claude/settings.json`;
  - relying on `agent_message` or on `failClosed` for `stop`/`subagentStop`.

## Open questions

- Does a blind trace catch more consumer misses than a planner-written one? This blocks a
  separate spawn for ordinary goals and needs an A/B on the kit's own goals.
- What recall does the severe-class restriction on late findings give up? This blocks a
  firm revision of the 2026-10-23 decision.
- How faithfully do evaluators reproduce issue wording across fresh calls? This blocks
  promoting computed keys from audit to gate.
- Which Cursor hook behaviors hold on desktop as well as cloud? Notes 5(c), (f), (g) and (i)
  are unconfirmed. Re-check by 2027-01-27; Cursor's hook behavior changed several times in
  2026.
- No agent vendor has a policy for pre-existing failures.

## Sources

1. [Does a Language Server Save Tokens for Coding Agents? (arXiv:2608.13568)](https://arxiv.org/abs/2608.13568) — arXiv, accessed 2026-10-27 (spot-checked)
2. [SWE Atlas (arXiv:2605.08366)](https://arxiv.org/abs/2605.08366) — arXiv, per report
3. [SWE-Bench 5G (arXiv:2604.26278)](https://arxiv.org/abs/2604.26278) — arXiv, per report
4. [Harness design for long-running application development](https://www.anthropic.com/engineering) — Anthropic engineering blog, 2026-03-24, per report
5. [All Verdicts are Not Equal: Rethinking LLM Judge Reliability (arXiv:2610.12083)](https://arxiv.org/abs/2610.12083) — arXiv, accessed 2026-10-27 (spot-checked)
6. [How Many Tries Does It Take? Iterative Self-Repair in LLM Code Generation (arXiv:2604.10508)](https://arxiv.org/abs/2604.10508) — arXiv, per report and the autonomous-escalation brief
7. [Is Three the Magic Number? An Empirical Evaluation of LLM-Based Repair Loops (arXiv:2607.05197)](https://arxiv.org/abs/2607.05197) — arXiv, per report
8. [Verify, Repair, Repeat, or Stop? (arXiv:2607.17641)](https://arxiv.org/abs/2607.17641) — arXiv, accessed 2026-10-27 (spot-checked; stress setting with injected mismatch, method keeps `K_max`)
9. [preToolUse hides user_message and ignores agent_message — Cursor 3.23.23 (thread 174283)](https://forum.cursor.com/t/174283) — Cursor forum, staff reply 2026-10-12, accessed 2026-10-27 (spot-checked)
10. [Cursor hooks documentation](https://cursor.com/docs/agent/hooks) — cursor.com, accessed 2026-10-27
11. [Configure agent hooks in Visual Studio Code](https://code.visualstudio.com/docs/copilot/customization/hooks) and [GitHub Copilot hooks configuration](https://docs.github.com/en/copilot/reference/hooks-configuration) — accessed 2026-10-27
12. [OpenDev terminal agent (arXiv:2603.05344)](https://arxiv.org/abs/2603.05344) — arXiv, per report
