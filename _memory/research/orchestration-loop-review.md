---
title: "Research: Hardening the Unattended Loop (budgets, retry context, verification, harness-native options)"
topic: orchestration-loop-review
date: 2026-10-20
status: adopted
recheck_by: 2027-01-20
shipped_in: []
goals: [loop-cli-recipes, loop-guards]
supersedes: []
memory: [20261020T231821Z-1e79114a]
---

# Research: Hardening the Unattended Loop (budgets, retry context, verification, harness-native options)

**Method**: `research` skill. A self-contained prompt
(`_memory/work/research/orchestration-loop-review/prompt.md`) went to an external
deep-research tool. The report (`_memory/work/research/orchestration-loop-review/report.md`,
scratch) was then reviewed critically against the loop driver, the model map, the harness matrix and local
CLI probes (`.../review.md`, scratch). **This brief is canonical.**

## Question

The interactive orchestration (phased `/feature`, evaluator gates, fix-cycle rotation,
continuation ladder, spawn audit, memory store) is mature. What should change in the
optional autonomous loop (`_loop/loop.sh` driver, backlog, slots, breakers, integrator) to
make unattended runs cheaper to bound, better at retries, harder to game, and easier to
review? Which parts, if any, could harness-native features replace?

## Load-bearing conclusions

- **Every surveyed unattended system ships hard caps on cost, turns or time; the kit's loop
  has none.** Today a run is bounded only by `max-iterations`. No per-iteration
  wall-clock limit exists, and parsed token/cost usage is printed but never acted on.
  SWE-agent ($3 default per instance), OpenHands (iterations + budget), Claude Code
  (`--max-budget-usd`) and Copilot cloud agent (59-minute cap) all enforce limits.
- **Retries need grounded, structured failure context, not more attempts.** Reflexion
  without execution feedback underperformed the no-reflection baseline (52% vs 60%).
  Self-repair is bottlenecked by feedback quality, and a stronger or different model's
  feedback beats self-feedback at every budget. The loop currently hands attempt 2 only the
  generic one-line `LEARNINGS.md`.
- **Prompt rules don't stop test gaming; deterministic checks partly do.** ImpossibleBench
  saw GPT-5 cheat on 54% of Conflicting-SWEbench tasks under a strict "do not modify tests"
  prompt. Read-only tests stop test edits but not special-casing, and EvilGenie shows
  holdout tests can be passed heuristically. Layer the guards: a diff-based tamper check,
  human-owned acceptance tests, and an independent judge where the harness allows it.
- **Specification defects are the largest multi-agent failure class** (MAST: 41.77%), which
  motivates a pre-run backlog readiness linter.
- **Harness-native loops are thinner than the kit's driver.** No native option provides
  disjoint-write admission, quarantine or protected-path guards. Keep bash as the portable
  core; use native flags (Claude Code budget flag, structured retry events) only as
  accelerators.
- **The driver cannot see the evaluator verdict today** (ingestion correction). The
  evaluator runs inside the slot session, the outbox is deleted after each reap, and goal
  scratch disappears with the worktree. A retry dossier needs a new pinned outbox file
  plus a persisted attempt store.

## Per-question findings

Confidence: **high** = documented by an official source or verified in this repo ·
**medium** = several independent sources agree · **low** = inferred or single community source.

### Stop conditions and budgets

The cheap additions are a per-iteration `timeout` (SIGINT first, because Claude Code
abandons the turn with exit 143 on SIGTERM), run-level and per-story ceilings computed from
the usage the driver already parses, and Claude Code `--max-budget-usd` passthrough
(present in 2.1.296 help, `--print` only). Claude's `total_cost_usd` is a client estimate
with a reported undercount after retries, so budget on tokens as well. No defensible
published defaults exist for a multi-story loop. — confidence: high (mechanisms), low
(defaults)

`--max-turns` is cited by the report but was **not** in the local 2.1.296 `--help`; verify
it before passing it through. — confidence: medium

### Retry context

A driver-persisted attempt dossier should contain the evaluator verdicts, unmet acceptance
criteria, failing test ids, `git diff --stat` and the failure signature. Inject it as fenced
DATA, with the prior diff offered as a reference the next attempt may discard. That
preserves the clean-slate diversity the self-repair study rewards. No fresh-session,
SWE-bench-scale ablation of dossier vs clean slate exists. — confidence: medium

