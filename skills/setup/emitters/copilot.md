Translation rules live in `bin/emit.sh` / `emit.ps1`; this file is caveats only.

# Emitter: GitHub Copilot (VS Code)

Target: `.github/`. Check the live VS Code custom-agents page
(https://code.visualstudio.com/docs/agent-customization/custom-agents)
before pinning tool names.

## Harness specifics

**Cost ceiling**: a subagent cannot run a stronger model than the session; a
too-strong pin makes the subagent **not run at all**. Orchestrated sessions
run the frontier tier; evaluators never pin above it; workers pin down.
Copilot has no `effort` key.

Nesting stays off (kit default). `chat.subagents.allowInvocationsFromSubagents`
must not be enabled by `/setup`. Do not write `.vscode/settings.json`.
`feature.agent.md` is the L1 orchestrator and spawns workers and evaluators
directly; that top-level spawn works with nesting off. Workers do not spawn
subagents of their own; when output needs isolating, spawn `terminal`.

Skills: copy `disable-model-invocation` as-is on
`.github/skills/*/SKILL.md`. Subagents are stateless — context packages must
be complete on first send.

The copilot-instructions pointer content is embedded in `bin/emit.sh` /
`emit.ps1`.

Loop-enabled installs emit `_loop/loop.ps1` and `_loop/breaker.ps1` (and the
bash twins). `_goals/backlog.md` (create if missing; never overwrite).
Always emits `_kit/log-spawn.sh` and `_kit/log-spawn.ps1` (single-copy).
