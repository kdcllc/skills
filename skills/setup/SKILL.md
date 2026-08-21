---
name: setup
description: Install the orchestrator/worker/judge multi-agent system into the current project, compiled for its AI coding harness(es) — Claude Code, Cursor, GitHub Copilot (VS Code), and/or OpenAI Codex. Generates the five subagents (judge, qa-judge, implementer, test-writer, terminal) with tiered model pins — terminal is light-tier: it runs any Bash or PowerShell command and returns only the result the caller asked for — plus the orchestrator skills (feature, research), the criteria skills, an optional autonomous feature loop, and a project-specific ORCHESTRATION.md. On empty or near-empty (greenfield) directories it first asks whether to scaffold a project tree and creates nothing until the user confirms. Run once per project; re-run to upgrade or re-target.
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

## Step 2a — Greenfield gate

**Run order (hard):** run this step after Step 1 and **before** Step 2, despite the
`2a` label. Evaluate it **once per `/setup` session** — evaluate the sparse heuristic
and ask at most once per invocation. After a confirmed generic tree (paths that sit on
the allowlist below), do not re-enter Step 2a; the only hand-back target is Step 2,
never Step 2a.

### Sparse heuristic

The workspace is sparse **only if every present file** is on this allowlist:

- `.git/` (any contents)
- `.gitignore`
- `LICENSE`
- `README*` (any suffix)
- `.editorconfig`
- `.gitattributes`
- `.DS_Store`
- `Thumbs.db`
- empty directories

**Any other file** means **not sparse** — including `skills/setup/SKILL.md`, anything
under `tests/`, `docs/`, `scripts/`, or `src/`, a language manifest,
`orchestration-kit.manifest.json`, `notes.md`, or `main.py`.

Worked negative example: a repo containing `skills/setup/SKILL.md`, or a non-empty
`tests/` directory, is **not** sparse and must skip Step 2a.

**Hard rule — not sparse:** skip **entirely** `## Step 2a — Greenfield gate` (no
scaffold offer, no skills.sh install step) and continue with Step 2 inspect below.

**Hard rule — sparse:** **always ask** whether to scaffold a new project. Never
silently scaffold; never skip the question.

### Decline path

If the user declines the scaffold: create no scaffold files, do not run the skills.sh
step, set `options.greenfield` to `false` at emit time (Step 6), and continue with the
normal inspect → interview → emit path.

### Accept path — guide, then confirm

1. Interview the stack with three choices only: **TypeScript/Node**, **Python**, or
   **Other**.
2. Present the matching frozen tree below as a list of paths — do not create anything
   yet. **Guide-then-confirm (hard):**
   create nothing until the user explicitly confirms that tree.
   No Write and no `mkdir` of scaffold paths before that confirmation. If they reject
   the presented tree, revise it and wait again — still create nothing.
3. After confirmation, create **exactly** the confirmed paths.
4. **Never overwrite:** if a confirmed path already exists, skip it and report the
   skip.

Frozen trees — create these after confirm and nothing else (no sample production
module, no failing test file, no CI):

| Stack | Paths to create after confirmation |
|-------|------------------------------------|
| **TypeScript/Node** | `package.json` (minimal: `name` from the project/folder name, `"private": true`), `tsconfig.json` (minimal `compilerOptions` sufficient for `src/`), `.gitignore` (at least `node_modules/` and `dist/`), `README.md` (title), `src/`, `tests/` |
| **Python** | `pyproject.toml` (minimal `[project]` name + version), `.gitignore` (at least `__pycache__/`, `.venv/`, `*.egg-info/`), `README.md` (title), `src/`, `tests/` |
| **Other / generic** | `.gitignore`, `README.md` (title), `src/`, `tests/` — no language manifest |

### Accept path — skills.sh stack skills (greenfield only)

Runs on the accept path only, after the tree exists and the stack is known. Search the
skills.sh leaderboard first, then `npx skills find` for the chosen stack (`typescript`
/ `node`, or `python`). Workflow reference:
https://www.skills.sh/vercel-labs/skills/find-skills

Offer a skill only if its install count is 1000 or more. Prefer listings whose GitHub
owner is `vercel-labs` or `anthropics`; also prefer a listing whose owner is
`microsoft` when it meets the floor. Still show other publishers that meet the floor.
Never list a skill under 1000.

Present each candidate with: skill name, what it does, install count, source
(`owner/repo`), install command, and a skills.sh link. The user picks zero or more.
Install **project-local** with exactly:

`npx skills add <owner>/<repo> --skill <picked-skill> -y`
Never pass -g (project-local only).

**Why `--skill` is required:** `-y` skips confirmation and accepts defaults — without
`--skill` the CLI installs **every** skill in that source, which is auto-install and
out of scope. Optional `-a <agent>` only when the CLI agent id for a Step 1 harness is
known; otherwise omit `-a` (do not guess). Do not vendor installed copies into the
kit's `templates/` tree.

**Fail-open:** if `npx` is missing, the command exits non-zero, or the network is
unavailable, do not abort `/setup`. Print the exact `npx skills add …` commands for the
user to run later, then continue — never stop before inspect/emit.

### Accept-path hand-back (hard)

