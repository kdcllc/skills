# AI Orchestration Kit

[![skills.sh installs](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills)

> Kit version: **0.23.0** (`skills/setup/VERSION`) · Version history: [CHANGELOG.md](CHANGELOG.md)

A portable orchestrator/worker/evaluator multi-agent system for AI coding harnesses —
**Claude Code, Cursor, GitHub Copilot (VS Code), and OpenAI Codex** — packaged as one
installable `setup` skill that compiles a single canonical template source into each
harness's native format.

## Quick start

```bash
# 1. Install the setup skill into your project (see §Install for options)
npx skills add kdcllc/skills

# 2. In a session inside the project, compile the kit for your harness(es)
/setup

# 3. Start your first orchestrated feature
/feature
```

Optional: start an unattended run (sandboxed!) with `_loop/loop.sh 10` or
`pwsh _loop/loop.ps1 10` (PowerShell 7+).

## What you get

- A **seven-phase feature workflow** (`/feature`): alignment → goal creation → goal
  evaluation → task execution → final audit → optional docs alignment → optional
  approval-gated pull request. Acceptance criteria are defined at planning and
  validated at Phase 3; Phases 6 and 7 are gated on a `phases:` block in `goal.md`.
  No phase advances without an evaluator verdict; fixes are always re-evaluated
  (3-cycle limits, explicit escalation).
- **Six subagents with tiered model pinning**: `evaluator`, `qa-evaluator`, and
  `diagnostician` on the frontier tier (effort high), `implementer`, `test-writer`, and
  `terminal` on the light tier (effort medium) — `terminal` runs Bash or PowerShell and
  returns only the result the caller asked for, so the raw stream stays out of the
  frontier session. Model IDs are configuration (`models.map.md`), with per-tier fallback
  chains, a never-fall-up rule, and a cost-ceiling policy.
- **Hardened evaluation** (patterns adopted from studying
  [bradygaster/squad](https://github.com/bradygaster/squad)): existence checks with a
  ✅/⚠️/❌/🔍 confidence ladder and anti-fabrication rules, a required devil's-advocate
  section in goal evaluation, fix-cycle **model rotation**, execute-before-score,
  `eval_depth` intensity routing, a post-exhaustion **continuation ladder**, and an
  append-only **orchestration log** per goal with proxy token fields. How each piece
  arrived is in [CHANGELOG.md](CHANGELOG.md); mechanics are in
  [docs/guide/evaluation-system.md](docs/guide/evaluation-system.md).
- A **staged test ladder** (`test-ladder`): new tests → impacted tests mid-cycle; full
  suites at cycle end — in a goal's designated closer task when it has one, and in the
  orchestrator's Phase 5 Quality Checks.
- An optional **autonomous loop** (`auto-loop` + `_loop/loop.sh` / `_loop/loop.ps1`):
  one backlog story per fresh-context iteration, evaluation-gated commits, circuit
  breakers enforced in the loop drivers (not prose), optional parallel slots in
  driver-managed worktrees, a six-code exit contract, and a single human-approved PR
  at run end. Knobs, exit codes, and the safety model are documented in
  [docs/guide/autonomous-loop.md](docs/guide/autonomous-loop.md).

## Documentation

Developer guide: [docs/guide/README.md](docs/guide/README.md).

| Guide | Description |
|-------|-------------|
| [getting-started.md](docs/guide/getting-started.md) | Install paths, `/setup` compile flow, greenfield gate, multi-harness emission, manifest basics |
| [decision-guide.md](docs/guide/decision-guide.md) | Choosing direct edit, `/feature`, `/research` → `/feature`, or autonomous loop; flowchart, mode comparison, anti-patterns |
| [feature-workflow.md](docs/guide/feature-workflow.md) | Seven phases in depth, acceptance criteria at planning, optional Phases 6/7, fix-cycle rotation, escalation, orchestration log, condensed worked example |
| [research-workflow.md](docs/guide/research-workflow.md) | Why research precedes implementation, prompt/report artifacts, ingestion into a goal, when to skip |
| [autonomous-loop.md](docs/guide/autonomous-loop.md) | Drivers, backlog stories, iteration lifecycle, circuit breakers, slots/worktrees, exit codes, quarantine, safety model |
| [agents-and-models.md](docs/guide/agents-and-models.md) | Six subagent roles and boundaries, model tiers, `models.map.md` anatomy, fallback chains, harness caveats |
| [evaluation-system.md](docs/guide/evaluation-system.md) | Verdict vocabulary, confidence ladder, anti-fabrication, devil's advocate, acceptance criteria validation, `eval_depth`, test ladder, orchestration log audit trail |
| [contributing.md](docs/guide/contributing.md) | Repo anatomy (canonical vs instance vs generated), self-install dogfood loop, templates/emitters, harness matrix, VERSION + manifest + upgrades, test harness |

## Layout

| Path | What it is |
|------|------------|
| [`skills/setup/`](skills/setup/) | The installable skill (the compiler): `SKILL.md` workflow, `VERSION`, `emitters/` (per-harness compile instructions), `reference/harness-matrix.md` (verified harness facts), and `templates/` — the canonical source: architecture doc, `models.map.md`, six agents, the skills (each a `SKILL.template.md`, renamed to `SKILL.md` at emit), and the loop drivers |
| [`docs/`](docs/) | The `guide/` developer suite (see §Documentation) plus the research and design studies behind shipped behavior — for example [research-autonomous-escalation.md](docs/research-autonomous-escalation.md) (→ the v0.20.0 continuation ladder) and [research-multi-harness-upgrade.md](docs/research-multi-harness-upgrade.md) (per-harness ground truth) |
| [`tests/`](tests/) | `docs-link-check.sh` (guide integrity), `templates/` (6 canonical-template sync guards), `loop-harness/run.sh` (behavioral suite incl. self-install assertions) |
| [`scripts/`](scripts/) | `self-install.sh` / `self-install.ps1` — first-mile dogfood copy (see §Self-install) |
| [`ORCHESTRATION.md`](ORCHESTRATION.md) | Pointer to the canonical architecture template inside the skill |
| [`CHANGELOG.md`](CHANGELOG.md) | Version history (v0.12.0 →) |

The full repo anatomy — canonical vs gitignored-instance vs tracked-docs layers — is in
[docs/guide/contributing.md](docs/guide/contributing.md).

## Install into a project

A public repo is NOT required — both CLIs install from this private repo as long as
the machine has git access to it. (That is also why the install badge above stays
dormant while the repo is private: [skills.sh](https://www.skills.sh/) filters private
repos out of its public index by design,
[vercel-labs/skills#381](https://github.com/vercel-labs/skills/issues/381). If the
repo publishes under a different owner/name, update the badge path
`skills.sh/b/<owner>/<repo>`.)

```bash
# Option A — skills CLI: clones with your LOCAL git credentials (SSH or gh auth),
# so private repos work today (vercel-labs/skills#381; see src/git.ts). Caveats
# from that thread: private repos are never indexed on skills.sh, and
# `npx skills update` is currently unreliable for private repos.
npx skills add kdcllc/skills

# Option B — agent-skills-cli: first-class private-repo support
# (SSH auto-detected; HTTPS via --token=... or GH_TOKEN=...; GitLab/Bitbucket too).
npx agent-skills-cli install git@github.com:kdcllc/skills.git
```

Or copy the skill in manually (any harness dir works — the skill detects and
asks):

```bash
cp -r skills/setup  <your-project>/.claude/skills/     # Claude Code
cp -r skills/setup  <your-project>/.cursor/skills/     # Cursor
```

**Greenfield / sparse directory:** On an empty or near-empty workspace, `/setup` runs
Step 2a (the greenfield gate) and **asks** before scaffolding. It **shows** a
recommended project tree and **creates nothing until you confirm**. First-class layouts
are **TypeScript/Node** and **Python**; other stacks get a generic `src/` + `tests/`
tree. After you confirm, it can optionally offer **skills.sh** stack skills with
**1000+** installs — you pick which ones, installed **into this project**. **Existing
projects are unchanged:** non-sparse repos skip the greenfield gate entirely.

Then, in a session inside that project, run `/setup`. It detects which harnesses to
target (multiple is normal), inspects the repo (stack, test commands, layers,
user-facing surfaces), interviews you for what it can't infer (project name, model
tiers, QA surfaces, research workflow, autonomous loop, delivery forge), and
emits:

| Generated | Purpose |
|-----------|---------|
| `agents/evaluator`, `agents/qa-evaluator` | Skeptical reviewers — frontier tier, existence checks + confidence ladder |
| `agents/diagnostician` | Root-cause analysis after fix-cycle exhaustion — frontier tier, no code writes |
| `agents/implementer`, `agents/test-writer` | Workers — light tier, ladder rungs 1–2 only |
| `skills/feature` | Seven-phase workflow + goal/task templates + orchestration log |
| `skills/research` | Research → Plan workflow (optional) |
| `skills/{goal,task,qa}-criteria` | Evaluation checklists (goal evaluation includes devil's advocate) |
| `skills/test-ladder` | New → impacted tests mid-cycle; full suites only at cycle end |
| `skills/align-docs` | Phase 6: evaluator-gated sync of all docs to shipped code |
| `skills/ship-pr` | Phase 7: approval-gated forge delivery (GitHub / Azure DevOps / GitLab / hand-over) |
| `skills/auto-loop` + `_loop/` + `_goals/backlog.md` | Autonomous loop with structural guards (optional) |
| `ORCHESTRATION.md` | The architecture doc, filled in for the project |
| `orchestration-kit.manifest.json` | Kit version + file hashes, enabling clean upgrades |

Everything is generated with project-specific content. Layer order, test commands, evaluator auto-fail triggers, and model IDs are derived from the codebase and your answers, never left generic.

Targeting Cursor emits a self-contained `.cursor/` tree containing agents, skills, the architecture doc, and the model map, with no dependency on `.claude/`.

Start your first feature with `/feature`.

Start an unattended run (sandboxed!) with `_loop/loop.sh 10` or `pwsh _loop/loop.ps1 10` (PowerShell 7+).

Loop driver behavior (dispatch, slots, worktrees, circuit breakers, exit codes) is
documented in [docs/guide/autonomous-loop.md](docs/guide/autonomous-loop.md); when each
piece shipped is in [CHANGELOG.md](CHANGELOG.md).

### Self-install (local development of the kit itself)

This repo dogfoods its own skill. `bash scripts/self-install.sh` — or
`pwsh -NoProfile -File scripts/self-install.ps1` (PowerShell 7+) — copies the
top-level skills into `.claude/skills/` and `.cursor/skills/` offline (no npx); then
run `/setup` in a repo session to emit the full instance. Everything emitted is
gitignored — the canonical source stays under `skills/setup/`. Script flags, the
dogfood loop, repo anatomy, and the test harnesses are documented in
[docs/guide/contributing.md](docs/guide/contributing.md).

## Model tiers

Evaluators and the orchestrating session run a frontier model; implementer and test-writer
run a light model. `models.map.md` is the single place model IDs live per install —
including fallback chains (never fall back *up* a tier), the fix-cycle rotation table,
and the cost-ceiling policy. The research behind the split — including the Copilot
cost-ceiling and Cursor silent-fallback caveats — is in
`docs/research-multi-harness-upgrade.md`. Re-run `/setup` when providers rotate model
names.

## Upgrading an installed project

1. **Re-pull the kit** with whichever CLI you installed with:
   `npx skills add kdcllc/skills` again, or `npx agent-skills-cli update`.
2. **Re-run `/setup`.** It reads `orchestration-kit.manifest.json`, diffs file hashes
   to spot your local modifications, and shows a diff before touching anything you
   edited. Seed files like `_goals/backlog.md` are never overwritten. Always re-run
   `/setup` after upgrading (updating `_loop/` drivers by hand skips new `.gitignore`
   lines).

Manifest semantics, seed files, and stale-file pruning are documented in
[docs/guide/contributing.md](docs/guide/contributing.md); kit maintainers bump
`skills/setup/VERSION` whenever kit behavior changes.

## Editing the templates

Templates use `{{TOKEN}}` placeholders and `<!-- BOOTSTRAP: ... -->` comments the setup
skill must resolve and delete. The placeholder reference lives in
`skills/setup/SKILL.md`. All canonical content lives under `skills/setup/templates/`;
per-harness differences belong in `emitters/`, verified facts in
`reference/harness-matrix.md`.
