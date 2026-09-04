# Changelog

Kit version lives in `skills/setup/VERSION` and is written into each install's
`orchestration-kit.manifest.json` as `kitVersion`. Entries below are newest first.
Versions without an entry (v0.14.0–v0.17.0 and earlier than v0.12.0) predate this
changelog; their history lives in git and the research/design docs under `docs/`.

## v0.27.0 — Deterministic emitter

- **Scripted emit** — `/setup` Steps 4–6 are deterministic: the LLM writes
  `orchestration-kit.answers.json` (schema 1; id table in
  `skills/setup/reference/bootstrap-ids.md`), then runs
  `skills/setup/bin/emit.sh` or `emit.ps1` (PowerShell 7 twin — same flags,
  stdout/stderr, exit codes, tree + manifest bytes). Bash twin requires `jq`;
  use `emit.ps1` when jq is missing. Flags: `--answers`, `--upgrade`,
  `--dry-run`, `--force`, `--check-answers`, `--root`, `--kit`. Exit codes:
  0 ok · 2 usage/jq/unreadable · 3 answers invalid · 4 upgrade blocked
  (user-modified; `--force` overrides) · 5 verify failed · 6 template syntax.
  Success prints one line:
  `emit: written N · unchanged M · pruned P · seeds-kept S · warnings W · manifest orchestration-kit.manifest.json · kit <VERSION>`.
- **Template grammar** — `<!-- BOOTSTRAP[id]: … -->` (replaces the retired
  `<!-- BOOTSTRAP: … -->` opener); `<!-- IF flag -->` … `<!-- ENDIF flag -->`
  (and `!flag`) for conditional spans. Resolution order: IF → BOOTSTRAP[id] →
  `{{TOKEN}}`. Placeholder table in `skills/setup/SKILL.md` Step 4; id/flag table in
  `skills/setup/reference/bootstrap-ids.md`; contributor grammar summary in
  `docs/guide/contributing.md`.
- **Manifest `answers`** — `orchestration-kit.manifest.json` embeds the answers
  snapshot; upgrades re-emit with `--upgrade` (add `--answers` only when the
  interview changed). Pre-v0.27.0 installs have no `answers` — run Steps 1–4
  once, then `--answers … --upgrade`.
- **Translation in script** — per-harness translation rules moved from emitter
  prose into `bin/emit.*`; `emitters/*.md` are caveats only (live model-check
  URLs, silent-fallback warnings).
- **Self-install dogfood** — `scripts/self-install.sh` / `.ps1` copy skills,
  then emit this repo's instance from `skills/setup/fixtures/self-answers.json`
  unless `--no-emit` (`--force-emit` passes `--force` to emit). `--dry-run`
  passes through to emit.
- **Tests** — new `tests/templates/emit-determinism.sh` guards the emitter
  (byte-identical twins when `pwsh` is present; idempotent re-run).

## v0.26.0 — Honest token metric

