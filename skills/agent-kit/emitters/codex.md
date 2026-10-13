Translation rules live in `bin/emit.sh` (Windows: `bin/emit.cmd`); this file is caveats only.

# Emitter: OpenAI Codex

Target: `AGENTS.md` + `.codex/`. No agent markdown format — roles live in
`config.toml` tables, instructions in AGENTS.md (plain markdown, no
frontmatter, **32 KiB combined cap**, read once per session). The `[agents.*]`
tables and the AGENTS.md pointer are embedded in `bin/emit.sh`.
Append the pointer to `AGENTS.md` (create if missing; keep ≤ 32 KiB).
Appends a separate `## Memory` block (marker `<!-- orchestration-kit:memory-pointer -->`) after the orchestration pointer when absent.

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
Always emits `_kit/log-spawn.sh` and `_kit/log-spawn.cmd` (single-copy; Git for Windows on Windows).
Always emits `_kit/memory.sh`, `_kit/memory.cmd`, `_kit/memory.ps1` (loop helper), and `_memory/README.md` (single-copy), appends `_memory/.index/` and `_memory/raw/` to `.gitignore`, and appends `_memory/** text eol=lf` to `.gitattributes`; `_memory/records/` and `_memory/quarantine/` stay tracked.
Codex-only installs emit **no kit skills tree** — document `capture` and distillation in
project docs only. `_kit/memory.sh capture --harness codex` is best-effort against
`~/.codex/sessions/` rollout JSONL (see `_memory/README.md`).
