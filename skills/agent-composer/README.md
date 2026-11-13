# agent-composer

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/agent-composer)

Designs a custom multi-agent crew through an interview, writes a YAML crew spec, and generates validated agent files plus an orchestrator skill for Claude Code and Cursor. Use it when you need distinct roles with explicit handoffs; if one agent or a single skill is enough, the skill says so.

## Install

```bash
npx skills add kdcllc/skills --skill agent-composer
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills agent-composer` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#agent-composer/vX.Y.Z --skill agent-composer` ([releases](https://github.com/kdcllc/skills/releases)) |

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

Ask your agent to use the skill, then answer the interview one round at a time. It asks for the crew goal, work type, inputs and deliverable, roles, handoffs, quality gates, tools and model tiers, and recommends one pattern (`pipeline`, `router`, `fan-out`, `evaluator-optimizer` or `orchestrator-workers`). It writes the spec to `.agent-composer/<name>.crew.yaml` and shows it to you. It generates no files until you confirm the spec.

Example prompts:

- "Use agent-composer to design a content crew for drafting and reviewing blog posts."
- "Use agent-composer to build a triage crew for incoming bug reports, for Claude Code and Cursor."
- "Re-run agent-composer after I edited my crew spec."

Per target harness it produces agent files, an orchestrator skill (`.claude/skills/<name>/SKILL.md` or `.cursor/skills/<name>/SKILL.md`), and optionally a Cursor rule. A manifest at `.agent-composer/<name>.manifest.json` lets later runs avoid overwriting files you edited. Roles that need no tools, model tier or isolation of their own can run inline from a role file instead of as a subagent.

Not sure you need a crew? Run `orchestration-advisor` first. For the standard orchestrator, worker and evaluator kit, use `agent-kit` instead.

## Requirements

- bash and python3 with PyYAML, used by the validation and manifest scripts. If they are missing, the skill offers `python3 -m pip install pyyaml`, or falls back to a manual validation checklist and says so.
- A project with `.claude/` (Claude Code) and/or `.cursor/` (Cursor) as the target.

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/spec-schema.md](references/spec-schema.md) — crew spec schema and validation codes
- [references/patterns.md](references/patterns.md) — the five patterns and when a crew is justified
- [assets/examples/](assets/examples/) — coding, content and triage example specs
