# Emitter: OpenAI Codex

Target: `AGENTS.md` + `.codex/`. Codex is the structurally different harness: no agent
markdown format — roles live in `config.toml` tables, instructions in AGENTS.md (plain
markdown, no frontmatter, **32 KiB combined cap**, read once per session).

## Emit

| Source (resolved) | Destination | Translation |
|-------------------|-------------|-------------|
| `templates/ORCHESTRATION.md` | `ORCHESTRATION.md` at repo root | full doc lives here, NOT in AGENTS.md (size cap) |
| Orchestration summary | append a **short** section to root `AGENTS.md` (create if missing; keep the whole file well under the 32 KiB cap, aim ≤300 lines) | see pointer content below |
| `templates/agents/*.md` bodies | `.codex/agents/<role>.md` | strip YAML frontmatter (Codex ignores it); keep the body as the role instruction file; these files double as Cursor-readable agents |
| Role config | `.codex/config.toml` | see below |
| Per-role model layers | `.codex/agents/<role>.toml` | `model = "{{CODEX_MODEL_FRONTIER}}"` for judges, `{{CODEX_MODEL_LIGHT}}` for workers |
| `templates/loop/*` (if loop enabled) | `_loop/loop.sh`, `_loop/loop.ps1`, `_goals/backlog.md` | loop CLI: `codex exec` with `approval_policy = "never"`, `sandbox_mode = "workspace-write"` — sandbox only; invocation forms as in the Claude Code emitter (`_loop/loop.sh [max-iterations]` / `pwsh _loop/loop.ps1 [MaxIterations]`) |

`.codex/config.toml` (merge with any existing project config):

```toml
[agents]
default_subagent_model = "{{CODEX_MODEL_LIGHT}}"
default_subagent_reasoning_effort = "medium"

[agents.judge]
description = "Skeptical goal/task/code judge. Spawn to verify any completed work; returns PASS/NEEDS FIXES/REJECT. Read .codex/agents/judge.md first."
config_file = "agents/judge.toml"

[agents.qa-judge]
description = "User-perspective behavioral QA judge for captured evidence. Read .codex/agents/qa-judge.md first."
config_file = "agents/qa-judge.toml"

[agents.implementer]
description = "Checklist-driven implementer for one task per spawn. Read .codex/agents/implementer.md first."
config_file = "agents/implementer.toml"

[agents.test-writer]
description = "Coverage-obsessed test writer, external services mocked. Read .codex/agents/test-writer.md first."
config_file = "agents/test-writer.toml"
```

AGENTS.md pointer section (keep short):

```markdown
## Orchestration
Non-trivial features run through the orchestrator/worker/judge flow in
ORCHESTRATION.md: plan → judge the plan → implement per task (spawn `implementer` /
`test-writer`) → judge every task (spawn `judge`) → final audit → quality checks.
Fixes are always re-judged. Role instructions: .codex/agents/*.md.
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
