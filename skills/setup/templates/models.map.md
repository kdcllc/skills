# Model Map

<!-- BOOTSTRAP: resolve every cell for the harness(es) being targeted, using CURRENT
     model IDs (verify against the harness's live model list — IDs rotate fast; never
     copy IDs from this kit's docs without checking). Delete columns for harnesses not
     installed. The resolved values replace {{MODEL_FRONTIER}} and {{MODEL_LIGHT}}
     everywhere they appear in emitted files. -->

Model IDs are **configuration, not constants**. This file is the single place they are
defined; re-run `/setup` (or edit here and re-emit) when providers rotate model names.

## Tier assignments

| Tier | Roles | Rationale |
|------|-------|-----------|
| `frontier` | orchestrator (main session), `judge`, `qa-judge` | Delegation and judging have a capability floor — don't cheap out on the roles that decide and verify |
| `light` | `implementer`, `test-writer` | Checklist-driven execution retains most quality at a fraction of the cost when the plan and the verification are strong |

## Resolved models

| Tier | Claude Code | Cursor | Copilot (VS Code) | Codex |
|------|-------------|--------|-------------------|-------|
| `frontier` | {{MODEL_FRONTIER}} | {{CURSOR_MODEL_FRONTIER}} | {{COPILOT_MODEL_FRONTIER}} | {{CODEX_MODEL_FRONTIER}} |
| `light` | {{MODEL_LIGHT}} | {{CURSOR_MODEL_LIGHT}} | {{COPILOT_MODEL_LIGHT}} | {{CODEX_MODEL_LIGHT}} |

Reasoning-effort pins (where the harness supports them): judges `high`, workers `medium`
— Claude Code `effort:` frontmatter, Cursor `[effort=...]` bracket params, Codex
`default_subagent_reasoning_effort`; Copilot has no effort key (drop it).

## Fallback chains

<!-- BOOTSTRAP: fill per targeted harness with CURRENT model IDs; delete columns for
     harnesses not installed. -->

| Tier | Chain (first available wins) |
|------|------------------------------|
| `frontier` | {{MODEL_FRONTIER}} → <same-family previous version> → <strongest standard model> → (omit pin — harness default) |
| `light` | {{MODEL_LIGHT}} → <alternate light model> → (omit pin — harness default) |

Rules (adapted from bradygaster/squad's model selector):

- **Never fall back UP a tier** — a light role must never silently land on a frontier
  model, and a frontier role never degrades below the standard rung of its chain.
- Fallbacks are silent to the user but **logged in the orchestration log**.
- Max 3 fallback attempts, then omit the model pin and take the harness default.
- Apply at most **one** complexity adjustment per spawn — no cascading bumps.
- **Cost ceiling policy**: an EXPLICIT human model choice above a plan/admin ceiling →
  warn loudly and honor it; an implicit (auto-selected) choice → downgrade to the
  ceiling; no compliant model at all → fail loud — never silently substitute.
- **Prompts are executable — treat like code**: tasks that author or edit agent, skill,
  or prompt files use the frontier tier, never the docs/light tier.

## Fix-cycle rotation (after judge rejections)

A model blind to its own class of mistake rarely fixes it on retry. Rotate:

| Fix cycle | Implementer model |
|-----------|-------------------|
| 1 | `{{MODEL_LIGHT}}` (normal) |
| 2 | `{{MODEL_ALT_FAMILY}}` — a different model **family** at comparable tier (analytical diversity) |
| 3 | `{{MODEL_FRONTIER}}` |

## Harness caveats that shape tiering

- **Copilot cost ceiling**: a subagent cannot run a *stronger* model than the session —
  the main session must run the `frontier` tier; workers pin down.
- **Cursor silent fallback**: under team-admin/plan restrictions Cursor substitutes a
  compatible model without erroring — judges should state their expected model in their
  prompt and report which model produced the verdict.
- **Claude Code env overrides**: `CLAUDE_CODE_SUBAGENT_MODEL` and
  `CLAUDE_CODE_EFFORT_LEVEL` override frontmatter; org `availableModels` allowlists can
  cause pins to be ignored.
- **Codex project config**: model pins are committable in `.codex/config.toml`, but
  `model_provider`/`model_providers`/`profile(s)` are ignored at project level.
