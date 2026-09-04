Translation rules live in `bin/emit.sh` / `emit.ps1`; this file is caveats only.

# Emitter: Claude Code

Target: `.claude/` — canonical format. The `CLAUDE.md` pointer and
`.claude/settings.json` merge content is embedded in `bin/emit.sh` / `emit.ps1`.

## Harness specifics

Orchestrator spawn allowlists use this literal tools line:

tools: Agent(implementer, test-writer, evaluator, qa-evaluator, terminal, diagnostician)

`terminal` is on the allowlist so callers can spawn it; `diagnostician` joins
for rung 4. P0 skills keep `disable-model-invocation: true` (this emitter never
strips frontmatter keys).

Model values: Claude aliases (`opus`, `sonnet`, `haiku`, `fable`) or full IDs
are both valid; `inherit` is the frontmatter default if a tier is deliberately
unpinned.

Pin nesting explicitly — the default flipped twice in July 2026. Merge
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=3` into `.claude/settings.json` (merge,
don't overwrite).

Loop-enabled installs emit `_loop/loop.ps1` and `_loop/breaker.ps1` (and the
bash twins). `_goals/backlog.md` (create if missing; never overwrite).
Always emits `_kit/log-spawn.sh` and `_kit/log-spawn.ps1` (single-copy).
