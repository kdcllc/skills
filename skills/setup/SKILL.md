---
name: setup
description: Install the orchestrator/worker/judge multi-agent system into the current project, compiled for its AI coding harness(es) — Claude Code, Cursor, GitHub Copilot (VS Code), and/or OpenAI Codex. Generates the four subagents (judge, qa-judge, implementer, test-writer) with tiered model pins, the orchestrator skills (feature, research), the criteria skills, an optional autonomous feature loop, and a project-specific ORCHESTRATION.md. Run once per project; re-run to upgrade or re-target.
---

# Setup (Orchestration Kit Compiler)

You are installing a multi-agent orchestration system (orchestrator coordinates,
worker subagents execute with fresh context, skeptical judges verify) into the
**current project**. The kit keeps ONE canonical template source in Claude Code format
(`templates/`) and **compiles** it per harness via the instruction files in `emitters/`.
Consult `reference/harness-matrix.md` for verified capabilities and friction points —
when live harness docs contradict it, trust the docs and update the matrix.

Skim `templates/ORCHESTRATION.md` first so you understand what you are instantiating.

## Step 1 — Detect target harness(es)

Evidence: existing `.claude/`, `.cursor/`, `.github/copilot-instructions.md` or
`.github/agents/`, `.codex/` or `AGENTS.md`; plus the session you are running in.
Present what you detected and ask which harnesses to target — **multiple is normal**
(the canonical `.claude/` tree already serves Cursor and VS Code partially; see the
matrix). If any destination file exists, list collisions and ask before overwriting —
unless a kit manifest exists (see Upgrading below).

## Step 2 — Inspect the repo

Establish from the code (do not ask what you can read):

- Language(s), runtime, package manager, workspace layout
- Exact commands for **targeted** tests (one file / pattern) and the **full** suite(s)
- Lint / type-check / build commands **that are actually configured** — never invent
- Code lanes/layers and their dependency order
- User-facing surfaces: CLIs, API endpoints, web UI, library entry points
- Existing skills/agents/rules, per-directory `AGENTS.md`/`CLAUDE.md`, canonical docs
- External services the code talks to (these must be mocked in tests)

## Step 3 — Interview the user

Ask (multiple-choice where possible) only what you could not infer:

1. **Project name** as it should appear in docs (propose one).
2. **Execution layer order** — confirm your inferred chain.
3. **Model tiers** — fill `templates/models.map.md` for each target harness: pick
   CURRENT frontier and light model IDs (check the harness's live model list; IDs
   rotate). Offer "inherit/unpinned" as an option (then strip model keys and the tier
   column from emitted files).
4. **QA gate surfaces** — which user-facing surfaces qa-judge covers; any existing
   evidence-producing skills (API smoke, visual QA)?
5. **Research workflow** — wanted? If not, skip the `research` skill and delete its
   section from ORCHESTRATION.md.
6. **Autonomous loop** — wanted? If yes: confirm sandbox strategy (worktree/container),
   max iterations, and that commits stay local (no auto-push) unless they say otherwise.
   If no: skip `templates/loop/` and delete the Autonomous Loop section.
7. **Pull-request workflow (Phase 7)** — confirm the project lives on GitHub and `gh`
   is available. If not, skip the `ship-pr` skill and delete Phase 7 from the
   emitted ORCHESTRATION.md.
8. **Ground-truth doc** — the committed reference file for domain decisions.

## Step 4 — Resolve the canonical templates

In a scratch copy, resolve every `{{TOKEN}}` and act on + delete every
`<!-- BOOTSTRAP: ... -->` comment in `templates/`. Rules:

- Table rows / sections that don't apply are removed, not left as placeholders.
- Judge auto-fail triggers must name **this project's** sins (from Step 2). Generic
  filler is a bootstrap failure.
- Model tiers resolve from the completed model map; keep the resolved
  `models.map.md` as the single place model IDs live.

### Placeholder reference

