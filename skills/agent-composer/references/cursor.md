Verified: 2026-11-04 against https://cursor.com/docs/subagents, https://cursor.com/docs/context/skills, and https://cursor.com/docs/context/rules

This reference maps a crew spec ([spec-schema.md](spec-schema.md)) to generated Cursor files. Where this text disagrees with `skills/agent-kit/reference/harness-matrix.md`, the live Cursor docs above win (for example subagent frontmatter fields, `.mdc` rules, and model fallback behavior).

## Agent files

**Path:** `.cursor/agents/<agent-id>.md` (project scope; the subagents page documents no nested-directory discovery for agents).

**Harness frontmatter (documented keys, all optional):** `name` (defaults to filename), `description`, `model` (default `inherit`), `readonly` (default `false`), `is_background` (default `false`; never written). **Cursor does not use a `tools:` frontmatter key for custom subagents** — tool access is not configured via frontmatter the way Claude Code uses `tools:`.

**Generator-written frontmatter (agents):**

| Key | Rule |
| --- | --- |
| `name` | Always written (Cursor treats it as optional); matches file stem `<agent-id>`. |
| `description` | Always written (optional in Cursor, but it drives delegation); from spec `description` (used for Task-tool delegation hints). |
| `model` | Unquoted YAML value: `inherit` for tier `inherit`, otherwise the ID from `models.cursor.<tier>`. Bracket params (documented on the subagents page) may be appended to IDs when the generator supports them; values must not be quoted strings. |
| `readonly` | `true` when the agent's spec `tools` list contains **neither** `edit` **nor** `shell`; otherwise omitted (`false` default). |

The generator never writes `tools:` for Cursor agents.

**Body:** Spec `instructions`, runtime protocol, and **explicit tool-limit prose** when the agent has `shell` but not `edit` (Cursor cannot express "shell without edit" in frontmatter). Immediately after frontmatter, the [generated-by marker](spec-schema.md).

