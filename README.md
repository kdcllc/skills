# kdcllc skills

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills)
[![Validate](https://github.com/kdcllc/skills/actions/workflows/validate.yml/badge.svg)](https://github.com/kdcllc/skills/actions/workflows/validate.yml)

A single home for the [Agent Skills](https://agentskills.io) published by [King David Consulting LLC](https://kingdavidconsulting.com). Every skill lives in `skills/<name>/` and follows the open `SKILL.md` format, so the same folder installs into Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI, and any other agent that supports skills.

## Install

### Any agent (skills.sh)

```bash
# See what's in the repo
npx skills add kdcllc/skills --list

# Install everything
npx skills add kdcllc/skills

# Install one skill
npx skills add kdcllc/skills --skill <skill-name>
npx skills add kdcllc/skills@<skill-name>
```

Add `-g` to install for your user instead of the current project, and `-a <agent>` to target a specific agent. See the [Skills CLI docs](https://github.com/vercel-labs/skills).

### Claude Code

```text
/plugin marketplace add kdcllc/skills
/plugin install kdcllc-skills@kdcllc
```

### GitHub Copilot

Copilot CLI reads the same marketplace:

```bash
copilot plugin marketplace add kdcllc/skills
copilot plugin install kdcllc-skills@kdcllc
```

Or install a single skill with the GitHub CLI (`gh` 2.90 or newer):

```bash
gh skill install kdcllc/skills <skill-name>
```

### OpenAI Codex

```bash
codex plugin marketplace add kdcllc/skills
```

Then install `kdcllc-skills` from the Codex plugin browser.

### Cursor

Open **Customize** in the sidebar, choose **From GitHub Repository**, paste `https://github.com/kdcllc/skills`, and install the `kdcllc-skills` plugin. Teams can add the repo under **Dashboard > Plugins & MCPs > Add Marketplace > Import from Repo**.

## Skills

| Skill | Category | Use when | Install |
| --- | --- | --- | --- |
| _No skills yet. See [CONTRIBUTING.md](CONTRIBUTING.md) to add or migrate one._ | | | |

## Repository layout

```text
skills/<name>/                     # one folder per skill
  SKILL.md                         # required: frontmatter + instructions
  scripts/  references/  assets/   # optional, loaded on demand
.claude-plugin/marketplace.json    # Claude Code, Copilot CLI, Codex
.cursor-plugin/                    # Cursor marketplace + plugin manifest
templates/SKILL.md.tmpl            # starter used by scripts/new-skill.sh
scripts/new-skill.sh               # scaffold a new skill
scripts/validate-skills.sh         # repo and frontmatter checks (also run in CI)
```

## Validate

```bash
bash scripts/validate-skills.sh
npx skills add . --list
claude plugin validate .
```

CI runs the same checks plus the reference [`skills-ref`](https://github.com/agentskills/agentskills/tree/main/skills-ref) validator on every push and pull request.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new skill, migrate one from another repo, and cut a release.

## License

[MIT](LICENSE), unless a skill's `license` frontmatter field and bundled `LICENSE.txt` say otherwise.
