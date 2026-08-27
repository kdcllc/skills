# Emitter: Cursor

Target: `.cursor/` as a **self-contained** tree. This emitter never relies on Cursor's
native cross-reading of `.claude/agents/` or `.claude/skills/` — per-field fidelity of
Claude-specific frontmatter keys (`effort:`, `tools:`, model aliases) is undocumented, so
a dual-install (both `.claude/` and `.cursor/` present) must behave identically whether
or not `.claude/` exists. Every file this emitter emits resolves `{{IDE_DIR}}` →
`.cursor`: `{{IDE_DIR}}` is re-resolved per emitter against the Step 4 scratch copy —
never resolved once globally for all harnesses.

> **Schema check first**: the exact `.cursor/agents` frontmatter schema failed
> adversarial verification, and Cursor's `model:` ID/slug format also changes without
> notice. Before emitting, check https://cursor.com/docs/subagents for the current
> agent-frontmatter key set AND the live Cursor model list for the current model-ID
> format, and adjust below — including the `{{MODEL_FRONTIER_ALT_FAMILY}}` arbitration
> pin from the model map's Cursor column. Unknown or stale model IDs are substituted
> silently by Cursor — no error surfaces, so a typo'd or rotated-out ID fails quietly
> downstream.

## Emit

Template skills are stored as `SKILL.template.md` so harnesses do not discover them
in the kit repo; emit them as `SKILL.md`.

| Source (resolved) | Destination | Translation |
|-------------------|-------------|-------------|
| `templates/agents/*.md` | `.cursor/agents/*.md` | `model:` → Cursor tier IDs from the model map's **Cursor column**, in whatever format the live docs/model list document at emit time — Cursor has documented both bracket-style `effort`/`context` options appended to the model ID and slug-suffix effort variants on the model name itself (shaped like `…-thinking-high`); never hardcode either scheme as the only one, use whichever form the model map's Cursor column encodes; drop the separate `effort:` key; drop `tools:` unless the live schema documents an equivalent |
| `templates/skills/*` | `.cursor/skills/*` (unconditional — emitted regardless of whether the Claude Code emitter also ran) | copy the full skill directory tree — rename each `SKILL.template.md` to `SKILL.md`; nested payloads (`feature/templates/*`, `feature/reference/*`, `research/templates/*`, etc.) copy through as-is; skills have **no model key** in Cursor — strip `model:`/`effort:` from any skill frontmatter; **keep** `disable-model-invocation` as-is (same key, same behavior as Claude Code — do not strip it) |
| `templates/models.map.md` | `.cursor/skills/setup-models.map.md` (reference copy, mirroring the Claude Code emitter's equivalent row) | — |
| `templates/ORCHESTRATION.md` | `.cursor/ORCHESTRATION.md` (unconditional — emitted regardless of whether `.claude/ORCHESTRATION.md` exists) | — |
| Pointer rule | `.cursor/rules/orchestration.mdc` | see below — **must be `.mdc`**, plain `.md` is silently ignored |
| `templates/loop/SKILL.template.md` (if loop enabled) | `.cursor/skills/auto-loop/SKILL.md` (`{{IDE_DIR}}` = `.cursor`) | — |
| `templates/loop/*` `_loop/` files (if loop enabled) | `_loop/loop.sh`, `_loop/loop.ps1`, `_loop/breaker.sh`, `_loop/breaker.ps1` — **single-copy**, resolved to the primary harness's dir (not duplicated per-harness even when multiple IDEs are installed) | loop CLI note: use `cursor-agent` or keep `claude` per user choice; invocation forms as in the Claude Code emitter (`_loop/loop.sh [max-iterations]` / `pwsh _loop/loop.ps1 [MaxIterations]`) |

Pointer rule content:

```markdown
---
alwaysApply: true
---
Feature work runs through the orchestrator/worker/evaluator system described in
.cursor/ORCHESTRATION.md. Non-trivial features start with the `feature` skill;
implementation goes to the implementer/test-writer subagents; all verification goes to
the evaluator subagents. Never mark orchestrated work complete without an evaluator PASS.
```

## Harness specifics

- Nesting: main→L1→L2 since Cursor 2.5 — the orchestrator prompt should explicitly tell
  L1 agents to spawn (users report delegation doesn't happen unprompted).
- `diagnostician`: pinned at the **frontier** Cursor model ID, the same tier as
  `evaluator` and `qa-evaluator` — it rides the `templates/agents/*.md` glob row above,
  no separate emit row needed, and its model value/format comes from the model map's
  **Cursor column** frontier row.
- `terminal`: pinned at the **light** Cursor model ID, the same tier as the other workers
  (`implementer`, `test-writer`) — it rides the `templates/agents/*.md` glob row above, no
  separate emit row needed, and its model value/format comes from the model map's
  **Cursor column**, in whichever form — bracket-param or slug-suffix — the live
  docs/model list document that day. Cursor **drops** `tools:` on
  the translated copy per that row's rule unless the live schema documents an equivalent
  by the time you check `cursor.com/docs/subagents`; when it drops, the Bash/shell + Read
  guard lives only in `terminal.md`'s prose, not in frontmatter — do not add a `tools:`
  key back in to compensate. The agent runs Bash or PowerShell (`pwsh` via the shell
  tool). The nesting note above (tell L1 to spawn) already covers `terminal`; do not add
  a second rule file for it.
- **Silent model fallback**: under team-admin/plan restrictions, or when the resolved ID
  is unknown or stale (a rotated-out or misspelled model name), Cursor substitutes a
  model without erroring — including the `{{MODEL_FRONTIER_ALT_FAMILY}}` arbitration pin.
  The evaluator templates already self-report their model; keep that, and require the
  arbiter to state which model actually produced its verdict when silent fallback may
  have applied.
- Cloud Agents support only main→L1 — the QA-gate flow still works, but warn in the
  emitted ORCHESTRATION.md if the project relies on cloud agents.

## Verify

- No `{{` / `BOOTSTRAP:` leftovers under `.cursor/`.
- No stray `.claude/` path references inside any file this emitter emits under
  `.cursor/`. Plain `rg` honors `.gitignore` and returns vacuously empty on a gitignored
  `.cursor/` instance tree, so use an ignore-blind grep form instead, e.g.
  `grep -rn '\.claude/' .cursor/ --exclude-dir=setup`. The `--exclude-dir=setup` exempts
  `.cursor/skills/setup/`, the self-install compiler copy, which legitimately references
  `.claude/` as source material and is not itself an emitted output.
- Rule file extension is `.mdc`; skill `name:` fields match folder names AND agent
  `name:` fields match file names (lowercase/numbers/hyphens).
- `.cursor/skills/setup-models.map.md` exists.
- Every emitted `.cursor/agents/*.md` `model:` value appears in the emitted
  `setup-models.map.md`'s **Cursor column** — a value that doesn't is either stale or
  pinned to the wrong tier.
- `.cursor/agents/terminal.md` exists.
