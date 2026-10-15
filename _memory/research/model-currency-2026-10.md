---
title: "Research: Model Currency per Role + Orchestration Developments (Oct 2026)"
topic: model-currency-2026-10
date: 2026-10-08
status: shipped
shipped_in: ["1.0.0"]
recheck_by: 2026-11-08
goals: [model-currency-v0-29]
supersedes: []
memory: [20261008T120007Z-01ee7555]
---

# Research: Model Currency per Role + Orchestration Developments (Oct 2026)

**Method**: external deep-research report
(`_memory/work/research/model-currency-2026-10/report.md`) plus an orchestrator
ingest review against the codebase and local CLIs.

**Legend**: ✅ documented (official vendor source) · 📊 measured (vendor-run unless noted)
· 🔬 verified locally on 2026-10-08 · 💬 community/secondary · 🤔 inferred.

> Model IDs and prices below are a **dated snapshot**, not configuration. The only place
> IDs live in an install is the model map; re-verify against each harness's live list
> before using any of them.

## 1. Model landscape snapshot (2026-10-08)

| Family | Frontier | Standard | Fast | Notes |
|---|---|---|---|---|
| Anthropic | Opus 5.5 `claude-opus-5-5` (2026-09-22, $4/$20) ✅ | Sonnet 5.5 `claude-sonnet-5-5` (2026-09-28, $2/$10, cache read $0.10) ✅ | Haiku 5.5 `claude-haiku-5-5` (2026-10-07, $0.10/$0.50 ≤100K prompts) ✅ | Fable 5.1 sits above Opus ($10/$50); no Haiku 5 |
| OpenAI (API) | GPT-6.1 Sol `gpt-6.1-sol` (2026-09-29, $2/$10) ✅ | — | GPT-6 Luna `gpt-6-luna` ($0.10/$0.50) 💬 | Cursor still lists GPT-5.6 Sol/Terra/Luna; Sol at $4/$20 there ✅ |
| xAI | Grok 4.7 `grok-4.7` (2026-09-21, $2/$6) ✅ | — | — | Grok 4.6 superseded; Grok 4.8 unconfirmed 💬 |
| Google | Gemini 3.1 Pro (preview) ✅ | — | Gemini 3.8 Flash ($0.75/$3.75 → $1.50/$7.50 on 2027-01-01) ✅ | |
| Cursor | — | Composer 2.5 standard ($0.50/$2.50) ✅ | — | Composer 2.5 **Fast** is the product default at $3/$15 ✅ |

- Frontier/standard token-price ratio is ~2× (Opus vs Sonnet 5.5); standard/fast is ~20×.
  Effort is as large a cost lever as tier: Sonnet 5.5 at max effort costs more per task
  than Opus 5.5 at max (Artificial Analysis via secondary reports) 💬.
- Vendor-reported benchmark gaps of a few points are within infrastructure noise
  (Anthropic: 6 pp on Terminal-Bench 2.0 from resourcing alone) ✅.

## 2. Harness facts that change kit assumptions

### Claude Code ✅

- Alias resolution is **provider-dependent**: on the Anthropic API `opus`/`sonnet`/`haiku`
  → 5.5 family; on Microsoft Foundry `opus` → Opus 4.6; Bedrock/Google Cloud `sonnet` →
  Sonnet 4.5. Full IDs pin reproducibly.
- Minimum versions: Opus 5.5 ≥ v2.1.280, Sonnet 5.5 ≥ v2.1.284, Haiku 5.5 ≥ v2.1.293.
  🔬 This machine runs v2.1.241 — below all three.
- Claude Code warns on retiring/remapped models, including subagent frontmatter `model`.
- **Cannot run non-Anthropic models**: "`ANTHROPIC_BASE_URL` changes where requests are
  sent, not which model answers them." A cross-family arbiter is unreachable natively; the
  only portable route is a Bash-capable agent shelling out to another harness's CLI 🤔.
  This contradicts the kit's prior fixture note that Claude Code "accepts full
  cross-provider model IDs when configured".
- New: `best`, `fable`, `opusplan` aliases; `PreModelSwitch` hooks; headless `-p` bills
  Fable usage credits **without asking** — a loop cost-runaway vector.

### Cursor

- **Bracket params are the documented frontmatter syntax** ✅ —
  `<model-id>[effort=high,context=300k]`, `composer-2.5[fast=false]`. Suffix slugs
  (`…-high`) still appear in pickers and CLI listings 💬. The CLI bracket key
  (`effort=` vs `reasoning=`) is unresolved 💬.
