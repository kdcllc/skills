# k2-rightsize

## Hypothesis

Small requests pay the full feature flow (goal evaluation, a separate final audit) for work that needs neither. A deterministic, logged size rubric before the Phase 1 questions can route them to a lite path, which lowers cost and duration without lowering the pass rate, while requests that touch a shared interface keep the full flow.

## Change

The first line of `## Phase 1 — Alignment` in the feature skill gains the clause ``Run `reference/size-check.md`;`` before the MCQs. The new `reference/size-check.md` holds the rubric and the routing:

- Rubric: lite only when (a) at most 3 files are expected to change, (b) no new or changed shared interface (exported signature, schema, CLI flag, config key or file format consumed by other modules), (c) no new dependency, (d) no destructive, security or infrastructure surface. Judged from the request and the files it names.
- The four answers and the route (`lite` or `full`) are logged with one `_kit/log-spawn.sh note` line, which is their only record; `goal.md` records just the route, as a `route: full|lite` key in the `phases:` block.
- `full` runs the phases as today. `lite` keeps the Phase 1 confirmation, writes one task file with acceptance criteria and no separate final test task, runs pre-flight (including trace-lint) after Phase 2 and before Phase 4, skips Phase 3 goal evaluation, runs one implementer and one evaluator in Phase 4 (fix cycles, their cap and the continuation ladder unchanged), and skips the separate Phase 5 audit. The task's Phase 4 PASS plus the Quality Checks (rung 3) is the final approval: the orchestrator logs `Phase 5 APPROVED (lite route, no separate audit)`, then runs Archive, then reads `phases:` for Phase 6 and 7.
- A lite goal that grows past the rubric switches to `full` and logs it.
- `reference/progress-line.md` says a lite goal counts Phases 1, 2, 4 and its task (plus Phases 6 and 7 when enabled).
- The goal template gains the `route:` key.
- `ORCHESTRATION.md` qualifies its two phase-exit INVARIANTs (Phase 3 to 4, Phase 5 to Quality Checks) with a lite-route clause pointing to `reference/size-check.md`, lists `size-check.md` in its four reference-tree listings, and `reference/preflight.md` says pre-flight runs before Phase 4 on the lite route.

## Expected effect

- Cost and duration: lower on `01-trivial-fix`, `02-bug-fix`, `03-small-feature`, `08-scope-trap` and `10-error-handling`, which the rubric routes to lite (no Phase 3 evaluator spawn, no Phase 5 audit spawn). `03-small-feature` is borderline: its `--json` CLI flag may be judged a shared interface under rubric (b), which would route it to full and show no change.
- No change on `04-multi-file-rename` and `09-signature-change`: rubric (b) routes them to full.
- Pass rate: expected equal. A drop on the lite tasks would mean the skipped goal evaluation or audit was catching real defects.
- The eval runner's kit prompt tells the agent to stop after Phase 5 is APPROVED. On the lite route the log line `Phase 5 APPROVED (lite route, no separate audit)` is that stop event; without it a lite run would not know when to stop.

## Marker

`Phase 5 APPROVED (lite route, no separate audit)`

## Files touched

- `templates/skills/feature/SKILL.template.md` (one in-line edit, 11230 to 11261 bytes)
- `templates/skills/feature/reference/size-check.md` (new)
- `templates/skills/feature/reference/progress-line.md`
- `templates/skills/feature/reference/preflight.md`
- `templates/ORCHESTRATION.md`
- `templates/skills/feature/templates/goal.md`
