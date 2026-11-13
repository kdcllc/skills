# terraform-azure-pipelines

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/terraform-azure-pipelines)

Creates Terraform CI pipelines for Azure that run fmt, validate and plan, using GitHub Actions reusable workflows, Azure DevOps templates, or GitLab CI, with OIDC and parameterized backends. Use it when adding Terraform CI, a plan job, a gated destroy workflow, or OIDC access to azurerm state.

## Install

```bash
npx skills add kdcllc/skills --skill terraform-azure-pipelines
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Install the four Azure Terraform skills together:

```bash
npx skills add kdcllc/skills --skill terraform-azure terraform-azure-modules terraform-azure-pipelines terraform-azure-upgrade
```

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills terraform-azure-pipelines` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#terraform-azure-pipelines/vX.Y.Z --skill terraform-azure-pipelines` ([releases](https://github.com/kdcllc/skills/releases)) |
| Claude Code / Copilot CLI (Azure bundle) | `/plugin install kdcllc-azure@kdcllc` (the four Azure Terraform skills plus azure-rbac-least-privilege) |

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

Ask for a pipeline for a domain stack under `resources/<domain>/`. The agent copies its YAML from the skill's `assets/` folder rather than inventing a new template. One pipeline (or caller job) is created per domain stack.

Example prompts:

- "Add a GitHub Actions plan pipeline for the networking stack."
- "Create an Azure DevOps pipeline for the storage stack."
- "Add a destroy option to the pipeline."

Defaults the skill enforces:

- The default action is `plan`. Apply only runs when explicitly requested.
- `terraform fmt -check -recursive` runs before init and always fails the job.
- Destroy appears in the action list but needs a separate confirmation input.
- No access keys, SAS tokens, client secrets or subscription IDs go into YAML; backend settings come from parameters, variables or secrets.

## Requirements

- An Azure Terraform consumer repository laid out as one stack per domain, ideally built with `terraform-azure`
- OIDC set up for CI (the `terraform-azure` skill's menu item 5 covers this)

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
