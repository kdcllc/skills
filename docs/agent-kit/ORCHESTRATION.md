# Orchestration Architecture

The canonical architecture template lives inside the installable skill:

**[`skills/agent-kit/templates/ORCHESTRATION.md`](../../skills/agent-kit/templates/ORCHESTRATION.md)**

It describes the orchestrator/worker/evaluator system as a template with `{{TOKEN}}`
placeholders and `<!-- BOOTSTRAP: ... -->` guidance. Summary:

- **Seven-phase feature flow** — alignment through optional docs alignment and pull request; acceptance criteria at planning; evaluator gates and fix-cycle model rotation
- **Fresh-context subagents** — tiered model pinning, explicit model per spawn, per-tier fallback chains
- **Hardened evaluation** — confidence ladder, anti-fabrication, `eval_depth`, `PASS (with notes)`, continuation ladder after cycle 3 when `phases.ladder: auto`
- **Ownership contracts** — per-task `writes`/`reads`/`depends_on`, write fences, staged test ladder
- **Continuation ladder** — rungs 5→4→6 on Phase 4 exhaustion when enabled; see [`docs/agent-kit/research-autonomous-escalation.md`](research-autonomous-escalation.md)
- **Autonomous loop** — optional headless iteration with structural guards in loop drivers
- **Self-contained Cursor emission** — a **self-contained** `.cursor/` tree (skills, architecture doc, model map) with no cross-harness reads

Version history: [CHANGELOG.md](../../skills/agent-kit/CHANGELOG.md). Running `/agent-kit` compiles the template into each targeted harness's native format. Edit the template in the skill's `templates/` directory only; this file is just a pointer.
