Verified: 2026-11-04 against https://code.claude.com/docs/en/sub-agents and https://code.claude.com/docs/en/skills

This reference maps a crew spec ([spec-schema.md](spec-schema.md)) to generated Claude Code files. Where this text disagrees with `skills/agent-kit/reference/harness-matrix.md`, the live Claude Code docs above win (for example current subagent frontmatter fields and skill invocation flags).

## Agent files

**Path:** `.claude/agents/<agent-id>.md` (project scope; discovered recursively under `.claude/agents/`).

**Harness frontmatter (all keys the format supports):** `name`, `description`, `tools`, `model`, plus optional keys documented on the sub-agents page (`skills`, `disallowedTools`, `permissionMode`, hooks, MCP, memory, and others). The generator writes only the subset below.

**Generator-written frontmatter (agents):**

| Key | Rule |
| --- | --- |
| `name` | Required; must match the file stem `<agent-id>`. |
| `description` | Required; from the spec agent `description`. |
| `tools` | Always written as a comma-separated tool name list. In Claude Code, omitting `tools` grants every subagent tool; the generator always emits an explicit list so read-only and partial-tool crews are enforceable. |
| `model` | Always written. For tier `inherit`, the generator emits `model: inherit` explicitly. For `frontier`, `light`, and `fast`, the value comes from `models.claude-code.<tier>`. On the harness, omitting `model` is not identical to `model: inherit`: with no key, Claude Code resolves per-invocation parameter → `CLAUDE_CODE_SUBAGENT_MODEL` (if set) → main conversation model, while `model: inherit` selects the main model ahead of that variable (live order since v2.1.251; `harness-matrix.md` still lists the variable first). |

**Body:** Spec `instructions`, plus generated runtime protocol prose (status lines, evaluator/router/planner behavior). Immediately after the closing `---` of frontmatter, the [generated-by marker](spec-schema.md) from the spec schema.

**Read-only enforcement:** There is no separate `readonly` flag. Restrict writes by omitting edit tools from `tools` (see Tool mapping). Agents whose spec `tools` omit `edit` must declare empty `outputs` (**S039**); they return results in their completion report and write no files—the orchestrator saves each report under `<workdir>/<run-id>/` per [spec-schema.md § Agent reports](spec-schema.md) (for example `<step-id>.report.md`). Evaluators must not list edit-capable tools (**S024** / **T008**).

## Tool mapping

Spec tool tokens map to Claude Code built-in tool names in the agent `tools` frontmatter (comma-separated string):

| Spec `tools` value | Claude Code tools emitted |
| --- | --- |
| `read` | `Read` |
| `search` | `Grep`, `Glob` |
| `edit` | `Edit`, `Write` |
| `shell` | `Bash` |
| `web` | `WebFetch`, `WebSearch` |

Default spec tools `[read, search]` become `Read, Grep, Glob`. Deduplicate names when merging lists. The spec tool `spawn` does not exist (**S026**); subagents never spawn subagents in v1 — the orchestrator skill in the main session performs all delegation via the `Agent` tool.

**Evaluator agents (`kind: evaluator`):** Must not include `edit` in the spec; the generator must not emit `Edit` or `Write` for them.

## Model

**Tier → model key** (see [spec-schema.md § Tier to model mapping](spec-schema.md)):

| Agent `tier` | Generated `model:` |
| --- | --- |
| `inherit` | `inherit` |
| `frontier`, `light`, `fast` | Value from `models.claude-code.<tier>` in the crew spec |

