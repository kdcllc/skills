# Research briefs

Curated research studies for the AI Orchestration Kit live here as mutable briefs (not
`_memory/records/`). The `/research` and `/feature` workflows maintain this folder and
update brief status; **worker tasks never write here** — only orchestrator-owned promotion.

| Topic | Status | Date | Re-check by | Summary |
|-------|--------|------|-------------|---------|
| [squad-ideas.md](squad-ideas.md) | shipped | 2026-08-18 | — | Structural enforcement patterns from bradygaster/squad (fix-cycle rotation, existence checks, WIP limits). |
| [multi-harness-upgrade.md](multi-harness-upgrade.md) | shipped | 2026-08-18 | — | One canonical template source for Copilot, Cursor, Claude Code, and Codex with per-role model pins. |
| [conflict-free-multi-agents.md](conflict-free-multi-agents.md) | shipped | 2026-08-19 | — | Planning-time disjoint write-sets and single-writer discipline beat merge-time repair for multi-agent coding. |
| [token-efficient-skills.md](token-efficient-skills.md) | shipped | 2026-08-20 | — | P0 invocation flags, terminal agent, and skill/instruction hygiene for token cost. |
| [autonomous-escalation.md](autonomous-escalation.md) | shipped | 2026-08-24 | — | Phase 4 continuation ladder, diagnostician, evaluator arbitration, and failure-class taxonomy. |
| [forge-adapter-support.md](forge-adapter-support.md) | shipped | 2026-08-26 | — | Azure DevOps and GitLab Phase 7 delivery via forge adapters and multi-remote defaults. |
| [agent-memory-store.md](agent-memory-store.md) | shipped | 2026-10-08 | — | Git-tracked `_memory/` records, search CLI, loop integrator proposals, and capture/backfill. |
| [model-currency-2026-10.md](model-currency-2026-10.md) | shipped | 2026-10-08 | 2026-11-08 | Oct 2026 model-map audit and harness-native orchestration developments. |
| [runtime-language.md](runtime-language.md) | shipped | 2026-10-12 | 2027-04-12 | Bash as single script source of truth; retire PowerShell twins incrementally. |
| [orchestration-loop-review.md](orchestration-loop-review.md) | adopted | 2026-10-20 | 2027-01-20 | Loop hardening: driver budgets and timeouts, run ledger, test-tamper check, retry dossier, structured breaker recovery. |

Scratch reports and prompts stay gitignored under `_memory/work/research/<topic>/`
(for example `<topic>/report.md`, `<topic>/prompt.md`).

## Formerly

| Old path | New path or fate |
|----------|------------------|
| `docs/agent-kit/research-agent-memory-store.md` | `_memory/research/agent-memory-store.md` |
| `docs/agent-kit/research-autonomous-escalation.md` | `_memory/research/autonomous-escalation.md` |
| `docs/agent-kit/research-designing-conflict-free-multi-agents.md` | `_memory/research/conflict-free-multi-agents.md` |
| `docs/agent-kit/research-forge-adapter-support.md` | `_memory/research/forge-adapter-support.md` |
| `docs/agent-kit/research-model-currency-2026-10.md` | `_memory/research/model-currency-2026-10.md` |
| `docs/agent-kit/research-multi-harness-upgrade.md` | `_memory/research/multi-harness-upgrade.md` |
| `docs/agent-kit/research-runtime-language.md` | `_memory/research/runtime-language.md` |
| `docs/agent-kit/research-squad-ideas.md` | `_memory/research/squad-ideas.md` |
| `docs/agent-kit/research-token-efficient-skills.md` | `_memory/research/token-efficient-skills.md` |
| `docs/agent-kit/research-harness-design-upgrade.md` | deleted (evaluator rename and contracts folded into guides and templates) |
| `docs/agent-kit/design-parallel-dispatch.md` | deleted (shipped loop behavior documented in [autonomous-loop.md](../../docs/agent-kit/guide/autonomous-loop.md)) |
| `docs/agent-kit/ORCHESTRATION.md` | deleted (replaced by [docs/agent-kit/README.md](../../docs/agent-kit/README.md)) |
