**Who this is for / What you'll learn:** Kit **users** and **contributors** who need to understand how the kit verifies work before it advances — not just *that* evaluators gate progression, but *how* they score, what each verdict means, and what evidence they require. You will learn the per-gate verdict vocabulary, the failure-class taxonomy, arbitration mode (rung 5), the confidence ladder and anti-fabrication rules, devil's advocate, acceptance criteria validated at Phase 3, `eval_depth` routing, the staged test ladder, and the orchestration log as an append-only audit trail. For where these gates sit in the seven phases, see [feature-workflow.md](feature-workflow.md); for who runs evaluation and model tiers, see [agents-and-models.md](agents-and-models.md).

# Evaluation system

The kit separates execution from verification: workers produce artifacts; evaluators read, verify, and return verdicts. This document **explains** the criteria skills and evaluator agent files — it is not a normative fork. When anything here disagrees with a canonical source, the source wins. Each section below points at its binding file under [`skills/agent-kit/templates/`](../../../skills/agent-kit/templates/).

Phase-by-phase orchestration narrative (alignment through pull request) belongs in [feature-workflow.md](feature-workflow.md). Here we stay inside the index scope row: verdict machinery, acceptance criteria, test ladder, and audit trail.

**Canonical vs instance:** Behavior described here is what [`skills/agent-kit/templates/`](../../../skills/agent-kit/templates/) emits via `/agent-kit`. Your harness writes an **instance** tree (agents, skills, `ORCHESTRATION.md`) into the target project — in this repo that instance is gitignored (e.g. `.claude/`) and is not source of truth. Paths below use the canonical template location unless labeled as instance-specific.

## Per-gate verdict vocabulary

Every gate has its **own** verdict set. Never collapse them into one triple.

| Gate | Phase / context | Verdicts | Binding source |
|------|-----------------|----------|----------------|
| **Goal evaluation** | Phase 3 — goal + task files | **PASS**, **NEEDS REVISION**, **REJECT** | [`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) |
| **Task evaluation** | Phase 4 — completed task work | **PASS**, **PASS (with notes)**, **NEEDS FIXES**, **REJECT** | [`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md) |
| **Final audit** | Phase 5 — whole goal | **APPROVED**, **ISSUES** | [`feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md) (Phase 5); lifecycle in [`ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) |
| **Align-docs plan evaluation** | Phase 6.3 — doc edit plan | **PASS**, **NEEDS REVISION**, **REJECT** | [`align-docs/SKILL.template.md`](../../../skills/agent-kit/templates/skills/align-docs/SKILL.template.md) |
| **Doc audit** | Phase 6.5 — whole doc change set | **APPROVED**, **ISSUES** | [`align-docs/SKILL.template.md`](../../../skills/agent-kit/templates/skills/align-docs/SKILL.template.md) |
| **QA gate** (optional behavioral) | When `qa: run` in `goal.md` (default `skip`); after Phase 5 **APPROVED** and Quality Checks — `evidence-collector` then `qa-evaluator` on user-facing surfaces | **PASS**, **ISSUES FOUND**, **REJECT** | [`qa-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/qa-criteria/SKILL.template.md); flow in [`feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md) Phase 5 |
| **Arbitration (rung 5)** | Phase 4 continuation ladder — orchestrator-invoked on unanimous same-item failure across fix cycles 1–3, or early at detection when `failure_class: criteria-defect` stops fix cycles on any cycle (run now with `ladder: auto`; offered as option 1 with `ladder: escalate`) | **criteria-sound**, **criteria-defective** (never PASS/NEEDS FIXES/REJECT) | [`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md) § Arbitration mode |

### Source precedence: `ISSUES` vs `ISSUES FOUND`

The Phase 5 final audit unhappy path is **ISSUES** — not `ISSUES FOUND`. **`ISSUES FOUND`** belongs to the QA gate only ([`qa-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/qa-criteria/SKILL.template.md)).

