# {{PROJECT_NAME}} Orchestration Architecture

<!-- BOOTSTRAP: This is a template. Every `{{TOKEN}}` must be replaced and every
     `BOOTSTRAP:` comment resolved (fill the section, then delete the comment)
     when this file is instantiated into a project. See the setup
     skill for the placeholder reference. -->

A guide to how the feature and research orchestration system works for **{{PROJECT_NAME}}**,
including subagent delegation, evaluation cycles, and retry mechanisms.

> **Stack note:** {{STACK_SUMMARY}}
> <!-- BOOTSTRAP: 2–5 sentences — language/runtime, package manager, major code lanes
>      (backend/frontend/CLI/etc.), and where the canonical domain reference lives
>      (domain skill and/or docs file). -->

<!-- BOOTSTRAP: GREENFIELD ONLY — resolve from this install's in-session greenfield
     decision, i.e. the Step 2a accept-and-confirm path. That decision is persisted as
     the manifest's `options.greenfield`, but this resolution step (Step 4) runs
     *before* Step 6 writes the manifest, so key off the decision recorded in this
     session and never off a not-yet-written or stale manifest file. When that
     decision is true, add an **Engineering practices** subsection here, at a heading
     level that fits this top-matter site: 4–8 sentences, stack-agnostic, stating that
     new behavior is developed test-first — a failing test is written before the
     production code that satisfies it — and that
     modules follow SOLID: one reason to change per unit, dependencies declared
     against ports/abstractions rather than concretions, and no god-files that
     accumulate unrelated responsibilities. Name no language, runtime, or package
     manager; the stack note above already carries that. These are authoring
     conventions for a fresh codebase, not evaluator auto-fail triggers — do not add them
     to the auto-fail table or to any evaluator criteria. When `options.greenfield` is
     false or absent — an existing-project install, a declined scaffold, or a Step 2a
     that was skipped as not sparse — delete this comment and add no subsection. -->

