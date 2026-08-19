# Harness Capability Matrix

Reference for the `setup` skill's emitters. **Verified 2026-08-18** against official
docs (✅ = 3-vote adversarial verification against the cited page; 🔎 = manually
spot-verified against the live page; ⚠️ = primary source, unverified). This space moves
fast — when an emitter hits behavior that contradicts this table, trust the live docs,
emit accordingly, and update this file with a new verified-on date.

## The interchange finding

The Claude Code format is the de-facto interchange format — which is why this kit's
canonical templates are Claude-format:

- Cursor natively reads `.claude/agents/`, `.codex/agents/`, `.claude/skills/`,
  `.codex/skills/` (`.cursor/` wins name conflicts). ✅ [cursor.com/docs/subagents, /skills]
- VS Code (Copilot) natively reads `.claude/agents` alongside `.github/agents`. ✅
  [code.visualstudio.com/docs/agent-customization/custom-agents]
- Caveat: directory *loading* is confirmed; per-field fidelity of Claude-specific keys
  (`tools:`, model aliases, `effort:`) is undocumented — emit translated per-harness
  copies for anything model- or tools-critical. (Claude Code raw-tree fidelity for
  name/description empirically verified 2026-08-18, CLI-observed; tools partial — see
  Empirical validation)

## Capability table

