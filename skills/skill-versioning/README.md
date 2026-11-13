# skill-versioning

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/skill-versioning)

Keeps each skill in a multi-skill repository (`skills/<name>/SKILL.md`) on its own semantic version and changelog. It records changes under `## [Unreleased]`, picks the MAJOR, MINOR or PATCH bump, and cuts per-skill releases tagged `<name>/vX.Y.Z` without pushing.

## Install

```bash
npx skills add kdcllc/skills --skill skill-versioning
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills skill-versioning` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#skill-versioning/vX.Y.Z --skill skill-versioning` ([releases](https://github.com/kdcllc/skills/releases)) |

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

Use it after editing, adding or importing files under `skills/<name>/`, or when you want to version, bump, release or tag a skill, or see which skills need a release.

- Recording a change adds a line under `## [Unreleased]` in that skill's `CHANGELOG.md`. It does not bump the version.
- Releasing happens only when you ask. The skill proposes a version, waits for your confirmation, and then runs `scripts/release-skill.sh` if the repo has one. Otherwise it follows the manual steps in the references. It never pushes unless you ask.

Example prompts:

- "Use skill-versioning to record my changes to the foo skill."
- "Which skills need a release?"
- "Release foo as a new version."

To check where each skill stands, run from the repo root (read-only):

```bash
bash <this-skill>/scripts/skill-status.sh
bash <this-skill>/scripts/skill-status.sh my-skill
```

## Requirements

- bash for the status script, and git.
- A repository laid out as `skills/<name>/SKILL.md`. Not for single-skill repos with one repo-wide version.

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/changelog-and-release.md](references/changelog-and-release.md) — how to write entries, adopt versioning, and release by hand