| Token | Meaning |
|-------|---------|
| `{{PROJECT_NAME}}` | Display name of the project |
| `{{STACK_SUMMARY}}` | 2–5 sentence stack note |
| `{{IDE_DIR}}` | Primary config dir of the target harness (`.claude`, `.cursor`, `.github`, `.codex`) |
| `{{MODEL_FRONTIER}}` / `{{MODEL_LIGHT}}` | Tier → model ID for the primary harness (from the model map) |
| `{{CURSOR_MODEL_*}}`, `{{COPILOT_MODEL_*}}`, `{{CODEX_MODEL_*}}` | Per-harness tier IDs (model map only) |
| `{{MODEL_ALT_FAMILY}}` | Different-family model at light-comparable tier, used by fix-cycle rotation (model map) |
| `{{LOOP_MODEL_CHAIN}}` | Comma-separated loop fallback chain, first = preferred (from the model map's "Loop fallback chain" row); empty ⇒ the breaker still tracks state but never passes a model flag |
| `{{EXECUTION_LAYERS}}` | Dependency-ordered layer chain |
| `{{GROUND_TRUTH_DOC}}` | Committed domain ground-truth doc path |
| `{{QA_SURFACES}}` | User-facing surfaces + evidence each produces |
| `{{SETUP_COMMANDS}}` | Dependency install commands |
| `{{TARGETED_TEST_COMMAND}}` / `{{FULL_TEST_COMMAND}}` | Staged test commands |
| `{{TEST_FRAMEWORKS}}` | Test framework(s) in use |
| `{{LINT_COMMAND}}` / `{{TYPECHECK_COMMAND}}` | Only if configured; else remove rows |
| `{{JUDGE_AUTO_FAIL_TRIGGERS}}` / `{{QA_AUTO_FAIL_TRIGGERS}}` | Project-specific instant-fail conditions |

## Step 5 — Emit per harness

For each target harness, follow its emitter exactly:

| Harness | Emitter |
|---------|---------|
| Claude Code | `emitters/claude-code.md` |
| Cursor | `emitters/cursor.md` |
| GitHub Copilot (VS Code) | `emitters/copilot.md` |
| OpenAI Codex | `emitters/codex.md` |

Emitters compose: run Claude Code first when it is among the targets — Cursor and
VS Code reuse parts of the emitted `.claude/` tree.

**Loop extras (all harnesses)**: both loop drivers (`_loop/loop.sh` and
`_loop/loop.ps1`) and their circuit-breaker helper twins (`_loop/breaker.sh` and
`_loop/breaker.ps1`, sourced/dot-sourced by the drivers) are always emitted for
loop-enabled installs, regardless of target harness or detected OS — the user picks
the driver that matches their platform at invocation time. If the loop is enabled,
append to the project's `.gitattributes` (create if missing) so parallel/append-only
state merges cleanly and the loop drivers always check out with the line endings
their interpreters require:

```
_goals/LEARNINGS.md merge=union
_goals/ESCALATIONS.md merge=union
_goals/*/orchestration-log.md merge=union
*.sh text eol=lf
*.ps1 text eol=lf
```

Also append `_goals/breaker-state.json` to the project's `.gitignore` (create if
missing) — this is runtime scratch written by the breaker helpers at run time and
must never enter commits.

**Checks scripts on Windows**: the kit does not emit a structural-checks script
itself. If a project's install adopts one (as the kit's own repository does), and the loop
is enabled or Windows is a target platform, emit a `.ps1` twin with the same checks
and exit semantics — the pattern mirrors the loop drivers (`checks.sh` /
`checks.ps1`, behaviorally identical, no OS-detection branching).

## Step 6 — Manifest, verify, report

1. Write `orchestration-kit.manifest.json` at the project root:
   ```json
   {
     "kit": "agent-kit",
     "kitVersion": "<contents of VERSION>",
     "installedAt": "<ISO date>",
     "harnesses": ["claude-code", "..."],
     "options": { "research": true, "loop": false },
     "files": { "<emitted path>": "<sha256>" }
   }
   ```
2. Run each emitter's Verify section. Global check: grep every emitted file for `{{`
   and `BOOTSTRAP:` — zero hits. Also: `pwsh -NoProfile -Command` parser check on
   emitted `.ps1` files when pwsh is available; otherwise note the skip in the report.
3. Report: files emitted per harness, the layer order / commands / model tiers baked
   in, and how to start (`/feature` — or the harness's equivalent invocation).

## Upgrading / re-running

If `orchestration-kit.manifest.json` exists: compare its `kitVersion` to `VERSION`,
diff manifest hashes against the working tree to find user-modified files, regenerate
into the scratch copy, and show the user a diff for any file they modified before
overwriting it. Unmodified files update silently. Update the manifest last.
