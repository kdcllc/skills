# Changelog

All notable changes to the `agent-kit` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `agent-kit/vX.Y.Z`.

The kit version is `metadata.version` in [SKILL.md](SKILL.md); the emitter writes it into each install's `orchestration-kit.manifest.json` as `kitVersion`. Before re-adding with a new tag, read the target version's entry, especially its **Upgrade notes**.

## [Unreleased]

## [1.0.0] - 2026-10-11

First release from [kdcllc/skills](https://github.com/kdcllc/skills). Kit behavior is unchanged from v0.30.0 apart from the items below.

### Added

- Imported from a private repository at v0.30.0, where the skill was named `setup`. That repository is archived; its history is kept below as the 0.x entries (versions without an entry — v0.14.0–v0.17.0 and earlier than v0.12.0 — predate the changelog).
- Maintainer material moved alongside the skill pack: the developer guide and research studies under [docs/agent-kit/](../../docs/agent-kit/), the test suites under [tests/agent-kit/](../../tests/agent-kit/), and the dogfood installer under [scripts/agent-kit/](../../scripts/agent-kit/). None of it ships inside the skill folder.

### Changed

- **Renamed `setup` → `agent-kit`.** The skill folder, the `name:` frontmatter, and the slash command (`/setup` → `/agent-kit`). The emitted model map is now `<ide>/skills/agent-kit-models.map.md` (was `setup-models.map.md`), and the manifest `kit` id is now `agent-kit`.
- **Version source.** The kit version moved from the `VERSION` file to `metadata.version` in `SKILL.md`; `bin/emit.sh` and `bin/emit.ps1` read it from there. `VERSION` is gone.
- **Emit verify** skips both `.cursor/skills/agent-kit/` and a leftover `.cursor/skills/setup/` compiler copy when checking `.cursor/` for `.claude/` references, so an upgrade does not fail before the old copy is deleted.
- **Memory `source` labels** — `_memory/README.md` now says to use a repo-relative path only for git-tracked files. Gitignored origins get a label instead: `goal <name> (<file>)`, `goals ledger (<file>)`, `research <name> (<file>)`, or `<harness>-session <short id>`. The rule applies to new records; existing records are immutable and keep their source (the id's 8-hex suffix hashes the body only, so a re-add with a relabeled source and the same body is reported as a duplicate).

### Fixed

- The `SKILL.md` `description` is now a quoted YAML string. Unquoted, its `): ` sequence made strict YAML parsers reject the frontmatter, so the Skills CLI skipped the skill.

### Upgrade notes

- Install from the new repository: `npx skills add kdcllc/skills --skill agent-kit`. Pin with `npx skills add kdcllc/skills#agent-kit/v1.0.0 --skill agent-kit`.
- Delete the old compiler copies — `.claude/skills/setup/`, `.cursor/skills/setup/`, `.github/skills/setup/`, or `.agents/skills/setup/`, whichever exist.
- Re-emit from the manifest: `bash .claude/skills/agent-kit/bin/emit.sh --upgrade` (or `pwsh .claude/skills/agent-kit/bin/emit.ps1 --upgrade`; Cursor: `.cursor/skills/agent-kit`, Copilot: `.github/skills/agent-kit`). The upgrade writes `agent-kit-models.map.md`, prunes `setup-models.map.md`, re-points the emitted skills and `ORCHESTRATION.md` at `/agent-kit`, and refreshes `_memory/README.md`. The manifest then shows `kit: agent-kit` and `kitVersion: 1.0.0`.
- Invoke `/agent-kit` wherever you used `/setup`.

## [0.30.0] - 2026-10-09

**Memory store (core).**

- **`_memory/` layout** — git-tracked `records/YYYY/MM/<id>.md` (immutable, one record
  per file) and `quarantine/`; derived `.index/` and reserved `raw/` are gitignored.
- **`_kit/memory.*` twins** — single-copy `memory.sh` / `memory.ps1` with `add`,
  `index`, `search`, and `show` subcommands.
- **Search** — keyword `grep` engine by default; `--engine fts` re-ranks the same
  candidate set by bm25 when SQLite FTS5 is available (auto-detected by `index`).
- **Admission screen** — instruction-like content routes to `quarantine/` (exit 5).
- **Emitter wiring** — emits `_memory/README.md`; appends `_memory/.index/` and
  `_memory/raw/` to `.gitignore` and `_memory/** text eol=lf` to `.gitattributes`.
- **Harness matrix** — documents that Claude Code reads `AGENTS.md` only when no
  `CLAUDE.md` exists; adds a dated native-memory/transcripts/hooks addendum.
- **Next releases** — B: read protocol and wiring; C: redaction and transcript capture;
  D: back-fill.

- **Upgrading** — Re-emit with `--upgrade` (or a full `/setup` re-run). New paths
  (`_kit/memory.*`, `_memory/README.md`, gitignore/gitattributes lines) appear on upgrade;
  existing installs keep prior behavior until re-emit.

## [0.29.0] - 2026-10-09

**Model currency (Oct 2026).**

- **Fast tier** — optional `models.<harness>.fast` in the answers file; `terminal` pins
  to it (defaults to `light` when omitted so existing installs keep prior pins).
- **Same-family arbiter warning** — emit warns when `frontier_alt_family` equals
  `frontier` without `arbiter_same_family: true`, or equals `alt_family` (≠ `frontier`)
  regardless of the flag; the model map labels rung-5 same-family arbiters explicitly.
- **Loop usage-credit guard** — `best`, `fable`, or `claude-fable*` in any `loop_chain`
  exit 3 at emit time.
- **`model_check` in log-spawn** — `_kit/log-spawn.* outcome` writes
  `model_check: match|MISMATCH|unverified` and warns on MISMATCH; scoped one-time
  re-spawn for evaluator-class verdicts only (orchestration template).
- **Setup verification guidance** — `/setup` Step 3 documents live model-list checks,
  Cursor silent fallback, and minimum Claude Code versions for pinned IDs.
- **Per-role effort** — diagnostician `xhigh`, terminal `low` in agent templates and the
  model map effort paragraph.
- **Dogfood pin refresh** — self-install fixture and emitted instance move to Oct 2026
  Anthropic 5.5 full IDs and Cursor picker-verified slugs; stale Grok/GPT arbitration
  pins removed.
- **Research** — decisions and live-check notes in
  [docs/research-model-currency-2026-10.md](../../docs/agent-kit/research-model-currency-2026-10.md).

- **Upgrading** — Re-emit with `--upgrade` (or a full `/setup` re-run). (a) When emit
  warns that `frontier_alt_family` equals `frontier`, set `arbiter_same_family: true` if
  a same-family rung-5 arbiter is intentional, or pick a different-family frontier
  arbiter. (b) When `frontier_alt_family` equals `alt_family`, `arbiter_same_family`
  does **not** silence the warning — point `frontier_alt_family` at a frontier model (a
  different-family one, or `frontier` itself with `arbiter_same_family: true`). Remove
  `best`/`fable`/`claude-fable*` from any `loop_chain` (emit now exits 3). For Claude
  Code pins to Opus/Sonnet/Haiku 5.5, upgrade the CLI to at least v2.1.280 / v2.1.284 /
  v2.1.293 respectively.

## [0.28.0] - 2026-09-04

**Signal-driven skill suggestions.**

- **Step 2b for every project** — After Step 2 inspect, interactive `/setup` runs
  skill suggestions for greenfield accept, greenfield decline, and non-sparse repos
  alike; Step 2a no longer owns a skills.sh install step.
- **Seven inspection signals** — Language/runtime, web UI, test framework,
  backend/web framework, infra/DevOps files, docs surfaces, and databases/ORMs drive
  `npx skills find` queries; absent signals produce no query.
- **Embedded find-skills workflow** — Leaderboard check → search → quality verify →
  present → user pick → install; references
  https://www.skills.sh/vercel-labs/skills/find-skills without installing or
  vendoring that skill.
- **Quality and volume caps** — Offer only skills with **1000+** installs; present at
  most **8** candidates total and **3** per signal, ranked by install count.
- **Dedupe and install rule** — Never re-offer skills already present under
  `.claude/skills`, `.cursor/skills`, `.agents/skills`, or `.github/skills`; install
  project-local with `npx skills add <owner>/<repo> --skill <picked-skill> -y` (never
  `-g`).
- **Recording and upgrade boundary** — Installed skills fill
  `bootstrap.domain-skill-rows` (ORCHESTRATION.md skills table) and
  `bootstrap.layer-skill-map` (feature skill layer → skills routing). A script-only
  `--upgrade` never runs Step 2b; a full interactive re-run does (skipping
  already-installed skills).
- **Fix: Copilot `feature` skill tree** — `emit.sh` / `emit.ps1` now emit
  `.github/skills/feature/SKILL.md` alongside `.github/agents/feature.agent.md`;
  previously only `reference/` and `templates/` were written, leaving a skill folder
  with no `SKILL.md`. Existing Copilot installs pick it up on `--upgrade`.

## [0.27.0] - 2026-09-04

**Deterministic emitter.**

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

## [0.26.0] - 2026-09-04

**Honest token metric.**

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

## [0.25.0] - 2026-09-04

**Scripted orchestration log.**

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

## [0.24.0] - 2026-09-04

**Token-efficiency policy.**

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

## [0.23.0] - 2026-08-26

**Feature-skill slimming.**

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

## [0.22.0] - 2026-08-26

**Forge adapter.**

- Phase 7 delivery through a **forge adapter**: GitHub / Azure DevOps / GitLab /
  hand-over. Phase 7 is never deleted from an install.

## [0.21.0] - 2026-08-25

**Canonical template sync.**

- Synced the canonical architecture template to shipped v0.12–v0.20 behavior:
  research handoff at Phase 3, the escalation **Ladder** line, the closer-task rung-3
  carve-out, and the loop dispatch / exit-funnel / merge-gate summary.

## [0.20.0] - 2026-08-24

**Continuation ladder.**

- Phase 4 **continuation ladder** after fix-cycle exhaustion: rung 5 arbitration
  (unanimous-failure heuristic), rung 4 diagnosis-first (new `diagnostician`
  subagent), rung 6 decomposition + selective retry.
- Closed failure-class taxonomy on every non-PASS verdict; always-escalate bypass for
  `destructive` / `security` / `infra`.
- Hard guards: attempt cap after cycle 3, repeated-failure signature detection, and
  required orchestration-log transitions.

## [0.19.0] - 2026-08-21

**Self-contained Cursor emission + greenfield gate.**

- Targeting Cursor emits a fully **self-contained** `.cursor/` tree — agents, skills,
  the architecture doc, and the model map — with no reliance on `.claude/` cross-reads.
- `{{IDE_DIR}}` resolved per emitter rather than once globally; the model-tier table
  references the emitted model map; emit-time obligation to check Cursor's live model
  list before emitting agent frontmatter.
- `/setup` Step 2a **greenfield gate**: on sparse workspaces it shows a recommended
  tree (TypeScript/Node and Python first-class) and creates nothing until confirmed,
  then optionally offers skills.sh stack skills with 1000+ installs.

## [0.18.0] - 2026-08-21

**Evaluator vocabulary + hardened evaluation.**

- Renamed the verification subagents to `evaluator` / `qa-evaluator`.
- Calibration exemplars and an **execute-before-score** rule in the evaluator agent.
- Hard per-criterion threshold in the criteria skills — no averaging away one failing
  dimension.
- `eval_depth` intensity routing (`full` / `light`), set by the orchestrator, never a
  skip.

## [0.13.0] - 2026-08-20

**Loop completion + exit aggregation.**

- Per-slot CB1/CB2 retirement instead of a run-fatal stop.
- Run exit aggregated across slots with precedence `4 > 3 > 2 > 1 > 0`.
- Quarantine-gated completion: drained-backlog exit `0` only when no branch was
  quarantined during the run.
- `.loop-worktrees/QUARANTINE-<branch>.md` markers (slashes in branch names become
  dashes) embedding the dispatched prompt.
- New exit code `5` for setup/integration failures.
- Completion-time backlog re-scan raises the missing/unreadable-backlog cause at a
  fifth site.

## [0.12.0] - 2026-08-20

**Driver-owned dispatch.**

- Driver-owned story selection (dispatch), write-set admission, and the
  single-writer integrator in the loop drivers.
- `LOOP_SLOTS` live under the N>1-iff-worktree rule: honored when `LOOP_WORKTREE=1`,
  clamped to an effective 1 when `LOOP_WORKTREE=0` (stderr note only when
  `LOOP_SLOTS>1` was set explicitly).