The canonical [`ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) progress-checklist placeholder `[APPROVED/ISSUES FOUND]` (workflow state tracking) is **not** final-audit vocabulary. The lifecycle diagram in that file correctly shows **APPROVED** / **ISSUES** for Phase 5. On apparent conflict, the feature skill and criteria skills win.

## Failure-class taxonomy

Every non-PASS task verdict carries `failure_class:` from this closed set ([`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md) § Failure-class taxonomy, [`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md) § Verdict format): `implementation` (default) · `criteria-defect` · `destructive` · `security` · `infra`.

- **`implementation`** — default when the work is wrong or incomplete but the criteria themselves are sound; fix and retry.
- **`criteria-defect`** — a criterion is defective (vacuous, blind, or mutually unsatisfiable with another criterion in the same task); stops fix cycles at detection on any cycle — with `ladder: auto` run rung 5 arbitration now; with `ladder: escalate` escalate with arbitration offered as option 1; not blind retry.
- **`destructive`** — would corrupt data, delete irrecoverable state, or cause irreversible harm.
- **`security`** — credential exposure, auth bypass, injection, or other security violation.
- **`infra`** — environment, tooling, or external dependency failure outside the implementer's control.

**Bypass consequence:** tagging `destructive`, `security`, or `infra` stops **all** retrying immediately — any cycle, not only after fix-cycle exhaustion — and escalates to the human. The evaluator tags at detection; it does not wait for the ladder to run out of attempts.

Non-**PASS** task verdicts route by `failure_class` as follows.

```mermaid
flowchart TD
    Verdict["Task verdict not PASS"]
    Class{"failure_class"}
    Impl["implementation\nfix cycle + re-evaluate"]
    Crit["criteria-defect\nroutes at detection\nrung 5 or human escalation"]
    Dest["destructive\nimmediate human escalation"]
    Sec["security\nimmediate human escalation"]
    Infra["infra\nimmediate human escalation"]
    Reject["REJECT\nimmediate human escalation"]

    Verdict --> Class
    Class -->|"implementation (default)"| Impl
    Class -->|"criteria-defect"| Crit
    Class -->|"destructive"| Dest
    Class -->|"security"| Sec
    Class -->|"infra"| Infra
    Verdict --> Reject
```

## Arbitration mode (rung 5)

Orchestrator-invoked only — the evaluator does not self-trigger this mode ([`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md) § Arbitration mode).

**Trigger** — Ladder rung 5: unanimous same-item failure across fix cycles 1–3 (every evaluator flagged the same required-fix item and it still fails after three implement→evaluate cycles), or early arbitration when `criteria-defect` stops fix cycles at detection on any cycle: with `ladder: auto` run rung 5 arbitration now; with `ladder: escalate` escalate with arbitration offered as option 1.