- **Rename** — orchestration-log `est_tokens` → `io_est_tokens` (orchestrator I/O proxy,
  chars/4; not the subagent's spend). Running totals split into `running io` and
  `running work`; pre-v0.26 logs fall back to `running total` for the io side.
- **Footprint block** — all six canonical agent templates end every report with
  `### Footprint` / `files_read: N (~C chars)` / `commands_run: N` (last non-blank
  lines inside the report fence). `log-spawn outcome` parses the `files_read` line and
  emits `work_read_chars: C · work_est_tokens: C/4`, or `n/a` when missing/malformed
  (never fails the outcome). Optional `--work-chars C` overrides parsing.
- **Loop usage capture** — `loop.sh` / `loop.ps1` twins: `LOOP_USAGE_FORMAT`
  (`auto`|`claude`|`codex`|`cursor`|`none`; default `auto` = basename of `LOOP_CLI`'s
  first word) splices machine-readable flags at startup (`claude --output-format json`,
  `agent --output-format json`, `codex exec --json`); post-processes raw output and
  prints `usage: input=<n> output=<n> cache_read=<n|n/a> cache_write=<n|n/a>
  cost_usd=<x|n/a> format=<f>` after each slot's `tail -n 25` block. Optional
  `LOOP_USAGE_LOG` appends the `usage:` line prefixed with an ISO timestamp, slot id,
  and story id. Silent-none when unset and `auto` resolves to
  `none`; explicit `LOOP_USAGE_FORMAT=none` prints `usage: unavailable (format none)`.
  Bash: `jq` missing → `usage: unavailable (jq not on PATH)` once at startup, then none
  for that run; no envelope → `usage: unavailable (no envelope)`. PowerShell uses
  built-in JSON parsing.
- **Harness matrix** — new row "Token usage exposure (headless CLI)" with per-harness
  flags and 2026-09-03 verification dates.

## v0.25.0 — Scripted orchestration log

- **`log-spawn` twins** — new canonical `skills/setup/templates/tools/log-spawn.sh` and
  `log-spawn.ps1` (PowerShell 7+, byte-identical output) write the per-goal
  orchestration log. Emitted **single-copy** to `_kit/log-spawn.sh` / `_kit/log-spawn.ps1`
  on every install (all four emitters; `SKILL.md` Step 5 "Tools extras"); manifest
  `files` gains both `_kit/` keys on upgrade, no prunes.
- **Artifacts instead of inlined prose** — the orchestrator writes each context package
  to `_goals/<goal>/spawns/NN-context.md` and each verbatim report to
  `spawns/NN-report.md`; the log references them. Subcommands: `spawn` (measures
  `context_chars`), `outcome` (measures `report_chars`, computes `est_tokens` =
  (context + report)/4 and the running total), `note` (phase completions, ladder
  transitions, skips). Exit codes 0 ok · 2 usage · 3 ledger integrity · 4 missing path.
- Feature skill and `ORCHESTRATION.md` template rewritten around the script; running
  `_kit/log-spawn.*` inline is exempt from the `terminal` spawn rule. Guard
  `tests/templates/log-spawn.sh` (behavioral + twin parity when `pwsh` is present).
- Carried-forward v0.24.0 minors: iron rule names `PASS (with notes)`; `phases.ladder`
  gate wording in the ORCHESTRATION Phase 4 step and Summary; docs list `model
  requested` before launch and `model reported` after return.

## v0.24.0 — Token-efficiency policy

- **A1 tiering** — context packages carry a required `## Model` section
  (`requested: <id> · tier: light|frontier · rotation: cycle N`); orchestrator passes
  the model explicitly on every spawn; every agent report starts with
  `**Model (self-reported)**: ...`. Model map (`skills/setup/templates/models.map.md`):
  "prompts are executable → frontier" narrowed to edits of `templates/agents/*` and
  `templates/skills/*-criteria/*` only.
- **A2 evaluation** — new verdict `PASS (with notes)` when every issue is `minor`
  (`skills/setup/templates/agents/evaluator.md`, `task-criteria/SKILL.template.md`);
  `NEEDS FIXES` requires ≥1 `major`/`blocker`. `eval_depth` default inverts to
  `light` in task templates; `full` required for contract tasks, interface consumers,
  and tasks writing agents/criteria/drivers/shared infra. Evaluator re-checks resume
  the same evaluator; implementer may resume for fix cycle 1 only.
- **A3 ladder** — `goal.md` `phases:` block gains `ladder: escalate|auto` (default
  `escalate`; loop sets `auto` in `loop/SKILL.template.md` and `PROMPT.md`).
- **A4 docs** — Phase 6 default off (`align_docs: false` in goal template); align-docs
  6.2 grep-confirmed edit list; ≤3 docs folds 6.3 into 6.5. Root `ORCHESTRATION.md`
  shrinks to a pointer; history in this changelog.
- Feature-skill byte budget raised 9728 → 10240 bytes (test retarget in task 08).

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
