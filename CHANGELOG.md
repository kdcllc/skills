# Changelog

Kit version lives in `skills/setup/VERSION` and is written into each install's
`orchestration-kit.manifest.json` as `kitVersion`. Entries below are newest first.
Versions without an entry (v0.14.0–v0.17.0 and earlier than v0.12.0) predate this
changelog; their history lives in git and the research/design docs under `docs/`.

## v0.23.0 — Feature-skill slimming

- Acceptance criteria are defined at planning: every task file carries an
  `## Acceptance Criteria` section (criterion + verification method each), created at
  Phase 2 and validated once by the Phase 3 goal evaluator.
- The separate pre-code contract gate (`contracts/NN-name.contract.md`, v0.18.0–v0.22.0)
  was removed; the task file is the testable scope source for Phase 4 workers and
  evaluators.
- Phases 6 (docs alignment) and 7 (pull request) are optional, gated on a `phases:`
  block in `goal.md`.
- Proxy token logging in the orchestration log: `context_chars`, `report_chars`,
  `est_tokens` fields with a running total.
- Per-phase ORCHESTRATION section reads instead of whole-file reads.
- The continuation ladder moved to `reference/continuation-ladder.md` inside the
  feature skill.
- Template skills renamed `SKILL.md` → `SKILL.template.md` for harness discovery
  hygiene (nested template payloads are no longer discovered as live skills).

## v0.22.0 — Forge adapter

- Phase 7 delivery through a **forge adapter**: GitHub / Azure DevOps / GitLab /
  hand-over. Phase 7 is never deleted from an install.

## v0.21.0 — Canonical template sync

- Synced the canonical architecture template to shipped v0.12–v0.20 behavior:
  research handoff at Phase 3, the escalation **Ladder** line, the closer-task rung-3
  carve-out, and the loop dispatch / exit-funnel / merge-gate summary.

## v0.20.0 — Continuation ladder

- Phase 4 **continuation ladder** after fix-cycle exhaustion: rung 5 arbitration
  (unanimous-failure heuristic), rung 4 diagnosis-first (new `diagnostician`
  subagent), rung 6 decomposition + selective retry.
- Closed failure-class taxonomy on every non-PASS verdict; always-escalate bypass for
  `destructive` / `security` / `infra`.
- Hard guards: attempt cap after cycle 3, repeated-failure signature detection, and
  required orchestration-log transitions.

## v0.19.0 — Self-contained Cursor emission + greenfield gate

- Targeting Cursor emits a fully **self-contained** `.cursor/` tree — agents, skills,
  the architecture doc, and the model map — with no reliance on `.claude/` cross-reads.
- `{{IDE_DIR}}` resolved per emitter rather than once globally; the model-tier table
  references the emitted model map; emit-time obligation to check Cursor's live model
  list before emitting agent frontmatter.
- `/setup` Step 2a **greenfield gate**: on sparse workspaces it shows a recommended
  tree (TypeScript/Node and Python first-class) and creates nothing until confirmed,
  then optionally offers skills.sh stack skills with 1000+ installs.

## v0.18.0 — Evaluator vocabulary + hardened evaluation

- Renamed the verification subagents to `evaluator` / `qa-evaluator`.
- Calibration exemplars and an **execute-before-score** rule in the evaluator agent.
- Hard per-criterion threshold in the criteria skills — no averaging away one failing
  dimension.
- `eval_depth` intensity routing (`full` / `light`), set by the orchestrator, never a
  skip.

## v0.13.0 — Loop completion + exit aggregation

- Per-slot CB1/CB2 retirement instead of a run-fatal stop.
- Run exit aggregated across slots with precedence `4 > 3 > 2 > 1 > 0`.
- Quarantine-gated completion: drained-backlog exit `0` only when no branch was
  quarantined during the run.
- `.loop-worktrees/QUARANTINE-<branch>.md` markers (slashes in branch names become
  dashes) embedding the dispatched prompt.
- New exit code `5` for setup/integration failures.
- Completion-time backlog re-scan raises the missing/unreadable-backlog cause at a
  fifth site.

## v0.12.0 — Driver-owned dispatch

- Driver-owned story selection (dispatch), write-set admission, and the
  single-writer integrator in the loop drivers.
- `LOOP_SLOTS` live under the N>1-iff-worktree rule: honored when `LOOP_WORKTREE=1`,
  clamped to an effective 1 when `LOOP_WORKTREE=0` (stderr note only when
  `LOOP_SLOTS>1` was set explicitly).
