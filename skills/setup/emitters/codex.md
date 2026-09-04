Translation rules live in `bin/emit.sh` / `emit.ps1`; this file is caveats only.

# Emitter: OpenAI Codex

Target: `AGENTS.md` + `.codex/`. No agent markdown format — roles live in
`config.toml` tables, instructions in AGENTS.md (plain markdown, no
frontmatter, **32 KiB combined cap**, read once per session). The `[agents.*]`
tables and the AGENTS.md pointer are embedded in `bin/emit.sh` / `emit.ps1`.
Append the pointer to `AGENTS.md` (create if missing; keep ≤ 32 KiB).

## Harness specifics

Project-scoped `.codex/config.toml` loads only for **trusted** projects, and
`model_provider`, `model_providers`, `profile`, `profiles`, `notify`, `otel`
are ignored at project level — pin models, not providers.

Multi-agent tools (`spawn_agent`, `wait_agent`, …) are stable and on by
default; do not gate on `features.multi_agent` unless the project has
disabled it.

AGENTS.md is read once at session start — edits require a new session.
Re-check https://developers.openai.com/codex/config-reference if any key is
rejected.

Loop-enabled installs emit `_loop/loop.ps1` and `_loop/breaker.ps1` (and the
bash twins). `_goals/backlog.md` (create if missing; never overwrite).
Always emits `_kit/log-spawn.sh` and `_kit/log-spawn.ps1` (single-copy).
