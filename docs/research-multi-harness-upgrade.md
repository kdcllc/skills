# Research Report & Upgrade Plan: Multi-Harness Orchestration Kit

**Date**: 2026-08-18 · **Method**: deep-research workflow (5 search angles, 25 sources
fetched, 119 claims extracted, 25 adversarially verified by 3-vote panels: 24 confirmed,
1 refuted) plus manual spot-verification of Codex claims against live official docs.

**Question**: How to upgrade this kit so one canonical template source serves GitHub
Copilot, Cursor, Claude Code, and OpenAI Codex, with per-agent model pinning
(frontier for orchestrator/judges, light models for code generation), running as a
fully autonomous feature-by-feature loop.

**Verification legend**: ✅ = confirmed 3-0 against official docs by the adversarial
panel · 🔎 = primary source, spot-verified manually against live docs · ⚠️ = primary
source, unverified · 💬 = blog/secondary, unverified.

---

## Part 1 — Findings

### 1.1 The headline: `.claude/` is the de-facto interchange format

The single most consequential finding for a one-source design:

- **Cursor natively reads `.claude/agents/` and `.codex/agents/`** (project and user
  level) in addition to `.cursor/agents/`, with `.cursor/` winning name conflicts. ✅
  ([cursor.com/docs/subagents](https://cursor.com/docs/subagents))
- **Cursor also loads `.claude/skills/` and `.codex/skills/` trees** alongside
  `.agents/skills/` and `.cursor/skills/`. ✅
  ([cursor.com/docs/skills](https://cursor.com/docs/skills))
- **VS Code (Copilot) natively reads the `.claude/agents` folder** with Claude-specific
  frontmatter, alongside `.github/agents` (workspace) and `~/.copilot/agents` (user). ✅
  ([code.visualstudio.com custom-agents](https://code.visualstudio.com/docs/agent-customization/custom-agents))

**Consequence**: the kit's canonical template format should be the Claude Code format
(which it already is). Cursor and VS Code consume it with at most thin adaptation;
only Codex needs a genuinely different compile target. Caveat (medium confidence):
directory *loading* is confirmed; per-field fidelity of Claude-specific frontmatter keys
(`tools:` allowlists, model aliases, `effort:`) in the other harnesses is undocumented —
so per-harness translated copies are still safer than a single shared tree for the
agents' model/tools keys.

### 1.2 Per-harness capability matrix

| Capability | Claude Code | Cursor | Copilot (VS Code) | OpenAI Codex |
|---|---|---|---|---|
| Agent definition | `.claude/agents/*.md`, YAML frontmatter ✅ | `.cursor/agents/` + reads `.claude/agents/`, `.codex/agents/` ✅ | `.github/agents/*.agent.md` (renamed from `.chatmode.md`) + reads `.claude/agents` ✅ | `[agents.<name>]` tables in `config.toml` with `config_file` + `description` 🔎 |
| Skills | `.claude/skills/SKILL.md` ✅ | `.cursor/skills/` + reads `.claude/skills/`; schema: `name`+`description` required, NO model key ✅ | skills supported (per ruler/AIS matrices ⚠️) | `skills.config` per-skill enablement 🔎 |
| Fresh-context subagents | Yes; nesting depth 3 by default via `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (default flipped twice in July 2026 — pin explicitly) ✅ | Yes; parallel/background; nesting main→L1→L2 since 2.5 (cloud agents: L1 only) ✅ | Yes, via `agent/runSubagent`; stateless, no follow-ups; nesting off by default (`chat.subagents.allowInvocationsFromSubagents`, max depth 5) ✅ | Yes: `spawn_agent`/`send_input`/`resume_agent`/`wait_agent`/`close_agent`, `features.multi_agent` stable & on by default 🔎 |
| Per-agent model pin | Frontmatter `model:` (aliases/full IDs/`inherit`); resolution: env var > Agent-tool param > frontmatter > parent. Cheaper-than-parent OK ✅ | Frontmatter `model` incl. bracket params `claude-opus-5[effort=high,context=300k]`; cheaper OR stronger OK; **silently falls back** under admin/plan restrictions ✅ | Frontmatter `model` (string or fallback array); **cost ceiling: subagent cannot exceed parent's tier** — stronger refuses to run (reports available models); CLI rejects array form ✅ | `agents.default_subagent_model`, per-role `config_file` layers, `agents.default_subagent_reasoning_effort`; spawn-time model wins 🔎 |
| Effort/reasoning pin | `effort:` (low→max) on agents, skills, commands ✅ | bracket param `[effort=...]` ✅ | — | `default_subagent_reasoning_effort` 🔎 |
| Repo-committable model config | Yes — agents/skills/commands frontmatter + `model` in project settings; managed/project > user's `/model` ✅ | Yes — frontmatter ✅ | Yes — frontmatter ✅ | Yes — project `.codex/config.toml` (trusted projects), but `model_provider`, `model_providers`, `profile(s)`, `notify`, `otel` etc. are ignored at project level 🔎 |
| Rules/instructions | `CLAUDE.md` (does NOT read AGENTS.md; standard workaround: import it from CLAUDE.md 💬) | `.cursor/rules/*.mdc` ONLY (plain `.md` silently ignored); 3 frontmatter keys (`alwaysApply`, `description`, `globs`) → 4 activation modes; also native AGENTS.md incl. nested ✅ | `.github/copilot-instructions.md`, `.github/instructions/` | AGENTS.md: global → root-down concatenation, nearest-last-wins; `project_doc_max_bytes` cap **32 KiB default**; read once at session start 🔎 |
| Orchestrator role controls | `tools: Agent(worker, judge)` spawn allowlists; 20 concurrent default ✅ | delegation via description or `/name`; L1 agents often need explicit "you MUST spawn" prompting (forum reports) ✅ | `agents:` allowlist, `user-invocable: false` (subagent-only), `disable-model-invocation: true`; subagents lack clarifying-question/todo tools ✅ | role `description` guides spawn choice 🔎 |
| Unattended mode | headless `claude -p`, `--output-format json`, `--continue/--resume` ⚠️ | Cloud Agents (L1 nesting only) ✅ | Copilot coding agent on GitHub issues ⚠️ | `approval_policy: never` + `sandbox_mode: read-only\|workspace-write\|danger-full-access` 🔎 |

**Refuted claim (0-3)**: the exact required/optional frontmatter key set for
`.cursor/agents` files (`name`/`description` required; `model`/`readonly`/`is_background`
optional). Re-verify the live Cursor schema before writing the Cursor emitter.

**Format friction points a compiler must handle**:
- Cursor rules must be `.mdc` — emitting `.md` into `.cursor/rules` is silently ignored. ✅
- `.claude/agents` files use comma-separated-string `tools:`; `.agent.md` uses YAML arrays. ✅
- Cursor skills have no model key — model pinning must live at the agent level for Cursor. ✅
- Codex AGENTS.md has no frontmatter at all — no schema for agents/models; all role and
  model configuration goes in `config.toml`. 🔎

### 1.3 Model tiering: what the evidence says

- **Cheap executors work; don't cheap out on the orchestrator/judge.** An Anthropic
  benchmark cited by Arize: a frontier-class orchestrator directing Sonnet-class workers
  retained **96% of an all-frontier team's BrowseComp score at 46% of the cost**; the
  same article argues delegation and judging have a capability floor. 💬
- **LLM-as-judge guidance** (Evidently): start with the strongest available judge model,
  downgrade only after evidence a cheaper judge agrees with it. 💬
- **Counter-evidence**: an April 2026 benchmark found a solo frontier model in a single
  harness matched or beat forced planner+executor mixed-model splits on a single-lane
  task (97/100 in 18 min, ~$4). Tiering pays off with parallel fan-out volume, not on
  one sequential lane. 💬
- **The ralph playbook** prescribes exactly the kit's shape: strong model for the loop
  driver (task selection/prioritization), cheap models for read/search/build subagents. ⚠️

**Harness-specific consequences**:
1. **Copilot's cost ceiling inverts the kit's economics**: a judge cannot be pinned
   *stronger* than the session model. On Copilot, the main session must run the frontier
   tier and workers pin down; never rely on pinning up.
2. **Cursor silently falls back** to a compatible model under team-admin/plan
   restrictions instead of erroring — a judge that must not degrade should state its
   expected model in its prompt and self-report which model produced the verdict.
3. **Model IDs rotate fast** (fable, composer-2, gpt-5.6-sol, claude-opus-5 are all
   current-cycle names). Model names must be **configuration, not template constants**.

### 1.4 Autonomous feature-by-feature loops (ralph pattern)

All primary-source (the canonical ghuntley repo + two implementation repos + playbook),
none panel-verified ⚠️:

- **Core mechanism**: `while :; do cat PROMPT.md | claude ; done` — a fixed prompt
  re-fed to a headless CLI, each iteration a **fresh context**, completing **exactly one
  task and one commit**. The loop, not the model, is the primary driver of results.
- **State persistence** — files + git, never conversation memory:
  - a prioritized backlog (`IMPLEMENTATION_PLAN.md` or `prd.json` with `passes: false`
    per story; the loop pulls the highest-priority incomplete item),
  - `AGENTS.md` as an append-only store of operational learnings written back each
    iteration (exploiting the cross-harness convention),
  - `specs/` for requirements; git history as durable memory.
- **Runaway guards** observed across implementations:
  - max-iterations cap (e.g. `./loop.sh 20`; snarktank/ralph defaults to 10),
  - rate limits (100 calls/hour) and token budgets (`MAX_TOKENS_PER_HOUR`),
  - circuit breaker: open after 3 no-progress loops or 5 same-error loops,
  - dual-condition exit: heuristic completion indicators AND an explicit sentinel
    (`EXIT_SIGNAL: true` / `<promise>COMPLETE</promise>`) — string matching alone is
    unreliable,
  - one-task-per-iteration scope rule; backlog items sized to one context window.
- **Merge gating ("backpressure")**: commit only when typecheck/tests/build pass, run by
  a dedicated validation subagent; programmatic verification beats self-assessment;
  LLM-as-judge gates for subjective criteria, iterated-until-pass rather than one-shot.
- **Documented failure modes**: unbounded cost ($50–100+ without converging), unreliable
  exact-string completion detection, iteration caps not preventing early destructive
  actions (hence sandbox + minimal credentials, since loops often run with permissions
  skipped), loop drift/circling.
- **Codex equivalent**: `approval_policy: never` + `sandbox_mode: workspace-write` is
  the official unattended configuration. 🔎

### 1.5 Cross-tool sync tooling precedents

- **ruler** ([intellectronica/ruler](https://github.com/intellectronica/ruler), beta) —
  the build-step-generator precedent: canonical `.ruler/` dir + `ruler.toml`,
  `ruler apply` distributes to 30+ harnesses, skills propagation to native skill dirs,
  **experimental subagent propagation for exactly our four harnesses**, centralized MCP
  config. Design choice worth noting: generated files are **gitignored build artifacts**
  with a `ruler revert` command. ⚠️
- **ai-rules-sync** — symlink federation (not a compiler): global cache + per-project
  symlinks + committed manifest (`ai-rules-sync.json`) with `ais install` for team
  re-bootstrap. Its support matrix lists **no subagent asset type for Codex** (predates
  Codex multi-agent going stable). ⚠️
- **AGENTS.md** — read by 20+ tools, 60k+ repos, stewarded by the Agentic AI Foundation
  (Linux Foundation). Plain markdown, no schema — the lowest-common-denominator
  instruction channel, not an agent-definition format. Claude Code is the notable
  non-reader (uses CLAUDE.md; standard fix is importing AGENTS.md from it). 💬

### 1.6 Open questions (not resolved by this research)

1. Per-field fidelity when Cursor/VS Code load a `.claude/agents` file — which
   Claude-specific keys are honored vs silently ignored (test empirically).

   > 2026-08-18 empirical update (CLI-observed): Claude Code (native, raw
   > `.claude/agents` tree) honors `name` and `description` verbatim — verified via
   > nonce-instrumented probes with an active file-read denial set and a decoy
   > negative control. `tools:` is partial: the injected pair (`WebSearch,
   > WebFetch`) was returned correctly (injected-key test), but the same reply also
   > asserted file-visibility facts (directory contents, exact frontmatter
   > key-order/formatting) that the active `Read,Grep,Glob,Bash` denial should have
   > made unobservable, so the cell is downgraded from `honored` to `partial`
   > rather than taken at face value. `model`/`effort` fidelity is untestable — no
   > introspection surface exposed model/effort metadata under `-p`/`--debug`. The
   > Cursor and Copilot arms of this question are untestable: Cursor was gated
   > pre-budget (`cursor-agent models` → no models available for this account,
   > though the account is logged in); Copilot lost authentication mid-session
   > (auth error on the first call after a clean auth smoke test). See
   > `skills/setup/reference/harness-matrix.md` § Empirical validation (2026-08-18,
   > CLI-observed).
   >
   > **Re-probe update:** a user-authorized re-auth and re-probe restored Copilot
   > access and re-ran the recognition and tools probes across both the native
   > `.github/agents/judge.agent.md` tree and the raw `.claude/agents` tree.
   > `name` and `description` landed at `partial (confound: file-read not
   > deniable)` on both trees, and `tools` at `partial` on the native
   > `.agent.md` tree (the raw tree's `tools:` injection sits on
   > `implementer.md` and was not probed) — Copilot exposes no file-read denial mechanism
   > (`copilot help permissions` documents only `shell()/write()/<mcp-server>()/
   > url()` kinds, no Read/Grep/Glob-equivalent), so no Copilot cell can clear
   > `honored` regardless of nonce fidelity. Observed once (CLI-observed, n=1):
   > with same-named `judge` agents in both `.github/agents` and `.claude/agents`,
   > only the native one surfaced in the recognition reply; mechanism unconfirmed —
   > reply-level dedup of same-named agents not excluded. Do not treat as a
   > precedence rule. `model`/`effort` remain untestable — the native `.agent.md`
   > fixture omits both keys. See `skills/setup/reference/harness-matrix.md` §
   > Empirical validation (2026-08-18, CLI-observed).
2. Exact current `.cursor/agents` frontmatter schema (the one refuted claim).

   > 2026-08-18 empirical update (CLI-observed): NO evidence was obtained. A
   > dual-emission fixture (`hv-cursor/`: raw `.claude/` tree plus distinct-named
   > `.cursor/agents/*-cursor` translated copies) was built specifically to test
   > schema acceptance, but the Cursor arm was gated before any probe budget was
   > spent — `cursor-agent models` reported "No models available for this
   > account" (`cursor-agent status` separately confirmed the account is logged
   > in, so this is a model-availability restriction, not an auth failure). This
   > question remains open. See `skills/setup/reference/harness-matrix.md` §
   > Empirical validation (2026-08-18, CLI-observed).
3. Quantitative judge-model-strength thresholds for reliable LLM-as-judge gating.
4. Copilot coding agent (GitHub-issue-driven) specifics for the autonomous loop.

---

## Part 2 — Upgrade Plan (approved 2026-08-18; phases A–C implemented in kit v0.2.0, D partially — local validation only; harness validation and E pending)

### Design decisions

1. **Canonical format stays Claude Code** (`agents/*.md` + `skills/*/SKILL.md`) — it is
   the de-facto interchange format (§1.1). The existing templates barely change.
2. **The bootstrap becomes a compiler** with four per-harness *emitters*. Emitted files
   are committed (not gitignored à la ruler) because target projects need them to work
   without the kit installed — but each emitted file gets a generated-by header + kit
   version for upgrade detection.
3. **Model tiers become configuration**: templates reference `{{MODEL_FRONTIER}}` /
   `{{MODEL_LIGHT}}` tier tokens; a per-harness model map (filled at bootstrap, easy to
   re-run when IDs rotate) resolves tiers to concrete IDs. Role assignment: orchestrator
   + judge + qa-judge = frontier tier; implementer +
   test-writer = light tier, with `effort:` pinned where supported.
4. **Autonomous loop as a new layer**, off by default, gated on the judge verdicts the
   kit already produces: backlog file → one feature per iteration through the existing
   5-phase flow → commit only on judge-PASS + green targeted tests → sentinel +
   circuit-breaker exits.
5. **Kit versioning**: a `VERSION` file in the kit; bootstrap writes an
   `orchestration-kit.manifest.json` (version + emitted file list + hashes) into the
   target project so a re-run can diff, upgrade, or cleanly regenerate.
6. **Distribution via [skills.sh](https://www.skills.sh/)**: the kit should be listed on
   the skills.sh registry so projects install it with
   `npx skills add kdcllc/skills --skill agent-kit` instead of manual `cp -r`. The repo already
   matches the expected layout (`skills/<name>/SKILL.md` in a GitHub repo), and skills.sh
   installs into 20+ harnesses — which also covers first-mile delivery for Copilot,
   Cursor, and Codex before our emitters run. Requirements: the GitHub repo must be
   public, and the `VERSION`/manifest scheme from decision 5 should align with registry
   updates (users re-run `npx skills add` to upgrade, then re-run the bootstrap).

### Repo changes

```
skills/setup/
├── SKILL.md                     # REWRITE: detect harness(es) → inspect → interview →
│                                #   compile via emitter(s) → verify → write manifest
├── VERSION                      # NEW: kit semver
├── reference/
│   └── harness-matrix.md        # NEW: §1.2 capability table + friction points, for the
│                                #   bootstrap agent to consult while emitting
├── emitters/                    # NEW: one instruction file per target
│   ├── claude-code.md           #   .claude/agents + .claude/skills + CLAUDE.md pointer;
│   #                                pin CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH in settings
│   ├── cursor.md                #   reuse .claude/ tree (native read) + .cursor/rules/
│   #                                orchestration.mdc (alwaysApply pointer rule, .mdc not .md!)
│   #                                + translated .cursor/agents copies with Cursor model IDs
│   #                                [effort=...] brackets; re-verify live schema first (§1.6.2)
│   ├── copilot.md               #   .github/agents/*.agent.md (tools as YAML arrays, agents:
│   #                                allowlist, user-invocable:false for workers/judges, model
│   #                                fallback arrays) + .github/copilot-instructions.md pointer;
│   #                                NOTE: session must run frontier tier (cost ceiling)
│   └── codex.md                 #   AGENTS.md (root ≤ ~300 lines, mind 32KiB cap; nested per
│   #                                lane) + .codex/config.toml with [agents.<role>] tables,
│   #                                per-role config_file layers pinning models/effort
├── templates/                   # canonical source (Claude format, mostly as today)
│   ├── models.map.md            # NEW: tier → per-harness model ID table, filled at bootstrap
│   ├── agents/*.md              # EDIT: model: {{MODEL_FRONTIER|MODEL_LIGHT}} + effort: key
│   ├── skills/...               # unchanged content; feature gains a
│   │                            #   "harness notes" section (spawn syntax per harness)
│   ├── loop/                    # NEW: autonomous loop layer
│   │   ├── SKILL.md             #   /autonomous-loop skill: pull next backlog item → run
│   │   │                        #   5-phase flow → gate on judge PASS + tests → commit →
│   │   │                        #   update backlog + learnings → sentinel/limits check
│   │   ├── loop.sh              #   headless driver (claude -p) with max-iterations,
│   │   │                        #   token/call budget, circuit breaker (3 no-progress /
│   │   │                        #   5 same-error), dual-condition exit sentinel
│   │   ├── PROMPT.md            #   the fixed per-iteration prompt (one feature, one commit)
│   │   └── backlog.md           #   _goals/backlog.md format: prioritized stories with
│   │                            #   passes/attempts fields, sized to one context window
│   └── ORCHESTRATION.md  # EDIT: add harness matrix, model-tier table,
│                                      #   autonomous-loop section with guards
└── (root) README.md             # EDIT: four-harness install matrix + loop quickstart
```

### Sequencing

1. **Phase A — model tiers + matrix** (small): tier tokens in agent templates,
   `models.map.md`, `reference/harness-matrix.md`, architecture-doc updates.
2. **Phase B — emitters** (core): rewrite `SKILL.md` as the compiler; write the four
   emitter files; add VERSION + manifest logic.
3. **Phase C — autonomous loop**: `templates/loop/` + architecture-doc section.
4. **Phase D — validation**: bootstrap into one scratch project per available harness;
   empirically test the §1.6 open questions (frontmatter fidelity) and fold results
   back into `harness-matrix.md`.
5. **Phase E — publish**: make the GitHub repo public and list the kit on
   [skills.sh](https://www.skills.sh/) (design decision 6) so it installs via
   `npx skills add kdcllc/skills --skill agent-kit`.

### Risks / caveats to carry into implementation

- This space is fast-moving: the chatmode→agent rename, the Claude Code nesting default
  flipping twice in four days, docs URLs shifting. The harness-matrix file should carry
  "verified on <date>" stamps and the bootstrap should degrade gracefully when a key is
  rejected.
- Codex remains the weakest target: no agent markdown format, 32 KiB instruction cap,
  and no project-level `model_provider` override — role definitions there are TOML +
  prose, structurally different from the other three.
- Loop safety: ship with conservative defaults (10 iterations, judge-gated commits,
  never `--dangerously-skip-permissions` outside a sandbox) and document the
  cost-runaway failure mode prominently.

---

## Sources

Panel-verified (3-0), official docs: [code.claude.com sub-agents](https://code.claude.com/docs/en/sub-agents) ·
[code.claude.com model-config](https://code.claude.com/docs/en/model-config) ·
[code.claude.com settings](https://code.claude.com/docs/en/settings) ·
[cursor.com/docs/subagents](https://cursor.com/docs/subagents) ·
[cursor.com/docs/rules](https://cursor.com/docs/rules) ·
[cursor.com/docs/skills](https://cursor.com/docs/skills) ·
[VS Code custom agents](https://code.visualstudio.com/docs/agent-customization/custom-agents) ·
[VS Code subagents](https://code.visualstudio.com/docs/agents/run/subagents)

Primary, spot-verified manually 2026-08-18: [Codex config reference](https://developers.openai.com/codex/config-reference) ·
[Codex AGENTS.md guide](https://developers.openai.com/codex/guides/agents-md)

Primary, unverified: [ghuntley/how-to-ralph-wiggum](https://github.com/ghuntley/how-to-ralph-wiggum) ·
[frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) ·
[snarktank/ralph](https://github.com/snarktank/ralph) ·
[intellectronica/ruler](https://github.com/intellectronica/ruler) ·
[lbb00/ai-rules-sync](https://github.com/lbb00/ai-rules-sync)

Secondary/blog, unverified: Arize (multi-agent economics) · Evidently (LLM-as-judge) ·
ralph-playbook (claytonfarr) · akitaonrails mixed-model benchmark · codersera AGENTS.md
guide · paddo.dev / devinterrupted (ralph history, Gas Town/MEOW)
