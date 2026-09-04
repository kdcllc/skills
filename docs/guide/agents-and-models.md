**Who this is for / What you'll learn:** Kit **users** and **contributors** who need to understand the six subagents, which model tier each role runs on, and how `models.map.md` governs IDs, fallbacks, and fix-cycle rotation. You will learn each agent's role, write boundaries, and prohibitions; why evaluators run frontier models while workers run light ones; the diagnostician's role in the post-exhaustion continuation ladder; the structure and rules of the model map; and harness caveats that affect tiering. For what evaluators enforce (verdict vocabulary, confidence ladder, contracts), see [evaluation-system.md](evaluation-system.md). For where each agent appears in the `/feature` phases, see [feature-workflow.md](feature-workflow.md).

# Agents and Model Configuration

The kit separates **coordination and verification** (frontier tier) from **execution** (light tier). One orchestrating main session prepares context, makes decisions, and spawns subagents — it never implements tasks itself. Every spawn passes its model explicitly (the model map's resolved ID for the agent's tier); each agent report starts with **`**Model (self-reported)**: ...`**. Six specialized subagents handle implementation, testing, command execution, evaluation, and post-exhaustion diagnosis. Model IDs, fallback chains, and fix-cycle rotation are configured in a single template file that `/setup` resolves per harness.

## The six subagents at a glance