### Backlog readiness

No published "definition of ready" linter or "fits one context window" heuristic exists. A
deterministic linter can check `writes:` syntax and pairwise overlap (reusing admission
code), protected-path references, criteria present and checkable, and size proxies.
Automatic `writes:` inference has no published reliability data; keep hand declaration
authoritative. — confidence: medium (motivation), low (heuristics)

### Convergence and drift

OpenHands' stuck detector (repeat ×4, failing-repeat ×4, A/B alternation ×6) and MAST's
failure modes suggest driver signals: file-hash oscillation across attempts, unmet-criteria
count not falling, test count dropping, and diff growth while red. None is validated as a
loop stop signal. — confidence: low

### Verification robustness

Deterministic, runner-free first step: fail a reap when the diff deletes test files, adds
skip/xfail/only/disabled markers, or reduces test count. Held-out acceptance tests need a
driver-run command. That is a trust decision: it must come from a protected path or run
configuration, never from backlog prose (story text is untrusted data). Cross-family
judging is the standard bias mitigation, but on Claude Code pins are Anthropic-only. It can
only be an install preference with the kit's existing "reduced independence" disclosure, not
a driver check. — confidence: high (gaming evidence), medium (designs)

### Rate-limit breaker

Claude Code `stream-json --verbose` emits documented `system/api_retry` events
(`error: rate_limit|overloaded|billing_error`, `retry_delay_ms`). Codex `exec --json` and
Cursor offer no typed rate-limit fields, so text matching stays for them. Upward recovery:
store `preferred_model` and `probe_after`, and probe the preferred model in HALF-OPEN on the
next claim after `probe_after`, doubling on failure. That removes today's "delete the state
file" reset. Switching Claude parsing from the `json` result envelope to `stream-json`
changes the usage-parsing path too. — confidence: high (Claude), medium (Codex/Cursor
gaps)

### Parallelism and integration

No source gives an optimal concurrency per account. Measure it from a ledger. The report's
"re-dispatch once on non-fast-forward" idea needs diagnosis first: with disjoint writes
and the subset check passing, a post-rebase conflict more likely comes from
integrator-written shared files than from story code. — confidence: low

### Human-in-the-loop and observability

Keep `ESCALATIONS.md` as the queue and render escalations plus quarantines into the
end-of-run PR body. Optional notification hook (`gh issue`/webhook), opt-in. A
gitignored JSONL run ledger with OTel GenAI-aligned field names (still "Development"
stability) enables pass rate, cost per passed story and escalation rate via `jq`, and is
the prerequisite for measuring every other change. — confidence: medium

### Sandboxing and CLI invocation

- `claude -p` without `--bare` runs project hooks and `.mcp.json` servers without a trust
  prompt. `--bare` (verified in 2.1.296 help) also skips `CLAUDE.md` auto-discovery and
  never reads OAuth or keychain (API-key auth only), so it can be opt-in only. — confidence: high
- The report says Claude Code ≥ 2.1.302 starts `-p` in Manual permission mode when nothing
  sets a mode. If true, the default `LOOP_CLI="claude -p"` stalls after upgrade. Not verified
  locally (2.1.296). — confidence: medium
- The report says Codex `exec` defaults to a read-only sandbox, which means the documented
  `LOOP_CLI="codex exec"` recipe could not write. Not verified (Codex not installed). —
  confidence: medium

### Harness-native replacement

Delegate only per-iteration budget flags and structured retry parsing. A Stop-hook loop
(`ralph-wiggum`) or Cursor Cloud Agents would drop admission, quarantine and portability and
add lock-in. — confidence: high

### Measuring the loop

Use a fixed 10–20-story benchmark backlog on a pinned toy repo, including trap stories
(conflicting tests, special-casing-only passes). Compare ledger metrics (pass within 3
attempts, cost per passed story, escalation and quarantine rate, false-APPROVED rate,
tamper trips) with interleaved A/B runs, ≥ 3 repeats, and a paired sign test. —
confidence: low (no published methodology)

## Decisions

