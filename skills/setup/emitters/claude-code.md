# Emitter: Claude Code

Target: `.claude/` — the canonical format, so this emitter is mostly a copy of the
resolved templates.

## Emit

Template skills are stored as `SKILL.template.md` so harnesses do not discover them
in the kit repo; emit them as `SKILL.md`.

| Source (resolved) | Destination |
|-------------------|-------------|
| `templates/agents/*.md` | `.claude/agents/*.md` (as-is; `model:` = Claude Code tier IDs/aliases from the model map, `effort:` kept) |
| `templates/skills/*` | `.claude/skills/*` (full tree copy; rename each `SKILL.template.md` → `SKILL.md`; other files copy through as-is) |
| `templates/models.map.md` | `.claude/skills/setup-models.map.md` (reference copy) |
| `templates/ORCHESTRATION.md` | `.claude/ORCHESTRATION.md` |
| `templates/loop/SKILL.template.md` + other `templates/loop/*` (if loop enabled) | `.claude/skills/auto-loop/SKILL.md`, `_loop/loop.sh` (chmod +x — no-op on Windows, harmless) AND `_loop/loop.ps1`, `_loop/breaker.sh` (chmod +x — no-op on Windows, harmless), `_loop/breaker.ps1`, `_loop/PROMPT.md`, `_goals/backlog.md` (create if missing; never overwrite) |

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
   Feature work runs through the orchestrator/worker/evaluator system — see
   .claude/ORCHESTRATION.md. Start features with /feature.
   ```
3. Orchestrator spawn allowlists use
   `tools: Agent(implementer, test-writer, evaluator, qa-evaluator, terminal, diagnostician)` comma-string
   syntax where needed — `terminal` joins the allowlist so any allowed caller can spawn
   it with a Bash or PowerShell command and get back only the requested result;
   `diagnostician` joins so the orchestrator can spawn rung 4 diagnosis after fix-cycle
   exhaustion.
4. Model values: Claude aliases (`opus`, `sonnet`, `haiku`, `fable`) or full IDs are both
   valid; `inherit` is the frontmatter default if a tier is deliberately unpinned.
   Resolve every token in `templates/models.map.md` at setup time — including
   `{{MODEL_FRONTIER_ALT_FAMILY}}` for evaluator arbitration (rung 5) — before the
   as-is copy; diagnostician pins to the frontier tier the same way evaluators do.
5. **Loop invocation is per-OS** — both drivers are always emitted; the user runs
   whichever matches their platform: `_loop/loop.sh [max-iterations]`
   (macOS/Linux/WSL/git-bash) or `pwsh _loop/loop.ps1 [MaxIterations]` (Windows,
   PowerShell 7+).

## Verify

- `grep -rn '{{\|BOOTSTRAP:' .claude/ _loop/ _goals/backlog.md` → zero hits.
- Each agent file has `name`, `description`; names match filenames.
- `claude` session lists the agents (`/agents`) and skills after restart.
- The seven P0 skills (`align-docs`, `ship-pr`, `auto-loop`, `test-ladder`,
  `goal-criteria`, `task-criteria`, `qa-criteria`) still carry
  `disable-model-invocation: true` after the as-is copy — this emitter never strips
  frontmatter keys.
- `.claude/agents/terminal.md` exists after the `templates/agents/*.md` copy, with the
  canonical `tools: Bash, Read` preserved as-is.
- `.claude/agents/diagnostician.md` exists after the same glob copy, with frontier-tier
  `model:` and `effort: high` preserved as-is.
