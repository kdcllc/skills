<!-- BOOTSTRAP[models-map-title]: heading after resolve — `# Model Map` or a subtitle naming the targeted harnesses and instance kind.
# Model Map
-->

Model IDs are **configuration, not constants**. This file is the single place they are
defined; re-run `/setup` (or edit here and re-emit) when providers rotate model names.

<!-- BOOTSTRAP[models-map-live-check]: resolve every cell for the harness(es) being targeted, using CURRENT
     model IDs (verify against the harness's live model list — IDs rotate fast; never
     copy IDs from this kit's docs without checking). The resolved values replace the
     harness-named tokens everywhere they appear in emitted files. For Cursor specifically: confirm every
     resolved ID against the harness's live model list before emitting — Cursor
     substitutes an unknown or invalid model ID silently (no error), so a typo'd or
     stale ID here fails quietly downstream instead of at resolution time. -->

## Tier assignments

| Tier | Roles | Rationale |
|------|-------|-----------|
| `frontier` | orchestrator (main session), `evaluator`, `qa-evaluator`, `diagnostician` | Delegation and evaluation have a capability floor — don't cheap out on the roles that decide and verify; continuation-ladder diagnosis needs frontier-tier reasoning |
| `light` | `implementer`, `test-writer`, `terminal` | Checklist-driven execution and compact command running retain most quality at a fraction of the cost when the plan and the verification are strong |

## Resolved models

<!-- IF want_claude -->
<!-- IF want_cursor -->
| Tier | Claude Code | Cursor |
|------|-------------|--------|
| `frontier` | {{CLAUDE_MODEL_FRONTIER}} | {{CURSOR_MODEL_FRONTIER}} |
| `light` | {{CLAUDE_MODEL_LIGHT}} | {{CURSOR_MODEL_LIGHT}} |
<!-- ENDIF want_cursor -->
<!-- IF !want_cursor -->
| Tier | Claude Code |
|------|-------------|
| `frontier` | {{CLAUDE_MODEL_FRONTIER}} |
| `light` | {{CLAUDE_MODEL_LIGHT}} |
<!-- ENDIF !want_cursor -->
<!-- ENDIF want_claude -->
<!-- IF !want_claude -->
| Tier | Cursor |
|------|--------|
| `frontier` | {{CURSOR_MODEL_FRONTIER}} |
| `light` | {{CURSOR_MODEL_LIGHT}} |
<!-- ENDIF !want_claude -->
<!-- IF want_copilot -->

- Copilot (VS Code): frontier `{{COPILOT_MODEL_FRONTIER}}`, light `{{COPILOT_MODEL_LIGHT}}`
<!-- ENDIF want_copilot -->
<!-- IF want_codex -->

- Codex: frontier `{{CODEX_MODEL_FRONTIER}}`, light `{{CODEX_MODEL_LIGHT}}`
<!-- ENDIF want_codex -->

<!-- BOOTSTRAP[models-map-effort]: fill per targeted harness; drop Copilot/Codex sentences when those harnesses are absent; Cursor effort encoding per live docs.
Reasoning-effort pins (where the harness supports them): evaluators `high`, workers `medium`
— Claude Code `effort:` frontmatter, Codex `default_subagent_reasoning_effort`; Copilot
has no effort key (drop it). Cursor's effort encoding is not stable enough to hardcode
here: Cursor's docs currently describe two coexisting forms — `…[effort=high]`-style
bracket params appended to the model ID, and slug-suffix effort variants on the model
name itself (shaped like `…-thinking-high`) that surface in some model lists. Neither
form has superseded the other — check the live Cursor docs/model list at emit time and
use whichever form they document that day.
-->

## Fallback chains

<!-- BOOTSTRAP[fallback-chains]: fill per targeted harness with CURRENT model IDs; delete columns for
     harnesses not installed.
| Tier | Chain (first available wins) |
|------|------------------------------|
| `frontier` | {{MODEL_FRONTIER}} → <same-family previous version> → <strongest standard model> → (omit pin — harness default) |
| `light` | {{MODEL_LIGHT}} → <alternate light model> → (omit pin — harness default) |
-->

Rules (adapted from bradygaster/squad's model selector):

- **Never fall back UP a tier** — a light role must never silently land on a frontier
  model, and a frontier role never degrades below the standard rung of its chain.
- Fallbacks are silent to the user but **logged in the orchestration log**.
- Max 3 fallback attempts, then omit the model pin and take the harness default.
- Apply at most **one** complexity adjustment per spawn — no cascading bumps.
- **Cost ceiling policy**: an EXPLICIT human model choice above a plan/admin ceiling →
  warn loudly and honor it; an implicit (auto-selected) choice → downgrade to the
  ceiling; no compliant model at all → fail loud — never silently substitute.
- **Prompts are executable — narrowly**: only tasks that edit `templates/agents/*`
  or `templates/skills/*-criteria/*` (the files that shape every later spawn's
  behavior) use the frontier tier; skills, emitters, drivers, docs, and tests stay
  on the light tier.
- **Every spawn names its model.** The orchestrator passes the tier's resolved ID
  explicitly on every spawn and records `requested` vs the agent's self-reported
  model in the orchestration log; `inherit` is legitimate only for a tier the
  install deliberately left unpinned.

<!-- IF loop -->
### Loop fallback chain

<!-- BOOTSTRAP[loop-fallback]: fill with CURRENT model IDs for the harness(es) targeted. Resolves {{LOOP_MODEL_CHAIN}}
     (one comma-separated string, first entry = preferred, no spaces around the
     commas — neither driver twin trims chain entries) wherever that token appears
     in the emitted loop templates.
| Chain (first available wins) | Resolves |
|-------------------------------|----------|
| {{MODEL_LIGHT}} → <alternate light model> → (omit pin — harness default) | `{{LOOP_MODEL_CHAIN}}` |

Light-tier by default — the loop's iterations are implementer/test-writer-shaped work,
same as the `light` row above. Ends with the same omit-the-pin rule as the tables
above: a trip past the last chain entry clears the model pin and the harness default
takes over (no hardcoded model IDs outside this file).
-->
<!-- ENDIF loop -->

## Fix-cycle rotation (after evaluator rejections)

A model blind to its own class of mistake rarely fixes it on retry. Rotate:

<!-- BOOTSTRAP[models-map-fix-cycle]: fill per targeted harness with CURRENT model IDs.
| Fix cycle | Implementer model |
|-----------|-------------------|
| 1 | `{{MODEL_LIGHT}}` (normal) |
| 2 | `{{MODEL_ALT_FAMILY}}` — a different model **family** at comparable tier (analytical diversity) |
| 3 | `{{MODEL_FRONTIER}}` |
-->

### After cycle 3 — continuation ladder pins

When fix cycles 1–3 exhaust, the continuation ladder (see ORCHESTRATION.md) applies:

<!-- BOOTSTRAP[frontier-alt-family]: resolve {{MODEL_FRONTIER_ALT_FAMILY}} to a frontier-tier model from a
     different provider family than {{MODEL_FRONTIER}} — same pattern as
     {{MODEL_ALT_FAMILY}} at light tier, but never reuse {{MODEL_ALT_FAMILY}} for
     arbitration (light tier ≠ frontier tier).
| Ladder step | Model pin |
|-------------|-----------|
| Diagnosis-driven implementation attempt (rung 4) | `{{MODEL_FRONTIER}}` |
| Evaluator arbitration mode (rung 5) | `{{MODEL_FRONTIER_ALT_FAMILY}}` — a different model **family** from the primary evaluator at frontier tier (analytical diversity at the capability floor) |
-->
<!-- IF want_copilot -->

**Copilot fit:** frontier = session tier, so diagnostician and arbiter pins respect the
cost ceiling; Copilot has no effort key (drop it).
<!-- ENDIF want_copilot -->

## Harness caveats that shape tiering

<!-- BOOTSTRAP[models-map-caveats]: keep bullets for targeted harnesses; drop Copilot/Codex when untargeted; add instance-specific notes (Cloud Agents, alias validity).
- **Copilot cost ceiling**: a subagent cannot run a *stronger* model than the session —
  the main session must run the `frontier` tier; workers pin down.
- **Cursor silent fallback**: under team-admin/plan restrictions, or when the resolved
  ID is unknown/stale (a rotated-out or misspelled model name), Cursor substitutes a
  compatible model without erroring — evaluators should state their expected model in
  their prompt and report which model produced the verdict.
- **Claude Code env overrides**: `CLAUDE_CODE_SUBAGENT_MODEL` and
  `CLAUDE_CODE_EFFORT_LEVEL` override frontmatter; org `availableModels` allowlists can
  cause pins to be ignored.
- **Codex project config**: model pins are committable in `.codex/config.toml`, but
  `model_provider`/`model_providers`/`profile(s)` are ignored at project level.
-->
