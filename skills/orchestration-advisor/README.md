# orchestration-advisor

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/orchestration-advisor)

Inspects a project and asks about its workload, then either recommends an agent orchestration shape (a single agent plus skills by default) or audits an existing orchestration system. It is read-only: it changes no file in your project unless you ask it to save its report.

## Install

```bash
npx skills add kdcllc/skills --skill orchestration-advisor
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills orchestration-advisor` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#orchestration-advisor/vX.Y.Z --skill orchestration-advisor` ([releases](https://github.com/kdcllc/skills/releases)) |

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

Ask your agent to use the skill. It runs a signal-counting script, then asks one question: recommend a setup, or audit the existing one. It pre-selects audit when agents, an `agent-kit` install, crews or orchestrator skills already exist. It then asks six workload questions.

- **Design mode** recommends one shape with the evidence, the shapes it ruled out, a cost note and a next step.
- **Audit mode** maps each existing orchestration system, accounts for what enforces each gate (hooks, rubrics, CI and so on), and produces a current-vs-recommended comparison.

Example prompts:

- "Use orchestration-advisor: do I need multiple agents for this project?"
- "Use orchestration-advisor to audit my agents and hooks for overlap."
- "Use orchestration-advisor to choose between agent-kit, agent-composer and installing nothing."

Once you have decided on a shape, `agent-kit` (evaluator-gated feature work) or `agent-composer` (custom roles) builds it.

## Requirements

- bash, with `find`, `awk`, `sort`, `wc` and `tr` on `PATH`, for `scripts/inspect.sh`. `git` and `jq` are optional; without them some signals report `unknown`.
- Without bash, the skill counts the signals by hand and says so in the report.

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/signals.md](references/signals.md) — what each inspected signal means
- [references/audit.md](references/audit.md) — the audit-mode procedure
- [references/patterns.md](references/patterns.md) — the orchestration shapes
