Translation rules live in `bin/emit.sh` / `emit.ps1`; this file is caveats only.

# Emitter: Cursor

Target: `.cursor/` as a **self-contained** tree. Every file this emitter emits
resolves `{{IDE_DIR}}` → `.cursor`. Dual-install must behave identically whether
or not `.claude/` exists.

> **Schema check first**: before emitting, check https://cursor.com/docs/subagents
> for the current agent-frontmatter key set AND the live Cursor model list.
> Unknown or stale model IDs are substituted silently by Cursor — no error
> surfaces, so a typo'd or rotated-out ID fails quietly downstream.

The `.mdc` pointer (`alwaysApply: true`) content is embedded in `bin/emit.sh` /
`emit.ps1`. Must be `.mdc`; plain `.md` is silently ignored.

## Harness specifics

Nesting: main→L1→L2 since Cursor 2.5 — the orchestrator prompt should tell L1
agents to spawn. Cloud Agents support only main→L1.

`diagnostician` pins the frontier Cursor model (same tier as `evaluator`).
`terminal` pins light; Cursor drops `tools:` unless the live schema documents
an equivalent — the Bash/shell + Read guard lives in `terminal.md` prose.
Skills have no model key — strip `model:`/`effort:`; keep
`disable-model-invocation`.

**Silent model fallback**: under team-admin/plan restrictions, or when the
resolved ID is unknown or stale, Cursor substitutes a model without erroring.
Evaluators must self-report which model produced the verdict.

Loop-enabled installs emit `_loop/loop.ps1` and `_loop/breaker.ps1` (and the
bash twins). `_goals/backlog.md` (create if missing; never overwrite).
Always emits `_kit/log-spawn.sh` and `_kit/log-spawn.ps1` (single-copy).
