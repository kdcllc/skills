# terraform-azure-upgrade

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/terraform-azure-upgrade)

Upgrades existing Azure Terraform library modules, and optionally stacks, to the current bounded azurerm 5.x schema and the pack's Terraform version pins. Use it when `terraform validate` fails after an azurerm major bump, when `providers.tf` has unbounded or old constraints, or when you need to migrate `skip_provider_registration`.

## Install

```bash
npx skills add kdcllc/skills --skill terraform-azure-upgrade
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Install the four Azure Terraform skills together:

```bash
npx skills add kdcllc/skills --skill terraform-azure terraform-azure-modules terraform-azure-pipelines terraform-azure-upgrade
```

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills terraform-azure-upgrade` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#terraform-azure-upgrade/vX.Y.Z --skill terraform-azure-upgrade` ([releases](https://github.com/kdcllc/skills/releases)) |
| Claude Code / Copilot CLI (Azure bundle) | `/plugin install kdcllc-azure@kdcllc` (the four Azure Terraform skills plus azure-rbac-least-privilege) |

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

The agent inventories `modules/`, shows you the list, and upgrades one module at a time. It only touches the modules you name (or all of them, if you say so after seeing the inventory). It checks argument names against the current HashiCorp azurerm docs and the 5.0 upgrade guide, then runs tier 1 validation.

Example prompts:

- "Upgrade the key_vault and storage_account modules to azurerm 5.x."
- "Fix the validate errors after bumping azurerm."
- "Replace skip_provider_registration in our stacks."

Target pins: `azurerm` `>= 5.0.0, < 6.0.0`, Terraform `required_version` `>= 1.9.0, < 2.0.0`. The skill never removes the upper bound, and never runs `terraform apply`, `terraform destroy` or `azd`.

## Requirements

- Terraform and Azure CLI as listed in `terraform-azure`
- Access to current azurerm provider docs

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/reference.md](references/reference.md) — common azurerm 5.x argument renames (examples; confirm against current docs)