**Model** — `{{MODEL_FRONTIER_ALT_FAMILY}}` (frontier tier, different family from the primary evaluator when reachable). When no different-family frontier model is reachable on the harness, setup may pin the same family with `arbiter_same_family: true` in the answers file (emit otherwise warns); the model map then labels the rung-5 row [`same-family arbiter (reduced independence)`](../../../skills/agent-kit/templates/models.map.md) and the arbiter's verdict header states `same-family arbiter`. Per the kit's Cursor silent-fallback caveat, the arbiter states in its verdict which model actually produced it ([`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md) § Arbitration mode).

**Scope** — evaluates the **criteria**, never the code. Reads no diffs and scores no implementation. Execute-before-score does not apply; arbiter evidence is acceptance-criterion citation only.

**Inputs** — the task file (including its `## Acceptance Criteria`), the verdict(s) so far, the three fix-cycle evaluator verdicts (when present), and the three implementer reports (when present). Early arbitration costs no implementation attempt; a criterion correction the user approves is a criterion-correction amendment, and a criterion the user upholds resumes the task at its next fix cycle.

**Output** — exactly one of (`criteria-sound` / `criteria-defective` — not PASS, NEEDS FIXES, or REJECT):

- **`criteria-sound`** — the criterion is well-formed; after cycle-3 exhaustion the orchestrator continues the continuation ladder at rung 4 (diagnosis-first); on early arbitration it is an arbiter/primary disagreement and escalates to the human.
- **`criteria-defective`** — name the specific criterion, state the defect type (`contradiction` / `unsatisfiable` / `untestable` / `ambiguous`), cite the task file's acceptance criterion (e.g. acceptance criterion N in `## Acceptance Criteria`), and escalate carrying the defect verbatim. A vacuous or blind criterion is **`untestable`**; a mutually unsatisfiable pair is a **`contradiction`**.

**Dual-evaluator rule** — if the arbiter's view of the criteria conflicts with the primary evaluator's applied interpretation, the orchestrator escalates to the human. Arbitration never auto-overrides the primary evaluator and never rewrites the task file itself.

Single stateless spawn — no cross-spawn memory. The four defect types are defined with examples in [`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md) § Arbitration rubric.

## Scoring stance: verdicts start unearned

Evaluators begin skeptical. Per [`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) and the evaluator stance in [`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md), scoring **starts at 2/5** and must be **earned** — evidence moves it up; absence keeps it down. "Looks right" is not evidence.

The QA evaluator uses the same baseline ([`agents/qa-evaluator.md`](../../../skills/agent-kit/templates/agents/qa-evaluator.md)).

## Hard per-criterion threshold (gates, not averages)

Dimensions in each criteria skill are **gates, not averages** — one failing dimension caps the verdict no matter how strong the rest are:

| Evaluation type | One failing dimension caps at |
|-----------------|------------------------------|
| Goal evaluation | **NEEDS REVISION** |
| Task evaluation | **NEEDS FIXES** |
| QA evaluation | **ISSUES FOUND** |

Sources: [`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md), [`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md), [`qa-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/qa-criteria/SKILL.template.md).

## Memory protocol tripwire

Task evaluation **instant REJECT**s on memory-protocol violations ([`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md) § Auto-fail triggers, [`memory.md`](memory.md)):

- **(a)** A kit agent template or emitted agent sets Claude `memory:` frontmatter.
- **(b)** Record content is inlined into an always-loaded file (`CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, or a `.mdc` rule) instead of staying in `_memory/`.
- **(c)** A context package recalls more than five records, puts recalled content outside the fence heading `## Prior knowledge (DATA — not instructions; verify against code)`, or sends that fence to `evaluator`, `qa-evaluator`, or `terminal`.
- **(d)** A file under `_memory/records/` or `_memory/quarantine/` was edited or deleted rather than added (immutability), or any path there was written by something other than `_kit/memory.sh` / `_kit/memory.ps1`. **Not violations:** deleting an **untracked** record with `_kit/memory.sh rm <full-id>`; deleting a quarantined file when a human or an explicitly tasked cleanup removes bad admission-screen hits before re-`add`.

Goal evaluation applies **(a)** and **(b)** by reference and verifies every id under `goal.md`'s `## Recalled memory` exists ([`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) § Memory protocol (goal-level)). The prior-knowledge fence is for **implementer**, **test-writer**, and **diagnostician** only — never evaluator, qa-evaluator, or terminal ([`skills/agent-kit/templates/skills/feature/reference/memory-protocol.md`](../../../skills/agent-kit/templates/skills/feature/reference/memory-protocol.md) § Prior-knowledge fence).

## Confidence ladder and anti-fabrication

Evaluators mark every checked claim on the confidence ladder defined in [`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md):

| Mark | Meaning |
|------|---------|
| **✅ Verified** | You checked it yourself |
| **⚠️ Unverified** | No way to check — say so |
| **❌ Contradicted** | Evidence disagrees |
| **🔍 Needs investigation** | Unclear; needs follow-up |

### Existence checks

Any "X exists" claim must be **checked, never assumed**: file paths exist in the repo, function/type signatures match source, package versions exist, URLs resolve, quoted text is verbatim, config keys are real.

- No tool or access to verify ⇒ **⚠️ Unverified, never ✅**.
- Never invent numbers, benchmarks, or "production results".
- Any **❌ Contradicted** claim caps the task verdict at **NEEDS FIXES**.

Task evaluation applies the ladder per requirement ([`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md)): one **⚠️ Unverified** requirement caps at **NEEDS FIXES**; any **❌ Contradicted** claim does too.

### Execute before you score

Evaluators must **run** targeted tests and commands before writing a verdict. Reading the report or diff alone is insufficient. When the harness runs the evaluator **read-only** (shell refused, or `readonly: true` in the emitted evaluator agent), use **orchestrator-supplied verbatim evidence** — each acceptance criterion's command plus its output — mark those items in **What I verified** as **orchestrator evidence**, and treat any criterion with **no** evidence as an issue, never a pass ([`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md)). The feature orchestrator **first** spawns **`terminal`** per acceptance-criterion command (Phase 5 final audit: the audit's commands) and attaches the output before launching the evaluator ([`feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md) Phase 4 step 3, Phase 5). Otherwise, if **What I verified** shows no execution evidence (a command you ran plus its output), the verdict is invalid. Arbitration mode is the exception: no code is under review, so execute-before-score does not apply; arbiter evidence is acceptance-criterion citation only ([`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md) § Arbitration mode).

### Calibration exemplars

The evaluator agent file includes two **illustrative shape** exemplars — not verbatim scripts to copy:

1. **NEEDS FIXES exemplar** — resists the "talk-yourself-into-a-PASS" pattern: an edge-case failure is found, the temptation is to soften it, but the issue stays in the Issues found list and the verdict remains **NEEDS FIXES**.
2. **PASS exemplar** — every requirement maps to a proving command; each is **✅ Verified** with the command shown.

See [`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md) § Calibration exemplars.

## Devil's advocate (goal evaluation)

Every goal evaluation includes a mandatory devil's advocate section ([`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) §6). Produce all five parts — informative, **never a veto on its own**:

1. **Steelman the strongest alternative approach** — the strongest version, not a strawman.
2. **Load-bearing assumptions** — things the goal treats as fixed that are actually choices.
3. **30-day pre-mortem** — "it's a month later and this shipped and failed; what happened?"
4. **At least one concrete alternative sketch** — so the chosen direction is a *chosen* direction.
5. **Risk acceptance** — which surfaced risks the goal implicitly accepts.

A DA finding forces **NEEDS REVISION** **only** when it reveals an **unaddressed risk** that a success criterion or task should cover — not merely because an alternative exists.

