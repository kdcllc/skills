# terraform-azure

[![skills.sh](https://skills.sh/b/kdcllc/skills)](https://skills.sh/kdcllc/skills/terraform-azure)

Walks you through Terraform work in a consumer Azure repository: new library modules, environment stacks, CI pipelines, remote-state bootstrap, and Azure OIDC connections. It uses Azure CLI only and stops at `terraform plan`. Use it when scaffolding or walking through any of that work.

## Install

```bash
npx skills add kdcllc/skills --skill terraform-azure
```

That works for Claude Code, Cursor, GitHub Copilot, Codex, Windsurf, Gemini CLI and any other agent that reads skills. Add `-g` to install for your user instead of the current project, or `-a <agent>` to target one agent.

Install the four Azure Terraform skills together:

```bash
npx skills add kdcllc/skills --skill terraform-azure terraform-azure-modules terraform-azure-pipelines terraform-azure-upgrade
```

Other ways to install:

| Where | Command |
| --- | --- |
| GitHub CLI (`gh` 2.90+) | `gh skill install kdcllc/skills terraform-azure` |
| Claude Code (whole pack) | `/plugin marketplace add kdcllc/skills` then `/plugin install kdcllc-skills@kdcllc` |
| Copilot CLI (whole pack) | `copilot plugin marketplace add kdcllc/skills` then `copilot plugin install kdcllc-skills@kdcllc` |
| Pin to a release | `npx skills add kdcllc/skills#terraform-azure/vX.Y.Z --skill terraform-azure` ([releases](https://github.com/kdcllc/skills/releases)) |
| Claude Code / Copilot CLI (Azure bundle) | `/plugin install kdcllc-azure@kdcllc` (the four Azure Terraform skills plus azure-rbac-least-privilege) |

Every install channel (Codex, Cursor marketplace) is described in the [repository README](https://github.com/kdcllc/skills#install).

## Use it

The agent first shows a five-item menu and waits for you to pick one:

1. New module (a reusable module under `modules/<name>/`)
2. New stack (one root module per domain under `resources/<domain>/`)
3. New pipeline (fmt, validate and plan for Azure DevOps, GitHub Actions and GitLab)
4. Bootstrap state storage (remote state resource group, storage account and container)
5. Create Azure connections (OIDC or service connections for CI)

Example prompts:

- "Use terraform-azure to create a new stack for key vaults."
- "Bootstrap remote state storage for the dev environment."
- "Create the OIDC connection for our CI pipeline."

The skill never runs `terraform apply`, `terraform destroy` or `azd`. After writing HCL it runs `terraform fmt -check`, `terraform init -backend=false` and `terraform validate`. Apply and destroy stay with you or a gated pipeline.

## Requirements

- Azure CLI (`az`), Terraform 1.15.8, Git, and bash or PowerShell 7
- Optional: `gh`, `az devops`, `glab`
- For bootstrap and connections, run `az login` and `az account set` first; the bundled scripts exist as bash and PowerShell versions

## More

- [SKILL.md](SKILL.md) — the instructions the agent follows
- [CHANGELOG.md](CHANGELOG.md) — release history
- [references/using-the-pack.md](references/using-the-pack.md) — operator guide: the model, resource group layout, versions, updating
- [references/deep-dive.md](references/deep-dive.md) — end-to-end walkthroughs
- [references/operating-process.md](references/operating-process.md) — the process contract the agent follows