- **Silent fallback goes to the parent's model** when a subagent model can't be resolved
  (staff, Aug 2026) ✅; quoting the YAML value is enough to trigger it 💬. 🔬 The kit
  emitter writes Cursor `model:` unquoted, so bracket values are safe.
- `agent models` / `--list-models` is team-filtered (v2026.08.26) and matches `--model`
  (v2026.09.15) ✅. 🔬 For this account it still returns "No models available" — setup
  cannot rely on it universally; the IDE picker remains an evidence source.
- Documented base IDs use hyphens for Claude (`claude-opus-5-5`) and dots for GPT/Grok
  (`gpt-5.6-sol`, `grok-4.7`). The prefixed `cursor-grok-4.6-xhigh` matches no documented
  ID ✅.

### Copilot

- Usage-based billing (GitHub AI Credits) since 2026-06-01; per-model multipliers only on
  legacy annual plans 💬/✅. Opus 5.5 and Grok 4.7 available. Subagent ≤ session-tier rule
  **not re-verified** — keep it.

### Codex ✅

- Effort values `low | medium | high | xhigh | max | ultra` (model-dependent); `ultra`
  fans out across subagents (avoid for kit roles 🤔).
- Standalone custom agent files `.codex/agents/<name>.toml` (`model`,
  `model_reasoning_effort`, `sandbox_mode`, `developer_instructions`) — native read-only
  enforcement via `sandbox_mode = "read-only"`.

## 3. Role → model conclusions

- **Frontier roles** (orchestrator, evaluator, qa-evaluator, diagnostician): Opus 5.5 on
  Claude Code and Cursor. Cursor's docs: "sets a new high score on CursorBench … We
  recommend the high thinking variant" 📊. No independent review-precision benchmark
  exists for Opus 5.5 vs GPT-6.1 Sol vs Grok 4.7.
- **Standard roles** (implementer, test-writer): Sonnet 5.5 (Claude Code); Composer 2.5
  *standard*, not Fast (Cursor).
- **Fast tier** is now evidenced: Anthropic positions Haiku 5.5 "as a subagent on coding
  work"; Cognition reports Opus 5.5 lead + Haiku 5.5 sidekick at FrontierCode 66.2 📊
  (vendor quote). `terminal` is the natural fit; implementer stays standard (Haiku 39% vs
  Sonnet 71% on Terminal-Bench 4.0, vendor).
- **Cross-family rotation** (fix cycle 2, rung-5 arbiter) remains an unproven hedge — no
  controlled study found. One model must not fill both the light alternate and the
  frontier arbiter slot; Cursor's `gpt-5.6-sol` is frontier-priced.
- **Read-only adherence** should rest on harness enforcement (Cursor `readonly: true`,
  Codex `sandbox_mode`, Claude Code tool allowlists), not model obedience 🤔.
- **Self-reported model is weak evidence** 🤔: it is model introspection, so a hard
  requested-vs-reported gate should fail only on an explicit family mismatch and prefer
  harness metadata (Claude Code JSON usage carries the model ID).

## 4. Orchestration developments (Apr–Oct 2026)

- Harness-native overlap: Claude Code agent teams (experimental), background agents,
  Code Review, auto mode; Cursor Bugbot, Automations, Cloud Agents, background subagents,
  SDK that reads `.cursor/agents/*.md`; Copilot ensemble code review (+47% addressed
  high-severity comments, GitHub-internal). Stance: wrap or defer to review/sandbox
  features; don't remove kit features until native equivalents are GA with per-role pins
  on all four harnesses.
- **No cross-vendor subagent standard** exists — per-harness emitters stay.
- MCP 2026-07-28: stateless core, Multi Round-Trip Requests, Tasks as an extension,
  Roots/Sampling/Logging deprecated, OAuth hardening — low kit impact.
- Verification research: execution-grounded checks beat self-evaluation (arXiv
  2607.25152); parallel tasks can "pass alone, fail together" (arXiv 2609.25396) — argues
  for a post-merge integration test run after parallel dispatch 💬 (details unreviewed).

## 5. Open questions

1. Which models a given Cursor plan exposes to subagents, when `agent models` is empty.
2. Cursor CLI bracket key (`effort=` vs `reasoning=`); whether frontmatter accepts suffix
   slugs.
3. Copilot `.agent.md` model strings and the subagent ≤ session rule under AI Credits.
4. Independent LLM-as-judge / bug-finding comparison of current frontier models.
5. Cross-family vs same-family-higher-effort retry evidence.
6. Anthropic's "Choosing a Claude model and effort level in Claude Code" guidance (unread).
7. AGENTS.md / Agent Skills / ACP / A2A status; community orchestrator traction.
