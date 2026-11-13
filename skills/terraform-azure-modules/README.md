# terraform-azure-modules

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/terraform-azure-modules)

Creates or updates one reusable Azure Terraform module under `modules/<name>/`, using azurerm, a `providers.tf` file, and the pack's canonical resource naming with `organization_name`. Use it to author a new library module, change an existing one, or fix its naming.

## Install

```bash
npx skills add kdcllc/skills --skill terraform-azure-modules
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Install the four Azure Terraform skills together:

```bash
npx skills add kdcllc/skills --skill terraform-azure terraform-azure-modules terraform-azure-pipelines terraform-azure-upgrade
```

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills terraform-azure-modules` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#terraform-azure-modules/vX.Y.Z --skill terraform-azure-modules` ([releases](https://github.com/kdcllc/skills/releases)) |
| Claude Code / Copilot CLI (Azure bundle) | `/plugin install kdcllc-azure@kdcllc` (the four Azure Terraform skills plus azure-rbac-least-privilege) |

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

Ask for a module in your consumer repository. The agent checks `modules/` first and updates an existing module instead of duplicating it. A new module gets its own snake_case folder with `main.tf`, `variables.tf`, `outputs.tf` (or `output.tf`, matching siblings) and `providers.tf`.

Example prompts:

- "Create a key_vault module for Azure."
- "Update the storage_account module to follow the naming convention."
- "Wrap azurerm_container_app as a library module."

This skill covers one module only. It does not write environment stacks, CI pipelines, or make live Azure changes; use `terraform-azure` for stacks.

## Requirements

- The other three Azure Terraform skills, installed together; this one reads templates and conventions from `terraform-azure`
- Access to current azurerm provider docs and Microsoft Learn (the HashiCorp Registry and Microsoft Learn in a browser also work)

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/reference.md](references/reference.md) — Azure resource abbreviations, file templates, name character-set exceptions