**Dual-harness crews:** When the spec lists both `cursor` and `claude-code`, the generator writes **both** `.cursor/` and `.claude/` trees with the **same agent ids/names**. Cursor also loads `.claude/agents/` and `.claude/skills/` for compatibility (see [skills directories](https://cursor.com/docs/context/skills)). On name conflicts between `.cursor/` and `.claude/` agents, live docs state **`.cursor/` takes precedence** over `.claude/` (and `.codex/`). For skills, the live skills page documents **no** precedence between same-named `.cursor/skills/` and `.claude/skills/` entries (`harness-matrix.md` claims `.cursor/` wins; the live page does not say so), so a dual-harness crew may surface two `/<crew-name>` skills in Cursor.

**Rules:** Optional crew pointer at `.cursor/rules/<crew-name>.mdc` when `cursor_rule: true`. Project rules **must** use the `.mdc` extension; a plain `.md` file in `.cursor/rules/` is **ignored** by the rules system.

## Tool mapping

Cursor subagents inherit the parent's tool surface; the generator does not emit a `tools:` list. Document intent in the agent body and use `readonly` when neither edit nor shell is allowed.

| Spec `tools` value | Cursor representation |
| --- | --- |
| `read` | Default agent capabilities; reinforce in body when read-only. |
| `search` | Same; body may instruct codebase search tools. |
| `edit` | Not `readonly`; body grants edit/file-change behavior. |
| `shell` | Not `readonly`; body instructs running terminal commands. |
| `web` | Body instructs web fetch/search tools when needed. |

**Agents without `edit`:** Spec `outputs` must be empty (**S039**). The agent returns results in its completion report only and must not write project or workdir artifact files. The orchestrator saves every subagent report verbatim per [spec-schema.md § Agent reports](spec-schema.md) (for example `<workdir>/<run-id>/<step-id>.report.md`).

**`shell` without `edit`:** Frontmatter cannot split shell vs edit. Set `readonly: false` and state in the body that the agent may run shell commands but must not modify files; command output and findings belong in the report, not ad-hoc file writes.

**Evaluators:** Spec must omit `edit` and declare empty `outputs` (**S039**); the line-18 `readonly` rule applies unchanged (an evaluator that lists `shell`, allowed with warning **S025**, gets no `readonly` key), body text forbids file edits, and the verdict lives in the saved report (**T008**).

The spec tool `spawn` does not exist (**S026**).

## Model

**Tier → model key** ([spec-schema.md § Tier to model mapping](spec-schema.md)):

| Agent `tier` | Generated `model` |
| --- | --- |
| `inherit` | `inherit` (unquoted) |
| `frontier`, `light`, `fast` | Unquoted ID from `models.cursor.<tier>` |

Optional bracket suffixes on IDs (effort/context) follow Cursor's documented `model` syntax; emit unquoted.

**How to verify IDs live:** Run the Cursor CLI model listing command (`agent models` when available) or use **Settings → Models** / the subagent model picker in the IDE. Record optional `verified` metadata on the spec `models.cursor` map after checking.

**Silent fallback:** If the configured model is unknown, quoted incorrectly, blocked by team admin, or unavailable on the plan, Cursor **falls back to a compatible model** (often the parent session model) **without surfacing an error**. Quoting the YAML `model` value can trigger fallback. Agent instructions should require a **self-reported model** line in each subagent completion report so operators can detect mismatches.

Orchestrator skills have **no** `model` key — pin models on agents only ([skills](https://cursor.com/docs/context/skills) format has no skill-level model field).

## Orchestrator skill

**Path:** `.cursor/skills/<crew-name>/SKILL.md`.

**Generator-written skill frontmatter:**

| Key | Rule |
| --- | --- |
| `name` | Crew `name`. |
| `description` | Crew `description`. |
| `disable-model-invocation` | `true` when spec `invocation` is `manual` (default); omitted/false for `auto`. Same spelling as Claude Code / Agent Skills. |

No `model` on the orchestrator skill.

**Body:** Scheduling, workdir protocol, Task-tool spawn wording, parallel batches, and evaluator gate handling. Generated-by marker after frontmatter.

## Spawning

The orchestrator skill runs in the **parent Agent session** (manual `/crew-name` when `disable-model-invocation: true`, or agent-chosen when `auto`).

**Launch mechanism:** The parent agent delegates using the **Task tool** (custom subagent), targeting agents under `.cursor/agents/` by `name` / `description`. The skill body lists agent ids, workdir inputs, declared `outputs` for edit-capable agents, and acceptance criteria. The orchestrator saves each agent's final report per [spec-schema.md § Agent reports](spec-schema.md); agents without `edit` are report-only (**S039**).

**Parallel steps:** For spec steps with `parallel`, instruct the parent to send **multiple Task tool calls in one message** so subagents run simultaneously (documented parallel execution). Subagents share the parent checkout; parallel writers need disjoint output paths.

**Nesting:** Since Cursor 2.5, nesting is **main → direct subagent → one further level**; a subagent launched by another subagent **cannot** launch further subagents. Nested launches also require Task tool access in the current mode (hooks/policies may block). Agent-composer v1 keeps **all spawning in the orchestrator skill** (main session only), so crews stay within this cap and never rely on subagent-to-subagent Task chains.

## Quirks

- **No `tools:` frontmatter** (see Agent files) — Cursor ignores it if present; **T006** rejects generated files that declare it.
- **`agent models` may return empty** on some accounts; use Settings → Models instead.
- **Dual tree:** Prefer validating `.cursor/agents/` for Cursor harness checks even when `.claude/agents/` copies exist.
- **Precedence:** `.cursor/agents` wins over `.claude/agents` for the same `name`; precedence between same-named `.cursor/skills` and `.claude/skills` is undocumented.
- **Rules extension:** Only `.mdc` rules load; plain `.md` in `.cursor/rules/` is ignored — use `AGENTS.md` for simple markdown instructions instead.
- **Cloud Agents:** Cloud subagents follow Cloud model/capability rules; local doc details may differ from desktop CLI behavior.
- **Token cost:** Each subagent has its own context; parallel batches multiply usage.

## Validator rules

Checks enforced by `validate.sh tree` for the Cursor harness (codes from [spec-schema.md](spec-schema.md)):

1. Expected `.cursor/agents/<id>.md`, `.cursor/skills/<name>/SKILL.md`, and optional `.cursor/rules/<name>.mdc` exist — **T001**.
2. Frontmatter parses — **T002**.
3. Agent `name` matches stem; orchestrator skill `name` matches crew `name` — **T003**.
4. Allowed frontmatter keys only (agents: `name`, `description`, `model`, `readonly`; skills: orchestrator keys including `disable-model-invocation`) — **T004**.
5. Cursor agent `model` values are unquoted scalars — **T005**.
6. Cursor agent files must not contain a `tools:` frontmatter field — **T006**.
7. Agent `model` matches spec tier mapping for `models.cursor` — **T007**.
8. Each `kind: evaluator` agent's spec `tools` omits `edit`, and its generated file has `readonly: true` unless the spec lists `shell` — **T008**.
9. No `{{` or block delimiter comments — **T009**.
10. Generated-by marker present — **T010**.
11. When `cursor_rule: true`, rule file is `.mdc` with required pointer semantics — **T011**.
12. Paths that collide with foreign unmarked files — **T012**.
13. Orchestrator `SKILL.md` ≤ 500 lines — **T013**.
