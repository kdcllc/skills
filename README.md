# AI Orchestration Kit

[![skills.sh installs](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills)

> Kit version: **0.19.0** (`skills/setup/VERSION`) · The install badge above applies
> only if the repo is made public: [skills.sh](https://www.skills.sh/) filters private
> repos out of its public index by design
> ([vercel-labs/skills#381](https://github.com/vercel-labs/skills/issues/381)), so it
> stays dormant while this repo is private. Private installs work regardless — see
> below. If the repo publishes under a different owner/name, update the badge path
> (`skills.sh/b/<owner>/<repo>`).

A portable orchestrator/worker/evaluator multi-agent system for AI coding harnesses —
**Claude Code, Cursor, GitHub Copilot (VS Code), and OpenAI Codex** — packaged as one
installable `setup` skill that compiles a single canonical template source into each
harness's native format.

What an install gives a project:

- A **seven-phase feature workflow** (`/feature`): alignment → goal creation → goal
  evaluation → task execution → final audit → docs alignment → approval-gated pull
  request. No phase advances without an evaluator verdict; fixes are always
  re-evaluated (3-cycle limits, explicit escalation).
- **Five subagents with tiered model pinning**: `evaluator` and `qa-evaluator` on the
  frontier tier (effort high), `implementer`, `test-writer`, and `terminal` on the light
  tier (effort medium) — `terminal` runs Bash or PowerShell and returns only the
  result the caller asked for, so the raw stream stays out of the frontier
  session. Model IDs are configuration (`models.map.md`), with per-tier fallback
  chains, a never-fall-up rule, and a cost-ceiling policy.
- **Hardened evaluation** (patterns adopted from studying
  [bradygaster/squad](https://github.com/bradygaster/squad)): existence checks with a
  ✅/⚠️/❌/🔍 confidence ladder and anti-fabrication rules, a required devil's-advocate
  section in goal evaluation, fix-cycle **model rotation** (retry with a different model
  family, then the frontier tier), silent-success artifact verification, and an
  append-only **orchestration log** per goal. v0.18.0 added **calibration exemplars**
  and an **execute-before-score** rule to the `evaluator` agent, a **hard per-criterion
  threshold** (no averaging away one failing dimension) to the criteria skills, pre-code
  **contracts** with two-party worker/evaluator sign-off before implementation, and
  **`eval_depth`** intensity routing set by the orchestrator (never a skip).
- A **staged test ladder** (`test-ladder`): new tests → impacted tests mid-cycle; full
  suites at cycle end — in a goal's designated closer task when it has one, and in the
  orchestrator's Phase 5 Quality Checks.
- An optional **autonomous loop** (`auto-loop` + `_loop/loop.sh` / `_loop/loop.ps1`):
  one backlog story per fresh-context iteration, evaluation-gated commits, circuit
  breakers (no-progress, repeated-error, and protected-path violations enforced in the
  loop drivers, not prose), memory size gates, and a single human-approved PR at run end.
  Slot-supervision knobs — `LOOP_SLOTS` (default 2, clamped `[1,3]`; live under the
  N>1-iff-worktree rule shipped in v0.12.0: honored when `LOOP_WORKTREE=1`, clamps to
  effective 1 when `LOOP_WORKTREE=0` (with a stderr note only when `LOOP_SLOTS>1` was
  set explicitly)) and `LOOP_WORKTREE` (default 0, main-tree iteration; `=1` opts into
  a driver-managed worktree) — sit alongside a six-code exit contract: codes 0–3
  aggregated across slots with precedence 4>3>2>1>0 (per-slot CB1/CB2 retirement
  instead of a run-fatal stop; drained completion exits 0 only when no branch was
  quarantined this run), exit 4 short-circuiting the table on protected-path
  violations, and exit 5 as the loud setup/integration stop.

## Layout

```
ORCHESTRATION.md              # Pointer to the canonical template inside the skill
docs/
├── research-multi-harness-upgrade.md  # Verified per-harness research + upgrade plan
├── research-squad-ideas.md            # bradygaster/squad study + adopted ideas (A1–A10)
├── research-token-efficient-skills.md # 2026-08-20: invocation flags, hygiene, terminal agent
├── research-harness-design-upgrade.md # 2026-08-21: Anthropic harness-design study →
│                                      #   evaluator vocabulary + contracts (shipped v0.18.0: phases 0–2)
└── design-parallel-dispatch.md        # Verdict-gated design: WIP-limited parallel dispatch
                                       #   in the autonomous loop (partially shipped; see its Status block)
skills/setup/                 # The installable skill (the compiler)
├── SKILL.md                  # Workflow: detect harness(es) → inspect → interview →
│                             #   resolve templates → emit per harness → manifest
├── VERSION                   # Kit version (written into each install's manifest)
├── reference/
│   └── harness-matrix.md     # Verified per-harness capability table + friction points
├── emitters/                 # Per-harness compile instructions
│   ├── claude-code.md        #   .claude/ (canonical format — mostly a copy)
│   ├── cursor.md             #   .cursor/ self-contained tree (agents, skills, ORCHESTRATION.md, model map)
│   ├── copilot.md            #   .github/agents/*.agent.md + copilot-instructions.md
│   └── codex.md              #   AGENTS.md + .codex/config.toml role tables
└── templates/                # Canonical source (Claude Code format)
    ├── ORCHESTRATION.md      # Architecture doc template
    ├── models.map.md         # Tier → model IDs, fallback chains, fix-cycle rotation
    ├── agents/               # evaluator, qa-evaluator (frontier) · implementer, test-writer (light)
    ├── skills/               # feature, research, {goal,task,qa}-criteria,
    │                         #   test-ladder, align-docs, ship-pr
    └── loop/                 # Optional autonomous loop: SKILL.md (one iteration),
                              #   loop.sh + loop.ps1 (guarded drivers), PROMPT.md, backlog.md
scripts/                      # self-install.sh / self-install.ps1 — first-mile dogfood (see §Self-install)
tests/
└── loop-harness/run.sh        # Tracked behavioral test suite (breaker state machine +
                              #   torn-read/fail-safe hardening, SIGPIPE regressions,
                              #   checks J/K mutations); self-install assertions run before
                              #   the `_loop/` guard (they execute on a fresh clone with no
                              #   `_loop/`); the remaining loop-instance assertions are skipped
                              #   if `_loop/` is absent (one aggregate skip, not per-row SKIP
                              #   lines); run: bash tests/loop-harness/run.sh
```

## Install into a project

A public repo is NOT required — both CLIs install from this private repo as long as
the machine has git access to it:

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
tiers, QA surfaces, research workflow, autonomous loop, GitHub/`gh` availability), and
emits:

| Generated | Purpose |
|-----------|---------|
| `agents/evaluator`, `agents/qa-evaluator` | Skeptical reviewers — frontier tier, existence checks + confidence ladder |
| `agents/implementer`, `agents/test-writer` | Workers — light tier, ladder rungs 1–2 only |
| `skills/feature` | Seven-phase workflow + goal/task templates + orchestration log |
| `skills/research` | Research → Plan workflow (optional) |
| `skills/{goal,task,qa}-criteria` | Evaluation checklists (goal evaluation includes devil's advocate) |
| `skills/test-ladder` | New → impacted tests mid-cycle; full suites only at cycle end |
| `skills/align-docs` | Phase 6: evaluator-gated sync of all docs to shipped code |
| `skills/ship-pr` | Phase 7: approval-gated PR drafted from branch commits |
| `skills/auto-loop` + `_loop/` + `_goals/backlog.md` | Autonomous loop with structural guards (optional) |
| `ORCHESTRATION.md` | The architecture doc, filled in for the project |
| `orchestration-kit.manifest.json` | Kit version + file hashes, enabling clean upgrades |

Everything is generated with project-specific content — layer order, test commands,
evaluator auto-fail triggers, and model IDs are derived from the codebase and your
answers, never left generic. Targeting Cursor emits a self-contained `.cursor/` tree —
agents, skills, the architecture doc, and the model map — with no dependency on
`.claude/`. Start your first feature with `/feature`; start an unattended
run (sandboxed!) with `_loop/loop.sh 10` (or `pwsh _loop/loop.ps1 10` — PowerShell 7+).
Driver-owned dispatch, write-set admission, and the single-writer integrator shipped in
v0.12.0. Completion and exit aggregation shipped in v0.13.0 — per-slot CB1/CB2
retirement instead of a run-fatal stop, the run exit aggregated across slots with
precedence 4>3>2>1>0, quarantine-gated completion (drained-backlog exit 0 only when no
branch was quarantined this run), and `.loop-worktrees/QUARANTINE-<branch>.md` markers
(slashes in the branch become dashes) embedding the dispatched prompt.
`LOOP_WORKTREE` still defaults to 0 (main-tree iteration; `=1` requires a
tracked-instance preflight); `LOOP_SLOTS` is live under the
N>1-iff-worktree rule (LOOP_WORKTREE=1 honors the configured value; LOOP_WORKTREE=0
clamps to effective 1, with a stderr note only when `LOOP_SLOTS>1` was set explicitly).
A new exit code 5 covers setup/integration failures; the completion-time backlog
re-scan added in v0.13.0 now raises the same missing/unreadable-backlog cause at a
fifth site (the four causes are unchanged — this adds loud completion-time coverage).

### Self-install (local development of the kit itself)

**First-mile skill copy (offline, no npx):** These scripts copy every top-level
`skills/<name>/` directory (each containing a `SKILL.md`) from the working tree
directly into `.claude/skills/` and `.cursor/skills/`. Overwrite-copy is the default;
no network access or npx is required.

```bash
bash scripts/self-install.sh
```

On Windows or any system where the `.ps1` may lack execute permission, use `pwsh -File` (PowerShell 7+):

```powershell
pwsh -NoProfile -File scripts/self-install.ps1
```

Flags: `--dry-run` prints the planned destinations and writes nothing (exit 0);
`--symlink` places the canonical real tree under `.agents/skills/` and makes
`.claude/skills/<name>` and `.cursor/skills/<name>` symlinks pointing there (fails
loudly on any symlink failure — never falls back to copy); `--force` is accepted
and ignored (overwrite is already the default). The destination paths
`.cursor/skills/` and `.agents/skills/` are gitignored alongside the entire `.claude/`
directory (see `.gitignore`); nothing the scripts write ever reaches git. `.gitignore`
also covers `.cursor/ORCHESTRATION.md`, the architecture doc `/setup` emits under `.cursor/`.

These scripts do **not** replace `/setup` and do **not** emit the compiled instance.
`/setup` is the **compile** step that emits `_loop/`, the agents, `_goals/`,
`orchestration-kit.manifest.json`, and all generated project-specific content. After
running the scripts above, invoke `/setup` inside the repo session to produce the full
local instance.

This repo dogfoods its own skill: run `/setup` in a session inside this repo and point
it at itself. The emitted instance (`.claude/`, `.cursor/skills/`, `.cursor/agents/`,
`.cursor/rules/`, `.cursor/ORCHESTRATION.md`, `_goals/`, `_loop/`, `_research/`,
`orchestration-kit.manifest.json`) is **gitignored** — a self-install never reaches
git, so it is safe to re-run at any time and nothing in the instance is source of
truth. The canonical kit stays under `skills/setup/`; after editing templates, re-run
`/setup` to refresh the local instance and exercise the change end-to-end before
committing the canonical side. The tracked test harness (`tests/loop-harness/run.sh`)
exercises the `/setup`-emitted instance when `_loop/` is present — run it with
`bash tests/loop-harness/run.sh`. Assertions for these scripts exist in the loop
harness and run without requiring `_loop/`.

## Model tiers

Evaluators and the orchestrating session run a frontier model; implementer and test-writer
run a light model. `models.map.md` is the single place model IDs live per install —
including fallback chains (never fall back *up* a tier), the fix-cycle rotation table,
and the cost-ceiling policy. The research behind the split — including the Copilot
cost-ceiling and Cursor silent-fallback caveats — is in
`docs/research-multi-harness-upgrade.md`. Re-run `/setup` when providers rotate model
names.

## Upgrading an installed project

Re-run `/setup`: it reads `orchestration-kit.manifest.json`, diffs file hashes to spot
your local modifications, regenerates, and shows a diff before touching anything you
edited. Seed files (today just `_goals/backlog.md`, listed in the manifest's
`seedFiles`) sit outside that flow: created only if missing, never overwritten, and
their hash drift is expected, not a modification the diff needs to show you. Bump
`skills/setup/VERSION` when changing the kit; users re-pull with whichever CLI they
installed with — `npx skills add kdcllc/skills` again, or
`npx agent-skills-cli update` (run `npx agent-skills-cli check` first to see installed
skills with source and version) — then re-run `/setup` to re-emit.

Installs that update `_loop/` drivers without re-running `/setup` Step 5 will lack the
new `.loop-worktrees/` and `_goals/breaker-state.json.tmp.*` `.gitignore` lines
(`skills/setup/SKILL.md:127-132`) — re-run `/setup` after upgrading (or append them
manually).

## Editing the templates

Templates use `{{TOKEN}}` placeholders and `<!-- BOOTSTRAP: ... -->` comments the setup
skill must resolve and delete. The placeholder reference lives in
`skills/setup/SKILL.md`. All canonical content lives under `skills/setup/templates/`;
per-harness differences belong in `emitters/`, verified facts in
`reference/harness-matrix.md`.
