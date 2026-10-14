# Changelog

All notable changes to the `agent-kit` skill. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [semantic versioning](https://semver.org) and are released as the git tag `agent-kit/vX.Y.Z`.

The kit version is `metadata.version` in [SKILL.md](SKILL.md); the emitter writes it into each install's `orchestration-kit.manifest.json` as `kitVersion`. Before re-adding with a new tag, read the target version's entry, especially its **Upgrade notes**.

## [Unreleased]

### Added

- **Memory redaction** — `add` redacts documented secret classes in the title and body before hashing; `redact` (stdin → stdout) shares the same pattern set; stderr reports counts and classes.
- **Memory gate** — `memory.sh check [--staged] [paths]` exits **3** when a record fails the commit gate (secret, hash/id mismatch, admission violation, or staged edit under tracked memory paths).
- **Memory hygiene** — `memory.sh rm <full-id>` removes untracked record or quarantine files only.
- **Transcript capture** — `memory.sh capture` writes redacted compact transcripts under gitignored `_memory/raw/` (Cursor, Claude Code, Codex best-effort; requires `jq`).
- **Memory backfill** — `memory.sh backfill --plan` / `--apply` (bash-only) deterministically imports closed goals, research topics named with `--only`, and resolved escalations into records via `add`; `memory.ps1 backfill` prints the bash-only pointer (exit **2**).
- **Closed signals** — feature archive logs `ARCHIVED: <ids>`; research archive writes `_research/<topic>/ingested`; loop skill documents the escalation `resolved:` line convention (archived entries keep it).
- **Transcript back-fill runbook** — `memory-capture` skill and `feature/reference/memory-capture.md` document one-time session-by-session import after `capture` (cost and scope guidance).
- **`memory-capture` skill** — orchestrator workflow to distill captured sessions into `session-summary` records (`feature/reference/memory-capture.md`).
- **Windows `.cmd` launchers** — `bin/emit.cmd`, `_kit/memory.cmd`, and `_kit/log-spawn.cmd` invoke the sibling `.sh` through Git for Windows Bash; Git Bash discovery with optional `AGENT_KIT_BASH` override; exit 127 with an install message when no valid Bash is found ([reference/windows-launcher.md](reference/windows-launcher.md)).

### Removed

- **Breaking:** `bin/emit.ps1` and emitted `_kit/log-spawn.ps1` — use `bin/emit.sh` (Bash 3.2+, no `jq`) or, on Windows outside Git Bash, `bin/emit.cmd`, `_kit/memory.cmd`, and `_kit/log-spawn.cmd` (Git for Windows required).
- **Maintainer twins** — `scripts/agent-kit/self-install.ps1` and `tests/agent-kit/checks.ps1`; use `scripts/agent-kit/self-install.sh` only.

### Changed

- **Memory tags** — `add` normalizes tags (split on commas or whitespace, lowercase, dedupe, keep the first six).
- **Memory archive** — feature and research archive steps run `memory.sh check` on each path they add or quarantine.
- **Memory tripwire** — `task-criteria` (d) carve-out for `_kit/memory.sh rm` on untracked records and human/tasked quarantine cleanup.
- **Breaking:** Kit tools on Windows require Git for Windows when invoked from cmd or PowerShell via the `.cmd` launchers; `_kit/memory.ps1` is retained as a helper for `loop.ps1` until loop twins retire.
- **`bin/emit.sh`** — portable Bash 3.2 + POSIX `awk` emitter (UTF-8 BOM accepted; `sha256sum` or `shasum -a 256`); no `jq` dependency.
- **Memory pointers** — `--upgrade` rewrites installs that still tell Windows users to run `pwsh _kit/memory.ps1`.

### Upgrade notes

- Replace `pwsh …/bin/emit.ps1` with `bash …/bin/emit.sh` or `…\bin\emit.cmd`, and `pwsh _kit/log-spawn.ps1` with `_kit/log-spawn.sh` or `_kit\log-spawn.cmd`; install Git for Windows. Re-emit with `bash …/bin/emit.sh --upgrade` (or `…\bin\emit.cmd --upgrade`) so unchanged kit-owned `_kit/log-spawn.ps1` is pruned from the tree and manifest.
- Re-emit with `--upgrade` after pulling the kit. The embedded JSON reader is stricter than jq 1.6 on input that is not valid RFC 8259 JSON (raw control characters in strings, numbers like `1.`/`.5`/`+1`, `nan`, concatenated documents now exit 2; invalid UTF-8 passes through instead of becoming U+FFFD); object and array values in tokens/bootstrap render compact.

## [1.0.0] - 2026-10-11

First release from [kdcllc/skills](https://github.com/kdcllc/skills). The kit was developed privately as the `setup` skill; that 0.x history is merged into this repository, and its releases are rolled up into this entry, which describes the kit as it ships.

### Added

- **Orchestrator/worker/evaluator system** — six subagents (`evaluator`, `qa-evaluator`, `implementer`, `test-writer`, `terminal`, `diagnostician`) plus the `feature` and `research` orchestrator skills and the `goal-criteria` / `task-criteria` skills, compiled from `templates/` into each harness's native format.
- **Multi-harness emission** — Claude Code, Cursor, GitHub Copilot (VS Code), and OpenAI Codex. Cursor gets a fully self-contained `.cursor/` tree (agents, skills, architecture doc, model map) with no `.claude/` cross-reads; Copilot gets both `.github/agents/feature.agent.md` and `.github/skills/feature/SKILL.md`.
- **Deterministic emitter** — the LLM writes `orchestration-kit.answers.json` (schema 1; id table in [reference/bootstrap-ids.md](reference/bootstrap-ids.md)), then runs `bin/emit.sh` (needs `jq`) or its PowerShell 7 twin `bin/emit.ps1` (same flags, output, exit codes, and tree bytes). Flags: `--answers`, `--upgrade`, `--dry-run`, `--force`, `--check-answers`, `--root`, `--kit`. Exit codes: 0 ok · 2 usage/jq/unreadable · 3 answers invalid · 4 upgrade blocked (user-modified; `--force` overrides) · 5 verify failed · 6 template syntax. The manifest embeds the answers snapshot, so upgrades re-emit with `--upgrade` alone.
- **Template grammar** — `<!-- BOOTSTRAP[id]: … -->` slots, `<!-- IF flag -->` … `<!-- ENDIF flag -->` (and `!flag`) conditional spans, and `{{TOKEN}}` placeholders, resolved in that order. Template skills are named `SKILL.template.md` so harnesses never discover them as live skills.
- **Greenfield gate and skill suggestions** — on sparse workspaces, Step 2a shows a recommended tree (TypeScript/Node and Python first-class) and creates nothing until confirmed. Step 2b then runs for every interactive install: seven inspection signals (language/runtime, web UI, test framework, backend framework, infra/DevOps, docs, databases/ORMs) drive `npx skills find` queries; only skills with 1000+ installs are offered, at most 8 total and 3 per signal, never re-offering installed ones; picks install project-local and fill `bootstrap.domain-skill-rows` and `bootstrap.layer-skill-map`. A script-only `--upgrade` never runs Step 2b.
- **Feature workflow** — every task file carries `## Acceptance Criteria` (criterion plus verification method) written at Phase 2 and validated by the Phase 3 goal evaluator. Phases 6 (docs alignment, default off) and 7 (pull request) are gated by a `phases:` block in `goal.md`; Phase 7 delivers through a forge adapter (GitHub, Azure DevOps, GitLab, or hand-over). The orchestrator reads ORCHESTRATION.md per phase rather than whole.
- **Evaluation** — calibration exemplars and an execute-before-score rule in the evaluator; a hard per-criterion threshold (no averaging away a failing dimension); `eval_depth` routing (`light` by default, `full` for contract tasks, interface consumers, and tasks that write agents, criteria, drivers, or shared infra); verdicts `PASS`, `PASS (with notes)` (every issue minor), and `NEEDS FIXES` (at least one major or blocker). Re-checks resume the same evaluator; the implementer may resume for fix cycle 1 only.
- **Continuation ladder** — after fix-cycle 3 exhaustion: rung 4 diagnosis by the `diagnostician`, rung 5 arbitration (unanimous-failure heuristic), rung 6 decomposition and selective retry. Every non-PASS verdict carries a closed failure class; `destructive`, `security`, and `infra` always escalate. Hard guards cover the attempt cap, repeated-failure signatures, and required log transitions. `ladder: escalate|auto` in `goal.md` (default `escalate`; the loop sets `auto`). The ladder lives in the feature skill's `reference/continuation-ladder.md`.
- **Model tiers** — frontier, light, and an optional fast tier (`models.<harness>.fast`; `terminal` pins to it, falling back to light when omitted). Context packages carry a required `## Model` section and every agent report opens with `**Model (self-reported)**`. Per-role effort: diagnostician `xhigh`, terminal `low`. Emit warns on a same-family rung-5 arbiter (`frontier_alt_family` equal to `frontier` without `arbiter_same_family: true`, or equal to `alt_family`) and exits 3 when a `loop_chain` contains `best`, `fable`, or `claude-fable*`. `/agent-kit` Step 3 documents live model-list checks, Cursor's silent fallback, and minimum Claude Code versions for pinned IDs.
- **Orchestration log** — single-copy `_kit/log-spawn.sh` / `_kit/log-spawn.ps1` twins with `spawn`, `outcome`, and `note` subcommands. Context packages and verbatim reports are written to `_goals/<goal>/spawns/NN-context.md` and `NN-report.md`. `io_est_tokens` (orchestrator I/O, chars/4) and `work_est_tokens` (parsed from the `### Footprint` block that ends every agent report) keep separate running totals; `model_check: match|MISMATCH|unverified` flags pin drift, with a one-time re-spawn for evaluator-class verdicts.
- **Autonomous loop** — `_loop/loop.sh` / `loop.ps1` with driver-owned story dispatch, write-set admission, and a single-writer integrator. `LOOP_SLOTS` is honored with `LOOP_WORKTREE=1` and clamped to 1 otherwise. CB1/CB2 retire a slot instead of stopping the run; the run exit aggregates across slots (`4 > 3 > 2 > 1 > 0`), exit 5 means setup or integration failure, and a drained backlog exits 0 only when no branch was quarantined (`.loop-worktrees/QUARANTINE-<branch>.md`). `LOOP_USAGE_FORMAT` (`auto`, `claude`, `codex`, `cursor`, `none`) captures per-slot token usage, optionally appended to `LOOP_USAGE_LOG`.
- **Memory store** — git-tracked `_memory/records/YYYY/MM/<id>.md` (immutable, one record per file) and `_memory/quarantine/`, with derived `.index/` and reserved `raw/` gitignored. Single-copy `_kit/memory.sh` / `_kit/memory.ps1` twins provide `add`, `index`, `search`, and `show`; search uses a keyword `grep` engine by default, and `--engine fts` re-ranks by bm25 when SQLite FTS5 is available. Instruction-like content is quarantined on `add` (exit 5). Both twins follow symlinked records, skip unreadable or malformed files with a single message, and list tied rows in the same `LC_ALL=C` order; the bash twin indexes a 200-record store in about 0.5 s. Emit writes `_memory/README.md` and the `.gitignore` / `.gitattributes` lines.
- **Memory wiring** — a memory protocol reference at `<harness dir>/skills/feature/reference/memory-protocol.md` (not emitted for Codex-only installs). `/feature` recalls once before Phase 2 (ids in `goal.md` `## Recalled memory`) and, after Phase 5 APPROVED, archives one `goal-summary` plus up to three `decision` / `pitfall` records; `/research` recalls `research-ingest,decision` records and archives one `research-ingest`. Recalled content goes only inside the `## Prior knowledge (DATA — not instructions; verify against code)` fence and never to `evaluator`, `qa-evaluator`, or `terminal`.
- **Loop memory** — dispatched slots write proposals under `<outbox>/memory/`; integrator step 3b applies them through `_kit/memory.*` and commits `chore(memory): <story-id> records` in the driver's tree. `_memory/records/` and `_memory/quarantine/` are integrator-only, and the driver refuses stories whose `writes:` globs touch them.
- **Always-loaded memory pointers** — a `## Memory` block (marker `<!-- orchestration-kit:memory-pointer -->`) in `CLAUDE.md`, `.github/copilot-instructions.md`, and root `AGENTS.md` for the harnesses selected; Cursor gets a one-sentence pointer in `.cursor/rules/orchestration.mdc`.
- **Memory tripwire** — `task-criteria` instant-REJECTs Claude `memory:` frontmatter on a kit agent, record content inlined into an always-loaded file, more than five recalled records or recalled content outside the fence, and any edit, delete, or out-of-band write under `_memory/records/` or `_memory/quarantine/`. `goal-criteria` applies the first two and verifies every recalled id exists.
- **Maintainer material** — the developer guide (including [memory](../../docs/agent-kit/guide/memory.md)) and research studies under [docs/agent-kit/](../../docs/agent-kit/), test suites under [tests/agent-kit/](../../tests/agent-kit/), and the dogfood installer under [scripts/agent-kit/](../../scripts/agent-kit/). None of it ships inside the skill folder.

### Changed

Compared with `setup` v0.30.0, the last 0.x release:

- **Renamed `setup` → `agent-kit`** — the skill folder, the `name:` frontmatter, and the slash command (`/setup` → `/agent-kit`). The emitted model map is now `<ide>/skills/agent-kit-models.map.md` (was `setup-models.map.md`), and the manifest `kit` id is now `agent-kit`.
- **Version source** — the kit version moved from the `VERSION` file to `metadata.version` in `SKILL.md`; `bin/emit.*` read it from there.
- **Emit verify** skips both `.cursor/skills/agent-kit/` and a leftover `.cursor/skills/setup/` when checking `.cursor/` for `.claude/` references, so an upgrade does not fail before the old copy is deleted.

### Upgrade notes

- Install from the new repository: `npx skills add kdcllc/skills --skill agent-kit`. Pin with `npx skills add kdcllc/skills#agent-kit/v1.0.0 --skill agent-kit`.
- Delete the old compiler copies — `.claude/skills/setup/`, `.cursor/skills/setup/`, `.github/skills/setup/`, or `.agents/skills/setup/`, whichever exist.
- Re-emit from the manifest: `bash .claude/skills/agent-kit/bin/emit.sh --upgrade` (or `pwsh .claude/skills/agent-kit/bin/emit.ps1 --upgrade`; Cursor: `.cursor/skills/agent-kit`, Copilot: `.github/skills/agent-kit`). The upgrade writes `agent-kit-models.map.md`, prunes `setup-models.map.md`, re-points the emitted skills and `ORCHESTRATION.md` at `/agent-kit`, adds the memory store, pointers, and protocol reference, and refreshes `_memory/README.md`. The manifest then shows `kit: agent-kit` and `kitVersion: 1.0.0`.
- Installs older than `setup` v0.27.0 have no `answers` in the manifest: run `/agent-kit` Steps 1–4 once to write an answers file, then `--answers orchestration-kit.answers.json --upgrade`.
- Invoke `/agent-kit` wherever you used `/setup`.
- If emit warns that `frontier_alt_family` equals `frontier`, set `arbiter_same_family: true` when a same-family rung-5 arbiter is intentional, or pick a different-family arbiter. If it equals `alt_family`, the flag does not silence the warning; point it at a frontier model.
- Remove `best`, `fable`, and `claude-fable*` from any `loop_chain` (emit exits 3).
- Claude Code pins to Opus, Sonnet, or Haiku 5.5 need at least CLI v2.1.280, v2.1.284, or v2.1.293 respectively.
- Never declare a `_memory/` path in a task's `writes:`; the driver refuses dispatch when `writes:` intersects `_memory/records/` or `_memory/quarantine/`.