Claude Code accepts provider aliases or full model IDs in `model:`; resolution order and allowlist substitution are defined in the [model configuration](https://code.claude.com/docs/en/model-config) docs. The generator must not hard-code IDs in templates — use placeholders such as `<light-model-id>` in the spec `models` map and verify live IDs at generation time; optional `verified` metadata on the harness map records the check.

**How to verify IDs live:** Consult the current Claude Code model configuration documentation and your organization's model allowlist (`availableModels`). After generation, spot-check that pinned agents run on the intended model (Claude Code may substitute when a value is blocked).

Skills do not carry a `model` key in generated orchestrator files (see Orchestrator skill).

## Orchestrator skill

**Path:** `.claude/skills/<crew-name>/SKILL.md` (folder name equals crew `name`).

**Generator-written skill frontmatter:**

| Key | Rule |
| --- | --- |
| `name` | Crew `name` (must match folder and `/command`). |
| `description` | Crew `description`. |
| `disable-model-invocation` | `true` when spec `invocation` is `manual` (default); omitted or `false` when `invocation: auto`. Same key and semantics as documented on the [skills](https://code.claude.com/docs/en/skills) page. |

No `model` (or `effort`) key on orchestrator skills — model choice stays at the main session and per-agent pins.

**Body:** Pattern-specific orchestration steps, workdir/run-id protocol, spawn instructions, and parallel-step guidance. Same generated-by marker line after frontmatter.

## Spawning

The orchestrator skill runs in the **main Claude Code session** (user invokes `/crew-name` or the skill loads per `invocation`). It does not run inside a subagent context.

**Launch mechanism:** The main agent delegates work using the **`Agent` tool**, passing the target subagent's frontmatter `name` (equal to spec agent `id`). The skill body names each step's agent id and the workdir artifacts to pass (context package / scratch files under `<workdir>/<run-id>/`). After each step, the orchestrator saves the agent's final report to the paths in [spec-schema.md § Agent reports](spec-schema.md); agents without `edit` deliver report-only results (**S039**).

**Parallel steps (`parallel` in the spec):** For a step with a `parallel` list, the orchestrator instructs the main agent to start **multiple subagents concurrently** — the live docs describe parallel research by spawning several subagents at once. Concurrent runs share the project checkout unless isolation is requested; disjoint output paths avoid clobbering.

**Nesting:** Claude Code allows nested subagent delegation when `Agent` appears in a subagent's `tools` list, subject to `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`. Agent-composer v1 **never** gives crew agents spawn capability (no `spawn` tool, no orchestration-from-subagent instructions), so every crew stays at **main → worker/evaluator** depth and remains inside harness nesting limits.

## Quirks

- **Omitted vs explicit `tools`:** Harness default for missing `tools` is "all subagent tools"; the generator always writes `tools` so validation matches intent.
- **Omitted `model` vs explicit `model: inherit` (harness behavior):** The generator always writes `model: inherit` for inherit-tier agents so `CLAUDE_CODE_SUBAGENT_MODEL` cannot override the main model. If the key were omitted instead, Claude Code would prefer that variable when set, not the main model.
- **Model substitution:** Blocked or unknown models may be replaced per org allowlist and model-config rules; check subagent reports for fallback notices.
- **Concurrent limit:** Default cap on concurrent subagents (documented on the sub-agents page); exceeding it errors (`Concurrent subagent limit reached`) — parallel fan-out should stay within reasonable batch size or serialize.
- **Name collisions:** Duplicate `name` values under the same `.claude/agents/` tree are undefined; only one definition loads.
- **Skills vs agents:** Orchestrator is a skill; workers are subagents. Do not add `model` to the skill frontmatter.

## Validator rules

Checks enforced by `validate.sh tree` for the Claude Code harness (codes from [spec-schema.md](spec-schema.md)):

1. Every expected `.claude/agents/<id>.md` and `.claude/skills/<name>/SKILL.md` for the spec exists — **T001**.
2. YAML frontmatter in each generated file parses — **T002**.
3. Each agent file's `name` matches its stem; orchestrator skill `name` matches crew `name` — **T003**.
4. Every agent file has exactly the keys `name`, `description`, `tools`, `model` (a missing key, including `model`, or any other key → **T004**); orchestrator skill frontmatter has only the allowed orchestrator keys — **T004**.
5. Each agent `model` value matches the spec tier mapping for `models.claude-code`, including tier `inherit` (`model: inherit`) — **T007**.
6. Evaluator agents do not grant `Edit`/`Write` via `tools` — **T008**.
7. No leftover `{{` tokens or `<!-- block:` / `<!-- /block:` delimiter lines — **T009**.
8. Generated-by marker line present immediately after frontmatter — **T010**.
9. Expected paths that exist without this crew's marker and manifest entry are collisions — **T012**.
10. Orchestrator `SKILL.md` body length ≤ 500 lines — **T013**.
