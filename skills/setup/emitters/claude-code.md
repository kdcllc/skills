# Emitter: Claude Code

Target: `.claude/` — the canonical format, so this emitter is mostly a copy of the
resolved templates.

## Emit

| Source (resolved) | Destination |
|-------------------|-------------|
| `templates/agents/*.md` | `.claude/agents/*.md` (as-is; `model:` = Claude Code tier IDs/aliases from the model map, `effort:` kept) |
| `templates/skills/*` | `.claude/skills/*` |
| `templates/models.map.md` | `.claude/skills/setup-models.map.md` (reference copy) |
| `templates/ORCHESTRATION.md` | `.claude/ORCHESTRATION.md` |
| `templates/loop/*` (if loop enabled) | `.claude/skills/auto-loop/SKILL.md`, `_loop/loop.sh` (chmod +x — no-op on Windows, harmless) AND `_loop/loop.ps1`, `_loop/breaker.sh` (chmod +x — no-op on Windows, harmless), `_loop/breaker.ps1`, `_loop/PROMPT.md`, `_goals/backlog.md` (create if missing; never overwrite) |

## Harness specifics

1. **Pin nesting explicitly** — the default flipped twice in July 2026. Merge into
   `.claude/settings.json`:
   ```json
   { "env": { "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "3" } }
   ```
   (Merge, don't overwrite — the project may have existing settings.)
2. **CLAUDE.md pointer** — append (or create) a short section:
   ```markdown
   ## Orchestration
   Feature work runs through the orchestrator/worker/judge system — see
   .claude/ORCHESTRATION.md. Start features with /feature.
   ```
3. Orchestrator spawn allowlists use `tools: Agent(implementer, test-writer, judge, qa-judge)`
   comma-string syntax where needed.
4. Model values: Claude aliases (`opus`, `sonnet`, `haiku`, `fable`) or full IDs are both
   valid; `inherit` is the frontmatter default if a tier is deliberately unpinned.
5. **Loop invocation is per-OS** — both drivers are always emitted; the user runs
   whichever matches their platform: `_loop/loop.sh [max-iterations]`
   (macOS/Linux/WSL/git-bash) or `pwsh _loop/loop.ps1 [MaxIterations]` (Windows,
   PowerShell 7+).

## Verify

- `grep -rn '{{\|BOOTSTRAP:' .claude/ _loop/ _goals/backlog.md` → zero hits.
- Each agent file has `name`, `description`; names match filenames.
- `claude` session lists the agents (`/agents`) and skills after restart.
