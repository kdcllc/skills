# Emitter: GitHub Copilot (VS Code)

Target: `.github/`. VS Code also reads `.claude/agents`, but Copilot-native features the
kit needs (subagent allowlists, `user-invocable`, model fallback arrays) require
`.agent.md` files, so agents are emitted natively.

## Emit

Template skills are stored as `SKILL.template.md` so harnesses do not discover them
in the kit repo; emit them as `SKILL.md`.

| Source (resolved) | Destination | Translation |
|-------------------|-------------|-------------|
| `templates/agents/evaluator.md`, `qa-evaluator.md` | `.github/agents/evaluator.agent.md`, `qa-evaluator.agent.md` | frontmatter below; `model:` as fallback array of frontier models; add `user-invocable: false` |
| `templates/agents/diagnostician.md` | `.github/agents/diagnostician.agent.md` | `model:` fallback array of frontier models; `user-invocable: false` (subagent-only, same as evaluators) |
| `templates/agents/implementer.md`, `test-writer.md` | `.github/agents/{implementer,test-writer}.agent.md` | `model:` fallback array of light models; `user-invocable: false` |
| `templates/agents/terminal.md` | `.github/agents/terminal.agent.md` | `model:` fallback array of **light** models (`{{COPILOT_MODEL_LIGHT}}`, same fallback-array shape used for implementer/test-writer — never frontier); `user-invocable: false`; `tools:` YAML array — check the live VS Code custom-agents page (`code.visualstudio.com/docs/agent-customization/custom-agents`) and the linked tools page at emit time; as of this writing those pages name `read`, `edit`, `search`, `execute`, `web` as the built-in tool categories and give no more specific run-command identifier in a `.agent.md` example, so emit `tools: ['read', 'execute']` — do not invent a narrower/namespaced form (e.g. a hypothetical `execute/runInTerminal`) unless the live page documents it that day; never include `edit`/write-capable tools by name |
| `templates/skills/feature/SKILL.template.md` body | `.github/agents/feature.agent.md` | becomes the user-invocable orchestrator agent: `agents: [implementer, test-writer, evaluator, qa-evaluator, terminal, diagnostician]`, `tools` must include the `agent` tool; model = frontier array |
| `templates/skills/feature/templates/*` (`goal.md`, `task.md`) | `.github/skills/feature/templates/` when the skills path is used (skills first-class per the harness matrix) | travels with the `feature` skill body — same source, no per-file translation |
| Other skills (`research`, `*-criteria`, `test-ladder`, `align-docs`, `ship-pr`) | `.github/skills/` if skills are supported in the current VS Code build, else inline their content into the agents that use them | copy `disable-model-invocation` as-is on the `.github/skills/*/SKILL.md` path — do not drop it; criteria + ladder content may also be appended to the evaluator/worker agents' bodies; align-docs and ship-pr can become additional `.agent.md` entries if inlining is too large |
| `templates/ORCHESTRATION.md` | `ORCHESTRATION.md` at repo root (Copilot has no conventional home for it) | — |
| Pointer | append to `.github/copilot-instructions.md` | "Feature work runs through the orchestrator/worker/evaluator system — see ORCHESTRATION.md. Start features with the `feature` agent." |
| `templates/loop/*` (if loop enabled) | `_loop/loop.sh`, `_loop/loop.ps1`, `_loop/breaker.sh`, `_loop/breaker.ps1`, `_goals/backlog.md` (create if missing; never overwrite) | note: unattended execution on Copilot means the coding agent on GitHub issues — the local `loop.sh`/`loop.ps1` path targets the `copilot` CLI if installed; invocation forms as in the Claude Code emitter (`_loop/loop.sh [max-iterations]` / `pwsh _loop/loop.ps1 [MaxIterations]`) |
| Do **not** emit | `.vscode/settings.json` (or any settings snippet) | never set `chat.subagents.allowInvocationsFromSubagents` to `true` — nesting stays off as the kit default (see Harness specifics below) |

Agent frontmatter shape (`.agent.md` uses YAML **arrays**, not comma strings):

```yaml
---
name: evaluator
description: <from canonical template>
model: ['{{COPILOT_MODEL_FRONTIER}}']   # fallback array; CLI rejects arrays — use a plain string if targeting Copilot CLI
user-invocable: false
---
```

## Harness specifics — read before emitting

1. **Cost ceiling**: a subagent cannot run a stronger model than the session; a
   too-strong pin makes the subagent **not run at all**. Therefore: the emitted
   ORCHESTRATION.md and copilot-instructions pointer must state that orchestrated
   sessions run the frontier tier; evaluators never pin above it; workers pin down.
   `diagnostician` and the rung-5 arbiter pin (`{{MODEL_FRONTIER_ALT_FAMILY}}` from the
   model map) run at the session's frontier tier — allowed, not stronger than the parent.
   Copilot has no `effort` key — drop it in translation.
2. **Nesting stays off (kit default)**: `chat.subagents.allowInvocationsFromSubagents`
   remains unset/`false` — the kit does not enable it and `/setup` must not instruct the
   user to enable it (a project may opt in later, on its own, up to max depth 5; that is
   the project's choice, not an installer step). `feature.agent.md` is the L1
   orchestrator and spawns `implementer`, `test-writer`, `evaluator`, `qa-evaluator`,
   `terminal`, and `diagnostician` directly via its own `agents:` allowlist — that
   top-level spawn works with nesting off. Workers (`implementer`, `test-writer`) do not spawn subagents of their
   own; when their output needs isolating, the orchestrator spawns `terminal` on their
   behalf instead.
3. Subagents are stateless with no follow-ups and lack clarifying-question/todo tools —
   context packages must be complete on first send (the kit already requires this).
4. There is no `effort` key — drop it in translation.

## Verify

- No `{{` / `BOOTSTRAP:` leftovers under `.github/`.
- Every `.agent.md` parses (open in VS Code chat: agents appear in the picker except
  `user-invocable: false` ones).
- `feature.agent.md` lists all **six** roles (`implementer`, `test-writer`, `evaluator`,
  `qa-evaluator`, `terminal`, `diagnostician`) in `agents:` and includes the `agent` tool.
- The emitted tree must not set `chat.subagents.allowInvocationsFromSubagents` to
  `true` anywhere (no `.vscode/settings.json` or other settings snippet does this).