| Capability | Claude Code | Cursor | Copilot (VS Code) | OpenAI Codex |
|---|---|---|---|---|
| Agent definition | `.claude/agents/*.md`, YAML frontmatter ✅ | `.cursor/agents/` + reads `.claude/agents/` ✅ | `.github/agents/*.agent.md` (ex-`.chatmode.md`) + reads `.claude/agents` ✅ | `[agents.<name>]` tables in `config.toml` (`config_file`, `description`) 🔎 |
| Skills | `.claude/skills/*/SKILL.md` ✅ | `.cursor/skills/` + reads `.claude/skills/`; `name`+`description` required; **no model key** ✅ | supported (per ruler/AIS matrices ⚠️) | `skills.config` per-skill enablement 🔎 |
| Fresh-context subagents | Yes; nesting depth via `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (default flipped twice July 2026 — **pin explicitly**) ✅ | Yes; main→L1→L2 since 2.5 (cloud: L1 only) ✅ | Yes (`agent/runSubagent`, stateless); nesting off by default (`chat.subagents.allowInvocationsFromSubagents`, max 5) ✅ | Yes: `spawn_agent` et al., `features.multi_agent` stable, on by default 🔎 |
| Per-agent model pin | frontmatter `model:` (alias/ID/`inherit`); env > tool param > frontmatter > parent ✅ | frontmatter `model` incl. `[effort=…,context=…]`; up or down OK; **silent fallback** under restrictions ✅ | frontmatter `model` (string or fallback array); **cannot exceed parent tier** — stronger refuses to run; CLI rejects array form ✅ | `agents.default_subagent_model`, per-role `config_file`; spawn-time wins 🔎 |
| Effort pin | `effort:` low→max on agents/skills/commands ✅ | `[effort=…]` ✅ | — | `default_subagent_reasoning_effort` 🔎 |
| Rules/instructions | `CLAUDE.md` (does NOT read AGENTS.md; import it from CLAUDE.md 💬) | `.cursor/rules/*.mdc` only (plain `.md` ignored); keys `alwaysApply`/`description`/`globs`; native nested AGENTS.md ✅ | `.github/copilot-instructions.md`, `.github/instructions/` | AGENTS.md root-down concat, nearest-last-wins; **32 KiB cap** (`project_doc_max_bytes`); read once per session 🔎 |
| Role controls | `tools: Agent(implementer, test-writer)` allowlists ✅ | description-driven or `/name`; L1 agents may need explicit "you MUST spawn" prompting ✅ | `agents:` allowlist, `user-invocable: false`, `disable-model-invocation: true` ✅ | role `description` guides spawn 🔎 |
| Unattended mode | headless `claude -p` ⚠️ | Cloud Agents (L1 only) ✅ | Copilot coding agent on issues ⚠️ | `approval_policy: never` + `sandbox_mode` 🔎 |

Windows note: per-harness CLI availability on Windows is unverified — the loop
drivers assume the harness CLI runs natively where invoked.

## Friction points every emitter must respect

1. Cursor rules must be **`.mdc`** — a plain `.md` in `.cursor/rules` is silently ignored. ✅
2. `.claude/agents` uses comma-separated-string `tools:`; `.agent.md` uses YAML arrays. ✅
3. Cursor skills have no model key — pin models at the **agent** level for Cursor. ✅
4. Codex AGENTS.md has no frontmatter/schema — roles and models live in `config.toml`. 🔎
5. The exact `.cursor/agents` frontmatter schema was **refuted** in verification (0-3) —
   re-check `cursor.com/docs/subagents` live before emitting Cursor agent files.
6. Copilot: the session runs the frontier tier (ceiling rule); judges cannot pin up.

## Empirical validation (2026-08-18, CLI-observed)

Live headless-CLI probes were run against per-harness scratch fixtures (outside this
repo, per story-001-harness-validation) to test per-field frontmatter fidelity
empirically rather than by documentation alone. Full detail, transcripts, and
per-claim evidence citations live in the session scratchpad's `hv-results.md`
(not committed to this repo — quoted here only where load-bearing).

**Method:** headless CLI probes (`claude -p`, `cursor-agent`, `copilot -p`) against
per-harness fixtures, instrumented with per-agent nonces embedded in `description:`
fields, file-read denial where the harness exposes a mechanism (Claude Code:
`--disallowedTools "Read,Grep,Glob,Bash"`), and a decoy negative-control agent/nonce
per fixture — a `honored` verdict requires nonce traversal under active denial AND
absence of the decoy nonce. Transcripts are retained in the session scratchpad
(`hv-*/probes/*.txt`) — not committed to this repo. **GUI/IDE behavior was not
exercised by any probe — every result below is CLI-scoped**, not evidence about any
IDE/GUI surface (VS Code Copilot chat panel, Cursor IDE panel, or a hypothetical
Claude Code IDE extension).

| Harness | `name` | `description` | `model` | `effort` | `tools` (injected-key test: `WebSearch, WebFetch`) |
|---|---|---|---|---|---|
| Claude Code (`claude`) | honored | honored | untestable (no model/effort metadata surfaced in captured output) | untestable (no model/effort metadata surfaced in captured output) | partial (ambiguity: injected pair returned verbatim — injected-key test credited — but the same reply also asserted file-visibility facts, e.g. directory contents and exact frontmatter key order/formatting, that the active `Read,Grep,Glob,Bash` denial should have made unobservable; downgraded from a clean `honored`) |
| Cursor (`cursor-agent`) | untestable (no model available for account) | untestable (no model available for account) | untestable (no model available for account) | untestable (no model available for account) | untestable (no model available for account) |
| Copilot (VS Code CLI, `copilot`) | partial (confound: file-read not deniable) | partial (confound: file-read not deniable) | untestable (no introspection surface; native file omits the keys) | untestable (no introspection surface; native file omits the keys) | partial (confound: file-read not deniable) |
| OpenAI Codex (`codex`) | untested — CLI absent | untested — CLI absent | untested — CLI absent | untested — CLI absent | untested — CLI absent |
| VS Code GUI (Copilot chat panel / Cursor IDE panel / any Claude Code IDE extension) | untested — not installed, no GUI surface in this headless environment | untested — not installed, no GUI surface in this headless environment | untested — not installed, no GUI surface in this headless environment | untested — not installed, no GUI surface in this headless environment | untested — not installed, no GUI surface in this headless environment |

Cursor's arm was gated pre-budget: `cursor-agent models` reported "No models
available for this account" (`cursor-agent status` separately confirmed the account
is logged in, so this is a model-availability restriction, not an auth failure) —
zero probe budget was spent, including for the Q2 dual-emission (`.cursor/agents/*-cursor`)
schema-acceptance check. Copilot's initial two probes failed unauthenticated (auth
lost mid-session, on the first invocation after a clean auth smoke test; the
auto-update-caused-invalidation explanation is the most plausible read of the
observed sequence but is not itself transcript-proven) — a user-authorized re-auth
and re-probe superseded that unauthenticated state with the results in the table
above. Copilot exposes no file-read denial mechanism (`copilot help permissions`
documents only `shell()/write()/<mcp-server>()/url()` permission kinds, no
Read/Grep/Glob-equivalent), so no Copilot cell can clear `honored` regardless of
nonce fidelity — every re-probed cell caps at `partial`. `model`/`effort` remain
untestable for a different reason: the native `.agent.md` fixture deliberately
omits both keys (a sanctioned manifest deviation), leaving nothing to introspect
even with working auth.

Observed once (CLI-observed, n=1): with same-named `judge` agents in both
`.github/agents` and `.claude/agents`, only the native one surfaced in the
recognition reply; mechanism unconfirmed — reply-level dedup of same-named agents
not excluded. Do not treat as a precedence rule.

**Evidence-floor status:** 9 non-untestable cells were obtained across all harnesses
vs the goal's floor of 5 non-untestable cells — floor cleared (9 ≥ 5): Claude Code
contributes 3 (`name` honored, `description` honored, `tools` partial); the Copilot
re-probe contributes 6 confound-capped `partial` cells (native `name`, native
`description`, native schema-acceptance, raw-tree `name`, raw-tree `description`,
and `tools` — native tree only).
Composition caveat: 6 of the 9 are confound-capped partials from Copilot, the one
harness with no file-read denial mechanism (so its cells are ceilinged at `partial`
independent of nonce fidelity); only the 3 Claude Code cells carry denial-controlled
evidence (an active `Read,Grep,Glob,Bash` deny list during the probe). Cursor still
contributes zero — its cells are gated on model availability, not auth, so the
Copilot re-authorization does not touch them.

## Sources

code.claude.com/docs/en/{sub-agents,model-config,settings,skills} ·
cursor.com/docs/{subagents,rules,skills} ·
code.visualstudio.com/docs/{agent-customization/custom-agents,agents/run/subagents} ·
developers.openai.com/codex/{config-reference,guides/agents-md} (redirects to
learn.chatgpt.com) · full citations in `docs/research-multi-harness-upgrade.md`.
