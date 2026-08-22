# Harness Capability Matrix

Reference for the `setup` skill's emitters. **Verified 2026-08-18** against official
docs for the interchange/capability table below (✅ = 3-vote adversarial verification
against the cited page; 🔎 = manually spot-verified against the live page; ⚠️ =
primary source, unverified). **Context/invocation/command-output addendum verified
2026-08-20** from live vendor docs (D = documented on the live page that day; I =
inferred; U = unknown) — see that section; it is not 3-vote adversarial. This space
moves fast — when an emitter hits behavior that contradicts this table, trust the
live docs, emit accordingly, and update this file with a new verified-on date.

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
- **Kit policy (as of v0.19.0):** the Cursor emitter emits a fully **self-contained**
  `.cursor/` tree and does not rely on this cross-read — per-field fidelity of
  Claude-specific keys is undocumented, and **dual-install** behavior (both `.claude/`
  and `.cursor/` present) must not depend on `.claude/`'s presence. The FACTS above
  remain true and verified; this is a kit emission policy built on top of them, not a
  correction to them.

## Capability table

| Capability | Claude Code | Cursor | Copilot (VS Code) | OpenAI Codex |
|---|---|---|---|---|
| Agent definition | `.claude/agents/*.md`, YAML frontmatter ✅ | `.cursor/agents/` + reads `.claude/agents/` ✅ | `.github/agents/*.agent.md` (ex-`.chatmode.md`) + reads `.claude/agents` ✅ | `[agents.<name>]` tables in `config.toml` (`config_file`, `description`) 🔎 |
| Skills | `.claude/skills/*/SKILL.md` ✅ | `.cursor/skills/` + reads `.claude/skills/`; `name`+`description` required; **no model key** ✅ | `.github/skills/*/SKILL.md` first-class (progressive disclosure, `/skill`, `disable-model-invocation`) ✅ 2026-08-20 | `skills.config` per-skill enablement 🔎 |
| Fresh-context subagents | Yes; nesting depth via `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (default flipped twice July 2026 — **pin explicitly**) ✅ | Yes; main→L1→L2 since 2.5 (cloud: L1 only) ✅ | Yes (`agent/runSubagent`, stateless); nesting off by default (`chat.subagents.allowInvocationsFromSubagents`, max 5) ✅ | Yes: `spawn_agent` et al., `features.multi_agent` stable, on by default 🔎 |
| Per-agent model pin | frontmatter `model:` (alias/ID/`inherit`); env > tool param > frontmatter > parent ✅ | frontmatter `model` incl. bracket params `[effort=…,context=…]` (e.g. `<model-id>[effort=high,context=300k]`); slug-suffix effort variants (e.g. `…-high`-shaped model IDs) also appear in Cursor's live model lists — both forms coexist; see the model map's guidance; up or down OK; **silent fallback** under restrictions — re-verified 2026-08-21 against cursor.com/docs/subagents ✅ | frontmatter `model` (string or fallback array); **cannot exceed parent tier** — stronger refuses to run; cheaper-than-parent is valid; CLI rejects array form ✅ | `agents.default_subagent_model`, per-role `config_file`; spawn-time wins 🔎 |
| Effort pin | `effort:` low→max on agents/skills/commands ✅ | `[effort=…]` bracket param (e.g. `[effort=high]`) — re-verified 2026-08-21 against cursor.com/docs/subagents, same scheme as the model-pin row above ✅ | — | `default_subagent_reasoning_effort` 🔎 |
| Rules/instructions | `CLAUDE.md` (does NOT read AGENTS.md; import it from CLAUDE.md 💬) | `.cursor/rules/*.mdc` only (plain `.md` ignored); keys `alwaysApply`/`description`/`globs`; native nested AGENTS.md ✅ | `.github/copilot-instructions.md`, `.github/instructions/` | AGENTS.md root-down concat, nearest-last-wins; **32 KiB cap** (`project_doc_max_bytes`); read once per session 🔎 |
| Role controls | `tools: Agent(implementer, test-writer)` allowlists; skill `disable-model-invocation: true` drops the description from session-start context ✅ 2026-08-20 | description-driven or `/name`; L1 agents may need explicit "you MUST spawn" prompting; skill `disable-model-invocation: true` (same spelling) ✅ 2026-08-20 | `agents:` allowlist, `user-invocable: false` (agents *and* skills, different meaning), skill/agent `disable-model-invocation: true` ✅ | role `description` guides spawn 🔎 |
| Unattended mode | headless `claude -p` ⚠️ | Cloud Agents (L1 only) ✅ | Copilot coding agent on issues ⚠️ | `approval_policy: never` + `sandbox_mode` 🔎 |

Windows note: per-harness CLI availability on Windows is unverified — the loop
drivers assume the harness CLI runs natively where invoked.

## Friction points every emitter must respect

1. Cursor rules must be **`.mdc`** — a plain `.md` in `.cursor/rules` is silently ignored. ✅
2. `.claude/agents` uses comma-separated-string `tools:`; `.agent.md` uses YAML arrays. ✅
3. Cursor skills have no model key — pin models at the **agent** level for Cursor. ✅
4. Codex AGENTS.md has no frontmatter/schema — roles and models live in `config.toml`. 🔎
5. The exact `.cursor/agents` frontmatter schema was **refuted** in verification (0-3) —
   re-check `cursor.com/docs/subagents` live before emitting Cursor agent files,
   including the current model-ID/bracket-param format and the live model list (an
   unknown or stale model ID is substituted silently, with no error surfaced).
6. Copilot: the session runs the frontier tier (ceiling rule); evaluators cannot pin
   up. Workers and other subagents **may pin down**. The ceiling is “cannot exceed the
   parent tier,” not “must equal the parent tier.”
7. Copilot skills live at `.github/skills/*/SKILL.md` (first-class as of 2026-08-20).
   Do **not** inline skill bodies into agents on current VS Code; reserve inlining
   for a detected legacy build with no skills support.
8. `disable-model-invocation: true` is the same skill frontmatter key on Claude Code,
   Cursor, and Copilot. On Claude Code it removes the skill **description** from
   session-start context (“full skill loads when you invoke”). Copilot `.prompt.md`
   is the zero-metadata-tax analogue for manual-only workflows.
9. Command-output size cap is Claude-only (`BASH_MAX_OUTPUT_LENGTH`, default 30,000
   characters, middle-truncation). Cursor and Copilot document no equivalent; Copilot
   documents terminal `outputLocation` and a timeout, not a size cap. Isolate noisy
   commands in a light-tier subagent and capture quiet command forms at setup —
   never invent runner flags.
10. Codex agent-name rule — **verified on 2026-08-21** against
    `developers.openai.com/codex/config-reference`: `[agents.<name>]` custom role
    names must not collide with the reserved scalar setting names under `[agents]`
    (`enabled`, `default_subagent_model`, `default_subagent_reasoning_effort`,
    `interrupt_message`, `max_concurrent_threads_per_session`, `max_threads`);
    `evaluator` and `qa-evaluator` collide with none of them, so both names are
    confirmed safe under the live rule. The external report's stronger "simple ASCII
    names… `name` is the source of truth" phrasing was NOT found verbatim on that
    page as of this check — only the reserved-name-collision constraint above is
    independently confirmed; treat any broader ASCII/charset claim as still
    unverified.

## Context, skills invocation, and command-output isolation (verified 2026-08-20)

Session start injects skill **name + description only** (not bodies, not parameter
schemas) on all three IDEs. Typical metadata ≈ 50–105 tokens/skill (description
words × ~1.3) or ~100 tokens/skill per the Agent Skills spec community figure.
Full sources and the kit skill-by-skill verdict:
`docs/research-token-efficient-skills.md`.

| Capability | Claude Code | Cursor | Copilot (VS Code) |
|---|---|---|---|
| Block auto-invoke, keep `/name` | `disable-model-invocation: true` (D) | `disable-model-invocation: true` (D) | `disable-model-invocation: true` (D) |
| “Only model invokes” | `user-invocable: false` (D) | via `paths` / agent-decides; no skill `user-invocable` doc (I) | `user-invocable: false` on skills (D); on `.agent.md` hides from picker but still spawnable |
| Manual-only prompt file | `.claude/commands/*.md` (D) | `.cursor/commands` / migrate-to-skills (D) | `.prompt.md` (D) |
| Path-scoped guidance | skill `paths:` + nested CLAUDE.md (D) | `.mdc` `globs:` (D) | `.github/instructions/*.instructions.md` `applyTo` (D) |
| Skill body model pin | `model:` on skill (D) | **no skill model key** — pin on agent (D) | pin on agent/prompt (D) |
| Command-output isolation | subagent + `model: haiku`; `context: fork` (D) | built-in Bash subagent; custom agent model ID (D) | `runSubagent` (summary only); **model ≤ parent tier** — pinning *down* is valid (D) |
| Output size cap | `BASH_MAX_OUTPUT_LENGTH` 30,000 default (D) | none (U) | none documented — only `outputLocation` / timeout (D) |
| Command-rewrite hook | PreToolUse `updatedInput` / PostToolUse `updatedToolOutput` (D) | `beforeShellExecution` / `afterShellExecution` in hooks.json (D) | agent hooks Preview; shell-rewrite not the documented pattern (I) |
| Cache-bust events | model, effort, fast-mode, compact, >1h, MCP change (D) | model/effort/context/tools change, inactivity (D) | model switch mid-session, instruction/agent change, inactivity (D) |
| `/context` equivalent | `/context` + `/doctor` (D) | Customize panel; dashboard usage (D; no token breakdown) | Cache Explorer + Diagnostics view (D) |
| Subagent nesting | subagents spawn subagents (D) | L1 + direct subagents spawn; grandchildren can't (D) | off by default; `chat.subagents.allowInvocationsFromSubagents` (D) |

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

Observed once (CLI-observed, n=1): with same-named `judge` (role renamed to
evaluator in v0.18.0) agents in both `.github/agents` and `.claude/agents`, only the
native one surfaced in the recognition reply; mechanism unconfirmed — reply-level
dedup of same-named agents not excluded. Do not treat as a precedence rule.

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
code.visualstudio.com/docs/{agent-customization/custom-agents,agents/run/subagents,copilot/copilot-customization,copilot/customization/prompt-files} ·
developers.openai.com/codex/{config-reference,guides/agents-md} (redirects to
learn.chatgpt.com) · full citations in `docs/research-multi-harness-upgrade.md` ·
2026-08-20 context/invocation addendum:
`docs/research-token-efficient-skills.md`.
