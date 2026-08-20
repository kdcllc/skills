# Token-efficient skills, instructions hygiene, and cheaper command execution

**Date**: 2026-08-20 · **Status**: the P0 invocation flags and the P1 `terminal`
agent are shipped — vehicle `_goals/invocation-flag-hygiene/`. **Feeds**: a
still-future `_goals/` for the quiet-command `/setup` interview, `reference/`
demotion, Copilot inline-legacy cleanup, and always-on pointer hygiene (none of
those shipped here).

**Method**: external deep-research report ingested against kit ground truth
(`skills/setup/reference/harness-matrix.md`, `docs/research-multi-harness-upgrade.md`
§1.3, `emitters/copilot.md`, canonical templates). Full scratch report:
`_research/token-efficient-skills-and-instructions/report.md` (gitignored). Seed
articles:

- [Maximizing the value of your Claude Code sessions](https://claude.com/blog/maximizing-the-value-of-your-claude-code-sessions)
- [Instructions Hygiene](https://devblogs.microsoft.com/dotnet/instructions-hygiene-what-frontier-models-still-need-you-to-say/)
- [Stop skillmaxxing, save your tokens](https://developer.microsoft.com/blog/stop-skillmaxxing-save-your-tokens/)

Harness capability cells from this work live in
`skills/setup/reference/harness-matrix.md` (2026-08-20 addendum). That table is
source of truth for emitters; this file is the product verdict and backlog.
`_goals/invocation-flag-hygiene/` owns the status line, skill-verdicts, backlog
rows, and terminal-agent-spec section below that it changed.

---

## Load-bearing conclusions

1. Session start injects skill **name + description only**. Nine kit skills ≈
   500–900 tokens/session. The urgent cost is **auto-fire and double-loading**, not
   raw description size.
2. `disable-model-invocation: true` is the same key on Claude Code, Cursor, and
   Copilot skills. Seven of the kit's nine skills now set it, shipped by
   `_goals/invocation-flag-hygiene/`; `feature` and `research` stay
   auto-invocable by design.
3. Copilot `.github/skills/*/SKILL.md` is first-class. Inlining skill bodies into
   agents is a legacy fallback, not the current default we should keep using.
4. A light-tier **`terminal` agent** (Bash/Read only, compact `{exit, excerpt, log
   path}` return) is emit-able on all three IDEs. Copilot has no documented Bash
   output size cap; Claude’s `BASH_MAX_OUTPUT_LENGTH` defaults to 30,000
   characters. Quiet command forms are captured at `/setup`, never invented.
5. **Copilot cost ceiling blocks pinning up, not down.** A Copilot `terminal`
   (and the existing workers) pin the **light** tier under a frontier parent.
   The research report’s “Copilot subagents run frontier” reading is rejected.
6. Do not save tokens by weakening frontier judges, verbatim-report integrity,
   fresh-context workers, or Cursor `.mdc` rules.

## Skill verdicts

| Skill | Verdict | First implementation move |
|-------|---------|---------------------------|
| `feature` | Keep auto-skill; later split thin SKILL.md + reference | Tighten description |
| `research` | Keep auto-skill | Tighten description |
| `align-docs` | Manual | `disable-model-invocation: true`; keep `/align-docs` |
| `ship-pr` | Manual | `disable-model-invocation: true`; keep `/ship-pr` |
| `auto-loop` | Loop-driver only | `disable-model-invocation: true` |
| `test-ladder` | Single load path | Flag off auto-invoke **or** demote to `reference/test-ladder.md`; context packages still cite it |
| `goal-criteria` / `task-criteria` / `qa-criteria` | Judge-only | Same as ladder. Lowest-migration: flag in the skills tree. Do not inline the two large files into `judge.md` |

**Flag in place for all seven** (`align-docs`, `ship-pr`, `auto-loop`,
`test-ladder`, `goal-criteria`, `task-criteria`, `qa-criteria`) — shipped by
`_goals/invocation-flag-hygiene/`. Open question 2 (below) resolved: stop at
the flag; the `reference/` demotion in the "First implementation move" column
above was **not** taken in this goal.

`test-ladder`'s previous worst-of-both-worlds shape — `user-invocable: true`
plus routing into every implement/test context package (`feature/SKILL.md`) —
is closed: `disable-model-invocation: true` now sits alongside
`user-invocable: true` on `test-ladder/SKILL.md`. The routing into context
packages is unchanged by design (it is an explicit path-cite, not
auto-invocation).

## Terminal agent (shipped)

Shipped by `_goals/invocation-flag-hygiene/` on Claude Code, Cursor, and
Copilot as first-class agents, plus a Codex `[agents.terminal]` registration
so the glob-copied `terminal.md` is not dangling. Canonical Claude source:
`templates/agents/terminal.md`.

- **Tools:** Bash (which also invokes `pwsh` / `powershell.exe` when the spawn
  prompt is PowerShell) + Read. No Edit/Write tools. Any Bash or PowerShell
  command the caller asked for — not limited to tests or git.
- **Model:** light (`haiku` / `{{MODEL_LIGHT}}` / `{{COPILOT_MODEL_LIGHT}}`).
  Cursor: pin on the translated `.cursor/agents/terminal.md` (no skill model key).
  Codex: `.codex/agents/terminal.toml` gets the same light pin via
  `[agents.terminal]` in `config.toml`.
- **Return:** only the result the spawn prompt asked for (exit code, last N
  lines, a match, pass/fail, a path). Default if unspecified: exit code; ≤30-line
  excerpt (kit convention for ≤N-line) or “all passed”; log path when truncated
  or non-zero. No Edit/Write, no extra commands, no advice.
- **Spawn:** any calling agent sends an exact Bash or PowerShell command plus
  the result shape it needs. Rung 3 is always a `terminal` spawn so the full
  suite never lands in the frontier session. That is delegation, not the
  orchestrator executing product code; rung-3 **authority** stays Phase 5 after
  APPROVED. On a truncated or non-zero result, the caller **Reads** the log
  path (or a targeted slice). `implementer` / `test-writer` keep small rungs 1–2
  inline and may spawn `terminal` for a noisy command where nesting exists.
- **Copilot nesting** is off by default
  (`chat.subagents.allowInvocationsFromSubagents`) and this goal does **not**
  turn it on as a kit default. Until nesting is a kit default or an installer
  choice, the orchestrator (L1) spawns `terminal` on Copilot.
- **Hooks:** still optional belt-and-suspenders on Claude (PreToolUse) and
  Cursor (`beforeShellExecution`) — not shipped by this goal. Copilot
  shell-rewrite hooks are not the documented path — rely on the agent + quiet
  flags.

## Always-on pointer target

Keep the three short pointers (`CLAUDE.md`, `copilot-instructions.md`,
`.cursor/rules/orchestration.mdc`). After hygiene they should be ~15–25 lines:
orchestrator coordinates / never edits product code; implementation →
implementer/test-writer; verification → judge/qa-judge; noisy commands →
`terminal`; captured quiet test/build commands; Copilot ceiling note. Do **not**
inline `ORCHESTRATION.md` (659 lines). Change `feature/SKILL.md` from “its
invariants are binding” (whole-doc required reading) to “read the section for
the current phase.”

## Prioritized backlog (P0/P1-terminal/P2-test-guard shipped by `_goals/invocation-flag-hygiene/`)

| Pri | Change | Effect | Status |
|-----|--------|--------|--------|
| P0 | `disable-model-invocation: true` on `auto-loop`, `align-docs`, `ship-pr`, `*-criteria` | Session-start metadata + auto-fire gone for six skills | **Shipped** — `_goals/invocation-flag-hygiene/` |
| P0 | Single load path for `test-ladder` and criteria (flag first; `reference/` demotion optional follow-up) | Stops double-loading | **Shipped** (flag only — `reference/` demotion not taken) — `_goals/invocation-flag-hygiene/` |
| P1 | Emit `terminal` agent on all three harnesses; spawn rules in ORCHESTRATION.md | Command output leaves the frontier context | **Shipped by this goal** — `_goals/invocation-flag-hygiene/` |
| P1 | `/setup` interview: quiet form of targeted/full test commands | No invented flags | Not this goal |
| P1 | Copilot emitter: `.github/skills/` default; inline = legacy-only | Stops body duplication in agents | Not this goal |
| P1 | Always-on + “binding” language hygiene | Stops whole-architecture pull into `/feature` | Not this goal |
| P2 | Split `feature` (181) / `auto-loop` (208) SKILL.md | Smaller per-turn body once invoked | Not this goal |
| P2 | Test guard: fail if criteria/`auto-loop` are auto-invocable | Regression lock | **Shipped by this goal** — `_goals/invocation-flag-hygiene/` |
| P2 | Setup-report MCP / `/context` warning | User education; kit does not emit MCP | Not this goal |
| P2 | Path-scoped lane rules (Copilot `applyTo`, Cursor `globs`, Claude `paths:`) | Test/docs/PR rules stay out of unrelated sessions | Not this goal |

## Non-goals

Do not: move judges to the light tier; drop verbatim-report integrity; stuff
criteria or architecture into always-on files; merge skills into one mega-skill;
auto-invoke a pile of domain skills; fold the loop into a long-lived chat; give
`terminal` edit tools.

## Open questions (1–3 resolved by `_goals/invocation-flag-hygiene/`; 4 still open)

1. Enable Copilot nested subagents as kit default, or leave it an installer
   choice? **Resolved: not a kit default.** Nesting
   (`chat.subagents.allowInvocationsFromSubagents`) stays off; the
   orchestrator (L1) spawns `terminal` on Copilot instead.
2. Stop at the invocation flag for criteria/ladder, or also demote them off the
   skills tree to `reference/` in the same change? **Resolved: flag in
   place.** The flag ships; `reference/` demotion is not taken in this goal.
3. Run Phase 6 (`align-docs`) and Phase 7 (`ship-pr`) as **new sessions**, or
   keep them in the same `/feature` conversation? **Deferred (path-Read).**
   They stay in the same conversation; `feature/SKILL.md` loads each by path
   rather than inlining or opening a new session.
4. Exact Copilot terminal-output size behavior (undocumented). Does not block
   shipping `terminal` + quiet flags.