| Agent | Tier | May write | Must never |
|-------|------|-----------|------------|
| `evaluator` | `frontier` (`{{MODEL_FRONTIER}}`) | Nothing — read and verify only | Edit files or fix anything; only evaluate |
| `qa-evaluator` | `frontier` | Nothing | Fix anything; extrapolate untested behavior |
| `implementer` | `light` (`{{MODEL_LIGHT}}`) | Only paths in the task's `writes` set | Edit out-of-fence files; run rung-3 full suites |
| `test-writer` | `light` | Only test files in task `writes` | Hit live external services; edit source to make tests pass |
| `terminal` | `light` | Shell side effects only (no Edit/Write tools) | Dump raw command streams into the caller session |
| `diagnostician` | `frontier` (`{{MODEL_FRONTIER}}`) | Nothing — diagnosis-only report | Edit files or write product code; re-litigate whether the acceptance criteria are sound (rung-5 arbitration's job) |

The sections below quote or paraphrase the canonical agent templates under [`skills/setup/templates/agents/`](../../skills/setup/templates/agents/). Capabilities not confirmed there are omitted.

## Report Footprint (all six agents)

As of **v0.26.0**, every agent completion report ends with a machine-readable **`### Footprint`** block — the last non-blank lines inside the report fence:

```markdown
### Footprint
files_read: <N> (~<C> chars)
commands_run: <N>
```

`C` is the agent's estimate of total characters read (sum of file sizes opened; rounding to the nearest thousand is fine). `terminal` reports `files_read: 0` and `commands_run: 1` (or the count it ran). The block is never omitted — write `files_read: 0 (~0 chars)` when nothing was read.

**Why it exists:** `_kit/log-spawn.* outcome` parses the `files_read: N (~C chars)` line and emits `work_read_chars: C · work_est_tokens: C/4` on the orchestration-log OUTCOME line (integer division), or `work_read_chars: n/a · work_est_tokens: n/a` when the line is absent or malformed. That **`work_est_tokens`** value is the subagent's self-reported working footprint — distinct from **`io_est_tokens`**, which measures only orchestrator↔subagent I/O chars/4. Neither is billed usage; the loop driver's `usage:` line (when `LOOP_USAGE_FORMAT` is active) is the only real token count. See [evaluation-system.md](evaluation-system.md) § Orchestration log.

## Evaluator

**Role:** Skeptical, problem-finding reviewer for goals, task definitions, and completed implementation work. Launch after every goal creation, every task execution, and as the final audit.

**Tier:** `frontier` — frontmatter `model: {{MODEL_FRONTIER}}`, effort `high`.

**What it may write:** Nothing. The evaluator reads, verifies, and returns a verdict. It never edits files and never fixes anything.

**What it must never do:**

- Fix or edit anything — only evaluate.
- Score from the report or diff alone without executing targeted tests first.
- Talk itself into a PASS after finding an issue (identified issues must appear in the verdict).
- Treat unverified claims as verified.

As of v0.20.0, the evaluator also has an orchestrator-invoked **arbitration mode** (continuation-ladder rung 5, pinned to `{{MODEL_FRONTIER_ALT_FAMILY}}`) that reviews criteria rather than code — semantics in [evaluation-system.md](evaluation-system.md).

Evaluation criteria — verdict vocabulary, confidence ladder, anti-fabrication rules, auto-fail triggers — are owned by [evaluation-system.md](evaluation-system.md), not repeated here.

## QA Evaluator

**Role:** Skeptical user-perspective QA reviewer for user-facing surfaces. Launch after a feature is implemented and evaluated, with captured behavioral evidence (command output, API responses, screenshots).

**Tier:** `frontier` — frontmatter `model: {{MODEL_FRONTIER}}`, effort `high`.

**What it may write:** Nothing. Fixes flow back through implementer and evaluator; QA re-runs.

**What it must never do:**

- Fix anything.
- Describe behavior not seen in the evidence — verdicts cite observed output only.
- Pass when evidence for a claimed surface was not provided.

The QA evaluator evaluates **behavior a user actually experiences**, not the code. Missing evidence is an issue, not a pass.

## Implementer

**Role:** Focused, checklist-driven task executor. Launch with a complete context package (task definition, requirements, files to read, constraints). Executes exactly one task or one fix cycle per invocation.

**Tier:** `light` — frontmatter `model: {{MODEL_LIGHT}}`, effort `medium`.

**What it may write:** Only paths listed in the task's `writes` set. The `reads` list is read-only interface briefs.

**What it must never do:**

- Edit, refactor, or "improve" anything outside the write fence — escalate instead, naming the exact path and why.
- Run rung 3 (full test suites) — that runs once at cycle end after the final audit.
- Touch live external services from tests (all network/service access is mocked).
- Guess when the context package is missing something — report it instead.

For noisy Bash or PowerShell commands whose raw output is not needed, spawn `terminal` with the exact command and the result you want back (where the harness allows — not Copilot).

## Test Writer

**Role:** Coverage-obsessed test author for the dedicated test task of a goal. Writes outcome-verifying tests with all external services mocked.

**Tier:** `light` — frontmatter `model: {{MODEL_LIGHT}}`, effort `medium`.

**What it may write:** Only paths in the task's `writes` set (test files). Modules under test in `reads` are read-only.

**What it must never do:**

- Hit the network or a live service — mock all external services.
- Edit out-of-fence files (source fixes, shared fixtures) to make tests pass — escalate instead.
- Write tests that assert nothing or mock the unit under test.
- Run rung 3 (full suites) — rungs 1–2 only during the task.

For noisy commands, spawn `terminal` where the harness allows (not Copilot).

## Terminal

**Role:** Command runner. Spawn with a Bash or PowerShell command and the result you need back (exit code, last N lines, a match, pass/fail, a path). Executes that command and returns **only** that result.

**Tier:** `light` — frontmatter `model: {{MODEL_LIGHT}}`, effort `medium`. Tools: Bash/shell and Read only — no Edit/Write.

**What it may write:** No files via Edit/Write tools. The shell command itself may create or change files if the caller asked — the terminal still runs it exactly.

**What it must never do:**

- Dump the full command stream into the caller (orchestrator or worker) — return only what the spawn prompt asked for.
- Use Edit/Write tools or add "helpful" extra commands beyond what the prompt lists.
- Diagnose failures, suggest fixes, or interpret output — the caller Reads a log slice if it needs more.

The terminal is the **shell-output shield**: noisy test runs, builds, and git operations stay in a light-tier subagent so raw streams do not flood the frontier orchestrating session.

## Diagnostician

**Role:** Fresh-context root-cause analyst spawned at continuation-ladder rung 4 after three implement→evaluate fix cycles exhaust without a PASS (as of v0.20.0).

**Inputs:** The task file (including its `## Acceptance Criteria` section), all three fix-cycle histories (implementer reports + evaluator verdicts), and pointers to the current code.

**Tier:** `frontier` — frontmatter `model: {{MODEL_FRONTIER}}`, effort `high`. Tools: Bash, Read, Grep, Glob — no Edit/Write.

**Execute before you diagnose:** Run the task's targeted verification command(s) yourself to observe the failure — reading prior reports or the diff alone is not enough.

**Report format:** Return a frozen five-section report — Root-Cause Hypothesis, Evidence, Rewritten Required-Fixes, Split Recommendation, Signature Declaration.

**What it may write:** Nothing — diagnosis-only report.

**What it must never do:**

- Edit files or write product code.
- Propose skipping evaluation.
- Re-litigate whether the contract is sound (defer to rung-5 arbitration).
- Invent command output (quoted output must come from commands it ran).

You supply the report — the orchestrator routes (signature match → rung 6 or escalate; otherwise ONE diagnosis-driven implementation attempt). Routing details in [feature-workflow.md](feature-workflow.md).

## Roster diagram

The orchestrating session runs on the frontier tier. It dispatches light-tier workers for execution and frontier-tier evaluators for verification. The terminal agent isolates command output. A frontier-tier diagnostician is spawned for post-exhaustion diagnosis.

```mermaid
flowchart TD
    Orch["Orchestrating session\n(frontier tier)"]
    Impl["implementer\n(light tier)"]
    TW["test-writer\n(light tier)"]
    Term["terminal\n(light tier)\nshell-output shield"]
    Eval["evaluator\n(frontier tier)"]
    QA["qa-evaluator\n(frontier tier)"]
    Diag["diagnostician\n(frontier tier)\ndiagnosis-only"]

    Orch -->|"spawn: implement / fix"| Impl
    Orch -->|"spawn: write tests"| TW
    Orch -->|"spawn: run command"| Term
    Orch -->|"spawn: verify task / goal"| Eval
    Orch -->|"spawn: verify UX"| QA
    Orch -->|"spawn: diagnose (rung 4)"| Diag
    Impl -->|"noisy command"| Term
    TW -->|"noisy command"| Term
    Term -->|"result only, no raw stream"| Orch
    Eval -->|"verdict"| Orch
    QA -->|"QA verdict"| Orch
    Diag -->|"diagnosis report"| Orch
```

Workers never advance a phase on their own — evaluators gate progression. See [feature-workflow.md](feature-workflow.md) for where each spawn happens in the seven phases.

## Why frontier vs light

Evaluators, the diagnostician, and the orchestrating session run **frontier** models; `implementer`, `test-writer`, and `terminal` run **light** models. The split follows a simple cost–quality tradeoff:

| Tier | Roles | Rationale |
|------|-------|-----------|
| `frontier` | Orchestrator (main session), `evaluator`, `qa-evaluator`, `diagnostician` | Delegation and evaluation have a capability floor — don't cheap out on the roles that decide and verify; continuation-ladder diagnosis needs frontier-tier reasoning |
| `light` | `implementer`, `test-writer`, `terminal` | Checklist-driven execution and compact command running retain most quality at a fraction of the cost when the plan and the verification are strong |

**Verification quality is where frontier spend pays off.** Implementation is cheaper-tier work that evaluators re-check before anything advances. A light-tier implementer following the task file (including its Acceptance Criteria) and strong evaluation is cheaper than running everything on frontier — without sacrificing gate quality at the roles that matter.

Reasoning-effort pins (where the harness supports them): evaluators and the diagnostician `high`, workers `medium`.

## `models.map.md` anatomy

[`skills/setup/templates/models.map.md`](../../skills/setup/templates/models.map.md) is the single place model IDs are defined for an install. Model IDs are **configuration, not constants** — re-run `/setup` (or edit the map and re-emit) when providers rotate model names.

### Tier → model ID table structure

The map has two related tables:

1. **Tier assignments** — maps each role to `frontier` or `light` (see previous section).
2. **Resolved models** — one row per tier, one column per harness, cells filled with placeholder tokens such as `{{MODEL_FRONTIER}}`, `{{MODEL_LIGHT}}`, `{{CURSOR_MODEL_FRONTIER}}`, `{{COPILOT_MODEL_LIGHT}}`, etc. During `/setup`, these tokens are replaced with harness-specific IDs from the live model list.

Describe the **structure** (tier rows, per-harness columns, placeholder tokens) — not any concrete ID as permanent truth. If you see an illustrative resolved value in a local install, treat it as a snapshot, not a recommendation.

### Per-tier fallback chains

Each tier has a ordered chain — **first available wins**:

| Tier | Chain (first available wins) |
|------|------------------------------|
| `frontier` | `{{MODEL_FRONTIER}}` → same-family previous version → strongest standard model → (omit pin — harness default) |
| `light` | `{{MODEL_LIGHT}}` → alternate light model → (omit pin — harness default) |

Additional rules from the map:

- Max **3** fallback attempts, then omit the model pin and take the harness default.
- Fallbacks are silent to the user but **logged in the orchestration log**.
- Apply at most **one** complexity adjustment per spawn — no cascading bumps.
- **Prompts are executable — narrowly**: only tasks that edit `templates/agents/*` or
  `templates/skills/*-criteria/*` use the frontier tier; skills, emitters, drivers, docs,
  and tests stay on the light tier.
- **Every spawn names its model.** The orchestrator passes the tier's resolved ID
  explicitly on every spawn and records requested vs self-reported in the orchestration log;
  `inherit` is legitimate only for a tier the install deliberately left unpinned.

The autonomous loop has its own light-tier chain resolving `{{LOOP_MODEL_CHAIN}}` when the loop is installed — same omit-the-pin rule at the end.

### Never fall back UP a tier

A **light** role must never silently land on a **frontier** model. A **frontier** role never degrades below the standard rung of its chain. This is the **never fall back UP** rule — it prevents cost surprises (light work on frontier models) and quality surprises (frontier verification on downgraded models).

### Fix-cycle rotation

After evaluator rejections, rotate the implementer's model — a model blind to its own class of mistake rarely fixes it on retry:

| Fix cycle | Implementer model |
|-----------|-------------------|
| 1 | `{{MODEL_LIGHT}}` (normal) |
| 2 | `{{MODEL_ALT_FAMILY}}` — a different model **family** at comparable tier (analytical diversity) |
| 3 | `{{MODEL_FRONTIER}}` |

The workflow context for when fix cycles fire is in [feature-workflow.md](feature-workflow.md).

### After cycle 3 — continuation ladder pins (as of v0.20.0)

When fix cycles 1–3 exhaust, the continuation ladder applies these pins:

| Ladder step | Model pin |
|-------------|-----------|
| Diagnosis-driven implementation attempt (rung 4) | `{{MODEL_FRONTIER}}` |
| Evaluator arbitration mode (rung 5) | `{{MODEL_FRONTIER_ALT_FAMILY}}` — a different model **family** from the primary evaluator at frontier tier |

`{{MODEL_ALT_FAMILY}}` (light tier) is never reused for arbitration.

### Cost-ceiling policy

Three outcomes when a model choice conflicts with a plan or admin ceiling:

1. **Explicit human choice above ceiling** → warn loudly and honor it.
2. **Implicit (auto-selected) choice above ceiling** → downgrade to the ceiling.
3. **No compliant model at all** → fail loud — never silently substitute.

## Harness caveats

These caveats shape tiering and emitter behavior. They are drawn from [`models.map.md`](../../skills/setup/templates/models.map.md) and [`harness-matrix.md`](../../skills/setup/reference/harness-matrix.md) only.

### Copilot cost ceiling

A Copilot subagent **cannot run a stronger model than the session**. The main session must run the `frontier` tier; workers pin **down**. Evaluators cannot pin up — the ceiling is "cannot exceed the parent tier," not "must equal the parent tier." Cheaper-than-parent pins are valid. Frontier = session tier, so the diagnostician and rung-5 arbiter pins respect the cost ceiling; Copilot has no reasoning-effort key (the effort pin is dropped there).

Practical implication: on Copilot, your orchestrating session is the frontier anchor. Light-tier worker pins must stay at or below that session's tier.

### Cursor silent fallback

Under team-admin or plan restrictions, or when a resolved model ID is unknown or stale (rotated-out or misspelled name), Cursor **substitutes a compatible model without erroring**. A typo'd or stale ID in the map fails quietly downstream instead of at resolution time.

Evaluators should state their expected model in the prompt and report **which model actually produced the verdict** so silent substitution is visible in the audit trail.

### Cursor live model list (emit-time check)

Before emitting Cursor agent files, **confirm every resolved model ID against the harness's live model list**. Unknown or invalid IDs are substituted silently — there is no error at resolution time. The model map's bootstrap comment and the harness matrix both require re-checking the live model list and current model-ID format before emission.

This obligation applies at `/setup` emit time; it is not tied to a specific kit version in the canonical sources cited here.

### Other harness notes (brief)

- **Claude Code:** `CLAUDE_CODE_SUBAGENT_MODEL` and `CLAUDE_CODE_EFFORT_LEVEL` env vars override frontmatter; org `availableModels` allowlists can cause pins to be ignored.
- **Codex:** Model pins are committable in `.codex/config.toml`, but `model_provider` / `model_providers` / `profile(s)` are ignored at project level.

For the full capability comparison, see [`harness-matrix.md`](../../skills/setup/reference/harness-matrix.md).

## Where agents appear in workflows

Each subagent is spawned at specific moments in the orchestration lifecycle:

- **Goal and task evaluation** — `evaluator` after goal creation, after each task, and at final audit; `evaluator` in **arbitration mode** at continuation-ladder rung 5 on unanimous same-item failure across fix cycles 1–3. Criteria and verdict mechanics: [evaluation-system.md](evaluation-system.md).
- **Post-exhaustion diagnosis** — `diagnostician` at continuation-ladder rung 4 after Phase 4 fix cycles exhaust.
- **Implementation and fixes** — `implementer` for each task and fix cycle (model rotates per the fix-cycle table above).
- **Dedicated test tasks** — `test-writer` when a goal includes a test-only task.
- **Noisy commands** — `terminal` for rung-3 full suites at cycle end, and whenever a worker or orchestrator needs command output without flooding context.
- **User-facing QA** — `qa-evaluator` after implementation and code evaluation, with captured behavioral evidence.

Phase-by-phase spawn timing, contracts, and escalation: [feature-workflow.md](feature-workflow.md).

## Maintaining model configuration

1. Edit [`skills/setup/templates/models.map.md`](../../skills/setup/templates/models.map.md) (contributors) or the emitted copy in your install.
2. Verify IDs against each harness's **live model list** — especially Cursor.
3. Re-run `/setup` to re-emit agents, skills, and loop drivers with updated pins.

Never copy model IDs from kit documentation without checking — IDs rotate frequently. Placeholder tokens (`{{MODEL_FRONTIER}}`, `{{MODEL_FRONTIER_ALT_FAMILY}}`, `{{MODEL_LIGHT}}`, `{{MODEL_ALT_FAMILY}}`, per-harness variants) describe the map's structure; concrete IDs are install-specific configuration.

## Sources

- [`skills/setup/templates/agents/evaluator.md`](../../skills/setup/templates/agents/evaluator.md) — evaluator role, stance, prohibitions
- [`skills/setup/templates/agents/qa-evaluator.md`](../../skills/setup/templates/agents/qa-evaluator.md) — QA evaluator role, evidence rules, prohibitions
- [`skills/setup/templates/agents/implementer.md`](../../skills/setup/templates/agents/implementer.md) — implementer rules, write fence, test ladder, terminal spawn
- [`skills/setup/templates/agents/test-writer.md`](../../skills/setup/templates/agents/test-writer.md) — test writer coverage rules, mocking, write fence
- [`skills/setup/templates/agents/terminal.md`](../../skills/setup/templates/agents/terminal.md) — terminal command runner, output isolation
- [`skills/setup/templates/agents/diagnostician.md`](../../skills/setup/templates/agents/diagnostician.md) — diagnostician role, report format, routing
- [`skills/setup/templates/models.map.md`](../../skills/setup/templates/models.map.md) — tier assignments, resolved models table, fallback chains, never-fall-up, fix-cycle rotation, cost ceiling, harness caveats
- [`skills/setup/reference/harness-matrix.md`](../../skills/setup/reference/harness-matrix.md) — per-harness capabilities, Copilot ceiling, Cursor silent fallback, live model list
- [`README.md`](../../README.md) — Model tiers section (frontier/light split, map as single source, re-run `/setup` on rotation)