---

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Component Overview](#component-overview)
3. [Feature Flow](#feature-flow)
4. [Research Flow](#research-flow)
5. [QA Evaluation (Optional Behavioral Gate)](#qa-evaluation-optional-behavioral-gate)
6. [Subagent Communication Protocol](#subagent-communication-protocol)
7. [Evaluation & Retry Mechanisms](#evaluation--retry-mechanisms)
8. [Autonomous Loop (Optional)](#autonomous-loop-optional)
9. [Quick Reference](#quick-reference)

---

## Core Concepts

### Why This Architecture?

Traditional single-agent execution suffers from:

| Problem | Cause | Impact |
|---------|-------|--------|
| **Context Fatigue** | Long conversations exhaust attention | Late tasks get less quality |
| **Sunk Cost Bias** | Agent invested in previous work | Reluctant to reject own output |
| **Optimism Creep** | Desire to "finish" | Cuts corners, skips edge cases |
| **Self-Review Blindness** | Reviewing own work | Misses obvious issues |

### The Solution: Separation of Concerns

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   ORCHESTRATOR                    WORKERS                   EVALUATORS      │
│   (Coordinates)                   (Execute)                 (Verify)        │
│                                                                             │
│   ┌───────────┐                  ┌───────────┐            ┌───────────┐    │
│   │           │    context       │           │   output   │           │    │
│   │  feature- │ ───────────────► │  impl-    │ ─────────► │           │    │
│   │  orchest- │                  │  executor │            │ evaluator │    │
│   │  rator    │ ◄─────────────── │           │ ◄───────── │           │    │
│   │           │    verdict       │           │   verdict  │           │    │
│   └───────────┘                  └───────────┘            └───────────┘    │
│                                                                             │
│   • Never executes               • Fresh context          • No stake in    │
│   • Prepares context             • Focused task             outcome        │
│   • Makes decisions              • Reports status         • Defaults to    │
│   • Handles retries              • Checklists               pessimism      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Principle: Fresh Context Per Task

Each subagent invocation:
- Starts with **zero conversation history**
- Receives **only what's in the prompt**
- Returns **one response** to the orchestrator
- Has **no knowledge** of previous attempts or other tasks

This eliminates fatigue and bias completely.

### Subagent Invocation: Retry on Transient Failures

Subagent invocations can fail due to transient issues (network timeouts, rate limits, temporary service unavailability). When this happens:

```
ON subagent invocation failure:
  DO NOT assume "subagent must not exist" or fall back to general agent

  INSTEAD:
  1. Retry the same subagent_type with the same prompt (up to 3 attempts)
  2. Wait briefly between retries (exponential backoff: 2s, 4s, 8s)
  3. Only after 3 failed attempts: escalate to user

  NEVER substitute a different subagent type due to transient errors
```

---

## Component Overview

### Orchestrator & Reference Skills (`{{IDE_DIR}}/skills/`)

| Skill | Type | Purpose |
|-------|------|---------|
| `feature` | Coordinator | Plans and executes feature implementation across {{PROJECT_NAME}} layers |
| `research` | Coordinator | Research → Plan workflow for domain topics |
| `goal-criteria` | Reference | Criteria for goal evaluation |
| `task-criteria` | Reference | Criteria for task evaluation |
| `qa-criteria` | Reference | Criteria for user-facing QA evaluation |
| `test-ladder` | Supporting | New tests → impacted tests mid-cycle; full suites (rung 3) only at cycle end |
| `align-docs` | Coordinator | Phase 6: evaluator-gated sync of all docs to shipped code (docs-only) |
| `ship-pr` | Delivery | Phase 7: draft + create the PR/MR on the project's forge, or hand over (approval-gated) |
<!-- BOOTSTRAP: append one row per project domain skill (the canonical knowledge base
     for the problem domain) and per supporting skill (TDD workflow, test ladder,
     smoke testing, frontend rules, visual QA, ...). Only list skills that exist. -->

> `goal-criteria`, `task-criteria`, `qa-criteria`, `test-ladder`, `align-docs`,
> `ship-pr`, and `auto-loop` set `disable-model-invocation: true` — they load via
> `/name` or a cited path, not session-start auto-discovery. `feature` and
> `research` remain auto-invocable.

> Domain skills are the project's knowledge base — the orchestration skills above
> reference them but do not replace them. Supporting skills are routed into subagent
> context packages by `feature` (see its "Supporting skills" section)
> based on which layer a task touches.

### Subagents (`{{IDE_DIR}}/agents/`)

| Subagent | Behavioral Style | Use Case | Model Tier |
|----------|------------------|----------|------------|
| `evaluator` | Skeptical, problem-finding | Goal / task / code verification | frontier, effort high |
| `qa-evaluator` | Skeptical, user-perspective | Behavioral QA of user-facing surfaces | frontier, effort high |
| `implementer` | Focused, checklist-driven | Implementation + fixes | light, effort medium |
| `test-writer` | Coverage-obsessed | Test creation, all external services mocked | light, effort medium |
| `terminal` | Compact command runner | Any Bash or PowerShell command — returns only the result the caller asked for | light, effort medium |
| `diagnostician` | Analytical, diagnosis-only | Root-cause analysis after fix-cycle exhaustion — no code writes | frontier |

The roster is six subagents — `evaluator`, `qa-evaluator`, `implementer`, `test-writer`,
`terminal`, and `diagnostician` — each with a dedicated agent file under `{{IDE_DIR}}/agents/`.

The orchestrator (and any worker that can spawn) sends `terminal` an exact Bash or
PowerShell command plus the result shape it needs; `terminal` executes it and returns
only that result, so the raw stream never lands in the caller. Rung 3 is always a
`terminal` spawn.

**Model tiers:** The orchestrator (main session) and both evaluators run the **frontier**
tier — delegation and evaluating have a capability floor. The light-tier agents — the
two workers **plus** `terminal` — run the **light** tier — checklist-driven execution
and compact command running keep quality when the plan and verification are strong, at
a fraction of the output-token cost. Model IDs are configuration, not constants: the
resolved per-harness model ID for each tier lives in exactly one place, the model map,
and is pinned into each agent's config from there — on harnesses with a skills tree
(Claude Code, Cursor) the map is also copied to `{{IDE_DIR}}/skills/setup-models.map.md`
for reference, while the Copilot and Codex emitters place no reference copy of the map,
so their pins live only in the harness's own config/frontmatter (Copilot `.agent.md`
frontmatter, Codex `.codex/agents/<role>.toml`), resolved from the map at setup time;
update the map (and re-pin) when providers rotate names. Harness caveats: on
Copilot a subagent cannot run a stronger model than the session (so the session itself
must run the frontier tier); Cursor silently falls back to a compatible model under
admin/plan restrictions, and does the same — without erroring — when the resolved ID is
unknown or stale (evaluators should report which model produced the verdict).
<!-- BOOTSTRAP: if the project does not pin models, delete the Model Tier column
     and this paragraph. -->

---

## Feature Flow

### Complete Lifecycle

```
PHASE 1: ALIGNMENT (Structured Discovery)
══════════════════════════════════════════

    User Request ──► Stay in Agent Mode ──► Structured questions (5-20 MCQs)
                                                  │
                                    ┌─────────────┘
                                    │
                     (Follow-up rounds if needed)
                                    │
                                    ▼
    Summarize "My Understanding" ──► User Confirms ──► Phase 2

    IMPORTANT: No files created during this phase.
    Covers: problem, affected layer/lane, external surfaces touched, auth/permissions,
    behavior/error handling, interface shape, existing patterns to follow, priority.


PHASE 2: GOAL CREATION (With Decision Gates)
════════════════════════════════════════════

    Create _goals/[name]/ ──► Write goal.md
           │
           ▼
    FOR EACH TASK:
    ┌─────────────────────────────────────────────┐
    │ Multiple approaches? ──YES──► Present to   │
    │         │                      user, WAIT  │
    │         NO                          │      │
    │         │◄──────────────────────────┘      │
    │         ▼                                  │
    │   Create task.md                           │
    └─────────────────────────────────────────────┘


PHASE 3: GOAL EVALUATION (Mandatory Re-Evaluate Loop)
═════════════════════════════════════════════════════

    Orchestrator ──► Launch evaluator
                     (includes Phase 1 Q&A for Discovery Coverage check)
           │
           ▼
    Receive Evaluation
           │
    ┌──────┼──────┐
    │      │      │
  PASS  NEEDS   REJECT
    │    REV      │
    │      │      │
    ▼      ▼      ▼
 Phase4  Revise  User
         & re-evaluate
        (3 max)

    INVARIANT: The ONLY exit to Phase 4 is a PASS verdict
    from the evaluator subagent. Revisions MUST be re-evaluated.


PHASE 4: TASK EXECUTION (Mandatory Re-Evaluate After Every Fix)
═══════════════════════════════════════════════════════════════

    FOR EACH TASK (in dependency order):

    Contract gate (before Step 1): owner agent proposes the contract from the task
    file (or the orchestrator drafts it directly for trivial tasks) ──► evaluator
    reviews in contract mode, counter-signs or requests one revision (max 2 rounds,
    each a single stateless spawn) ──► both signoff.worker/evaluator agreed:true,
    logged to the orchestration log ──► Step 1. No implementation dispatch before
    both sign-offs land.

    Step 1: Launch implementer (or test-writer for the test task) — context
            package includes the signed contract
    Step 2: Receive completion report
    Step 3: Launch evaluator
    Step 4: Handle verdict
            │
    ┌───────┼───────┐
    │       │       │
  PASS   NEEDS    REJECT
    │    FIXES      │
    │       │       │
    ▼       ▼       ▼
  Next   Re-impl  Escalate
  Task   & re-evaluate to User
        (3 max)

    INVARIANT: A task is only marked complete after the evaluator
    returns PASS. There is no path where fixes are made and the
    orchestrator proceeds without re-verification. The contract gate is
    a separate invariant: implementation never begins until both
    signoff.worker.agreed and signoff.evaluator.agreed are true.


PHASE 5: FINAL AUDIT (Mandatory Re-Audit Loop)
══════════════════════════════════════════════

    All Tasks Complete
           │
           ▼
    Final evaluator audit
           │
    ┌──────┴──────┐
    │             │
    APPROVED     ISSUES
    │             │
    ▼             ▼
 Quality Checks  Fix & Re-audit
 (ladder rung 3) (ladder rungs 1–2,
                  then re-audit; 3 max)

    INVARIANT: The ONLY exit to Quality Checks is an
    APPROVED verdict from the audit subagent. Remediations
    MUST be re-audited.


PHASE 6: ALIGN DOCS (Evaluator-Gated Doc Sync)
══════════════════════════════════════════════

    Quality Checks green
           │
           ▼
    align-docs skill: discover shipped surface ──► per-doc edit plan
           │
           ▼
    evaluate the plan ──► implementer per doc ──► evaluate each doc ──► final doc audit
    (same re-evaluate invariants and 3-cycle limits as Phases 3–5)

    RULES: docs-only (never code), anti-invention (every claim traces
    to a read file), _research/ and _goals/ are READ-ONLY.


PHASE 7: PULL REQUEST (Approval-Gated)
══════════════════════════════════════

    Docs aligned
           │
           ▼
    ship-pr skill: analyze branch commits + diff
           │
           ▼
    Draft PR (exec summary + technical breakdown)
           │
           ▼
    Show draft ──► USER APPROVES ──► push (if needed) ──► create PR/MR or hand over ──► URL

    INVARIANT: The PR is never created before the user approves the draft.
```

### Forge adapter (Phase 7 delivery)

Phase 7 (`ship-pr`) classifies git remotes at invocation time and branches on the forge. **Phase 7 is never deleted from an install** — a repo with no detected forge takes the `none` branch (draft + human hand-over), not a removed phase.

**Taxonomy.** Four values; each names its create mechanism:

| Value | Create mechanism |
|-------|------------------|
| `github` | `gh pr create` |
| `azuredevops` | `az repos pr create` |
| `gitlab` | `glab mr create` |
| `none` | draft + hand-over; never creates |

**Detection.** Classify the chosen remote's URL by domain. Host patterns live only in this table:

| Host pattern | Forge |
|--------------|-------|
| `github.com` | `github` |
| `dev.azure.com`, `ssh.dev.azure.com`, `*.visualstudio.com`, `vs-ssh.visualstudio.com` | `azuredevops` |
| `gitlab.com` | `gitlab` |

The `_git` path segment is the strong signal on Azure DevOps URLs. Anything else classifies to `none` unless overridden. Self-hosted GitLab, GHE (GitHub Enterprise), and on-prem Azure DevOps Server are pattern-undetectable — override-only.

**Remote selection.** Choose the PR-target remote with this procedure:

1. Classify every remote's URL per the taxonomy.
2. A candidate is a remote that classifies to a known forge (`github`, `azuredevops`, `gitlab`). `none`-classified remotes (for example a deploy remote) are NOT candidates and can never trigger disagreement.
3. If candidates span two or more different forges, stop and ask the human — never pick silently.
4. Otherwise pick the PR-target remote by precedence `upstream` → a remote named for its forge (`github`, `azuredevops`/`azure`, `gitlab`) → `origin` → remaining candidates in `git remote` listed order.
5. Zero candidates → the `none` branch unless the manifest override names a forge.

**PR-target remote vs push remote.** Forge classification and base-branch resolution use the chosen PR-target remote. `git push` uses the branch's existing tracking remote if set, else `origin`. A GitHub fork setup (`origin` = fork, `upstream` = parent) keeps pushing to the fork while targeting the parent, exactly as `gh` behaves.

**Override.** In `orchestration-kit.manifest.json`, `options.forge` (one of the four taxonomy values) and optional `options.forgeHost` (self-hosted host mapping) beat detection. The adapter never writes `git config`.

**Base-branch resolution.** Resolve always against the chosen PR-target remote. Name that remote explicitly in every base-resolution command (`ls-remote`/`fetch`/`log`/`diff`) — never a bare hardcoded `origin` in those templates.
Primary resolver: `git ls-remote --symref <remote> HEAD`.
Offline fallback: the cached `refs/remotes/<remote>/HEAD` symref (repair with `git remote set-head <remote> -a`).
On the `github` branch, `gh repo view` remains an accepted resolver.

**Stop and ask** when:

- (a) the chosen remote's HEAD is unresolvable (cached symref unset AND `ls-remote` fails or is auth-blocked);
- (b) two candidate remotes resolve to different forges;
- (c) the resolved base differs from the branch the current commits diverged from.

The human-approval invariant (draft → user approves → create/hand over) holds in all four branches. On-prem Azure DevOps Server is routed to the `none` branch (Microsoft: `az repos` CLI is Services-only).

### Execution Order for {{PROJECT_NAME}}

```
SEQUENTIAL: {{EXECUTION_LAYERS}}
                │
                ▼ (implementation complete)
                │
            Tests (test-writer; ladder rungs 1–2 only)
                │
                ▼ (new + impacted tests pass)
                │
            Final Audit ──► Quality Checks (rung 3: full suites)
                │
                ▼
            Align Docs (Phase 6) ──► Pull Request (Phase 7)
```
<!-- BOOTSTRAP: {{EXECUTION_LAYERS}} is the project's dependency-ordered layer chain,
     e.g. "Shared Core (if new lane) → Capability Module → CLI → Packaging". -->

Per-task and TDD verification follows the `test-ladder` skill: rung 1 (new
tests) → rung 2 (impacted tests) mid-cycle; rung 3 (every stack's full suite) runs
at cycle end — in the orchestrator's Phase 5 Quality Checks after the audit is APPROVED,
and additionally in a goal's designated closer task when one exists (a Phase 4 worker
gate with a written mandate that never replaces Phase 5).

Use only the layers the feature actually touches — most features reuse shared
infrastructure and add one module plus its interface and tests.

### Evaluation intensity (`eval_depth`)

Every task file's ownership-contract block carries `eval_depth: full` (default) or
`light`. It is orchestrator-set at planning time only — a worker never sets it — and
`light` is never a skip: it shortens the evaluator's rubric to a requirements walk +
targeted tests + write-fence check, while still ending in a real PASS / NEEDS FIXES /
REJECT verdict. The orchestrator assigns `light` only by explicit decision, with a
stated reason recorded in the task file or the goal's Discovery Summary;
`goal-criteria` flags an unexplained `light` and fails a missing field closed to
`full`.

Maintainers periodically compare the verdicts recorded in each goal's
`orchestration-log.md` against what actually happened afterward, then tune the
**criteria skills** — never the evaluator's fixed stance — when its behavior drifts
(see `evaluator.md`'s tuning note). This log-driven ritual is how both `eval_depth`
routing and the evaluation criteria stay calibrated over time.

---

## Research Flow

For domain topics an external research agent must investigate without codebase access.

```
Phase 1: Generate Research Prompt → _research/prompts/[topic].md  (user copy-pastes out)
Phase 2: Ingest Research Report   → _research/[topic]/report.md
Phase 3: High-Level Plan          → Collaborative planning (Plan Mode)
Phase 4: Low-Level Tasks          → _goals/[goal-name]/ structure
```

**Research locations:**
- {{GROUND_TRUTH_DOC}} — committed ground-truth reference. Cite as ground truth.
- `_research/` — working/scratch area for new prompts and raw reports. Promote durable
  findings into {{GROUND_TRUTH_DOC}}.

The output of Phase 4 (`_goals/[goal-name]/`) enters the `feature` skill at Phase 3 (goal evaluation) — it must PASS the evaluator before Phase 4 execution begins.

---

## QA Evaluation (Optional Behavioral Gate)

User-facing QA is a lightweight, optional gate run with the `qa-evaluator` subagent after a feature
is implemented. It covers **all user-facing surfaces**:

<!-- BOOTSTRAP: list this project's user-facing surfaces and the evidence each produces,
     e.g. CLIs (invocation, stdout/stderr, exit codes), API endpoints (status codes per
     route via a smoke-testing skill), web UI (screenshots/console/network via a visual
     QA skill), library entry points. -->
- {{QA_SURFACES}}

```
Implementation complete (ladder rungs 1–2 green; rung 3 at cycle end)
        │
        ▼
Exercise the affected surface and capture evidence
(exact invocations, outputs, exit codes / status codes, screenshots, logs)
        │
        ▼
Launch qa-evaluator ──► Verdict
        │
  ┌─────┼─────┐
PASS  ISSUES  REJECT
  │     │       │
  ▼     ▼       ▼
Done  Create  Escalate
      fix tasks → implementer → evaluator → re-run QA
```

QA never fixes issues — it finds them. Fixes flow back through the standard
implementer + evaluator loop, then QA re-runs.

---

## Subagent Communication Protocol

### Context Package Structure

Every subagent invocation requires a complete context package:

```
┌─────────────────────────────────────────────────────────────────┐
│  SECTION 1: ROLE ASSIGNMENT                                      │
│  "You are the [subagent-name] subagent."                        │
│  "Read: {{IDE_DIR}}/agents/[subagent-name].md"                  │
├─────────────────────────────────────────────────────────────────┤
│  SECTION 2: TASK DEFINITION                                      │
│  "## Task"                                                       │
│  "[Clear description of what to accomplish]"                    │
├─────────────────────────────────────────────────────────────────┤
│  SECTION 3: INPUT DATA                                          │
│  "## Requirements" (exhaustive list)                            │
│  "## Files to Read" (explicit paths)                            │
│  "## Domain Reference" (domain skill + ground-truth excerpts)   │
├─────────────────────────────────────────────────────────────────┤
│  SECTION 4: CONSTRAINTS                                         │
│  "## Write fence" (the task's writes list)                      │
│  "## Rules" or "## Critical Requirements"                       │
│  - Must do X (e.g. reuse shared core modules)                   │
│  - Must NOT do Y (e.g. re-implement auth, hit live services)    │
├─────────────────────────────────────────────────────────────────┤
│  SECTION 5: OUTPUT FORMAT                                       │
│  "## Output"                                                    │
│  "[Exact structure expected in response]"                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Evaluation & Retry Mechanisms

### Continuation ladder (Phase 4 task execution)

When Task Execution (Phase 4) exhausts its 3 implement→evaluate fix cycles, the
orchestrator runs this ladder before terminal human escalation. Apply in this order:

1. **Bypass check (every verdict, every cycle).** A verdict tagged with a bypass failure
   class (`destructive`, `security`, `infra`) stops all retrying immediately — including
   cycles 1–3 — and escalates to the human. Requirement ambiguity routes through rung 5,
   not the bypass — it is not a bypass class.

2. **Rung 5 — arbitration (conditional, checked first on exhaustion).** If cycles 1–3 all
   failed on the *same* required-fix item (unanimous-failure heuristic), spawn the
   evaluator in **arbitration mode** on `{{MODEL_FRONTIER_ALT_FAMILY}}` before any
   further fixing. Outcomes: `criteria-defective` → escalate to the human carrying the
   specific defect; arbiter/primary **disagreement → escalate (never auto-resolve)**;
   `criteria-sound` → continue to rung 4.

3. **Rung 4 — diagnosis-first.** Spawn the `diagnostician` (frontier tier, no code writes)
   with the task file, signed contract, and all three fix-cycle histories. If its
   hypothesis matches a previously tried fix signature → skip to rung 6 if it recommended
   a split, else escalate. Otherwise run **ONE** diagnosis-driven implementation attempt
   (fresh implementer on `{{MODEL_FRONTIER}}`, using the diagnostician's rewritten
   required-fixes list) and re-evaluate.

4. **Rung 6 — decomposition + selective retry.** Only on a diagnostician split
   recommendation; the orchestrator derives subtasks with ownership contracts (write sets
   ⊆ the parent task's) from the **failing pieces only** — work earlier cycles
   implemented that the evaluator did not flag stays as-is, is not re-run, and gets no
   separate evaluation. The parent task is complete when every derived subtask has an evaluator PASS. Each subtask gets one implement→evaluate cycle; evaluator spawns never consume the attempt budget — only implementation attempts do.

5. **Terminal.** Human escalation with the full ladder history.

**Failure-class taxonomy (closed set):** `implementation` (default) · `criteria-defect`
· `destructive` · `security` · `infra`. Bypass subset — destructive, security, infra.

**Hard guards:**

- At most **3 additional implementation attempts** after cycle 3, summed across rungs 4
  and 6.
- A **repeated failure signature** stops the ladder immediately.
- Every rung transition is an orchestration-log entry recording agent, model, rung, and
  trigger.
- token/cost budgets are NOT a guard in this kit — no harness exposes token counts
  to markdown policy.

**Attempt accounting:** The diagnosis-driven implementation attempt costs 1 of the 3.
Each rung-6 subtask implement→evaluate cycle costs 1 of the 3. Before splitting, the
orchestrator compares the failing-subtask count against the remaining budget — if the
count exceeds the remaining budget, escalate instead of splitting. **Signature identity:**
the evaluator's required-fixes list as recorded in the orchestration log, identical to an
earlier cycle's list item-for-item after normalizing whitespace and list numbering.

**Deferred future rungs (out of scope):**

- **high-effort pin** — evidence-marginal for routine coding; no procedure defined here.
- **best-of-N** — conflicts with disjoint write-set admission; no procedure defined here.

The headless loop inherits this ladder because each iteration runs the phased flow; the
loop drivers' per-story attempt cap and circuit breakers stay the unchanged outer
backstop.

### Retry Limits by Phase

| Phase | Max Cycles | On Exhaust |
|-------|------------|------------|
| Goal Evaluation (Phase 3) | 3 revise→re-evaluate | Escalate to user |
| Contract Gate (Phase 4 pre-step) | 2 propose→review rounds (stateless spawns) | Orchestrator tiebreak or escalate to user |
| Task Execution (Phase 4) | 3 implement→evaluate per task | Continuation ladder (rungs 5→4→6), then escalate to user |
| Final Audit (Phase 5) | 3 fix→re-audit | Escalate to user |
| Align Docs (Phase 6) | 3 per doc + 3 for plan and final doc audit | Escalate to user |
| Pull Request (Phase 7) | n/a — gated on explicit user approval | User edits or declines the draft |
| QA Gate (optional) | bounded by runtime; fixes loop through impl+evaluate | Escalate if unresolved |

### Mandatory Re-Evaluate Invariants

- **Phase 3**: Goal evaluation loop ONLY exits to Phase 4 via a PASS verdict. Revisions without re-evaluate are forbidden.
- **Phase 4**: A task is ONLY marked complete after the evaluator returns PASS. Fixes without re-evaluate are forbidden.
  Fix cycles rotate models — cycle 2 uses a different model family, cycle 3 the frontier tier (see the model map) — and every spawn is recorded in the goal's append-only orchestration log.
  The contract gate is a separate invariant: implementation is ONLY dispatched once both `signoff.worker.agreed` and `signoff.evaluator.agreed` are `true`.
- **Phase 5**: Audit loop ONLY exits to Quality Checks via an APPROVED verdict. Remediations without re-audit are forbidden.
- **Phase 6**: A doc is ONLY complete after the evaluator returns PASS; the doc set ONLY ships after the final doc audit returns APPROVED. `_research/`, `_goals/`, and code are never touched.
- **Phase 7**: The PR/MR is ONLY created, or the hand-over printed, after the user approves the drafted title and body.

### Escalation Format

```markdown
## Escalation Required

**Phase**: [current phase]
**Issue**: [what went wrong]
**Attempts**: [what was tried]
**Ladder**: [rungs attempted and their outcomes]

**Options**:
1. [option with tradeoffs]
2. [option with tradeoffs]

**What I need from you**: [specific decision or input]
```

For `criteria-defective` escalations (from rung 5 arbitration), state the defective
criterion **verbatim** in the **Issue** line.

---

## Autonomous Loop (Optional)

<!-- BOOTSTRAP: include this section only if the project opted into the autonomous
     loop; otherwise delete it and the loop rows in File Locations. -->

The `auto-loop` skill runs the orchestration flow unattended, **one feature per
iteration**, pulling work from a backlog instead of Phase 1 user alignment. Each
iteration is a fresh context; all state lives in files and git.

**Dual-mode dispatch** (see `auto-loop` and the loop driver): in **driver-dispatched**
runs the driver picks the story, performs `writes:` write-set admission against
in-flight claims, increments `attempts` at claim time, and integrates via the
single-writer integrator; dispatched slots never re-select stories, never increment
`attempts`, and never print the completion sentinel — that sentinel belongs to
**manual** runs only. Concurrency: `LOOP_SLOTS` > 1 is honored iff `LOOP_WORKTREE=1`
(default 2, clamped [1,3]).

**Manual-mode view** (human-invoked or non-dispatched `auto-loop`):

```
_goals/backlog.md ──► pick highest-priority story with passes: false, attempts < 3
        │
        ▼
Run the feature flow (Phases 2–6; backlog acceptance criteria replace Phase 1,
align-docs runs per story so docs never drift)
        │
        ▼
Evaluator PASS + ladder rungs green? ──NO──► attempts += 1; if attempts == 3:
        │ YES                             mark blocked, log to ESCALATIONS.md,
        ▼                                 move to next story
Commit (one commit per story, docs included) ──► mark passes: true ──► append learnings
        │
        ▼
All stories passed or blocked? ──YES──► print <promise>COMPLETE</promise> and stop
        │ NO
        ▼
Next iteration (fresh context)
```

**Guards (non-negotiable):**

| Guard | Default |
|-------|---------|
| Max iterations per run | 10 (argument to the loop driver (`loop.sh`/`loop.ps1`)) |
| Per-story attempt cap | 3, then blocked + escalation entry |
| Circuit breaker | per slot: retire after 3 consecutive no-commit reaps or 5 identical failure signatures (run continues); every slot retired stops the run — exit 3 if any signature-retirement, else 2 |
| Model breaker | CLOSED/OPEN/HALF-OPEN on anchored rate-limit detection; 600s cooldown, 2 successes to close; falls down the loop model chain, omit-pin at chain end; OPEN sleeps instead of hammering; rate-limited passes CB1-exempt |
| Exit condition | driver-dispatched runs: the driver's own backlog re-scan, gated on zero quarantined branches (exit 0); manual runs: explicit `<promise>COMPLETE</promise>` sentinel — never inferred from prose |
| Merge gate | evaluator PASS + green ladder rungs 1–2 before any commit; rung 3 per story after that story's Phase 5 audit, before that story's commit |
| Docs | align-docs (Phase 6) runs per story — doc updates land in the story's commit |
| Protected paths | the loop may not modify `_loop/`, kit agents/skills, the manifest, or `.gitattributes` — the loop driver (`loop.sh`/`loop.ps1`) reverts the iteration and stops (exit 4) |
| Memory gates | `_goals/LEARNINGS.md` ≥ 15 KB → compact; `_goals/ESCALATIONS.md` ≥ 20 KB → archive resolved entries |
| Shipping | the loop never pushes; at run end, `ship-pr` (Phase 7) drafts and creates the PR/MR on the project's forge, or hand over, with the user approving the draft |
| Sandbox | run in a worktree/container with minimal credentials; never skip permission prompts outside a sandbox |

**Exit funnel** (driver-aggregated across slots; precedence **4>3>2>1>0** — exit 4 and
exit 5 short-circuit): **exit 1** = max-iterations reached with eligible stories
remaining, or drained backlog with quarantined branches retained; **exit 5** = setup or
integration failure (tracked-instance preflight, missing/unreadable backlog, PROMPT.md
substitution point, non-fast-forward integration). Quarantine markers
`.loop-worktrees/QUARANTINE-<branch>.md` (reasons: `mismatch|abnormal|subset|killed`)
block exit 0 until inspected.

Known failure mode: loops can burn large budgets without converging — prefer more,
smaller stories (each sized to one context window) and let the circuit breaker stop a
drifting run early. Headless entry point: `_loop/loop.sh [max-iterations]` (bash) or
`pwsh _loop/loop.ps1 [MaxIterations]` (PowerShell 7+).

---

## Quick Reference

### File Locations

```
{{IDE_DIR}}/
├── agents/
│   ├── evaluator.md     # Skeptical code/goal/task reviewer
│   ├── qa-evaluator.md              # Skeptical user-facing QA reviewer
│   ├── implementer.md  # Focused implementer
│   ├── test-writer.md           # Test creator (external services mocked)
│   ├── terminal.md              # Bash/PowerShell runner — returns only the asked-for result
│   └── diagnostician.md         # Diagnosis-only (post-cycle-3, no code writes)
│
├── skills/
│   ├── feature/       # Feature coordination
│   │   ├── SKILL.md
│   │   └── templates/{goal.md,task.md,contract.md}
│   │
│   ├── research/ # Research → Plan
│   │   ├── SKILL.md
│   │   └── templates/{research-prompt.md,research-report.md}
│   │
│   ├── goal-criteria/SKILL.md         # Goal evaluation criteria
│   ├── task-criteria/SKILL.md         # Task evaluation criteria
│   ├── qa-criteria/SKILL.md           # User-facing QA evaluation criteria
│   ├── test-ladder/SKILL.md    # Rungs 1–2 mid-cycle, rung 3 at cycle end
│   ├── align-docs/SKILL.md            # Phase 6: evaluator-gated doc sync
│   ├── ship-pr/SKILL.md       # Phase 7: approval-gated PR creation
│   └── auto-loop/SKILL.md             # One autonomous iteration (if loop enabled)
│
└── ORCHESTRATION.md   # This file

_goals/backlog.md               # Story backlog for the autonomous loop (if enabled)
_goals/<goal>/orchestration-log.md  # Append-only spawn ledger per goal
_goals/<goal>/contracts/NN-task-name.contract.md  # Per-task sign-off (Phase 4 contract gate)
_goals/breaker-state.json       # Model circuit breaker state (runtime, gitignored)
_loop/{loop.sh,loop.ps1,breaker.sh,breaker.ps1,PROMPT.md}  # Headless loop driver (if enabled)
```
<!-- BOOTSTRAP: add the project's domain and supporting skills to this tree. -->

### Critical Reference Files

| File | Purpose | When to Include |
|------|---------|-----------------|
<!-- BOOTSTRAP: one row per canonical reference the orchestrator must route into
     subagent context packages — domain skills, ground-truth docs, per-directory
     AGENTS.md/CLAUDE.md files, supporting skill SKILL.md files. -->

### Quality Checks

<!-- BOOTSTRAP: table of the project's cycle-end quality commands. Only list commands
     for tools that are actually configured. -->

| Step | Command |
|------|---------|
| Tests (rung 3 — full suites, cycle end only) | {{FULL_TEST_COMMAND}} |
| Lint | {{LINT_COMMAND}} |
| Type check | {{TYPECHECK_COMMAND}} |

Don't invent commands for tools that aren't configured. Tests must mock all external
service/network access. Do not run rung 3 during Phase 4 tasks or TDD loops — except
in a goal's designated closer task when its task file mandates the full-suite run as
the closing gate — the `test-ladder` skill governs which rung runs when. Rung 3 is executed by **spawning
`terminal`** with the command above, never by the orchestrator running it in this
session.

### Common Commands

**Setup:**
```bash
{{SETUP_COMMANDS}}
```

**Tests** (staged ladder — see `test-ladder`):
```bash
{{TARGETED_TEST_COMMAND}}     # rungs 1–2, during Phase 4 / TDD loops
{{FULL_TEST_COMMAND}}         # rung 3 — cycle end only
```

### Invoking Skills

```
/feature            - Start a new feature implementation (Phases 1–7)
/research           - Research → Plan workflow for a domain topic
/align-docs         - Phase 6 standalone: sync docs to shipped code
/ship-pr    - Phase 7 standalone: draft + create the PR/MR on the project's forge, or hand over
/test-ladder - Test-rung rules (also routed into every impl/test task)
```

The criteria skills (`goal-criteria`, `task-criteria`, `qa-criteria`) are reference checklists used by the
evaluator subagents — they are not invoked directly.

### Subagent Behaviors

| Subagent | Default Stance | Key Behavior | Auto-Fail Triggers |
|----------|----------------|--------------|-------------------|
| `evaluator` | Score starts at 2/5 | Actively looks for code problems | {{EVALUATOR_AUTO_FAIL_TRIGGERS}} |
| `qa-evaluator` | Score starts at 2/5 | User-perspective behavioral QA | {{QA_AUTO_FAIL_TRIGGERS}} |
| `implementer` | Must complete ALL | Checklist-driven execution | Skipping requirements |
| `test-writer` | 100% coverage required | Outcome-verifying tests | Functions without tests, live external-service calls |

<!-- BOOTSTRAP: auto-fail triggers should name project-specific sins, e.g.
     "re-implemented core auth/transport, swallowed 401/403, ignored pagination,
     secrets in code, weak tests" / "raw tracebacks, wrong exit code, malformed JSON,
     defined route 404/5xx, unauthenticated data access, success-without-effect". -->

### Workflow State Tracking

The orchestrator maintains this state throughout execution:

```markdown
## Orchestration Progress: [Goal Name]

### Phase 1: Alignment (structured discovery — no files created)
- [ ] Discovery questions asked
- [ ] Follow-up questions asked (if needed)
- [ ] Summary presented to user
- [ ] User confirmed understanding ("yes, proceed")

### Phase 2: Goal Creation
- [ ] Goal.md created
- [ ] Decision gates passed (or user decided)
- [ ] Task files created

### Phase 3: Goal Evaluation (must loop until PASS)
- [ ] Evaluator subagent invoked (attempt 1)
- [ ] Verdict: [PASS/NEEDS REVISION/REJECT]
- [ ] Final verdict that allowed progression: PASS

### Phase 4: Execution (each task must loop evaluator until PASS)
| Task | Cycle 1 | Cycle 2 | Cycle 3 | Final Verdict |
|------|---------|---------|---------|---------------|
| 01-... | ⬜ | - | - | ⬜ |
| 02-... | ⬜ | - | - | ⬜ |

### Phase 5: Final Audit (must loop until APPROVED)
- [ ] Audit subagent invoked (attempt 1)
- [ ] Verdict: [APPROVED/ISSUES FOUND]
- [ ] Final verdict that allowed progression: APPROVED
- [ ] Quality checks (ladder rung 3: full suites) passed

### Phase 6: Align Docs (must loop until doc audit APPROVED)
- [ ] Change surface + per-doc edit list built
- [ ] Edit plan evaluated PASS
- [ ] Each doc executed + evaluated PASS
- [ ] Final doc audit APPROVED (docs only; _research/ and _goals/ untouched)

### Phase 7: Pull Request (gated on user approval)
- [ ] PR title + body drafted from branch commits
- [ ] User approved the draft
- [ ] PR/MR created/updated on the project's forge, or hand-over printed — URL or artifact: [link]
See ### Forge adapter (Phase 7 delivery).
```

---

## Summary

1. **Orchestrators coordinate, never execute** - They prepare context and make decisions
2. **Subagents execute with fresh context** - No fatigue, no bias
3. **Evaluation is always separate** - Pessimistic evaluators review all work (code AND behavior)
4. **Re-evaluate is mandatory** - Fixes/revisions MUST be re-verified by an evaluator subagent
5. **Retries have limits (3 cycles)** - Phase 4 task execution continues through the continuation ladder (rungs 5→4→6) before escalation; other phases escalate after 3 cycles
6. **Escalation is explicit** - User gets clear options and required decisions
7. **The Iron Law is enforced** - Tests define behavior, implementation must conform
8. **Shared core is reused** - New modules build on shared infrastructure; never re-implement auth/transport/plumbing
9. **Tests never touch live services** - All external/network access is mocked
10. **Staged test ladder** - New tests, then impacted tests; full suites only after all cycle changes are applied
11. **Docs ship with the code** - Phase 6 aligns every doc to shipped behavior (docs-only, evaluator-gated) before the work is done
12. **Delivery is a PR/MR on the project's forge, or a hand-over, approved by a human** - Phase 7 drafts from the branch's commits; it is never created or handed over without user approval
