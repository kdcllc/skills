# Emitter: Cursor

Target: `.cursor/` + reuse of the `.claude/` tree. Cursor natively reads
`.claude/agents/` and `.claude/skills/`, so if the Claude Code emitter also ran, skills
need no copies. Agents still get translated `.cursor/agents/` copies because Cursor's
handling of Claude-specific frontmatter (`effort:`, `tools:`, model aliases) is
undocumented, and `.cursor/` wins name conflicts.

> **Schema check first**: the exact `.cursor/agents` frontmatter schema failed
> adversarial verification. Before emitting, check https://cursor.com/docs/subagents for
> the current key set and adjust below.

## Emit

| Source (resolved) | Destination | Translation |
|-------------------|-------------|-------------|
| `templates/agents/*.md` | `.cursor/agents/*.md` | `model:` → Cursor model IDs from the model map, effort as bracket param: `{{CURSOR_MODEL_FRONTIER}}[effort=high]` for judges, `…[effort=medium]` for workers; drop the separate `effort:` key; drop `tools:` unless the live schema documents an equivalent |
| `templates/skills/*` | `.cursor/skills/*` **only if** Claude Code emitter did not run (otherwise Cursor reads `.claude/skills/`) | Skills have **no model key** in Cursor — strip `model:`/`effort:` from any skill frontmatter; **keep** `disable-model-invocation` as-is (same key, same behavior as Claude Code — do not strip it) |
| `templates/ORCHESTRATION.md` | `.cursor/ORCHESTRATION.md` (skip if `.claude/ORCHESTRATION.md` exists; reference that instead) | — |
| Pointer rule | `.cursor/rules/orchestration.mdc` | see below — **must be `.mdc`**, plain `.md` is silently ignored |
| `templates/loop/*` (if loop enabled) | as in the Claude Code emitter — `_loop/loop.sh`, `_loop/loop.ps1`, `_loop/breaker.sh`, and `_loop/breaker.ps1` | loop CLI note: use `cursor-agent` or keep `claude` per user choice; invocation forms as in the Claude Code emitter (`_loop/loop.sh [max-iterations]` / `pwsh _loop/loop.ps1 [MaxIterations]`) |

Pointer rule content:

```markdown
---
alwaysApply: true
---
Feature work runs through the orchestrator/worker/judge system described in
ORCHESTRATION.md (in .claude/ or .cursor/). Non-trivial features start with the
`feature` skill; implementation goes to the implementer/test-writer subagents; all
verification goes to the judge subagents. Never mark orchestrated work complete
without a judge PASS.
```

## Harness specifics

- Nesting: main→L1→L2 since Cursor 2.5 — the orchestrator prompt should explicitly tell
  L1 agents to spawn (users report delegation doesn't happen unprompted).
- `terminal`: pinned at the **light** Cursor model ID with `[effort=medium]`, the same
  tier as the other workers (`implementer`, `test-writer`) — it rides the
  `templates/agents/*.md` glob row above, no separate emit row needed. Cursor **drops**
  `tools:` on the translated copy per that row's rule unless the live schema documents an
  equivalent by the time you check `cursor.com/docs/subagents`; when it drops, the
  Bash/Read guard lives only in `terminal.md`'s prose, not in frontmatter — do not add a
  `tools:` key back in to compensate. The nesting note above (tell L1 to spawn) already
  covers `terminal`; do not add a second rule file for it.
- **Silent model fallback**: under team-admin/plan restrictions Cursor substitutes a
  model without erroring. The judge templates already self-report their model; keep that.
- Cloud Agents support only main→L1 — the QA-gate flow still works, but warn in the
  emitted ORCHESTRATION.md if the project relies on cloud agents.

## Verify

- No `{{` / `BOOTSTRAP:` leftovers under `.cursor/`.
- Rule file extension is `.mdc`; skill `name:` fields match folder names
  (lowercase/numbers/hyphens).
