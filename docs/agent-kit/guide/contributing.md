**Who this is for / What you'll learn:** Kit **contributors and maintainers** working on the AI Orchestration Kit itself — not end users installing into their projects. You will understand the repo's three-layer anatomy (canonical source, gitignored emitted instance, tracked docs), the self-install dogfood loop for exercising template changes locally, how to edit templates and emitters safely, what the harness matrix and manifest are for, how version bumps, releases, and install upgrades flow, and how to run the tracked test harnesses before committing canonical changes. For install paths, `/agent-kit` compile flow, and first-session usage, see [getting-started.md](getting-started.md).

# Contributing to the Kit

The kit keeps **one canonical template source** under `skills/agent-kit/` and compiles it per harness via `/agent-kit`. Contributors, as of v0.19.0, edit that canonical side only; the emitted instance in this repo is gitignored and never source of truth. User-side install and compile mechanics live in [getting-started.md](getting-started.md); harness research ground truth lives in [../research-multi-harness-upgrade.md](../research-multi-harness-upgrade.md); the full install story is in the skill's [README.md](../../../skills/agent-kit/README.md).

## Repo anatomy: three layers

The kit lives in the multi-skill [kdcllc/skills](https://github.com/kdcllc/skills) repository. Every kit path in it belongs to one of three layers. Treat them differently: commit canonical and doc changes; treat instance paths as disposable output.

| Layer | Role | Key paths (tracked unless noted) |
|-------|------|----------------------------------|
| **CANONICAL** | Source of truth — what `/agent-kit` reads and compiles | `skills/agent-kit/templates/` (Claude Code format), `skills/agent-kit/bin/` (`emit.sh` + `emit.cmd` (Windows launcher) — deterministic emit), `skills/agent-kit/emitters/` (per-harness caveats), `skills/agent-kit/reference/` (`harness-matrix.md`, `bootstrap-ids.md`), `metadata.version` in `skills/agent-kit/SKILL.md` (kit version written into each install's manifest) |
| **INSTANCE** | Emitted by `/agent-kit` and self-install in **this repo only** — gitignored, re-runnable, never committed | Entire `.claude/`; **partial** `.cursor/` only — `.cursor/skills/`, `.cursor/agents/`, `.cursor/rules/`, `.cursor/ORCHESTRATION.md` (the rest of `.cursor/` is **not** gitignored); `.agents/skills/` (self-install `--symlink` canonical tree); `.loop-worktrees/` (loop driver scratch); `_kit/`, `_loop/`, `_memory/work/`, `_memory/loop/`, `_memory/.index/`, `_memory/raw/`; `orchestration-kit.manifest.json`. Tracked memory: `_memory/README.md`, `_memory/records/`, `_memory/quarantine/` |
| **MAINTAINER (tracked, not shipped)** | Tooling and documentation for kit contributors; lives outside the skill folder so it never reaches installs | `skills/agent-kit/README.md` and `CHANGELOG.md` (ship with the skill), `docs/agent-kit/` (this guide suite, research studies, the architecture **pointer** `ORCHESTRATION.md`), `tests/agent-kit/` (checks, guards, harness, `fixtures/self-answers.json`), `scripts/agent-kit/` (`self-install.sh`), `scripts/checks/agent-kit.sh` (fast guard run by `scripts/validate-skills.sh`) |

**Instance-specific note:** In consumer projects, `/agent-kit` emits into harness-native directories (`.claude/`, `.cursor/`, `.github/`, `.codex/`, root `ORCHESTRATION.md`, etc.) per the emitters. This repo dogfoods the kit: its `.gitignore` lists the instance paths above so local dogfood output never reaches git, and `scripts/validate-skills.sh` rejects agent skill directories only when they contain tracked files.

### docs/agent-kit/ORCHESTRATION.md is a pointer

The tracked [`docs/agent-kit/ORCHESTRATION.md`](../ORCHESTRATION.md) is **not** the architecture source. It states:

> Edit the template in the skill's `templates/` directory only; this file is just a pointer.

The canonical architecture template lives at [`skills/agent-kit/templates/ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md). `/agent-kit` compiles it into each harness's native location (for example `.claude/ORCHESTRATION.md` or `.cursor/ORCHESTRATION.md` as of v0.19.0). Never edit emitted instance copies when changing kit behavior — edit templates and re-run `/agent-kit` locally to refresh the instance.

## The dogfood loop

When you change canonical kit content, exercise the full path before committing tracked files:

```mermaid
flowchart TD
    Edit["Edit canonical templates\nskills/agent-kit/templates/"]
    SelfInstall["bash scripts/agent-kit/self-install.sh\n(skill copy + emit)"]
    Exercise["Exercise the change end-to-end"]
    Commit["Commit the canonical side"]

    Edit --> SelfInstall
    SelfInstall --> Exercise
    Exercise --> Commit
```

1. **Edit** templates (and `bin/emit.*` when translation logic changes; emitters or reference docs when harness caveats change).
2. **Self-install** copies `skills/agent-kit/` into harness skill directories and emits the instance from `tests/agent-kit/fixtures/self-answers.json` (unless `--no-emit`).
3. **Exercise** the change — run workflows, spot-check emitted files, run the test harnesses below.
4. **Commit** only canonical and repo-doc paths; instance output stays gitignored.

If you also changed emitter mappings or `skills/agent-kit/SKILL.md`, include those tracked paths in the commit. Record kit behavior changes under `## [Unreleased]` in `skills/agent-kit/CHANGELOG.md` (see [Version, manifest, and upgrades](#version-manifest-and-upgrades)).

## Self-install script

[`scripts/agent-kit/self-install.sh`](../../../scripts/agent-kit/self-install.sh) is a **kit-repo-only** first-mile helper with defaults, guards, and exit codes documented below.

### What it copies

As of v1.0.0 it installs only `skills/agent-kit/` — the other skills in kdcllc/skills would also land in `.cursor/skills/`, where their `.claude/` references fail emit verify and checks M/N. Nested paths like `skills/agent-kit/templates/skills/feature/SKILL.md` are not skills. Destinations:

| Mode | Destinations |
|------|----------------|
| **Default (copy)** | `.claude/skills/<name>/` and `.cursor/skills/<name>/` — overwrite-copy from the working tree |
| **`--symlink`** | Canonical real tree at `.agents/skills/<name>/`; `.claude/skills/<name>` and `.cursor/skills/<name>` become symlinks pointing there |

Run from repo root:

```bash
bash scripts/agent-kit/self-install.sh
```

### Flags

| Flag | Semantics |
|------|-----------|
| `--dry-run` | Prints planned destination paths to stdout; writes nothing; exits 0. Combined with `--symlink`, prints the symlink plan. When emit runs, passes `--dry-run` to `emit.sh` (action lines only; no writes). |
| `--symlink` | Places the canonical real tree at `.agents/skills/<name>/` and makes `.claude/skills/<name>` and `.cursor/skills/<name>` symlinks pointing there. Fails loudly on symlink failure; **never** falls back to copy. |
| `--force` | Accepted and ignored — overwrite is already the default. |
| `--no-emit` | Copy skills only; skip emit (legacy behaviour). |
| `--force-emit` | Pass `--force` to `emit.sh` (overwrite user-modified instance files). |

### What self-install emits

After copying skills, self-install runs `skills/agent-kit/bin/emit.sh --answers tests/agent-kit/fixtures/self-answers.json` unless `--no-emit`. That produces the full gitignored instance (agents, loop drivers, manifest, project-specific resolved content) with zero LLM involvement. Consumer projects still use `/agent-kit` Steps 1–6 in a session; self-install is kit-repo dogfood only.

Nothing the self-install script writes reaches git — all destination paths are listed in [`.gitignore`](../../../.gitignore).

## Editing templates

All canonical orchestration content lives under [`skills/agent-kit/templates/`](../../../skills/agent-kit/templates/) in Claude Code format. As of v0.27.0, `skills/agent-kit/bin/emit.*` resolves and translates templates deterministically.

### Template grammar (authoring)

- **`{{TOKEN}}`** — replaced from `answers.tokens` (and derived keys such as `{{IDE_DIR}}` resolved per harness).
- **`<!-- BOOTSTRAP[id]: … -->`** — `id` matches `^[a-z0-9]+(-[a-z0-9]+)*$`; the whole comment is replaced by `answers.bootstrap[id]` verbatim; `""` deletes silently; missing keys warn and appear in `--check-answers` output. Whole-line comments collapse to ≤1 blank between neighbours. Class-d instruction comments use the `kit-` prefix and are always deleted.
- **`<!-- IF flag -->` … `<!-- ENDIF flag -->`** (and `!flag`) — keep or drop the span; nesting allowed; mismatch ⇒ exit 6. Flags include `research`, `loop`, `greenfield`, `lint`, `typecheck`, `models_pinned`, per-target `is_*`, and harness-membership `want_*`.

Resolution order: IF → BOOTSTRAP[id] → `{{TOKEN}}`. Id table:
[`skills/agent-kit/reference/bootstrap-ids.md`](../../../skills/agent-kit/reference/bootstrap-ids.md). Verify greps emitted files for stray `{{…}}`, `<!-- BOOTSTRAP`, and `<!-- IF` — zero hits required.

The full placeholder reference table lives in [`skills/agent-kit/SKILL.md`](../../../skills/agent-kit/SKILL.md) (Step 4). Read it before adding or renaming tokens.

### Where harness-specific logic belongs

| Concern | Location |
|---------|----------|
| Canonical prose and structure | `skills/agent-kit/templates/` |
| Harness-agnostic tool twins (`log-spawn.sh`, `memory.sh` / `memory.ps1`, and the `bash-launcher.cmd` Windows launcher; no tokens) | `skills/agent-kit/templates/tools/` — emitted single-copy to `_kit/log-spawn.sh`, `_kit/memory.sh` / `_kit/memory.ps1`, and `bash-launcher.cmd` copied to `_kit/log-spawn.cmd` and `_kit/memory.cmd` (`_kit/` is gitignored in this repo; `_memory/records/` and `_memory/quarantine/` are tracked; `_memory/work/` and `_memory/loop/` are gitignored here) |
| Per-harness translation (frontmatter shape, path mapping, pointer rules) | `skills/agent-kit/bin/emit.sh` — see [`bin/README.md`](../../../skills/agent-kit/bin/README.md) |
| Harness caveats (live model-check URLs, silent-fallback warnings) | `skills/agent-kit/emitters/` |
| Verified harness capabilities and friction points | `skills/agent-kit/reference/harness-matrix.md` |

When live vendor docs contradict the harness matrix, trust the live docs for emission, then **update the matrix** with a new verified-on date. The matrix is the kit's ledger of verified facts; `bin/emit.*` implements translation on top of it.

## Emitters (caveats only)

As of v0.27.0, per-harness translation runs in [`skills/agent-kit/bin/emit.sh`](../../../skills/agent-kit/bin/emit.sh) /
[`emit.cmd`](../../../skills/agent-kit/bin/emit.cmd). Emitter files under
[`skills/agent-kit/emitters/`](../../../skills/agent-kit/emitters/) hold **caveats only** — live
model-list check URLs, silent-fallback warnings, and similar harness friction — not
translation tables. Full CLI contract: [`skills/agent-kit/bin/README.md`](../../../skills/agent-kit/bin/README.md).

| Emitter file | Target harness | Caveats cover |
|--------------|----------------|---------------|
| [`claude-code.md`](../../../skills/agent-kit/emitters/claude-code.md) | Claude Code (`.claude/`) | Model-config docs plus `claude --version` per-pin floor; Anthropic models only (same-family arbiter flag); aliases resolve per provider (prefer full IDs); `best`, `fable`, or `claude-fable*` in a loop chain → emit exit 3; inherit/unpinned behaviour |
| [`cursor.md`](../../../skills/agent-kit/emitters/cursor.md) | Cursor (self-contained `.cursor/`) | Unresolved IDs → parent's model ([`harness-matrix.md`](../../../skills/agent-kit/reference/harness-matrix.md) ⚠️); admin/plan limits → compatible model (vendor docs); values emitted unquoted; bracket-param form documented, suffix slugs in pickers; empty `agent models` → IDE picker; live model list check URL |
| [`copilot.md`](../../../skills/agent-kit/emitters/copilot.md) | GitHub Copilot VS Code (`.github/`) | Cost-ceiling policy; model fallback arrays |
| [`codex.md`](../../../skills/agent-kit/emitters/codex.md) | OpenAI Codex (`AGENTS.md` + `.codex/`) | Role config in TOML; `AGENTS.md` size cap |

When you change a canonical template file, update `bin/emit.*` if translation paths
change — emitters no longer carry Emit tables. The Cursor emitter, as of v0.19.0, is
order-independent relative to Claude Code (self-contained emission).

## Version, manifest, and upgrades

### Version and releases

As of v1.0.0, `metadata.version` in [`skills/agent-kit/SKILL.md`](../../../skills/agent-kit/SKILL.md) holds the kit version; `bin/emit.*` reads it from there (the old `VERSION` file is gone). Never edit it by hand. Write the change under `## [Unreleased]` in [`skills/agent-kit/CHANGELOG.md`](../../../skills/agent-kit/CHANGELOG.md), merge, then release with `bash scripts/release-skill.sh agent-kit X.Y.Z` from the repository root — it bumps `metadata.version`, promotes the changelog section, validates, commits, and tags `agent-kit/vX.Y.Z`. Changes confined to `docs/agent-kit/`, `tests/agent-kit/`, or `scripts/` ship nothing to users and need no release.

### Manifest shape

`/agent-kit` writes `orchestration-kit.manifest.json` at the project root. The manifest, as of v0.19.0, records:

- `kit` (`agent-kit` as of v1.0.0), `kitVersion` (from `metadata.version`), `installedAt`, `harnesses`, `options`
- `files`: map of emitted path → SHA-256 hash
- `seedFiles`: paths created-if-missing, never overwritten on upgrade

As of v0.27.0, it also records `answers` (snapshot of the answers file used at emit),
`primary` (primary harness id), and flat `options` flags (`"forge": "<detected>"` plus
optional `forgeHost`; see [`skills/agent-kit/SKILL.md`](../../../skills/agent-kit/SKILL.md) Upgrading).

In this repo the manifest is gitignored (instance layer). See the live example shape in `orchestration-kit.manifest.json` after a local `/agent-kit` run.

### Upgrade flow

For installed projects (including dogfood in this repo):

1. **Re-pull** the kit — for example `npx skills add kdcllc/skills --skill agent-kit` again, or `npx agent-skills-cli update` (run `npx agent-skills-cli check` first to see installed skills).
2. **Re-emit** — `bash .claude/skills/agent-kit/bin/emit.sh --upgrade` (or `.cursor/skills/agent-kit`, `.github/skills/agent-kit`; answers come from the manifest; add `--answers` only when the interview changed). Pre-v0.27.0 installs have no embedded `answers` — run `/agent-kit` Steps 1–4 once, then `--answers … --upgrade`. Exit 4 lists user-modified files; confirm with `--force`. Use `--dry-run` to preview.

**Hash diff protects local modifications:** Unmodified emitted files update silently; modified files require confirmation before overwrite.

**`seedFiles` semantics (as of v0.27.0):** When loop is enabled, the manifest lists `_memory/loop/backlog.md` in `seedFiles` only (not in `files`). Seeds are created only when missing, never overwritten on upgrade, and are exempt from the hash-diff overwrite flow.

**Stale-file pruning (as of v0.19.0):** After regeneration, paths in the old manifest but absent from the new emit set are deleted if unmodified, or reported for manual removal if the user edited them.

## Running tests

Contributors should run the tracked harnesses before committing canonical changes.

### Loop and self-install harness

```bash
bash tests/agent-kit/loop-harness/run.sh
```

This is the tracked **behavioral** test suite (test-ladder rung 3 territory — run manually or via `tests/agent-kit/run-all.sh`). Coverage, as of v0.19.0 per the script header, includes:

- **Breaker state machine** — canonical `breaker.sh` assertions with injected timestamps (no wall-clock reads)
- **Rate-limit detection** — live `detect_rate_limit` extracted from canonical `loop.sh`
- **Re-emitted instance stub** — end-to-end `_loop/loop.sh` run inside a throwaway repo when `_loop/` exists in this repo
- **Structural guards** — PowerShell parity, emitter/SKILL text coverage, SIGPIPE regressions, checks J/K mutation proofs, and related story additions
- **Self-install block** — runs **without** requiring `_loop/`: exercises `scripts/agent-kit/self-install.sh` (copy mode, overwrite, `--force`, `--dry-run`, `--symlink`, rollback, `.gitignore` dest-lines, and related assertions)
- **Memory integrator step 3b** (as of v1.0.0) — assertions 136–141

When `_loop/` is absent (fresh clone before `/agent-kit`), loop-instance assertions are skipped in aggregate — self-install assertions still run.

### Standalone template guards

Tracked structural guards live under `tests/agent-kit/templates/` — [`cursor-isolation.sh`](../../../tests/agent-kit/templates/cursor-isolation.sh), [`invocation-flags.sh`](../../../tests/agent-kit/templates/invocation-flags.sh), [`escalation-ladder.sh`](../../../tests/agent-kit/templates/escalation-ladder.sh) (added with the v0.20.0 continuation-ladder goal), [`template-currency.sh`](../../../tests/agent-kit/templates/template-currency.sh) (added with the v0.21.0 template-currency goal; locks the six template-currency claims — research handoff at Phase 3, escalation **Ladder** line, closer-task rung-3 carve-out, loop dispatch/exit-funnel/merge-gate — with SKIP-when-absent instance-mirror assertions), [`skill-slimming.sh`](../../../tests/agent-kit/templates/skill-slimming.sh), [`forge-adapter.sh`](../../../tests/agent-kit/templates/forge-adapter.sh), [`model-enforcement.sh`](../../../tests/agent-kit/templates/model-enforcement.sh) (v0.24.0 policy strings), [`model-currency.sh`](../../../tests/agent-kit/templates/model-currency.sh) (v0.29.0: fast tier, arbiter warnings, loop denylist, upgrade compatibility, template text, dogfood pins), [`log-spawn.sh`](../../../tests/agent-kit/templates/log-spawn.sh) (v0.25.0: runs the canonical `log-spawn.sh` against a mktemp fixture — entries, measured fields, io/work running totals (v0.26.0: Footprint ingestion, `--work-chars`, pre-v0.26 fallback), exit codes, the `_kit/log-spawn.sh` + `.cmd` emit wiring (the retired `log-spawn.ps1` must not appear); v0.29.0: OUTCOME `model_check`), [`memory.sh`](../../../tests/agent-kit/templates/memory.sh) (v0.30.0+: runs the canonical `memory` twins against a mktemp fixture — add/index/search/show, grep default and optional FTS re-rank, admission quarantine exit 5, Release C **redact** / **check** / **rm** / **capture** coverage with bash, pwsh, and parity legs for redaction cases; **check** / **rm** / **capture** exercised via bash-only helpers in [`tests/agent-kit/lib/memory-release-c.sh`](../../../tests/agent-kit/lib/memory-release-c.sh) with pwsh legs asserting bash-only stubs exit **2**; twin redaction cases in [`tests/agent-kit/lib/memory-redaction-behavioral.sh`](../../../tests/agent-kit/lib/memory-redaction-behavioral.sh) — plus `_memory/` emit wiring), [`memory-capture.sh`](../../../tests/agent-kit/templates/memory-capture.sh) (Release C: synthetic transcript fixtures for `capture`), [`memory-wiring.sh`](../../../tests/agent-kit/templates/memory-wiring.sh) (v1.0.0: memory wiring — templates, emitter pointer blocks, memory-capture emission, mutation-proven), [`emit-determinism.sh`](../../../tests/agent-kit/templates/emit-determinism.sh) (v0.27.0: byte-identical re-emit; Unreleased: portability (Bash 3.2, POSIX `awk`, no `jq`)), [`emit-golden.sh`](../../../tests/agent-kit/templates/emit-golden.sh) (Unreleased: byte-compares a golden corpus for `bin/emit.sh`; intended changes need `bash tests/agent-kit/templates/emit-golden.sh --update` plus a reviewed diff), [`emit-portability.sh`](../../../tests/agent-kit/templates/emit-portability.sh) (Unreleased: `emit.sh` portability — jq-free PATH, sha256 tools, Bash 3.2 docker, JSON edges; `AGENT_KIT_DOCKER=1` opt-in runs the bash:3.2 docker emit-golden check, default skips it; opt-in set but docker/image missing → FAIL; CI pulls `bash:3.2` and sets `AGENT_KIT_DOCKER=1` before the full suite), [`emit-migrate.sh`](../../../tests/agent-kit/templates/emit-migrate.sh) (Unreleased: guard for `bin/emit.sh` legacy layout migration (`--upgrade` path); fixtures under a private TMPDIR; runs cases in parallel via [`tests/agent-kit/lib/parallel.sh`](../../../tests/agent-kit/lib/parallel.sh) — `AGENT_KIT_CASE_JOBS`), [`emit-perf.sh`](../../../tests/agent-kit/templates/emit-perf.sh) (Unreleased: default = structural checks + in-suite mutation proofs (no timing, no strace); `EMIT_PERF=1` adds three timed self-answers emits (median vs `EMIT_PERF_MAX`, default 4.0) and, when strace works, a fork budget (`EMIT_PERF_MAX_FORKS`, default 589)), [`legacy-paths.sh`](../../../tests/agent-kit/templates/legacy-paths.sh) (Unreleased: kit sources must not reintroduce legacy `_goals`/`_research` tokens outside an allow-list), [`memory-backfill.sh`](../../../tests/agent-kit/templates/memory-backfill.sh) (Unreleased: `memory.sh backfill` (Release D), synthetic fixtures), and [`windows-launcher.sh`](../../../tests/agent-kit/templates/windows-launcher.sh) (Unreleased: Windows `.cmd` launchers; static checks everywhere, behavior checks only under Git Bash on Windows, otherwise SKIP). The escalation-ladder guard locks the Phase 4 continuation-ladder subsection, failure-class taxonomy identity across canonical templates, diagnostician template and dual-instance emission wiring, and `{{MODEL_FRONTIER_ALT_FAMILY}}` documentation. Run any guard directly with `bash tests/agent-kit/templates/<name>.sh`; they are not invoked by `tests/agent-kit/loop-harness/run.sh`.

### Everything at once

```bash
bash scripts/validate-skills.sh     # repo layout, frontmatter, versions, plus scripts/checks/agent-kit.sh
bash tests/agent-kit/run-all.sh      # self-install, then checks.sh, every guard, the docs checker, and the harness
```

`scripts/checks/agent-kit.sh` runs only the checks that need no emitted instance (it emits into temp roots), so it is safe inside the validator and in CI. `run-all.sh` refreshes the gitignored instance first. Options: `--quick`, `--only SUBSTR` (repeatable), `-j N`, `--no-install`; environment `AGENT_KIT_CASE_JOBS`, `AGENT_KIT_DOCKER`.

### Documentation suite checker

```bash
bash tests/agent-kit/docs-link-check.sh
```

Added by the developer-guide-docs goal: validates the finished `docs/agent-kit/guide/` suite against the conventions frozen in [README.md](README.md). Run this after editing any guide document. This contributing doc describes purpose and run command only — the check implementations are owned by the goal's dedicated test task.

## Documentation conventions

If you add or revise guide content under `docs/agent-kit/guide/`, follow the frozen conventions in [README.md](README.md): Mermaid rules (core types only, `flowchart TD` default, no init directives, quoted punctuation labels), relative file-level cross-links resolved from the linking file's directory, opener blocks, Sources sections, version anchoring (version-sensitive kit-behavior claims anchored at the kit version where the behavior shipped — for example "as of v0.19.0" or "as of v0.20.0"), and canonical-vs-instance labeling.

Install and user-side usage topics belong in [getting-started.md](getting-started.md), not here.

## Quick reference

| Task | Command or path |
|------|-----------------|
| Copy skills for local dogfood | `bash scripts/agent-kit/self-install.sh` |
| Preview self-install plan | `bash scripts/agent-kit/self-install.sh --dry-run` |
| Symlink mode (single canonical tree) | `bash scripts/agent-kit/self-install.sh --symlink` |
| Full instance emit | `bash scripts/agent-kit/self-install.sh` (copy + emit from fixture) or `/agent-kit` in a consumer project |
| Emitter CLI contract | `skills/agent-kit/bin/README.md` |
| Edit architecture template | `skills/agent-kit/templates/ORCHESTRATION.md` |
| Placeholder reference | `skills/agent-kit/SKILL.md` |
| Harness verified facts | `skills/agent-kit/reference/harness-matrix.md` |
| Behavioral tests | `bash tests/agent-kit/loop-harness/run.sh` |
| Structural template guards | `bash tests/agent-kit/templates/escalation-ladder.sh` (and siblings) |
| Guide suite integrity | `bash tests/agent-kit/docs-link-check.sh` |
| Full kit suite | `bash tests/agent-kit/run-all.sh` |
| Fast subset of the kit suite | `bash tests/agent-kit/run-all.sh --quick` |
| Bash 3.2 Docker check | `docker pull bash:3.2`, then `AGENT_KIT_DOCKER=1 bash tests/agent-kit/templates/emit-portability.sh` |
| Emitter speed guard | `EMIT_PERF=1 bash tests/agent-kit/templates/emit-perf.sh` |
| Release | `bash scripts/release-skill.sh agent-kit X.Y.Z` |
| Harness research ground truth | [../research-multi-harness-upgrade.md](../research-multi-harness-upgrade.md) |

## Sources

- [`docs/agent-kit/guide/README.md`](README.md) — frozen document map, Mermaid/link/opener conventions, glossary
- [`skills/agent-kit/README.md`](../../../skills/agent-kit/README.md) — install, generated files, upgrading, editing templates
- [`docs/agent-kit/ORCHESTRATION.md`](../ORCHESTRATION.md) — architecture pointer and v0.18.0–v0.21.0 capability summary
- [`.gitignore`](../../../.gitignore) — instance paths gitignored in this repo
- [`skills/agent-kit/SKILL.md`](../../../skills/agent-kit/SKILL.md) — `/agent-kit` workflow, placeholder reference, manifest and upgrade semantics
- [`skills/agent-kit/bin/README.md`](../../../skills/agent-kit/bin/README.md) — emitter CLI contract (flags, exit codes, determinism)
- [`skills/agent-kit/reference/bootstrap-ids.md`](../../../skills/agent-kit/reference/bootstrap-ids.md) — bootstrap id and flag table
- [`skills/agent-kit/emitters/claude-code.md`](../../../skills/agent-kit/emitters/claude-code.md) — Claude Code caveats
- [`skills/agent-kit/emitters/cursor.md`](../../../skills/agent-kit/emitters/cursor.md) — Cursor caveats
- [`skills/agent-kit/emitters/copilot.md`](../../../skills/agent-kit/emitters/copilot.md) — Copilot VS Code caveats
- [`skills/agent-kit/emitters/codex.md`](../../../skills/agent-kit/emitters/codex.md) — Codex caveats
- [`skills/agent-kit/reference/harness-matrix.md`](../../../skills/agent-kit/reference/harness-matrix.md) — verified per-harness capability ledger
- [`scripts/agent-kit/self-install.sh`](../../../scripts/agent-kit/self-install.sh) — bash self-install flags and copy/symlink logic
- [`tests/agent-kit/loop-harness/run.sh`](../../../tests/agent-kit/loop-harness/run.sh) — behavioral harness header and coverage scope
- [`tests/agent-kit/run-all.sh`](../../../tests/agent-kit/run-all.sh) — full kit suite driver (options, env, timing summary)
- [`.github/workflows/agent-kit.yml`](../../../.github/workflows/agent-kit.yml) — CI agent-kit workflow (bash:3.2 pull, `AGENT_KIT_DOCKER`)
- `orchestration-kit.manifest.json` — manifest shape and `seedFiles` (instance file; gitignored in this repo)