After confirmed tree creation **and** after the skills.sh step (including its
fail-open branch), the flow continues at Step 2 — Inspect the repo on the newly
created tree, then Step 3 interview, then Steps 4–6 emit. This gate never ends the
skill.

### Greenfield token disposition (hard)

The frozen trees include **no** test runner and no failing test file, so nothing about
testing can be inferred from them. Step 3 **must ask** for the targeted and full test
commands, the setup commands, and the test framework name(s), and **must never invent**
`npm test` / `pytest`. Then resolve the four inference-only tokens by this table. Every
`{{TOKEN}}` in the scratch copy must be replaced or its containing row/sentence
deleted, so Step 6's grep for `{{` stays at zero hits.

| Token | User supplied a value | User has none |
|-------|----------------------|---------------|
| `{{TARGETED_TEST_COMMAND}}` | replace **every** occurrence under `templates/` (today 5 sites: `ORCHESTRATION.md` code block, `agents/implementer.md`, `agents/test-writer.md`, `skills/test-ladder/SKILL.md`, `skills/task-criteria/SKILL.md` — **none** is a table row) | there is no token-only table row for this token; replace every occurrence with the literal `(not configured)` |
| `{{FULL_TEST_COMMAND}}` | replace **every** occurrence (today 9 sites; the only token-only table row among these four tokens is the `templates/ORCHESTRATION.md` Quality-checks / rung-3 row, plus 8 prose/code-block sites) | delete that table row if its cell is only this token; replace every remaining occurrence with `(not configured)` |
| `{{TEST_FRAMEWORKS}}` | replace the occurrence (`agents/test-writer.md` prose) | replace with `not configured` |
| `{{SETUP_COMMANDS}}` | replace the occurrence (`ORCHESTRATION.md` code block) | TypeScript/Node accept path: `npm install`; Python accept path: `pip install -e .`; Other or decline: `(not configured)` |

Do **not** analogize to the lint/typecheck "remove the row" rule: `{{LINT_COMMAND}}`
and `{{TYPECHECK_COMMAND}}` each occupy **exactly one** table row, so deleting the row
is complete. Every test/setup/framework token above has at least one **non-table** site
(prose or code block), so row-deletion alone always leaves a `{{` behind. The counts
above are a snapshot — the rule is replace every occurrence, not a frozen inventory.

### Greenfield signal (hard)

Record the branch in the Step 6 manifest `options`: `"greenfield": true` **only** when
the user accepted **and** confirmed a tree; otherwise `"greenfield": false`. Downstream
`<!-- BOOTSTRAP: ... -->` resolution keys off that flag — do not rely on remembering
which branch ran.

## Step 2 — Inspect the repo

Step 2a has already run (sparse workspace) or was skipped entirely (not sparse); either
way, inspect now and never re-enter the gate.

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

**Seed files (create if missing; never overwrite)**: `_goals/backlog.md` is emitted as
a *seed*, not as managed content — the user owns it from the first install onward.
Create it only when it does not exist; on every re-run or upgrade leave an existing
seed untouched, even when its recorded manifest hash no longer matches (see Step 6).

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
must never enter commits. Append two more lines to the same list: `.loop-worktrees/`
(the per-slot worktree scratch created and destroyed by the driver at
`LOOP_WORKTREE=1`) and `_goals/breaker-state.json.tmp.*` (crash-orphaned temp files
left behind by the breaker's write-temp-then-rename, per STORY-009).

**Checks scripts on Windows**: the kit does not emit a structural-checks script
itself. If a project's install adopts one (as the kit's own repository does), emit a
`.ps1` twin with the same checks and exit semantics — the pattern mirrors the loop
drivers (`checks.sh` / `checks.ps1`, behaviorally identical, no OS-detection
branching).

## Step 6 — Manifest, verify, report

1. Write `orchestration-kit.manifest.json` at the project root:
   ```json
   {
     "kit": "agent-kit",
     "kitVersion": "<contents of VERSION>",
     "installedAt": "<ISO date>",
     "harnesses": ["claude-code", "..."],
     "options": { "research": true, "loop": false, "greenfield": false },
     "files": { "<emitted path>": "<sha256>" },
     "seedFiles": ["_goals/backlog.md"]
   }
   ```
   `options.greenfield` is `true` **only** when Step 2a's accept path ran and the user
   confirmed a tree; on the decline path, or when Step 2a was skipped as not sparse, it
   is `false`.
   `seedFiles` lists the emitted paths that are seeds (today exactly one): their hash
   is recorded in `files` at emit time and is EXEMPT from the upgrade diff-confirm
   flow. Semantics:
   a seed's recorded hash is an emit-time record; drift is expected and is never read as user modification.
   `_goals/LEARNINGS.md`, `_goals/ESCALATIONS.md`, and `_goals/breaker-state.json`
   are runtime/user artifacts the kit does not emit — never manifested in `files` or
   `seedFiles`, no hash ever recorded.
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

Paths listed in `seedFiles` are outside this flow: create a seed if it is missing,
otherwise leave it exactly as it is — never overwrite it, never diff-confirm it, and
never report its hash drift as a user modification (the recorded hash is an emit-time
record only). Runtime/user artifacts (`_goals/LEARNINGS.md`, `_goals/ESCALATIONS.md`,
`_goals/breaker-state.json`) have no manifest entry and are never touched.
