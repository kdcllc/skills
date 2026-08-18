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
  copies for anything model- or tools-critical.

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

## Sources

code.claude.com/docs/en/{sub-agents,model-config,settings,skills} ·
cursor.com/docs/{subagents,rules,skills} ·
code.visualstudio.com/docs/{agent-customization/custom-agents,agents/run/subagents} ·
developers.openai.com/codex/{config-reference,guides/agents-md} (redirects to
learn.chatgpt.com) · full citations in `docs/research-multi-harness-upgrade.md`.
