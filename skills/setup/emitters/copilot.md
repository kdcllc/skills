# Emitter: GitHub Copilot (VS Code)

Target: `.github/`. VS Code also reads `.claude/agents`, but Copilot-native features the
kit needs (subagent allowlists, `user-invocable`, model fallback arrays) require
`.agent.md` files, so agents are emitted natively.

## Emit

| Source (resolved) | Destination | Translation |
|-------------------|-------------|-------------|
| `templates/agents/judge.md`, `qa-judge.md` | `.github/agents/judge.agent.md`, `qa-judge.agent.md` | frontmatter below; `model:` as fallback array of frontier models; add `user-invocable: false` |
| `templates/agents/implementer.md`, `test-writer.md` | `.github/agents/{implementer,test-writer}.agent.md` | `model:` fallback array of light models; `user-invocable: false` |
| `templates/skills/feature/SKILL.md` body | `.github/agents/feature.agent.md` | becomes the user-invocable orchestrator agent: `agents: [implementer, test-writer, judge, qa-judge]`, `tools` must include the `agent` tool; model = frontier array |
| Other skills (`research`, `*-criteria`, `test-ladder`, `align-docs`, `ship-pr`) | `.github/skills/` if skills are supported in the current VS Code build, else inline their content into the agents that use them | criteria + ladder content may also be appended to the judge/worker agents' bodies; align-docs and ship-pr can become additional `.agent.md` entries if inlining is too large |
| `templates/ORCHESTRATION.md` | `ORCHESTRATION.md` at repo root (Copilot has no conventional home for it) | — |
| Pointer | append to `.github/copilot-instructions.md` | "Feature work runs through the orchestrator/worker/judge system — see ORCHESTRATION.md. Start features with the `feature` agent." |
| `templates/loop/*` (if loop enabled) | `_loop/loop.sh`, `_loop/loop.ps1`, `_goals/backlog.md` | note: unattended execution on Copilot means the coding agent on GitHub issues — the local `loop.sh`/`loop.ps1` path targets the `copilot` CLI if installed; invocation forms as in the Claude Code emitter (`_loop/loop.sh [max-iterations]` / `pwsh _loop/loop.ps1 [MaxIterations]`) |

Agent frontmatter shape (`.agent.md` uses YAML **arrays**, not comma strings):

```yaml
---
name: judge
description: <from canonical template>
model: ['{{COPILOT_MODEL_FRONTIER}}']   # fallback array; CLI rejects arrays — use a plain string if targeting Copilot CLI
user-invocable: false
---
```

## Harness specifics — read before emitting

1. **Cost ceiling**: a subagent cannot run a stronger model than the session; a
   too-strong pin makes the subagent **not run at all**. Therefore: the emitted
   ORCHESTRATION.md and copilot-instructions pointer must state that orchestrated
   sessions run the frontier tier; judges never pin above it; workers pin down.
2. **Nesting off by default**: enable `chat.subagents.allowInvocationsFromSubagents` in
   `.vscode/settings.json` if the flow needs judge-spawned helpers (max depth 5).
3. Subagents are stateless with no follow-ups and lack clarifying-question/todo tools —
   context packages must be complete on first send (the kit already requires this).
4. There is no `effort` key — drop it in translation.

## Verify

- No `{{` / `BOOTSTRAP:` leftovers under `.github/`.
- Every `.agent.md` parses (open in VS Code chat: agents appear in the picker except
  `user-invocable: false` ones).
- `feature.agent.md` lists all four roles in `agents:` and includes the `agent` tool.
