# Orchestration Architecture

The canonical architecture template lives inside the installable skill, so it ships with
every install:

**[`skills/setup/templates/ORCHESTRATION.md`](skills/setup/templates/ORCHESTRATION.md)**

It describes the orchestrator/worker/judge system as a template with `{{TOKEN}}`
placeholders and `<!-- BOOTSTRAP: ... -->` guidance. As of kit v0.7.0 that covers:

- the **seven-phase feature flow** — alignment, goal creation, goal judgment, task
  execution, final audit, docs alignment (`align-docs`), and an approval-gated pull
  request (`ship-pr`) — with mandatory re-judge loops, 3-cycle retry limits, and
  fix-cycle **model rotation** (different family on retry 2, frontier tier on retry 3);
- **fresh-context subagents** with tiered model pinning (frontier judges, light
  workers), per-tier fallback chains, and a cost-ceiling policy in the model map;
- **hardened judging**: existence checks with a ✅/⚠️/❌/🔍 confidence ladder,
  anti-fabrication rules, and a required devil's-advocate section in goal judgment;
- the **staged test ladder** (rungs 1–2 mid-cycle, full suites once at cycle end);
- an append-only **orchestration log** per goal, silent-success artifact verification,
  and untrusted-input rules in every agent;
- the optional **autonomous loop** with structural guards — protected paths enforced by
  the loop drivers (`loop.sh`/`loop.ps1`, PowerShell 7+), circuit breakers, memory size
  gates, one human-approved PR per run.

Running `/setup` in a target project compiles the template — along with the subagents
and skills — into the native format of each targeted harness (Claude Code, Cursor,
GitHub Copilot, OpenAI Codex). See [`README.md`](README.md) for install steps,
[`docs/research-multi-harness-upgrade.md`](docs/research-multi-harness-upgrade.md) for
the harness research, [`docs/research-squad-ideas.md`](docs/research-squad-ideas.md) for
the adopted hardening patterns, and
[`docs/design-parallel-dispatch.md`](docs/design-parallel-dispatch.md) for the judged
design for WIP-limited parallel dispatch in the autonomous loop (not yet implemented).

Edit the template in the skill's `templates/` directory only; this file is just a
pointer.