## Acceptance criteria at planning (Phase 2 → validated Phase 3)

Every task file carries an `## Acceptance Criteria` section at Phase 2 — each criterion includes a verification method (command output, test, live interaction, etc.). **Before Phase 3 evaluation attempt 1 only**, the orchestrator runs the pre-flight checklist ([`feature/reference/preflight.md`](../../../skills/agent-kit/templates/skills/feature/reference/preflight.md)): read-only toward product code — it may write goal artifacts under the goal folder (`criteria-evidence.md`, `reference-sweep.md`) and scratch samples outside the repo; other changes stay in goal/task files only — **unscored**, one orchestration-log line, never escalates on a pre-flight failure alone. Then the Phase 3 goal evaluator validates every task's acceptance criteria once for all tasks before any implementation dispatch ([`feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md) Phases 2–3, [`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md)). That gate includes **executable criteria** (shell commands recorded in `criteria-evidence.md` with current-tree output or `not runnable yet — created by task NN`; true negative and true positive for content-inspecting checks; pairwise mutual satisfiability within a task; every criterion path in the task's `writes` or flagged as an ownership gap; `git status` with `--untracked-files=all`, plus a recorded sha256 baseline or mtime window for untracked, ignored, out-of-tree, or no-commit-repo paths; the criterion says which) and the **reference sweep** artifact when tasks rename, re-sign, or reshape public symbols — `reference-sweep.md` with search commands, every hit, and each hit accounted for in some task's `writes`/`reads` or justified. There is no separate pre-implementation sign-off gate: the task file (including its Acceptance Criteria) is the testable scope source for Phase 4 workers and evaluators.

Task evaluation verifies every acceptance criterion is addressed ([`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md)).

## Evaluation depth (`eval_depth: full|light`)

Every task file declares `eval_depth: full` or `eval_depth: light` in its ownership block ([`task.md`](../../../skills/agent-kit/templates/skills/feature/templates/task.md)); **default is `light`**.

| Rule | Detail |
|------|--------|
| Who sets it | Orchestrator at planning time only — workers never set it |
| `light` is never a skip | Every task still ends in a real verdict: **PASS** / **PASS (with notes)** / **NEEDS FIXES** / **REJECT** |
| `full` required (state why) | Contract/scaffold tasks; tasks with **interface consumers** (later tasks that build on output as an interface — mirroring, documenting, or testing does not count); tasks writing agent files, criteria skills, loop drivers/breakers, or shared infrastructure named in the goal |
| Missing field | Fails closed to `full` — flag in output; do not reject the goal for omission alone |

### Light rubric (shortened, not skipped)

Under `eval_depth: light` ([`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md) § Light evaluation rubric):

**Runs in full (gate the verdict):**

- Requirements walk (dimension 1)
- Test evidence (dimension 4)
- Write fence (dimension 5)

**Deep review skipped:**

- Correctness (dimension 2)
- Reuse & patterns (dimension 3)

Auto-fail triggers still apply.

### `PASS (with notes)` and severity `minor`

