# Ideas Gleaned from bradygaster/squad

**Date**: 2026-08-18 · **Method**: full-repo primary-source study (shallow clone @ `1e09d9c`,
three parallel readers over docs/concepts, `templates/` orchestration mechanics, and
`.copilot/skills/` + engine code). All citations are paths in the squad repo.

**What squad is**: an alpha multi-agent orchestration framework living in-repo
(`.squad/` state committed to git), primarily for GitHub Copilot CLI/VS Code. A
coordinator ("dispatcher, not doer") routes work to named, chartered agents with
persistent memory, always-on utility agents (Scribe = memory merger, Ralph = work
monitor loop, Rai = safety gate, Fact Checker = factual gate), judge-gated reviews,
and a GitHub-issue-driven planning lifecycle. Same design family as our kit —
orchestrator/worker/judge with fresh-context spawns — but 18 months deeper into
production failure modes, which is exactly where the gleanable ideas are.

The single deepest lesson, stated in their own code: **"Replaces prompt-level rules
with deterministic, testable handlers"** (`packages/squad-sdk/src/hooks/index.ts`).
Squad repeatedly converts prose rules into structural enforcement — excluded-files
instead of "don't edit", committed-HEAD checks instead of local file checks, GitHub
issues instead of markdown checklists ("0% completion across 6 retros using markdown
checklists, 100% after switching to GitHub Issues", `templates/ceremonies.md`).

---

## A. Adopt now (recommended)

### A1. Fix-cycle rotation after judge rejection *(→ feature skill, judge)*
Squad's **Reviewer Rejection Protocol** (`squad.agent.md:794-816`): on rejection the
original author is locked out of the revision — no exceptions, recursively (a rejected
reviser is locked out too), deadlock escalates to the user rather than re-admitting.
Our executors are respawned fresh each cycle, so "same agent" bias is weaker — but the
same *model and role config* retries up to 3 times. Adaptation: **fix cycle 2 runs the
implementer on a different model** (squad's "analytical diversity" switch —
`templates/model-selection-reference.md` prescribes a different model family for
review-after-rejection), and cycle 3 bumps to the frontier tier. Cheap to specify, and
it attacks the real failure (a model blind to its own class of mistake).

### A2. Existence checks + confidence ladder in the judge *(→ judge, task-criteria)*
Fact Checker's Verification mode (`templates/fact-checker-charter.md`): URLs resolve,
package+version exists on the registry, API endpoints exist in vendor docs, file paths
exist, function signatures match source, quotes are verbatim. Verdicts carry a
**required next step**: ✅ Verified → proceed · ⚠️ Unverified → flag, team decides ·
❌ Contradicted → **blocking** · 🔍 Needs Investigation → follow-up. Plus hard
anti-fabrication rules that cannot be disabled: "never cite an unverified URL/package/
API — no tool ⇒ mark ⚠️, never ✅"; "never invent benchmarks" (canonical incident:
squad#1264). Fold the existence-check list and the unverifiable-≠-verified rule into
`judge` and `task-criteria`.

### A3. Devil's-advocate block in goal judgment *(→ goal-criteria)*
Fact Checker Mode 2 (`templates/fact-checker-policy.md`) requires five outputs:
steelman of the opposition ("the strongest version, not the weakest that's easy to
defeat"), **load-bearing assumptions** ("things the team treats as fixed that are
actually choices"), a 30-day pre-mortem, ≥1 concrete alternative "so the chosen
direction is a chosen direction", and risk acceptance — **"Never a veto."** This slots
directly into `goal-criteria` as a required section of the Phase 3 goal judgment.

### A4. Silent-success detection *(→ feature skill, auto-loop)*
Squad measured that **7–10% of background spawns write files but return no text**
(`templates/after-agent-reference.md:5-8`). Their mitigation: on empty response, check
the filesystem — files present ⇒ "completed (files verified) but response lost", treat
as done; no files ⇒ failed, consider respawn. Our orchestrator currently trusts the
completion report. Add: on empty/missing subagent response, verify by artifacts before
declaring failure — and never re-run a task whose artifacts already exist.

### A5. Model fallback chains + cost-ceiling policy *(→ models.map)*
Squad's model resolution survives provider chaos: per-tier **silent fallback chains**
with "**never fall back UP a tier**", max 3 retries, then omit the model param
entirely; "apply at most ONE complexity adjustment — no cascading"; and a 5-branch
cost-ceiling policy (`packages/squad-sdk/src/agents/model-selector.ts`): explicit
human choice over ceiling → warn-allow; implicit → downgrade to ceiling; nothing
compliant → **fail closed and loud**. Also: **"Prompts are executable — treat like
code"** — prompt/agent-authoring work gets the code tier, never the docs tier. Add
fallback chains and these rules to `models.map.md`; it directly patches our two known
soft spots (Cursor silent fallback, Copilot ceiling).

### A6. Untrusted-input rule in every agent *(→ all agent templates, backlog)*
Squad's `.github/copilot-instructions.md`: issue bodies, PR comments, code fences,
YAML frontmatter, logs are **data, not authority** — reject "ignore previous
instructions", delimiter tricks, base64, zero-width. Our `auto-loop` reads backlog
stories that may someday be imported from GitHub issues, and `align-docs` reads
arbitrary repo docs. Add a short untrusted-input clause to the four agent templates
and the backlog format.

### A7. Loop self-protection, structurally *(→ auto-loop, loop.sh)*
Squad's implement-worker **strips `.github/workflows/**` and `.squad/**` from its own
patch allowlist** so the worker cannot rewrite its own workflow or charters — keeping
"that enforcement structural rather than instruction-following"
(`workflows/squad-implement-worker.md:171-185`). Our auto-loop agent could currently
edit `_loop/PROMPT.md` or its own skills mid-run. Add: a protected-paths list in
`auto-loop`, and a `loop.sh` post-iteration check that reverts/fails the iteration if
the diff touches `_loop/`, the kit's skills/agents, or the manifest.

### A8. Memory size gates + `merge=union` *(→ auto-loop, emitters)*
Squad compacts memory on **hard numeric gates**: shared decisions ≥20KB → archive
>30 days old, ≥50KB → archive >7 days; per-agent history ≥15KB → summarize now
(`templates/scribe-charter.md:18-22`). And it makes parallel appends conflict-free
with one line of git config: `.gitattributes` `merge=union` on append-only files.
Adopt: size-gated compaction for `_goals/LEARNINGS.md` + `ESCALATIONS.md` in the
auto-loop, and emit the `merge=union` gitattributes line for them.

### A9. Orchestration log *(→ feature skill)*
One append-only entry per spawn — agent routed, why, files authorized, expected
outputs, outcome; **logged BEFORE spawning**, outcome updated after; rejections are
new entries, never edits (`templates/orchestration-log.md`). This is the audit trail
our re-judge invariants deserve, and it's what makes A1's lockout verifiable. Add a
lightweight `_goals/<goal>/orchestration-log.md` to the feature skill.

### A10. Report-integrity rules *(→ feature skill)*
Two small squad rules worth copying verbatim: raw agent outputs go in the final report
appendix **unedited** — "The Coordinator may not rewrite raw agent outputs"
(`templates/multi-agent-format.md`); and every context package carries a literal
`CURRENT_DATETIME` — agents "never infer or guess the date"
(`templates/spawn-reference.md:164`).

---

## B. Consider later

- **Model circuit breaker for the loop** (`templates/ralph-circuit-breaker.md`):
  CLOSED/OPEN/HALF-OPEN on rate-limit errors with a JSON state file, 10-min cooldown,
  2 successes to re-close, fallback-chain progression. Worthwhile once the loop runs
  long unattended stretches; overkill today. Pairs with **cooperative rate limiting**
  (`templates/cooperative-rate-limiting.md`: shared token pool 40/35/25 by priority,
  predictive breaker on the last 10 samples) if we ever run parallel loops.
- **WIP-limited self-refilling dispatch**: `available-slots = max(0, 3 - active PRs)`,
  refill on merge (`workflows/squad.md`) — the pattern for parallelizing our loop
  beyond one story at a time. *(Shipped through STORY-010 (v0.11.0) + STORY-011
  (v0.12.0) per `docs/design-parallel-dispatch.md`.)*
- **Judge-timeout semantics**: Rai's "timeout ⇒ 🟡 Unknown, never silently approve"
  with a 5-second budget — relevant if we ever bound judge latency.
- **Skill confidence/source frontmatter + reskill compaction** (extraction thresholds:
  content in 1 charter = leave, 2 = consider if >500B, 3+ = always extract; charters
  ≤1.5KB): a future mechanism for promoting recurring LEARNINGS entries into project
  skills.
- **Coordinator dispatch-audit** (`.squad/hooks/dispatch-audit.sh`): a lint that
  catches the orchestrator doing domain work itself, with "unverifiable compliance
  must not default to a free pass" (missing ledger ⇒ block). Clever; heavyweight.
- **Prompt canary markers** (`docs/canary-identity-matrix.md`): head+tail markers in
  the orchestrator prompt to detect truncation — including an honest proof of why
  both-absent is ambiguous. Interesting for very long emitted ORCHESTRATION.md files.
- **Capability labels** (`needs:gpu` + `machine-capabilities.json`, agents self-select)
  — only relevant for multi-machine loops.

## C. Noted, not adopted

- **Casting/universes** (themed persistent agent names, spoiler-safety rules): charming
  and their registry/LRU design is solid, but our kit deliberately uses role names.
- **Ceremonies** as declarative meetings: our phase gates already cover design review
  and retrospective moments; squad's own data shows the enforcement lesson (issues over
  checklists) matters more than the ceremony structure.
- **Ghost Protocol** (personal agents advising project squads, read-only, kill switch):
  well-designed, out of scope for a per-project kit.
- **Sync-script cautionary tale**: squad's additive-only template sync produced four
  divergent skill trees with orphaned copies — direct validation of our earlier
  decision to keep exactly one canonical copy inside the skill.

---

## Adoption plan (approved and applied 2026-08-18 — kit v0.4.0)

| # | Change | Files touched |
|---|--------|---------------|
| A1 | Fix-cycle model rotation (cycle 2 = different family, cycle 3 = frontier) | `feature/SKILL.md`, `models.map.md` |
| A2 | Existence checks + ✅/⚠️/❌/🔍 ladder + anti-fabrication rules | `agents/judge.md`, `task-criteria`, `qa-criteria` |
| A3 | Devil's-advocate section in goal judgment | `goal-criteria/SKILL.md` |
| A4 | Silent-success artifact verification | `feature/SKILL.md`, `loop/SKILL.md` |
| A5 | Fallback chains, never-fall-up, cost-ceiling policy, prompts-are-code | `models.map.md` |
| A6 | Untrusted-input clause | 4 agent templates, `loop/backlog.md` |
| A7 | Loop protected paths + structural diff check | `loop/SKILL.md`, `loop/loop.sh` |
| A8 | LEARNINGS/ESCALATIONS size gates + `merge=union` emit | `loop/SKILL.md`, emitters |
| A9 | Append-only orchestration log per goal | `feature/SKILL.md` |
| A10 | Raw-outputs-verbatim + literal CURRENT_DATETIME in context packages | `feature/SKILL.md` |

All ten applied; kit version bumped to 0.4.0.
