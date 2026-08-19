# Designing Conflict-Free Multi-Agent Software Development: Architecture-Level Prevention Over Merge-Level Repair

## TL;DR
- **The problem of two agents writing the same file is solved at *planning time*, not merge time: declare a disjoint, one-owner-per-file write-set for every task; make the orchestrator statically verify those write-sets are non-overlapping (and their dependency graph acyclic) before dispatch; and keep all *writes* single-threaded per file even when reads/reviews fan out.** This is exactly what CodeTeam's machine-checkable ownership contract, ATM's pre-write admission broker, and Cognition's "single-writer" principle each independently converge on.
- **The clean-design substrate that makes this cheap is contract/interface-first architecture**: define types/schemas/ports in a dedicated interface task first, scaffold empty file skeletons, then let each worker fill exactly one owned file behind stable interfaces (SOLID's SRP + Dependency Inversion + Interface Segregation, realized as hexagonal ports-and-adapters and vertical feature slices). Rewrites then happen *whole-file, in place*, touching no consumer.
- **For your orchestrator/worker/judge system specifically**: add a `writes:` (owned paths) and `reads:` (interface briefs) block to every `task.md`; make the goal-judge FAIL any goal whose task write-sets intersect or whose shared-file work isn't serialized; give `implementer`/`test-writer` an allowed-paths fence with a "fail loudly, escalate — never edit outside the fence" rule; and size autonomous-loop stories to a single ownership boundary.

## Key Findings

**1. The field has converged on a "single-writer" rule for state-changing actions.** Cognition's Walden Yan, writing from building Devin, argues in *Don't Build Multi-Agents* (June 12, 2025) that you should "by default rule out any agent architectures" that violate two principles: (1) "Share context, and share full agent traces, not just individual messages," and (2) "Actions carry implicit decisions, and conflicting decisions carry bad results." His Flappy Bird example shows two subagents producing stylistically incompatible outputs a final agent cannot reconcile. His April 2026 follow-up, *Multi-Agents: What's Actually Working*, sharpens rather than retracts this: "multi-agent systems work best today when writes stay single-threaded and the additional agents contribute intelligence rather than actions." The working patterns are all read/review-only helpers: a clean-context **code-review loop** (per Cognition, "even on PRs written by Devin, Devin Review catches an average of 2 bugs per PR, of which roughly 58% are severe — logic errors, missing edge cases, security vulnerabilities"), a frontier "smart friend," and "map-reduce-and-manage."

**2. Anthropic's own multi-agent system is read-heavy by design and deliberately avoids parallel writers.** Anthropic's *How we built our multi-agent research system* (June 13, 2025) uses an orchestrator-worker pattern where subagents "never talk to each other," each gets "a self-contained task description, an output format, and a fresh context window," and a *separate* citation pass does the final synthesis. The system — "with Claude Opus 4 as the lead agent and Claude Sonnet 4 subagents" spawning 3–5 subagents — "outperformed single-agent Claude Opus 4 by 90.2% on [the] internal research eval," at roughly 15x the tokens of a normal chat. Crucially, Anthropic states this architecture is for breadth-first *research* and cautions that "most coding tasks involve fewer truly parallelizable tasks than research, and LLM agents are not yet great at coordinating and delegating to other agents in real time." The reconciliation: parallelism is safe for reads; writes need coordination.

**3. Merge conflicts from AI agents are empirically large and worth designing away.** The AgenticFlict dataset (AIware '26, Ogenrwot & Businge; DOI 10.1145/3805760.3814923) collected "142K+ Agentic PRs from 59K+ repositories, of which 107K+ are successfully processed," identified "29K+ PRs exhibiting merge conflicts, yielding a conflict rate of 27.67%, and extract[ed] 336K+ fine-grained conflict regions." This is the concrete cost of the branch-and-merge model the user is right to reject for intra-run coordination.

**4. Research has produced machine-checkable, non-git ownership mechanisms.** Three 2026 systems are directly on-point:
   - **CodeTeam** (arXiv 2606.22082) builds a *Software Design Sketch* (SDS): "a machine-checkable design contract" with a fixed repo file tree, per-file responsibilities and public interfaces, explicit cross-file dependencies, and a **developer-to-file ownership mapping** ("which files are owned by Developer 0 to Developer D−1"). A CTO agent validates it — every file in the tree, every owner declared, every dependency edge resolvable, and "the resulting inter-file dependency graph is acyclic after collapsing same-file symbol references." At runtime, "developers are constrained to operate strictly within the predefined structure: no extra files outside the SDS can be created," and agents get only **interface briefs** (path, exported symbols, typed signatures, invariants, and a summarized `update_reason`) of files they depend on — "they do not read the full content of files owned by other agents." CodeTeam reaches 34.6% (prompt-engineered) / 42.3% (fine-tuned) average test pass rate on NL2Repo-Bench, the highest among compared systems.
   - **ATM** (arXiv 2607.00041) does *sub-file* pre-write admission: it "decomposes the notion of same file into adapter-declared regions, CIDs, ConflictKeys, shared surfaces, and dependency sets that the broker can evaluate before governed mutation is applied." A seven-layer admission gate — CID identity → shared surface → read/write set (`R(I) ∩ W(I') ≠ ∅`) → file range/virtual atom → ConflictKey mergeability → CAS base-hash → fallback whole-file lock — issues a verdict (`parallel-safe`, `needs-physical-split`, `SERIAL`, `blocked-cid-conflict`, `blocked-shared-surface`) *before* any write is applied by a single "neutral steward." Its governing rule: "physical disjointness remains necessary but not sufficient" — two intents that write physically disjoint regions are still blocked if they touch a shared non-file surface (a registry, generated artifact, or validator). (Caveat: ATM's evidence is self-hosting/design-matrix, not a controlled benchmark; its value is the formal vocabulary.)
   - **Co-Coder** (arXiv 2606.00953, *When Parallelism Pays Off*) shows *why* this matters quantitatively: naive file-based parallelism gives "negligible" gains over sequential (57.7% vs 56.8% pass on DevEval) at +44% cost ($0.36 vs $0.25), because "poor task partitioning causes parallel agents to produce conflicting interfaces, requiring redundant re-generation." Cohesion-aware partitioning that co-locates coupled files in one owner "achieves the highest average pass rate (68.1%)… improving over the sequential baseline by 11.3% while reducing wall-clock latency by 45% (442s vs. 800s) and API cost by 28%." Conflict-improvement correlates positively with dependency edge density.

**5. Existing frameworks split cleanly into "conflict-free by design" vs "isolate-and-merge."**
   - *Conflict-free by role/artifact separation*: **MetaGPT** (ICLR 2024) encodes Standard Operating Procedures — Product Manager → Architect → Engineer → QA — where "the output of one role becomes the structured input of the next," communicating via a shared message pool with structured schemas rather than concurrent edits. **Kiro** (AWS) enforces spec-driven development with `requirements.md` → `design.md` → `tasks.md` and executes "waves sequentially; tasks within a wave execute concurrently." **CodeTeam/Co-Coder** as above.
   - *Isolate-and-merge (what to avoid as the primary answer)*: **GitHub Copilot coding agent** and its `/fleet` command (April 2026) run "each agent session in its own isolated git worktree"; notably, `/fleet` sub-agents "share a filesystem with no file locking. If two agents write to the same file, the last one to finish silently wins — no merge, no error." Claude Code offers `isolation: worktree`. These prove the branch/worktree model is the *dominant* commercial answer — and precisely the after-the-fact reconciliation the user wants to avoid.

**6. SOLID maps cleanly onto agent/task design.** Practitioner and academic sources (Manchikatla, *Applying SOLID Principles to Agentic Application Design*; Jansen, *The SOLID Principles are Universal*; arXiv 2503.13786) map: **SRP** → one agent/task owns one module or concern ("many focused agents than one Swiss Army knife agent"); **Open/Closed** → agents add new files/plugins rather than editing shared ones; **Interface Segregation** → "many specialised agents with narrow responsibilities" behind narrow contracts; **Dependency Inversion** → "your orchestrator should depend on abstractions of agents, not on concrete implementations," and agents depend on interface briefs, not each other's file contents; **Liskov** → contract/behavioral tests as the substitution guarantee that a wholesale file rewrite still satisfies consumers.

## Details

### The core mechanism: declared, disjoint write-sets verified statically before dispatch

The single most important architectural move is to make **file ownership an explicit, machine-checkable property of the plan** rather than an emergent property of execution. CodeTeam operationalizes this most concretely: the plan is a JSON artifact in which every file records `{purpose, exported interface, owner, dependencies}`; a candidate is only valid if it parses, every file appears in the repo tree, every owner is declared, every dependency edge resolves, and the file-level dependency graph is acyclic. Ownership is 1:1 (one owner per file) and immutable for the run: "that developer-to-file ownership mapping becomes the initial division of labor for the entire execution."

This is the agent analogue of a **CODEOWNERS map**, but enforced at *plan time* against *tasks* rather than at review time against *people*. The orchestrator's job before dispatch is a set-disjointness check: for any two tasks that may run without a strict ordering between them, `writes(A) ∩ writes(B)` must be empty. If it is not, one of two things must happen: (a) the plan is rejected and re-decomposed so the overlapping file goes to a single owner, or (b) the tasks are *serialized* — an ordered dependency edge is added so they run sequentially, never concurrently.

### Read/write asymmetry is the deep principle

Augment Code's guides state the underlying law cleanly: "read operations are naturally parallelizable, while write operations that must maintain consistency require sequential coordination." This is why Anthropic can fan out 3–5 research subagents safely (they only read) while Cognition insists writes stay single-threaded. For a *coding* system, the implication is: parallelize research, review, QA, and test-*design* freely; serialize or partition all file *writes* so each file has exactly one writer at any time.

### Sequencing shared-file work instead of parallelizing it

When a file genuinely must be touched by multiple concerns (routing tables, DI registries, config, migrations, lockfiles — the "hotspot files" Augment Code flags), the answer is **serialization, not concurrency**. Convert the shared-file work into ordered nodes in a DAG. The `aakashx` parallel-Claude-Code guide and the Kimi/Union.ai planner writeups all describe "dependency-aware parallelism: parallelize what can run independently, wait where waiting protects quality," with a stage gate that checks contract alignment (e.g., frontend expects `revenueTotal` but API returns `total_revenue`) before proceeding.

### Interface-first and scaffold-then-fill

The pattern that makes disjoint write-sets *natural* rather than forced is **interface-first planning**: a dedicated first task defines the contracts (types, schemas, API shapes, port interfaces) in a `contracts/` location; all downstream implementation tasks then build against those stable interfaces and can be developed in parallel because "the frontend task can build against that contract without waiting for the backend to be done" (Nimbalyst). The `aakashx` guide formalizes this as "scaffold-then-split: define shared contracts first, then dispatch implementation agents," and warns of a real fintech incident where two agents parallelized auth work *without* scaffolding contracts first and shipped a login-response shape mismatch to production.

**Scaffold-then-fill** takes this further: the orchestrator (or a single scaffolding task) creates the empty file skeletons and the contracts, and each worker then only *fills* its one assigned file. CodeTeam does exactly this — "a fixed repository file tree that the system instantiates *before* implementation." This makes the whole-file-rewrite semantic safe: because a worker owns its entire file and depends only on interface briefs, it can rewrite the file wholesale without a diff/patch merge, echoing the 2024 "edit-apply model" insight Cognition describes (small models rewriting whole files given a markdown explanation).

### Clean architecture is what makes a codebase "agent-parallelizable by construction"

- **Hexagonal / ports-and-adapters** (Cockburn, 2005): the domain core depends only on port interfaces; adapters (DB, HTTP, UI, mocks) plug in. Because "the inner hexagon has no knowledge of the implementations of the adapters," an agent can rewrite an adapter file wholesale without touching the core or other adapters. Your `test-writer`'s "mock all external services" rule is literally the mock-adapter pattern.
- **Vertical slice / feature folders**: each feature is "a whole slice that goes through all layers," so a feature task owns a self-contained directory (`features/checkout/…`) rather than editing shared horizontal layers that many tasks touch. This maximizes write-set disjointness.
- **High cohesion / low coupling**: Co-Coder's empirical result is that co-locating strongly coupled files in one owner ("internalizing the majority of dependencies") is what makes parallelism actually pay off; splitting coupled files across owners is what generates conflicts.

### Coordination mechanisms without git branches (evaluated for markdown/fresh-context subagents)

| Mechanism | What it is | Fit for Claude Code / Cursor / Copilot markdown subagents |
|---|---|---|
| **Declared disjoint write-sets + static check** | Ownership map in the plan; orchestrator verifies non-overlap + acyclic deps before dispatch | **Best fit.** Pure planning-layer discipline; needs no runtime infra; works with fresh-context subagents because the fence travels *in the prompt*. This is the primary recommendation. |
| **Allowed-paths write fence in the prompt** | Each subagent's prompt lists the only paths it may write; "fail loudly if you need to edit outside" | **Excellent fit.** Fresh-context subagents get everything from the prompt anyway. Reinforce with tool-level allowlists where the harness supports them (see below). |
| **Tool-level path allow/deny** | Harness enforces filesystem scope | Partial/emerging. Claude Code's `tools:` frontmatter is an allowlist *by tool*, not by path (a missing tool means the call fails, not asks). LangChain deepagents `FilesystemPermission`, OpenCode/Antigravity per-path rules, and open feature requests (openclaw #12202, opencode #5529) show path-level control is arriving but not yet universal — so treat it as defense-in-depth, not the primary guarantee. |
| **Task manifest / claimed-paths ledger** | Append-only log of which task owns which paths (your `orchestration-log.md`) | Strong fit; you already have the substrate. Make path-claims first-class entries. |
| **Blackboard / shared state** | Agents read/write a shared workspace, control component sequences them | Fits your goal-dir + orchestration-log model, but blackboards reintroduce read-write conflicts unless writes are serialized; use it for *handoff artifacts*, not concurrent code edits. |
| **Actor model / single owner of a resource** | Exactly one actor owns each resource; others message it | Conceptually equivalent to single-writer-per-file; the "owner" is the one task assigned that file. |
| **File locks / leases / CAS base-hash** | Runtime mutual exclusion (ATM's fallback layer; CodeTeam's no-git ablation lock) | Overkill for a design-time-partitioned system; keep as a last-resort fallback only. Copilot `/fleet`'s "last writer silently wins" shows what happens with *no* mechanism. |

The decision-relevant conclusion: for your architecture, **prevention lives in the planning layer (write-sets) and the prompt layer (fences)**, with tool/OS enforcement as optional hardening. You do not need locks, CRDTs, or worktrees if the plan guarantees disjointness.

## Recommendations

### Stage 1 — Make write-sets a first-class, verified part of every plan (do this first)

**1a. Extend `task.md` with an ownership contract.** Add a required, machine-parseable block to your task template:

```yaml
# --- task ownership contract ---
writes:            # the ONLY paths this task may create or modify (globs allowed)
  - src/features/checkout/service.ts
  - src/features/checkout/service.test.ts
reads:             # interface briefs this task may depend on (read-only)
  - src/contracts/payment.ts        # exported symbols + signatures only
depends_on:        # task IDs that must complete before this one (shared-file ordering)
  - T02-define-payment-contract
owner: implementer # single writer for these paths
rewrite_semantics: whole-file      # workers rewrite owned files wholesale, not patch
```

This mirrors CodeTeam's per-file `{purpose, exported interface, owner, dependencies}` and makes disjointness checkable.

**1b. Add a `contracts/` directory and an interface-first task rule.** In the goal-creation skill, require that any goal touching a shared boundary produces a dedicated **contract/scaffold task first** (define types/schemas/ports + create empty file skeletons), listed as a `depends_on` prerequisite of all implementation tasks. This is your "scaffold-then-fill" gate.

### Stage 2 — Make the goal-judge enforce disjointness as a PASS criterion

Add these to the **goal-criteria** skill (goal-judge must FAIL the goal if any is violated):
- **Disjoint write-sets**: for every pair of tasks without a `depends_on` ordering between them, `writes` sets do not intersect. Any shared path must be resolved by (a) reassigning that file to a single owner task, or (b) adding an explicit `depends_on` edge that serializes the writers.
- **Single owner per file**: no file appears in more than one task's `writes` across the whole goal unless those tasks are strictly ordered.
- **Acyclic dependencies**: the `depends_on` graph is a DAG (CodeTeam's acyclicity check).
- **Contract-first ordering**: any file in `contracts/` (or any interface both a producer and a consumer task touch) is created/frozen by an earlier task than its consumers.
- **Coverage**: every file the goal intends to change is owned by exactly one task (CodeTeam's "no extra files outside the plan" rule, inverted).

### Stage 3 — Give workers an allowed-paths fence with fail-loud semantics

Add to the `implementer` and `test-writer` agent prompts (and inject the concrete list per task):
- *"You may create or modify ONLY the files listed in `writes`. You have read-only access to the interface briefs in `reads`."*
- *"If completing this task requires editing any file outside your `writes` fence, DO NOT edit it. Stop and return an escalation stating exactly which out-of-fence path you need and why. The orchestrator will re-plan ownership."* (This converts a silent cross-file collision into a loud, logged planning event — the opposite of `/fleet`'s "last writer silently wins.")
- *"Rewrite owned files wholesale to satisfy the contract; do not assume another agent will reconcile your changes."*
- Where the harness supports it (Claude Code `tools:`/`permissionMode`, LangChain deepagents permissions, OpenCode/Antigravity path rules), also set a tool/path allowlist as defense-in-depth — but never rely on it alone, since coverage varies across harnesses.

### Stage 4 — Judge and QA stay read/review-only (you already do this — keep it)

Your `judge` and `qa-judge` are the "additional agents contribute intelligence, not actions" pattern Cognition validated (the clean-context reviewer that catches ~2 bugs/PR, ~58% severe). Keep them strictly non-writing. This is the safe, proven form of multi-agent parallelism.

### Stage 5 — Wire ownership into the autonomous loop

- **Story sizing = one ownership boundary.** Size each backlog story so its write-set fits one vertical slice / feature folder owned end-to-end within one context window. A story that must edit a hotspot shared file should either own it exclusively for that iteration or be split.
- **Claimed-paths ledger.** Extend the append-only `orchestration-log.md` so each dispatched task appends its `writes` claim; the loop refuses to dispatch a task whose `writes` intersect an unfinished task's claim.
- **Protected paths = permanent fences.** Your existing protected-paths list is already an allowed-paths deny-rule; make it a hard fence the write-set checker enforces.
- **LEARNINGS.md** should capture recurring hotspot files so the planner learns to define contracts around them proactively.

### Proposed checklist additions (drop-in for goal-criteria / task-criteria skills)

**task-criteria additions:**
- [ ] Task declares a non-empty `writes` set (explicit owned paths).
- [ ] Task declares `reads` as interface briefs, not full-file dependencies on other tasks' owned files.
- [ ] Task declares `depends_on` for every file it must consume that another task produces.
- [ ] Task states rewrite-whole-file semantics for its owned files.
- [ ] Task's prompt embeds the allowed-paths fence and the fail-loud/escalate rule.

**goal-criteria additions:**
- [ ] Union of all task `writes` = the set of files the goal intends to change (full coverage, no orphan edits).
- [ ] Pairwise write-set intersection is empty for all non-ordered task pairs.
- [ ] Every file has exactly one owner (single-writer invariant).
- [ ] `depends_on` graph is acyclic (DAG).
- [ ] Contracts/interfaces defined and frozen in an earlier task than their consumers.
- [ ] Hotspot/shared files are either owned by one task or serialized — never concurrently written.

### What would change these recommendations (thresholds)
- If your harness ships **reliable per-path write enforcement** for subagents (path allow/deny at the tool layer, not just per-tool), promote it from defense-in-depth to a hard guarantee and relax prompt-level fencing.
- If you ever need **true concurrent editing of one file** (rare; e.g., a giant generated file), only then reach for ATM-style sub-file region admission or a CRDT — but first try splitting the file (signature-preserving decomposition) so single-writer holds again.
- If empirical conflict/escalation rates stay near zero across many loop iterations, you can widen story size / increase parallel task fan-out; if out-of-fence escalations rise, your slices are too coupled — invest more in contract-first decomposition (Co-Coder's cohesion lesson).

## Caveats
- **Recency and source tier vary.** The strongest primary sources are Cognition's and Anthropic's engineering posts and the benchmarked CodeTeam and Co-Coder papers. ATM (arXiv 2607.00041) is a single-author preprint whose author explicitly disclaims "broad comparative superiority"; treat its seven-layer gate as a useful *formal vocabulary* (CIDs, ConflictKeys, shared surfaces), not proven results. Several supporting citations are practitioner blogs (aakashx, AddyOsmani, Augment Code, Kimi, Nimbalyst) — directionally consistent with the primary sources but not independently verified.
- **Dates.** Some cited posts carry 2026 datestamps (Cognition's April 2026 follow-up, GitHub `/fleet`, framework version notes); these reflect the sources as found and should be re-verified against originals before formal publication.
- **Single-writer is a current-model constraint, not a law of nature.** Cognition explicitly expects that as single-threaded agents get better at communicating, safe parallel writing "will come." The recommendations here are the robust choice for 2025–2026 model capabilities.
- **This solves *write-write* conflicts by construction; it does not by itself guarantee *semantic* consistency.** Even with disjoint files, a wholesale rewrite can violate a consumer's expectations — which is exactly why the contract-first interfaces plus your judge/qa-judge review loop (Liskov-style contract tests) remain essential. CodeCRDT (arXiv 2510.18893) found that across 600 trials it achieved "100% convergence with zero merge failures" yet still saw a 5–10% *semantic* conflict rate — underscoring that ownership discipline and contract tests are complementary, not substitutes.