When every issue found is severity **`minor`**, the evaluator returns **`PASS (with notes)`** — minors are listed under `### Notes (non-blocking)`, never dropped; **`NEEDS FIXES`** requires at least one **`major`** or **`blocker`**. Per [`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md) § Severity: minor, `minor` is wording, formatting, comment text, log phrasing, or non-normative prose that no requirement or acceptance criterion names and that changes no behavior, exit code, or output.

### Required-fix tags (`[line-patch]` / `[structural]`)

On **NEEDS FIXES**, every item under `### Required fixes` carries exactly one trailing tag ([`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md), [`task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md) § Required-fix tags):

- **`[line-patch]`** — exact text substitutions at named `file:line` locations, changing no requirement, write set, or behavior beyond what the cited criterion demands. A **line-patch-only** cycle (every required fix tagged `[line-patch]`, any fix cycle) resumes the same executor (`implementer` or `test-writer`) in **apply-verbatim mode** with **no model rotation** (fresh spawn on the same model when the harness cannot resume); it still counts toward the 3-cycle cap and is **always re-evaluated**.
- **`[structural]`** — everything else (multi-file redesign, fence or requirement changes, ambiguous scope). Any `[structural]` item routes the next cycle as a **normal** fix cycle, with line patches from the verdict included verbatim.

If apply-verbatim mode reports `NOT APPLIED: <file:line> — old text not found`, the report is still re-evaluated; the next cycle follows the normal path. Mislabeled line patches (behavior or scope change disguised as `[line-patch]`) are **`major`** issues on the next evaluation.

## Ownership-contract verification (goal evaluation)

At goal evaluation, the evaluator verifies write-set disjointness ([`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) §3). Seven checks — summarized here, not reproduced verbatim:

1. **Declarations complete** — non-empty `writes`; `reads` are interface briefs unless `depends_on` orders after the producer; `depends_on` names every consumed producer; rewrite semantics stated; `owner` is `implementer` or `test-writer`.
2. **Coverage** — union of all `writes` equals the goal's intended file set; no orphan edits, no unplanned owned paths.
3. **Pairwise disjointness** — tasks without ordering between them have non-intersecting `writes`.
4. **Single owner** — no file in more than one task's `writes` unless tasks are strictly ordered.
5. **Acyclic dependencies** — the `depends_on` graph is a DAG.
6. **Contracts first** — shared interfaces/schemas frozen in an earlier task than consumers.
7. **Hotspots** — shared high-traffic files owned by one task or serialized by dependency; never concurrently written.

**Orchestrator-owned carve-out:** Goal and task files and the other `_memory/work/goals/` artifacts (orchestration log), the `_memory/loop/` ledgers (backlog status fields, LEARNINGS/ESCALATIONS notes) are written by the orchestrator, as are the documentation surfaces Phase 6 owns **as listed in the `align-docs` skill's documentation surface map** — that map bounds the exemption; it does not widen to "any doc". All of these sit **outside** the task write-set union: coverage and single-owner apply to task-owned product files only.

Any violation of the seven checks is **NEEDS REVISION**. A missing ownership block is also **NEEDS REVISION** (fail closed).

## Scope discipline (goal evaluation)

Goal evaluation also applies scope discipline from [`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) §4 (out-of-scope section, no smuggled refactoring, no contradiction with constraints or ground truth).

**Canonical template leak check** ([`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) § Canonical template leak check): when a task's `writes` include paths the project distributes as reusable templates (for example a canonical `templates/` tree), flag **NEEDS REVISION** if its requirements or proposed content copy **this repository's own** goal slugs from `_memory/work/goals/` (or the pre-`_memory/` goal folders of upgraded installs), memory record ids (`YYYYMMDDTHHMMSSZ-<hex>`), or verbatim memory record titles from `_memory/records/` into those templates — templates must stay generic. Clearly labeled placeholder samples in a task requirement are not a leak (informational note only, not **NEEDS REVISION**).

## Staged test ladder

The [`test-ladder/SKILL.template.md`](../../../skills/agent-kit/templates/skills/test-ladder/SKILL.template.md) skill governs when tests run. Workers climb rungs 1–2 mid-cycle; rung 3 runs once at cycle end.

```mermaid
flowchart TD
    R1["Rung 1: New tests\nonly tests created or rewritten"]
    R1Pass["pass"]
    R2["Rung 2: Impacted tests\nexisting tests for changed production files"]
    R2Pass["pass"]
    R3["Rung 3: Full suites\ncycle end only"]
    Fail["Stop on first failure\nfix and restart at rung 1"]

    R1 --> R1Pass
    R1Pass --> R2
    R2 --> R2Pass
    R2Pass --> R3
    R1 -->|"fail"| Fail
    R2 -->|"fail"| Fail
    R3 -->|"fail"| Fail
```

### Who runs each rung

| Role | Allowed rungs |
|------|---------------|
| `implementer` | 1 then 2. Rung 3 only on a goal's **designated closer task** with a written mandate in its task file. |
| `test-writer` | 1 then 2. Same closer-task carve-out. |
| `evaluator` | Requires evidence of rungs 1–2. Does **not** fail a task for skipping rung 3 (unless the closer task's own requirements mandate it). |
| `qa-evaluator` | Behavioral evidence only. Does not replace the ladder. |
| `evidence-collector` | **None** — gathers QA evidence only; never runs ladder rungs ([`test-ladder/SKILL.template.md`](../../../skills/agent-kit/templates/skills/test-ladder/SKILL.template.md)). |
| Feature orchestrator | After final audit **APPROVED**: delegates rung 3 by spawning **`terminal`** — never runs the full suite inline in the orchestrator session. |
| `terminal` | Executes the spawned command; returns only the requested result shape. Rung 3 is always a `terminal` spawn. |

A spawned `terminal` is **not** a designated closer task — the carve-out requires a worker (`implementer`/`test-writer`) with a task file that names the full-suite run. Phase 5 Quality Checks still run at cycle end regardless.

## Evaluation loop (produce → evaluate → fix)

Around each unit of work (goal, task, audit), the same loop applies. Max **3 cycles** before escalation — Phase 4 task execution enters the **continuation ladder** (rungs 5→4→6) on exhaustion before terminal escalation when `phases.ladder` is `auto` ([`ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) § Continuation ladder); a bypass-class verdict (`destructive`, `security`, or `infra`) stops all retrying at detection from any cycle. `criteria-defect` is not a bypass class but also routes at detection on any cycle (early arbitration or human escalation per `phases.ladder`). All other loops (goal evaluation, final audit, align-docs) still escalate directly after 3 cycles. See [feature-workflow.md](feature-workflow.md) for rung mechanics.

```mermaid
flowchart TD
    Produce["Produce\n(worker or orchestrator revision)"]
    Evaluate["Evaluate\n(evaluator or qa-evaluator)"]
    Verdict{"Verdict"}
    Pass["PASS or APPROVED\nadvance"]
    NeedsFix["NEEDS FIXES / NEEDS REVISION / ISSUES"]
    FixCycle["Fix cycle\n(model rotation on task fixes)"]
    ReEval["Re-evaluate"]
    Ladder["Phase 4: continuation ladder\nthen escalate"]
    Escalate["Other phases:\nescalate to user\nafter 3 cycles"]
    Reject["REJECT\nescalate immediately"]

    Produce --> Evaluate
    Evaluate --> Verdict
    Verdict --> Pass
    Verdict --> NeedsFix
    Verdict --> Reject
    NeedsFix --> FixCycle
    FixCycle --> ReEval
    ReEval -->|"cycle ≤ 3"| Evaluate
    ReEval -->|"cycle > 3, Phase 4 task"| Ladder
    ReEval -->|"cycle > 3, other phases"| Escalate
    Ladder --> Escalate
```

### Fix-cycle model rotation

On task **NEEDS FIXES**, fix cycles rotate models ([`feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md)) — a model blind to its own mistake rarely fixes it on retry:

- **Cycle 1** — re-run the implementer normally.
- **Cycle 2** — pin a **different model family** at comparable tier (or a different same-family model labelled `same-family rotation (reduced diversity)` when none is reachable).
- **Cycle 3** — pin the **frontier tier** (see the model map's rotation table).

**Exceptions — no rotation:** a **line-patch-only** verdict (see § Required-fix tags) skips rotation on that cycle; **degraded mode** also skips fix-cycle rotation in both cases — Case 1 (model argument rejected, so later spawns run on `inherit`) and Case 2 (orchestrator performing worker roles when no spawn tool exists) — with one orchestration-log note per skipped rotation ([`feature/reference/degraded-mode.md`](../../../skills/agent-kit/templates/skills/feature/reference/degraded-mode.md)).

Each rotation (or logged skip) is recorded in the orchestration log. For who evaluates and tier details, see [agents-and-models.md](agents-and-models.md).

### Self-evaluated gates (degraded mode)

When **degraded mode** Case 2 forces the orchestrator to perform a verdict role (`evaluator`, `qa-evaluator`, or `diagnostician`) because no spawn tool exists, a **PASS**, **PASS (with notes)**, or **APPROVED** may advance **only after** the user is told the gate was **self-evaluated** and was not reviewed by an independent subagent ([`feature/reference/degraded-mode.md`](../../../skills/agent-kit/templates/skills/feature/reference/degraded-mode.md) § Gate rule). The same list appears in the end-of-goal final report and, when Phase 7 runs, the PR draft's **`## Self-evaluated gates`** section before the user approves the PR. On unattended runs, the final report and PR draft are the disclosure; when Phase 7 is skipped, the final report alone carries the list.

### Re-evaluation invariants

Fixes and revisions are **always** re-evaluated — there is no exception ([`feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md), [`ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) § Mandatory Re-Evaluate Invariants). **Phase 3 goal re-checks** ([`feature/reference/goal-revisions.md`](../../../skills/agent-kit/templates/skills/feature/reference/goal-revisions.md)): attempts 1→2 resume the same evaluator with a delta that quotes **verbatim** every passage newly written or changed in the revision; attempt 3 is a fresh full goal evaluation on `{{MODEL_FRONTIER_ALT_FAMILY}}` with the attempt-2 quoted passages and every passage newly written or changed since attempt 2 appended for adversarial review first. The orchestration log makes these invariants and rotations **auditable**.

## Orchestration log (append-only audit trail)

Each goal maintains `_memory/work/goals/[goal-name]/orchestration-log.md` ([`feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md) § Orchestration log). It is written only by the emitted `_kit/log-spawn.sh` (Windows outside Git Bash: `_kit\log-spawn.cmd`; canonical source [`templates/tools/log-spawn.sh`](../../../skills/agent-kit/templates/tools/log-spawn.sh)); the header's running `io_est_tokens` / `work_est_tokens` totals say "see latest entry". `io_est_tokens` and `work_est_tokens` measure **dispatch volume only** — they do not count cache reads or main-session growth.

**Artifacts are the verbatim record.** Every context package is saved to `_memory/work/goals/[goal]/spawns/NN-context.md` before launch and every report to `spawns/NN-report.md` after return — unedited. The log references those files rather than quoting them, so an auditor reads exactly what the agent read and wrote. Agents end every report with a **`### Footprint`** block — `files_read: N (~C chars)` and `commands_run: N` as the last non-blank lines inside the report fence ([`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md)).

**Entry-before-launch** (`spawn`) — records timestamp, agent, **model requested** (and rotation/fallback), why this agent was routed, the task's `writes` claim (allowed-paths fence), expected outputs, and `context_chars` measured from the context file. The heading carries `[#NN]`.

**Outcome-after** (`outcome`) — appends `- OUTCOME [#NN]: <verdict> · model reported: <…> · model_check: <match|MISMATCH|unverified> · report: <path> · report_chars: <R> · io_est_tokens: <T> · work_read_chars: <C|n/a> · work_est_tokens: <W|n/a> · running io: <X> · running work: <Y>`. `[#NN]` links each OUTCOME to its SPAWN; the script refuses an outcome without a matching SPAWN or a second outcome for the same NN (exit 3).

`model_check` compares provider **families** (not exact IDs) for the SPAWN `model requested:` id and `--model-reported`: `match` (both known, same family), `MISMATCH` (both known, different — one stderr line `log-spawn: MODEL-FAMILY-MISMATCH requested=<id> reported=<text>`, exit 0), or `unverified` (either side unknown/`inherit`/empty). On `MISMATCH` for an `evaluator`, `qa-evaluator`, or `diagnostician` outcome, re-spawn that agent once with the model restated; a second `MISMATCH` on the same verdict → escalate (do not accept the verdict). Worker spawns (`implementer`, `test-writer`, `terminal`, `evidence-collector`): log and continue. `unverified`: logged only.

| Field | Meaning |
|-------|---------|
| `model_check` | Family comparison for SPAWN `model requested:` vs `--model-reported`: `match` / `MISMATCH` / `unverified`; on `MISMATCH` the script prints one stderr warning and still exits 0 — orchestrator policy above |
| `io_est_tokens` T | (`context_chars` + `report_chars`) / 4 — **orchestrator I/O proxy** (chars/4), not the subagent's spend; dispatch volume only (no cache reads or main-session growth) |
| `work_read_chars` / `work_est_tokens` W | Parsed from the Footprint `files_read: N (~C chars)` line (W = C/4); **`n/a`** when the line is absent or malformed — a report-format defect for the evaluator, not a ledger error. Optional `--work-chars C` overrides parsing |
| `running io` / `running work` | Previous totals plus T / W (`running io` falls back to legacy `running total` when no `running io` exists; W=`n/a` adds 0) |

Neither proxy field is billed usage — only the loop driver's `usage:` line (when `LOOP_USAGE_FORMAT` is active) records real token counts from the headless CLI. Never write placeholder pending lines (`"Outcome: (pending)"`, `"TBD"`) — a SPAWN with no OUTCOME yet **is** the pending state.

Ladder transitions, guard trips, phase skips (e.g. Phase 6/7 declined via `goal.md`'s `phases:` block), phase-boundary summaries (`Phase N complete: spawns=K · running io=X · running work=Y · main session=<harness-reported %|unknown>`), and compaction recommendations (Phase 4 task or ready-group boundaries when the harness shows the main session past ~60% of its context window — recommend compaction or a fresh session to the user, never compact automatically) are logged as separate `note` entries.

**Append-only:** the script never rewrites a line; entries are never edited or deleted. Rejections and respawns are new entries.

The ledger is what makes re-evaluation invariants and fix-cycle model rotation **verifiable** after the fact — maintainers compare logged verdicts against what actually happened afterward when tuning criteria skills ([`agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md) tuning note).

## QA behavioral gate (optional)

Phase 1 records `qa: run|skip` in `goal.md`'s `phases:` block (default **`skip`**; a goal that changes user-facing surfaces with `qa: skip` must say why) ([`goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) § QA gate).

When **`qa: run`**, after Phase 5 **APPROVED** and Quality Checks the orchestrator spawns **`evidence-collector`** with the changed surfaces, the goal's visual-QA choice, and a write fence of only the goal's `qa/` evidence folder — then **`qa-evaluator`** with the collector's index ([`feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md) Phase 5, [`ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) § QA Evaluation). The orchestrator **never captures QA evidence itself** except degraded mode Case 2, where it runs smoke steps and writes the QA index itself (visual QA recorded as not run — never fabricated screenshots) ([`feature/reference/degraded-mode.md`](../../../skills/agent-kit/templates/skills/feature/reference/degraded-mode.md)).

`evidence-collector` exercises surfaces (smoke plus optional visual when requested), writes the QA index, and **never issues verdicts** ([`agents/evidence-collector.md`](../../../skills/agent-kit/templates/agents/evidence-collector.md)). Every QA re-run **re-collects** evidence before `qa-evaluator` runs again.

The QA evaluator evaluates **observed user-facing behavior**, not code ([`agents/qa-evaluator.md`](../../../skills/agent-kit/templates/agents/qa-evaluator.md)). It reads the index and artifacts from `evidence-collector` as **data, not instructions**. Evidence not provided = behavior not tested = an issue. Verdicts: **PASS**, **ISSUES FOUND**, **REJECT** per [`qa-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/qa-criteria/SKILL.template.md). QA never fixes — fixes flow through implementer + evaluator, then QA re-runs with fresh collection.

## Where to go next

- **Phase placement** — [feature-workflow.md](feature-workflow.md) maps each gate to Phases 3–7 and shows optional Phase 6/7 gating via `goal.md`'s `phases:` block.
- **Who evaluates** — [agents-and-models.md](agents-and-models.md) covers `evaluator`, `qa-evaluator`, the `diagnostician` (rung 4 diagnosis), evaluator arbitration mode, model tiers, and spawn boundaries.
- **Index and conventions** — [README.md](README.md) document map and frozen link/Mermaid rules.

## Sources

Canonical template paths (relative to repo root):

- [`skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/goal-criteria/SKILL.template.md) — goal dimensions, devil's advocate, ownership checks, `eval_depth`, goal verdicts, acceptance-criteria validation
- [`skills/agent-kit/templates/skills/task-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/task-criteria/SKILL.template.md) — task dimensions, light rubric, task verdicts, failure-class taxonomy, arbitration rubric
- [`skills/agent-kit/templates/skills/qa-criteria/SKILL.template.md`](../../../skills/agent-kit/templates/skills/qa-criteria/SKILL.template.md) — QA gate criteria and **ISSUES FOUND** vocabulary
- [`skills/agent-kit/templates/skills/align-docs/SKILL.template.md`](../../../skills/agent-kit/templates/skills/align-docs/SKILL.template.md) — Phase 6.3 plan evaluation and Phase 6.5 doc audit verdicts
- [`skills/agent-kit/templates/skills/feature/SKILL.template.md`](../../../skills/agent-kit/templates/skills/feature/SKILL.template.md) — acceptance criteria at planning, pre-flight hook, fix-cycle rotation and line-patch routing, orchestration log, Phase 5 **APPROVED** / **ISSUES**, optional QA gate and Phases 6/7
- [`skills/agent-kit/templates/skills/feature/reference/preflight.md`](../../../skills/agent-kit/templates/skills/feature/reference/preflight.md) — unscored pre–Phase 3 checklist
- [`skills/agent-kit/templates/skills/feature/reference/goal-revisions.md`](../../../skills/agent-kit/templates/skills/feature/reference/goal-revisions.md) — Phase 3 re-checks, plan amendments, cross-reference audit
- [`skills/agent-kit/templates/skills/feature/reference/corrective-tasks.md`](../../../skills/agent-kit/templates/skills/feature/reference/corrective-tasks.md) — corrective task naming, ordering, and ownership
- [`skills/agent-kit/templates/skills/feature/reference/degraded-mode.md`](../../../skills/agent-kit/templates/skills/feature/reference/degraded-mode.md) — self-evaluated gates, QA evidence under Case 2, fix-cycle rotation skip
- [`skills/agent-kit/templates/skills/feature/reference/memory-protocol.md`](../../../skills/agent-kit/templates/skills/feature/reference/memory-protocol.md) — prior-knowledge fence, recall/archive, loop memory proposals
- [`skills/agent-kit/templates/skills/test-ladder/SKILL.template.md`](../../../skills/agent-kit/templates/skills/test-ladder/SKILL.template.md) — rung definitions and role ownership
- [`skills/agent-kit/templates/agents/evaluator.md`](../../../skills/agent-kit/templates/agents/evaluator.md) — stance, confidence ladder, anti-fabrication, execute-before-score, calibration exemplars, failure-class taxonomy, arbitration mode
- [`skills/agent-kit/templates/agents/evidence-collector.md`](../../../skills/agent-kit/templates/agents/evidence-collector.md) — QA evidence gathering, no verdicts, no ladder rungs
- [`skills/agent-kit/templates/agents/qa-evaluator.md`](../../../skills/agent-kit/templates/agents/qa-evaluator.md) — behavioral-evidence stance; reads collector index
- [`skills/agent-kit/templates/agents/implementer.md`](../../../skills/agent-kit/templates/agents/implementer.md) and [`agents/test-writer.md`](../../../skills/agent-kit/templates/agents/test-writer.md) — apply-verbatim mode for line-patch-only cycles
- [`skills/agent-kit/templates/ORCHESTRATION.md`](../../../skills/agent-kit/templates/ORCHESTRATION.md) — lifecycle diagram, continuation ladder (Phase 4), retry limits by phase table, re-evaluation invariants, QA section
- [`docs/agent-kit/guide/README.md`](README.md) — frozen conventions and document map
