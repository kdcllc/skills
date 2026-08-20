# Token-efficient skills, instructions hygiene, and cheaper command execution

**Date**: 2026-08-20 · **Status**: researched, not yet implemented · **Feeds**: a
future `_goals/` for invocation-flag hygiene, reference-file demotion, a `terminal`
agent, and always-on pointer hygiene.

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

---

## Load-bearing conclusions

1. Session start injects skill **name + description only**. Nine kit skills ≈
   500–900 tokens/session. The urgent cost is **auto-fire and double-loading**, not
   raw description size.
2. `disable-model-invocation: true` is the same key on Claude Code, Cursor, and
   Copilot skills. None of the kit’s nine skills set it today.
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

`test-ladder` today is the worst of both worlds: `user-invocable: true` plus
routing into every implement/test context package (`feature/SKILL.md`).

## Terminal agent (spec for a later task)

Canonical Claude source: `templates/agents/terminal.md`.

- **Tools:** Bash + Read. No edit/write.
- **Model:** light (`haiku` / `{{MODEL_LIGHT}}` / `{{COPILOT_MODEL_LIGHT}}`).
  Cursor: pin on the translated `.cursor/agents/terminal.md` (no skill model key).
- **Return:** exit code; ≤N-line failure excerpt or “all passed”; path to full
  log if truncated. No code edits, no extra commands.
- **Spawn:** orchestrator may spawn it for read-only inspection (git log/status,
  full-suite) so output stays out of the frontier session — that is delegation,
  not the orchestrator executing product code. `implementer` / `test-writer` keep
  rung 1–2 inline; spawn `terminal` for noisy full runs where nesting exists.
- **Copilot nesting** is off by default
  (`chat.subagents.allowInvocationsFromSubagents`). Until that is a kit default
  or an installer choice, the orchestrator (L1) spawns `terminal` on Copilot.
- **Hooks:** optional belt-and-suspenders on Claude (PreToolUse) and Cursor
  (`beforeShellExecution`). Copilot shell-rewrite hooks are not the documented
  path — rely on the agent + quiet flags.

## Always-on pointer target

Keep the three short pointers (`CLAUDE.md`, `copilot-instructions.md`,
`.cursor/rules/orchestration.mdc`). After hygiene they should be ~15–25 lines:
orchestrator coordinates / never edits product code; implementation →
implementer/test-writer; verification → judge/qa-judge; noisy commands →
`terminal`; captured quiet test/build commands; Copilot ceiling note. Do **not**
inline `ORCHESTRATION.md` (659 lines). Change `feature/SKILL.md` from “its
invariants are binding” (whole-doc required reading) to “read the section for
the current phase.”

## Prioritized backlog (not yet a judged goal)

| Pri | Change | Effect |
|-----|--------|--------|
| P0 | `disable-model-invocation: true` on `auto-loop`, `align-docs`, `ship-pr`, `*-criteria` | Session-start metadata + auto-fire gone for six skills |
| P0 | Single load path for `test-ladder` and criteria (flag first; `reference/` demotion optional follow-up) | Stops double-loading |
| P1 | Emit `terminal` agent on all three harnesses; spawn rules in ORCHESTRATION.md | Command output leaves the frontier context |
| P1 | `/setup` interview: quiet form of targeted/full test commands | No invented flags |
| P1 | Copilot emitter: `.github/skills/` default; inline = legacy-only | Stops body duplication in agents |
| P1 | Always-on + “binding” language hygiene | Stops whole-architecture pull into `/feature` |
| P2 | Split `feature` (181) / `auto-loop` (208) SKILL.md | Smaller per-turn body once invoked |
| P2 | Test guard: fail if criteria/`auto-loop` are auto-invocable | Regression lock |
| P2 | Setup-report MCP / `/context` warning | User education; kit does not emit MCP |
| P2 | Path-scoped lane rules (Copilot `applyTo`, Cursor `globs`, Claude `paths:`) | Test/docs/PR rules stay out of unrelated sessions |

## Non-goals

Do not: move judges to the light tier; drop verbatim-report integrity; stuff
criteria or architecture into always-on files; merge skills into one mega-skill;
auto-invoke a pile of domain skills; fold the loop into a long-lived chat; give
`terminal` edit tools.

## Open questions (block planning, not P0 flags)

1. Enable Copilot nested subagents as kit default, or leave it an installer
   choice? Blocks `implementer` → `terminal` on Copilot.
2. Stop at the invocation flag for criteria/ladder, or also demote them off the
   skills tree to `reference/` in the same change?
3. Run Phase 6 (`align-docs`) and Phase 7 (`ship-pr`) as **new sessions**, or
   keep them in the same `/feature` conversation?
4. Exact Copilot terminal-output size behavior (undocumented). Does not block
   shipping `terminal` + quiet flags.
