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
| [terraform-azure](skills/terraform-azure/SKILL.md) | Azure Terraform | Operator menu for a consumer Azure Terraform repo: new module, domain stack, pipeline, remote-state bootstrap, Azure OIDC, or module upgrade. Azure CLI only; stops at `terraform plan`. | `npx skills add kdcllc/skills --skill terraform-azure` |
| [terraform-azure-modules](skills/terraform-azure-modules/SKILL.md) | Azure Terraform | Create or update one reusable module under `modules/<name>/` with `providers.tf` and `organization_name` naming. | `npx skills add kdcllc/skills --skill terraform-azure-modules` |
| [terraform-azure-pipelines](skills/terraform-azure-pipelines/SKILL.md) | Azure Terraform | Copy GitHub Actions, Azure DevOps, or GitLab templates that run fmt, validate, and plan with OIDC; apply and a gated destroy are opt-in. | `npx skills add kdcllc/skills --skill terraform-azure-pipelines` |
| [terraform-azure-upgrade](skills/terraform-azure-upgrade/SKILL.md) | Azure Terraform | Inventory existing modules, bump to bounded azurerm 5.x pins, apply the current HashiCorp schema, and stop at `validate`. | `npx skills add kdcllc/skills --skill terraform-azure-upgrade` |
| [azure-rbac-least-privilege](skills/azure-rbac-least-privilege/SKILL.md) | Azure RBAC | Rank the smallest built-in Azure roles that grant a set of operations, from an offline snapshot; flags roles that can assign roles. | `npx skills add kdcllc/skills --skill azure-rbac-least-privilege` |
| [greek-to-hebrew](skills/greek-to-hebrew/SKILL.md) | Bible study | Trace a New Testament Greek word through the Septuagint to the Old Testament Hebrew behind it, with free web tools, a first-mention study, and a confidence level. Licensed CC BY-SA 4.0. | `npx skills add kdcllc/skills --skill greek-to-hebrew` |
| [agent-kit](skills/agent-kit/SKILL.md) | Agent orchestration | Install the orchestrator/worker/evaluator multi-agent system (six subagents, `/feature` and `/research` workflows, evaluator gates, optional autonomous loop) compiled for Claude Code, Cursor, GitHub Copilot, and Codex. Run `/agent-kit` once per project; re-run to upgrade. | `npx skills add kdcllc/skills --skill agent-kit` |
| [skill-versioning](skills/skill-versioning/SKILL.md) | Skill authoring | Keep each skill in a multi-skill repo on its own version and changelog: record changes under Unreleased, pick the bump, and tag `<name>/vX.Y.Z` releases. | `npx skills add kdcllc/skills --skill skill-versioning` |

The four Azure Terraform skills link to each other, so install them together:

```bash
npx skills add kdcllc/skills --skill terraform-azure terraform-azure-modules terraform-azure-pipelines terraform-azure-upgrade
```

In Claude Code or Copilot CLI, `/plugin install kdcllc-azure@kdcllc` installs these four plus `azure-rbac-least-privilege`. Operator guides ship inside the skill: [using-the-pack.md](skills/terraform-azure/references/using-the-pack.md) and [deep-dive.md](skills/terraform-azure/references/deep-dive.md).

`agent-kit` (the AI Orchestration Kit, formerly the private `setup` skill) has its own [README](skills/agent-kit/README.md) and a developer guide under [docs/agent-kit/guide/](docs/agent-kit/guide/README.md). Upgrading from `setup`? Follow the 1.0.0 upgrade notes in its [CHANGELOG](skills/agent-kit/CHANGELOG.md).

## Versions

Each skill is versioned on its own. Its version is `metadata.version` in its `SKILL.md`, its history is the `CHANGELOG.md` next to it, and each release is a git tag named `<skill>/vX.Y.Z` with a matching [GitHub release](https://github.com/kdcllc/skills/releases). To pin a skill to a release:

```bash
npx skills add kdcllc/skills#terraform-azure/v1.0.0 --skill terraform-azure
```

The ref goes after `#`. A tag pins the whole repository at that commit, so run one `npx skills add` per skill when you pin. `npx skills update` re-downloads from the pinned ref, so pinned installs stay on their tag until you re-add with a newer one.

## Repository layout

```text
skills/<name>/                     # one folder per skill
  SKILL.md                         # required: frontmatter (incl. metadata.version) + instructions
  CHANGELOG.md                     # required: per-skill release history
  scripts/  references/  assets/   # optional, loaded on demand
.claude-plugin/marketplace.json    # Claude Code, Copilot CLI, Codex
.cursor-plugin/                    # Cursor marketplace + plugin manifest
skills.sh.json                     # skill groupings on the skills.sh repo page
templates/                         # SKILL.md and CHANGELOG.md starters used by scripts/new-skill.sh
scripts/new-skill.sh               # scaffold a new skill
scripts/validate-skills.sh         # repo, frontmatter, and version checks (also run in CI)
scripts/checks/                    # skill-specific content guards, run by validate-skills.sh
scripts/release-skill.sh           # release one skill: bump, commit, tag <skill>/vX.Y.Z
scripts/agent-kit/                 # agent-kit dogfood installer (self-install.sh / .ps1)
docs/agent-kit/                    # agent-kit developer guide and research studies (not shipped)
tests/agent-kit/                   # agent-kit test suites; run-all.sh runs everything
_memory/                           # agent-kit memory store for this repo (immutable records)
```

## Validate

```bash
bash scripts/validate-skills.sh
npx skills add . --list
claude plugin validate .
```

`validate-skills.sh` also runs every guard in `scripts/checks/`. CI runs the same checks plus the reference [`skills-ref`](https://github.com/agentskills/agentskills/tree/main/skills-ref) validator on every push and pull request.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new skill, migrate one from another repo, and cut a release.

## License

[MIT](LICENSE), unless a skill's `license` frontmatter field and bundled `LICENSE.txt` say otherwise.
