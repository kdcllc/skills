# Emitter: OpenAI Codex

Target: `AGENTS.md` + `.codex/`. Codex is the structurally different harness: no agent
markdown format — roles live in `config.toml` tables, instructions in AGENTS.md (plain
markdown, no frontmatter, **32 KiB combined cap**, read once per session).

## Emit

Template skills are stored as `SKILL.template.md` so harnesses do not discover them
in the kit repo; emit them as `SKILL.md`.

| Source (resolved) | Destination | Translation |
|-------------------|-------------|-------------|
| `templates/ORCHESTRATION.md` | `ORCHESTRATION.md` at repo root | full doc lives here, NOT in AGENTS.md (size cap) |
| Orchestration summary | append a **short** section to root `AGENTS.md` (create if missing; keep the whole file well under the 32 KiB cap, aim ≤300 lines) | see pointer content below |
| `templates/agents/*.md` bodies | `.codex/agents/<role>.md` | strip YAML frontmatter (Codex ignores it); keep the body as the role instruction file; these files double as Cursor-readable agents |
| Role config | `.codex/config.toml` | see below |
| Per-role model layers | `.codex/agents/<role>.toml` | `model = "{{CODEX_MODEL_FRONTIER}}"` for evaluators **and** `diagnostician`, `{{CODEX_MODEL_LIGHT}}` for workers **and** `terminal` — `terminal` is light-tier, never frontier, same as `implementer`/`test-writer`; resolve `{{MODEL_FRONTIER_ALT_FAMILY}}` from the model map for rung-5 arbitration |
| `templates/loop/*` (if loop enabled) | `_loop/loop.sh`, `_loop/loop.ps1`, `_loop/breaker.sh`, `_loop/breaker.ps1`, `_goals/backlog.md` (create if missing; never overwrite) | loop CLI: `codex exec` with `approval_policy = "never"`, `sandbox_mode = "workspace-write"` — sandbox only; invocation forms as in the Claude Code emitter (`_loop/loop.sh [max-iterations]` / `pwsh _loop/loop.ps1 [MaxIterations]`) |

`.codex/config.toml` (merge with any existing project config):

```toml
[agents]
default_subagent_model = "{{CODEX_MODEL_LIGHT}}"
default_subagent_reasoning_effort = "medium"

[agents.evaluator]
description = "Skeptical goal/task/code evaluator. Spawn to verify any completed work; returns PASS/NEEDS FIXES/REJECT. Read .codex/agents/evaluator.md first."
config_file = "agents/evaluator.toml"

[agents.qa-evaluator]
description = "User-perspective behavioral QA evaluator for captured evidence. Read .codex/agents/qa-evaluator.md first."
config_file = "agents/qa-evaluator.toml"

[agents.implementer]
description = "Checklist-driven implementer for one task per spawn. Read .codex/agents/implementer.md first."
config_file = "agents/implementer.toml"

[agents.test-writer]
description = "Coverage-obsessed test writer, external services mocked. Read .codex/agents/test-writer.md first."
config_file = "agents/test-writer.toml"

[agents.terminal]
description = "Command runner — any Bash or PowerShell command; returns only the result the caller asked for. Read .codex/agents/terminal.md first."
config_file = "agents/terminal.toml"

[agents.diagnostician]
description = "Root-cause diagnostician for task failures after fix-cycle exhaustion. Read .codex/agents/diagnostician.md first."
config_file = "agents/diagnostician.toml"
```

`.codex/agents/terminal.toml` gets the same light pin as the other workers:
`model = "{{CODEX_MODEL_LIGHT}}"`, `default_subagent_reasoning_effort` unchanged
(inherits the `[agents]` default). The `templates/agents/*.md` glob row above already
copies `terminal.md` to `.codex/agents/terminal.md` — `[agents.terminal]` above is what
registers that file so it is not a dangling, unregistered copy.

`.codex/agents/diagnostician.toml` gets the same frontier pin as the evaluators:
`model = "{{CODEX_MODEL_FRONTIER}}"` — the glob row copies `diagnostician.md` to
`.codex/agents/diagnostician.md`, and `[agents.diagnostician]` above registers it.

AGENTS.md pointer section (keep short):

```markdown
## Orchestration
Non-trivial features run through the orchestrator/worker/evaluator flow in
ORCHESTRATION.md: plan → evaluate the plan → implement per task (spawn `implementer` /
`test-writer`) → evaluate every task (spawn `evaluator`) → final audit → quality checks.
Fixes are always re-evaluated. After three fix cycles, spawn `diagnostician` for rung 4
diagnosis. Quality checks spawn `terminal` for the full-suite run so its raw output stays
out of the session. Role instructions: .codex/agents/*.md (six roles).
```

## Harness specifics

1. Project-scoped `.codex/config.toml` loads only for **trusted** projects, and
   `model_provider`, `model_providers`, `profile`, `profiles`, `notify`, `otel` are
   ignored at project level — pin models, not providers.
2. Multi-agent tools (`spawn_agent`, `wait_agent`, …) are stable and on by default; do
   not gate on `features.multi_agent` unless the project has disabled it.
3. AGENTS.md is read once at session start — edits require a new session.
4. This emitter rests on manually spot-verified (not panel-verified) docs — re-check
   https://developers.openai.com/codex/config-reference if any key is rejected.

## Verify

- No `{{` / `BOOTSTRAP:` leftovers in `AGENTS.md`, `.codex/`.
- `wc -c AGENTS.md` comfortably below 32768.
- TOML parses (`python3 -c "import tomllib,pathlib; tomllib.loads(pathlib.Path('.codex/config.toml').read_text())"`).
- `.codex/agents/terminal.md` and `.codex/agents/terminal.toml` both exist, and
  `config.toml` has an `[agents.terminal]` table pointing at
  `agents/terminal.toml` — the glob-copied file is registered, not dangling.
- `.codex/agents/diagnostician.md` and `.codex/agents/diagnostician.toml` both exist,
  and `config.toml` has an `[agents.diagnostician]` table pointing at
  `agents/diagnostician.toml` — the glob-copied file is registered, not dangling.
