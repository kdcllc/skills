# Orchestration Architecture

The canonical architecture template lives inside the installable skill, so it ships with
every install:

**[`skills/setup/templates/ORCHESTRATION.md`](skills/setup/templates/ORCHESTRATION.md)**

It describes the orchestrator/worker/judge system as a template with `{{TOKEN}}`
placeholders and `<!-- BOOTSTRAP: ... -->` guidance. As of kit v0.17.0 that covers:

- the **seven-phase feature flow** — alignment, goal creation, goal judgment, task
  execution, final audit, docs alignment (`align-docs`), and an approval-gated pull
  request (`ship-pr`) — with mandatory re-judge loops, 3-cycle retry limits, and
  fix-cycle **model rotation** (different family on retry 2, frontier tier on retry 3);
- **fresh-context subagents** with tiered model pinning (frontier judges, light
  workers), per-tier fallback chains, and a cost-ceiling policy in the model map;
- **hardened judging**: existence checks with a ✅/⚠️/❌/🔍 confidence ladder,
  anti-fabrication rules, and a required devil's-advocate section in goal judgment;
- **plan-time ownership contracts** — per-task `writes`/`reads`/`depends_on`
  declarations, disjointness verified at goal judgment, and an allowed-paths
  write fence in every worker prompt and context package;
- the **staged test ladder** (rungs 1–2 mid-cycle, full suites at cycle end);
- an append-only **orchestration log** per goal, silent-success artifact verification,
  and untrusted-input rules in every agent;
- a **GREENFIELD ONLY** `BOOTSTRAP:` comment in the canonical template that, on a
  greenfield `/setup`, adds an **Engineering practices** subsection (test-first / TDD
  and SOLID — documentation-only conventions, not judge auto-fail triggers), keyed off
  this install's greenfield decision / `options.greenfield`;
- the optional **autonomous loop** with structural guards — protected paths enforced by
  the loop drivers (`loop.sh`/`loop.ps1`, PowerShell 7+), circuit breakers, memory size
  gates, one human-approved PR per run;
- the loop drivers' **slot-supervision structure** (the `LOOP_SLOTS`/`LOOP_WORKTREE`
  knob documentation below and the v0.12.0 write-set-admission and
  single-writer-integration responsibilities are not in this template's prose — the
  `LOOP_WORKTREE` knob is covered in `templates/loop/SKILL.md`; `LOOP_SLOTS` and the
  v0.12.0 write-set-admission / single-writer-integration responsibilities live only
  in the drivers, `templates/loop/loop.sh`/`loop.ps1`; driver-owned dispatch is
  already covered below via the guard table's Exit-condition row, and the
  retirement + exit-aggregation material is now carried by this template's guard
  table's Circuit-breaker and Exit-condition rows) —
  `LOOP_SLOTS` (default 2, clamped `[1,3]`; live under the N>1-iff-worktree rule
  shipped in v0.12.0: honored when `LOOP_WORKTREE=1`, clamps to effective 1 when
  `LOOP_WORKTREE=0` (with a stderr note only when `LOOP_SLOTS>1` was set explicitly))
  and `LOOP_WORKTREE` (default 0 = main-tree
  iteration; `=1` runs each iteration in a driver-managed worktree with a
  tracked-instance preflight); and the drivers' new responsibilities shipped in
  v0.12.0: driver-owned story selection (dispatch), write-set admission, and
  single-writer integration (§4/§6 of the parallel-dispatch design) — with a new
  exit code 5 = setup or integration failure. The drivers' v0.13.0 responsibilities:
  completion and exit aggregation (§7) — per-slot CB1/CB2 retirement instead of a
  run-fatal stop, the run's exit codes 0–3 aggregated across slots at precedence
  4>3>2>1>0 (exit 4 short-circuiting), drained completion gated on zero quarantined
  branches, and quarantine marker files (`.loop-worktrees/QUARANTINE-<branch>.md`
  — slashes in the branch become dashes) embedding the dispatched prompt.

Running `/setup` in a target project compiles the template — along with the subagents
and skills — into the native format of each targeted harness (Claude Code, Cursor,
GitHub Copilot, OpenAI Codex). See [`README.md`](README.md) for install steps,
[`docs/research-multi-harness-upgrade.md`](docs/research-multi-harness-upgrade.md) for
the harness research, [`docs/research-squad-ideas.md`](docs/research-squad-ideas.md) for
the adopted hardening patterns, and
[`docs/design-parallel-dispatch.md`](docs/design-parallel-dispatch.md) for the judged
design for WIP-limited parallel dispatch in the autonomous loop (partially shipped —
§1/§2/§5-supervision (v0.11.0); §3.2 (parts 1-3 v0.10.0, part 4 v0.12.0); §4/§6
(v0.12.0); §3.3 (v0.12.0, extending STORY-010's per-slot counters); §7 shipped (v0.13.0
— §7.1/§7.2 deviations ratified or resolved in place; §7.3 aggregation); §5 shipped
(v0.13.0: retirement + quarantine markers, extending v0.11.0's supervision — argued
deviation on marker location recorded in place); see its Status block).

Edit the template in the skill's `templates/` directory only; this file is just a
pointer.