- **Adopted:** none yet (status `ingested`). Candidate ranking after ingestion corrections:
  1. driver budgets + per-iteration timeout (C1)
  2. JSONL run ledger + end-of-run summary (C4)
  3. runner-free test-tamper check (first half of C3)
  4. attempt dossier via a new outbox file + persisted attempt store (C2, effort M)
  5. structured Claude rate-limit parsing + upward breaker recovery (C5)

  Small hygiene items: explicit Claude permission mode and Codex sandbox in documented
  `LOOP_CLI` recipes; backlog linter (C7).
- **Rejected:** harness-native replacement of dispatch (C13): loses admission,
  quarantine and portability. `--bare` as a default (breaks subscription auth and
  `CLAUDE.md` loading). A driver-level cross-family evaluator check (C10): the driver
  can't see subagent models, and Claude Code has no cross-family pins.
- **Unchanged:** driver-owned dispatch, disjoint `writes:` admission, best-of-N rejection,
  bash as single script source. No evidence overturns them. The earlier "budgets
  unenforceable" decision applied to markdown policy; driver-level enforcement from parsed
  CLI usage is consistent with it.

## Open questions

- Cursor `--output-format json` usage fields: our 2026-09-03 live probe saw camelCase
  `usage`, while Cursor's docs list none. Re-probe before any Cursor budget logic; budgets
  must fail open when fields are absent.
- Is `--max-turns` still supported by Claude Code `-p`?
- Does Claude Code ≥ 2.1.302 default `-p` to Manual permission mode?
- Does Codex `exec` default to read-only, and does `--json` ever emit typed rate limits?
- Optimal slots per account (measure via the ledger).
- Dossier with prior diff vs dossier only (A/B on a benchmark backlog).
- Where non-fast-forward integration failures actually come from.
- Copilot CLI usage output; mutation testing value; Aider, merge queues and stacked PRs (not
  researched).

## Sources

1. [Claude Code headless / CLI reference](https://code.claude.com/docs/en/headless) — Anthropic, accessed 2026-10-20 (via report); local `claude --help` 2.1.296 probed 2026-10-20
2. [SWE-agent configuration](https://swe-agent.com/latest/config/) — SWE-agent docs, accessed 2026-10-20 (via report)
3. [OpenHands configuration options](https://docs.all-hands.dev/) — All Hands AI, accessed 2026-10-20 (via report)
4. [GitHub Copilot cloud agent docs](https://docs.github.com/en/copilot) — GitHub, accessed 2026-10-20 (via report)
5. [Reflexion: Language Agents with Verbal Reinforcement Learning](https://arxiv.org/abs/2303.11366) — Shinn et al., NeurIPS 2023
6. [Is Self-Repair a Silver Bullet for Code Generation?](https://arxiv.org/abs/2306.09896) — Olausson et al., ICLR 2024
7. [Why Do Multi-Agent LLM Systems Fail? (MAST)](https://arxiv.org/abs/2503.13657) — Cemri et al., 2025
8. [ImpossibleBench](https://arxiv.org/abs/2510.20270) — Zhong, Raghunathan, Carlini, 2025
9. [EvilGenie](https://arxiv.org/abs/2511.21654) — 2025
10. [LLM Evaluators Recognize and Favor Their Own Generations](https://arxiv.org/abs/2404.13076) — Panickssery et al., 2024
11. [OpenTelemetry GenAI semantic conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/) — OpenTelemetry, accessed 2026-10-20 (via report)
12. [Effective harnesses for long-running agents](https://www.anthropic.com/engineering) — Anthropic Engineering, 26 Nov 2025 (via report)
13. [Cursor CLI output format](https://cursor.com/docs/cli) — Cursor, accessed 2026-10-20 (via report; conflicts with harness-matrix probe 2026-09-03)
14. [OpenAI Codex non-interactive mode](https://developers.openai.com/codex) — OpenAI, accessed 2026-10-20 (via report)

Scratch report: `_memory/work/research/orchestration-loop-review/report.md` · ingestion
review: `_memory/work/research/orchestration-loop-review/review.md`

Related kit ground truth: [autonomous-loop.md](../../docs/agent-kit/guide/autonomous-loop.md) ·
[autonomous-escalation.md](autonomous-escalation.md) · [runtime-language.md](runtime-language.md)
