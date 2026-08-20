# {{PROJECT_NAME}} Orchestration Architecture

<!-- BOOTSTRAP: This is a template. Every `{{TOKEN}}` must be replaced and every
     `BOOTSTRAP:` comment resolved (fill the section, then delete the comment)
     when this file is instantiated into a project. See the setup
     skill for the placeholder reference. -->

A guide to how the feature and research orchestration system works for **{{PROJECT_NAME}}**,
including subagent delegation, judgment cycles, and retry mechanisms.

> **Stack note:** {{STACK_SUMMARY}}
> <!-- BOOTSTRAP: 2–5 sentences — language/runtime, package manager, major code lanes
>      (backend/frontend/CLI/etc.), and where the canonical domain reference lives
>      (domain skill and/or docs file). -->

---

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Component Overview](#component-overview)
3. [Feature Flow](#feature-flow)
4. [Research Flow](#research-flow)
5. [QA Judgment (Optional Behavioral Gate)](#qa-judgment-optional-behavioral-gate)
6. [Subagent Communication Protocol](#subagent-communication-protocol)
7. [Judgment & Retry Mechanisms](#judgment--retry-mechanisms)
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
│   ORCHESTRATOR                    WORKERS                   JUDGES          │
│   (Coordinates)                   (Execute)                 (Verify)        │
│                                                                             │
│   ┌───────────┐                  ┌───────────┐            ┌───────────┐    │
│   │           │    context       │           │   output   │           │    │
│   │  feature- │ ───────────────► │  impl-    │ ─────────► │ pessim-   │    │
│   │  orchest- │                  │  executor │            │ istic-    │    │
│   │  rator    │ ◄─────────────── │           │ ◄───────── │ judge     │    │
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
| `goal-criteria` | Reference | Criteria for goal judgment |
| `task-criteria` | Reference | Criteria for task judgment |
| `qa-criteria` | Reference | Criteria for user-facing QA judgment |
| `test-ladder` | Supporting | New tests → impacted tests mid-cycle; full suites (rung 3) only at cycle end |
| `align-docs` | Coordinator | Phase 6: judge-gated sync of all docs to shipped code (docs-only) |
| `ship-pr` | Delivery | Phase 7: draft + create the GitHub PR from branch commits (approval-gated) |
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
| `judge` | Skeptical, problem-finding | Goal / task / code verification | frontier — `{{MODEL_FRONTIER}}`, effort high |
| `qa-judge` | Skeptical, user-perspective | Behavioral QA of user-facing surfaces | frontier — `{{MODEL_FRONTIER}}`, effort high |
| `implementer` | Focused, checklist-driven | Implementation + fixes | light — `{{MODEL_LIGHT}}`, effort medium |
| `test-writer` | Coverage-obsessed | Test creation, all external services mocked | light — `{{MODEL_LIGHT}}`, effort medium |
| `terminal` | Compact command runner | Noisy test/build/git commands — runs the command, returns a summary | light — `{{MODEL_LIGHT}}`, effort medium |

The orchestrator spawns `terminal` for ladder rung 3 (full-suite runs) and for
read-only git log/status inspection, so that noisy command output stays out of the
frontier session instead of accumulating in this conversation.

**Model tiers:** The orchestrator (main session) and both judges run the **frontier**
tier (`{{MODEL_FRONTIER}}`) — delegation and judging have a capability floor. The
light-tier agents — the two workers **plus** `terminal` — run the **light** tier
(`{{MODEL_LIGHT}}`) — checklist-driven execution and compact command running keep
quality when the plan and verification are strong, at a fraction of the output-token
cost. Model IDs are configuration, not constants: they are defined once in the model
map and pinned in each agent's frontmatter; update them there when providers rotate
names. Harness caveats: on Copilot a subagent cannot run a stronger model than the
session (so the session itself must run the frontier tier); Cursor silently falls back
to a compatible model under admin/plan restrictions (judges should report which model
produced the verdict).
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


PHASE 3: GOAL JUDGMENT (Mandatory Re-Judge Loop)
════════════════════════════════════════════════

    Orchestrator ──► Launch judge
                     (includes Phase 1 Q&A for Discovery Coverage check)
           │
           ▼
    Receive Judgment
           │
    ┌──────┼──────┐
    │      │      │
  PASS  NEEDS   REJECT
    │    REV      │
    │      │      │
    ▼      ▼      ▼
 Phase4  Revise  User
         & re-judge
        (3 max)

    INVARIANT: The ONLY exit to Phase 4 is a PASS verdict
    from the judge subagent. Revisions MUST be re-judged.


PHASE 4: TASK EXECUTION (Mandatory Re-Judge After Every Fix)
════════════════════════════════════════════════════════════

    FOR EACH TASK (in dependency order):

    Step 1: Launch implementer (or test-writer for the test task)
    Step 2: Receive completion report
    Step 3: Launch judge
    Step 4: Handle verdict
            │
    ┌───────┼───────┐
    │       │       │
  PASS   NEEDS    REJECT
    │    FIXES      │
    │       │       │
    ▼       ▼       ▼
  Next   Re-impl  Escalate
  Task   & re-judge to User
        (3 max)

    INVARIANT: A task is only marked complete after the judge
    returns PASS. There is no path where fixes are made and the
    orchestrator proceeds without re-verification.


PHASE 5: FINAL AUDIT (Mandatory Re-Audit Loop)
══════════════════════════════════════════════

    All Tasks Complete
           │
           ▼
    Final judge audit
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


PHASE 6: ALIGN DOCS (Judge-Gated Doc Sync)
══════════════════════════════════════════

    Quality Checks green
           │
           ▼
    align-docs skill: discover shipped surface ──► per-doc edit plan
           │
           ▼
    judge the plan ──► implementer per doc ──► judge each doc ──► final doc audit
    (same re-judge invariants and 3-cycle limits as Phases 3–5)

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
    Show draft ──► USER APPROVES ──► push (if needed) ──► gh pr create ──► URL

    INVARIANT: The PR is never created before the user approves the draft.
```

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
**once**, after the audit is APPROVED.

Use only the layers the feature actually touches — most features reuse shared
infrastructure and add one module plus its interface and tests.

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

The output of Phase 4 (`_goals/[goal-name]/`) feeds directly into the `feature` skill's
Phase 4 execution.

---

## QA Judgment (Optional Behavioral Gate)

User-facing QA is a lightweight, optional gate run with the `qa-judge` subagent after a feature
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
Launch qa-judge ──► Verdict
        │
  ┌─────┼─────┐
PASS  ISSUES  REJECT
  │     │       │
  ▼     ▼       ▼
Done  Create  Escalate
      fix tasks → implementer → judge → re-run QA
```

QA never fixes issues — it finds them. Fixes flow back through the standard
implementer + judge loop, then QA re-runs.

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

## Judgment & Retry Mechanisms

### Retry Limits by Phase

| Phase | Max Cycles | On Exhaust |
|-------|------------|------------|
| Goal Judgment (Phase 3) | 3 revise→re-judge | Escalate to user |
| Task Execution (Phase 4) | 3 implement→judge per task | Escalate to user |
| Final Audit (Phase 5) | 3 fix→re-audit | Escalate to user |
| Align Docs (Phase 6) | 3 per doc + 3 for plan and final doc audit | Escalate to user |
| Pull Request (Phase 7) | n/a — gated on explicit user approval | User edits or declines the draft |
| QA Gate (optional) | bounded by runtime; fixes loop through impl+judge | Escalate if unresolved |

### Mandatory Re-Judge Invariants

- **Phase 3**: Goal judgment loop ONLY exits to Phase 4 via a PASS verdict. Revisions without re-judge are forbidden.
- **Phase 4**: A task is ONLY marked complete after the judge returns PASS. Fixes without re-judge are forbidden.
  Fix cycles rotate models — cycle 2 uses a different model family, cycle 3 the frontier tier (see the model map) — and every spawn is recorded in the goal's append-only orchestration log.
- **Phase 5**: Audit loop ONLY exits to Quality Checks via an APPROVED verdict. Remediations without re-audit are forbidden.
- **Phase 6**: A doc is ONLY complete after the judge returns PASS; the doc set ONLY ships after the final doc audit returns APPROVED. `_research/`, `_goals/`, and code are never touched.
- **Phase 7**: The PR is ONLY created after the user approves the drafted title and body.

### Escalation Format

```markdown
## Escalation Required

**Phase**: [current phase]
**Issue**: [what went wrong]
**Attempts**: [what was tried]

**Options**:
1. [option with tradeoffs]
2. [option with tradeoffs]

**What I need from you**: [specific decision or input]
```

---

## Autonomous Loop (Optional)

<!-- BOOTSTRAP: include this section only if the project opted into the autonomous
     loop; otherwise delete it and the loop rows in File Locations. -->

The `auto-loop` skill runs the orchestration flow unattended, **one feature per
iteration**, pulling work from a backlog instead of Phase 1 user alignment. Each
iteration is a fresh context; all state lives in files and git.

```
_goals/backlog.md ──► pick highest-priority story with passes: false, attempts < 3
        │
        ▼
Run the feature flow (Phases 2–6; backlog acceptance criteria replace Phase 1,
align-docs runs per story so docs never drift)
        │
        ▼
Judge PASS + ladder rungs green? ──NO──► attempts += 1; if attempts == 3:
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
| Merge gate | judge PASS + green ladder rungs 1–2 before any commit; rung 3 at run end |
| Docs | align-docs (Phase 6) runs per story — doc updates land in the story's commit |
| Protected paths | the loop may not modify `_loop/`, kit agents/skills, the manifest, or `.gitattributes` — the loop driver (`loop.sh`/`loop.ps1`) reverts the iteration and stops (exit 4) |
| Memory gates | `_goals/LEARNINGS.md` ≥ 15 KB → compact; `_goals/ESCALATIONS.md` ≥ 20 KB → archive resolved entries |
| Shipping | the loop never pushes; at run end, `ship-pr` (Phase 7) ships the branch as ONE PR, with the user approving the draft |
| Sandbox | run in a worktree/container with minimal credentials; never skip permission prompts outside a sandbox |

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
│   ├── judge.md        # Skeptical code/goal/task reviewer
│   ├── qa-judge.md                 # Skeptical user-facing QA reviewer
│   ├── implementer.md  # Focused implementer
│   ├── test-writer.md           # Test creator (external services mocked)
│   └── terminal.md              # Compact command runner (rung 3, noisy read-only)
│
├── skills/
│   ├── feature/       # Feature coordination
│   │   ├── SKILL.md
│   │   └── templates/{goal.md,task.md}
│   │
│   ├── research/ # Research → Plan
│   │   ├── SKILL.md
│   │   └── templates/{research-prompt.md,research-report.md}
│   │
│   ├── goal-criteria/SKILL.md         # Goal judgment criteria
│   ├── task-criteria/SKILL.md         # Task judgment criteria
│   ├── qa-criteria/SKILL.md           # User-facing QA judgment criteria
│   ├── test-ladder/SKILL.md    # Rungs 1–2 mid-cycle, rung 3 at cycle end
│   ├── align-docs/SKILL.md            # Phase 6: judge-gated doc sync
│   ├── ship-pr/SKILL.md       # Phase 7: approval-gated PR creation
│   └── auto-loop/SKILL.md             # One autonomous iteration (if loop enabled)
│
└── ORCHESTRATION.md   # This file

_goals/backlog.md               # Story backlog for the autonomous loop (if enabled)
_goals/<goal>/orchestration-log.md  # Append-only spawn ledger per goal
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
service/network access. Do not run rung 3 during Phase 4 tasks or TDD loops — the
`test-ladder` skill governs which rung runs when. Rung 3 is executed by **spawning
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
/ship-pr    - Phase 7 standalone: draft + create the PR
/test-ladder - Test-rung rules (also routed into every impl/test task)
```

The criteria skills (`goal-criteria`, `task-criteria`, `qa-criteria`) are reference checklists used by the
judge subagents — they are not invoked directly.

### Subagent Behaviors

| Subagent | Default Stance | Key Behavior | Auto-Fail Triggers |
|----------|----------------|--------------|-------------------|
| `judge` | Score starts at 2/5 | Actively looks for code problems | {{JUDGE_AUTO_FAIL_TRIGGERS}} |
| `qa-judge` | Score starts at 2/5 | User-perspective behavioral QA | {{QA_AUTO_FAIL_TRIGGERS}} |
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

### Phase 3: Goal Judgment (must loop until PASS)
- [ ] Judge subagent invoked (attempt 1)
- [ ] Verdict: [PASS/NEEDS REVISION/REJECT]
- [ ] Final verdict that allowed progression: PASS

### Phase 4: Execution (each task must loop judge until PASS)
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
- [ ] Edit plan judged PASS
- [ ] Each doc executed + judged PASS
- [ ] Final doc audit APPROVED (docs only; _research/ and _goals/ untouched)

### Phase 7: Pull Request (gated on user approval)
- [ ] PR title + body drafted from branch commits
- [ ] User approved the draft
- [ ] PR created/updated — URL: [link]
```

---

## Summary

1. **Orchestrators coordinate, never execute** - They prepare context and make decisions
2. **Subagents execute with fresh context** - No fatigue, no bias
3. **Judgment is always separate** - Pessimistic judges review all work (code AND behavior)
4. **Re-judge is mandatory** - Fixes/revisions MUST be re-verified by a judge subagent
5. **Retries have limits (3 cycles)** - Prevents infinite loops, forces escalation
6. **Escalation is explicit** - User gets clear options and required decisions
7. **The Iron Law is enforced** - Tests define behavior, implementation must conform
8. **Shared core is reused** - New modules build on shared infrastructure; never re-implement auth/transport/plumbing
9. **Tests never touch live services** - All external/network access is mocked
10. **Staged test ladder** - New tests, then impacted tests; full suites only after all cycle changes are applied
11. **Docs ship with the code** - Phase 6 aligns every doc to shipped behavior (docs-only, judge-gated) before the work is done
12. **Delivery is a PR, approved by a human** - Phase 7 drafts the PR from the branch's commits; it is never created without user approval
