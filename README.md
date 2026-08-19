# AI Orchestration Kit

[![skills.sh installs](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills)

> Kit version: **0.8.0** (`skills/setup/VERSION`) · The install badge above goes live
> once the repo is public and listed on [skills.sh](https://www.skills.sh/); it shows
> anonymous install counts. If the repo publishes under a different owner/name, update
> the badge path (`skills.sh/b/<owner>/<repo>`).

A portable orchestrator/worker/judge multi-agent system for AI coding harnesses —
**Claude Code, Cursor, GitHub Copilot (VS Code), and OpenAI Codex** — packaged as one
installable `setup` skill that compiles a single canonical template source into each
harness's native format.

What an install gives a project:

- A **seven-phase feature workflow** (`/feature`): alignment → goal creation → goal
  judgment → task execution → final audit → docs alignment → approval-gated pull
  request. No phase advances without a judge verdict; fixes are always re-judged
  (3-cycle limits, explicit escalation).
- **Four subagents with tiered model pinning**: `judge` and `qa-judge` on the frontier
  tier (effort high), `implementer` and `test-writer` on the light tier (effort
  medium). Model IDs are configuration (`models.map.md`), with per-tier fallback
  chains, a never-fall-up rule, and a cost-ceiling policy.
- **Hardened judging** (patterns adopted from studying
  [bradygaster/squad](https://github.com/bradygaster/squad)): existence checks with a
  ✅/⚠️/❌/🔍 confidence ladder and anti-fabrication rules, a required devil's-advocate
  section in goal judgment, fix-cycle **model rotation** (retry with a different model
  family, then the frontier tier), silent-success artifact verification, and an
  append-only **orchestration log** per goal.
- A **staged test ladder** (`test-ladder`): new tests → impacted tests mid-cycle; full
  suites run exactly once, at cycle end.
- An optional **autonomous loop** (`auto-loop` + `_loop/loop.sh` / `_loop/loop.ps1`):
  one backlog story per fresh-context iteration, judge-gated commits, circuit breakers
  (no-progress, repeated-error, and protected-path violations enforced in the loop
  drivers, not prose), memory size gates, and a single human-approved PR at run end.

## Layout

```
ORCHESTRATION.md              # Pointer to the canonical template inside the skill
docs/
├── research-multi-harness-upgrade.md  # Verified per-harness research + upgrade plan
├── research-squad-ideas.md            # bradygaster/squad study + adopted ideas (A1–A10)
└── design-parallel-dispatch.md        # Judged design: WIP-limited parallel dispatch
                                       #   in the autonomous loop (not yet implemented)
skills/setup/                 # The installable skill (the compiler)
├── SKILL.md                  # Workflow: detect harness(es) → inspect → interview →
│                             #   resolve templates → emit per harness → manifest
├── VERSION                   # Kit version (written into each install's manifest)
├── reference/
│   └── harness-matrix.md     # Verified per-harness capability table + friction points
├── emitters/                 # Per-harness compile instructions
│   ├── claude-code.md        #   .claude/ (canonical format — mostly a copy)
│   ├── cursor.md             #   .cursor/ + reuse of .claude/ (Cursor reads it natively)
│   ├── copilot.md            #   .github/agents/*.agent.md + copilot-instructions.md
│   └── codex.md              #   AGENTS.md + .codex/config.toml role tables
└── templates/                # Canonical source (Claude Code format)
    ├── ORCHESTRATION.md      # Architecture doc template
    ├── models.map.md         # Tier → model IDs, fallback chains, fix-cycle rotation
    ├── agents/               # judge, qa-judge (frontier) · implementer, test-writer (light)
    ├── skills/               # feature, research, {goal,task,qa}-criteria,
    │                         #   test-ladder, align-docs, ship-pr
    └── loop/                 # Optional autonomous loop: SKILL.md (one iteration),
                              #   loop.sh + loop.ps1 (guarded drivers), PROMPT.md, backlog.md
```

## Install into a project

Once public and listed on skills.sh:

```bash
npx skills add kdcllc/skills
```

Until then, copy the skill in manually (any harness dir works — the skill detects and
asks):

```bash
cp -r skills/setup  <your-project>/.claude/skills/     # Claude Code
cp -r skills/setup  <your-project>/.cursor/skills/     # Cursor
```

Then, in a session inside that project, run `/setup`. It detects which harnesses to
target (multiple is normal), inspects the repo (stack, test commands, layers,
user-facing surfaces), interviews you for what it can't infer (project name, model
tiers, QA surfaces, research workflow, autonomous loop, GitHub/`gh` availability), and
emits:

| Generated | Purpose |
|-----------|---------|
| `agents/judge`, `agents/qa-judge` | Skeptical reviewers — frontier tier, existence checks + confidence ladder |
| `agents/implementer`, `agents/test-writer` | Workers — light tier, ladder rungs 1–2 only |
| `skills/feature` | Seven-phase workflow + goal/task templates + orchestration log |
| `skills/research` | Research → Plan workflow (optional) |
| `skills/{goal,task,qa}-criteria` | Judgment checklists (goal judgment includes devil's advocate) |
| `skills/test-ladder` | New → impacted tests mid-cycle; full suites only at cycle end |
| `skills/align-docs` | Phase 6: judge-gated sync of all docs to shipped code |
| `skills/ship-pr` | Phase 7: approval-gated PR drafted from branch commits |
| `skills/auto-loop` + `_loop/` + `_goals/backlog.md` | Autonomous loop with structural guards (optional) |
| `ORCHESTRATION.md` | The architecture doc, filled in for the project |
| `orchestration-kit.manifest.json` | Kit version + file hashes, enabling clean upgrades |

Everything is generated with project-specific content — layer order, test commands,
judge auto-fail triggers, and model IDs are derived from the codebase and your answers,
never left generic. Start your first feature with `/feature`; start an unattended run
(sandboxed!) with `_loop/loop.sh 10` (or `pwsh _loop/loop.ps1 10` — PowerShell 7+).

### Self-install (local development of the kit itself)

This repo dogfoods its own skill: run `/setup` in a session inside this repo and point
it at itself. The emitted instance (`.claude/`, `_goals/`, `_loop/`, `_research/`,
`orchestration-kit.manifest.json`) is **gitignored** — a self-install never reaches
git, so it is safe to re-run at any time and nothing in the instance is source of
truth. The canonical kit stays under `skills/setup/`; after editing templates, re-run
`/setup` to refresh the local instance and exercise the change end-to-end before
committing the canonical side.

## Model tiers

Judges and the orchestrating session run a frontier model; implementer and test-writer
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
`skills/setup/VERSION` when changing the kit; registry users re-run `npx skills add` to
pull the new version, then re-run `/setup` to re-emit.

## Editing the templates

Templates use `{{TOKEN}}` placeholders and `<!-- BOOTSTRAP: ... -->` comments the setup
skill must resolve and delete. The placeholder reference lives in
`skills/setup/SKILL.md`. All canonical content lives under `skills/setup/templates/`;
per-harness differences belong in `emitters/`, verified facts in
`reference/harness-matrix.md`.
