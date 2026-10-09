# Using the Terraform Azure skills

Operator guide for a **consumer** Azure Terraform repository: the model the four Terraform Azure skills (`terraform-azure`, `terraform-azure-modules`, `terraform-azure-pipelines`, `terraform-azure-upgrade`) build to, the resource group layout you now choose, how versions work, and how to update.

- Full end-to-end walkthroughs (module → stack → state → OIDC → pipeline, plus an upgrade pass): [deep-dive.md](deep-dive.md)
- The binding contract the agent follows, inside the installed skill: [operating-process.md](operating-process.md) (process), [ai-conventions.md](ai-conventions.md) (layout freeze), [resource-group-layout.md](resource-group-layout.md) (resource groups)
- What changed in each release: the `CHANGELOG.md` next to each skill's `SKILL.md` (this skill's is [../CHANGELOG.md](../CHANGELOG.md))
- Release policy and the maintainer checklist: [CONTRIBUTING.md](https://github.com/kdcllc/skills/blob/master/CONTRIBUTING.md#releases) in kdcllc/skills

---

# Part 1 — The model, and the choice you now make

## The model in one page

| Thing | Where | Rule |
| --- | --- | --- |
| **Module** (interface) | `modules/<name>/` | One primary Azure resource type per folder. Reusable, no backend. |
| **Stack** (class) | `resources/<domain>/` | One **domain** per stack. `.tf` written once; environments are tfvars files in `envs/`, not folders. |
| **Domain** | a catalog row | `networking`, `key-vaults`, `storage`, … each with a dependency tier and an `rg_segment`. |
| **Composition** | `data.tf` | Stacks read each other with azurerm `data` blocks only — never `terraform_remote_state`, never cross-stack module outputs. |
| **State** | one key per stack per environment | `tfstate.{resource}.{domain}.{environment}` |

Naming is deterministic — `{abbr}-{organization_name}-{resource}-{environment}` — where `{resource}` is the **workload** (`webapp`) and stays identical across all of that workload's stacks. That determinism is what lets a downstream stack reconstruct an upstream name without anything being passed between stacks.

## The resource group question

When you ask for a new stack, the agent now asks a sixth create-time question: **how should resources be grouped into resource groups?**

| | `per-type` (default) | `single` |
| --- | --- | --- |
| Grouping | One RG **per domain** — all key vaults together, all storage together, all container apps and their environments together | One RG for the **whole workload** |
| RG name | `rg-acme-webapp-kv-dev` (`kv` = the domain's `rg_segment`) | `rg-acme-webapp-dev` |
| Who creates it | Each domain stack creates its own | The tier-1 `resource-group` stack |
| `resources/resource-group/` | does not exist | exists, runs first |
| Blast radius | One RG per resource type | One RG holds everything |

### Which to pick

Choose **`per-type`** when different resource types have different lifecycles, owners, or access rules — a platform team owning networking while an app team owns container apps, RBAC or policy scoped per resource type, or deletion of one type that must not be able to reach another. It is the default because RG-scoped role assignments and locks are the usual way to separate those concerns.

Choose **`single`** when the workload is small and one team owns all of it, and you want one resource group to grant, audit, and tear down. It is also the right answer for a workload that *is* just a resource group, and it is what every repo built before this feature already uses.

### The rules

1. **One layout per workload.** Every stack for `webapp` must agree. Downstream stacks derive upstream RG names from the layout, so a mismatch fails `data.tf` at plan time.
2. **The segment comes from the catalog**, not from taste: `net`, `id`, `obs`, `kv`, `acr`, `st`, `db`, `aca`, `app`. Adding a domain row means adding a segment for it.
3. **Only the resource group carries the domain in its name.** A key vault inside `rg-acme-webapp-kv-dev` is still `kv-acme-webapp-dev`.
4. **Never convert a live workload between layouts.** That moves Azure resources between resource groups — a human-reviewed operation, not a skill task.

## What you get on disk

Ask for "a VNet, key vault, storage, ACR, Log Analytics and container apps" for workload `webapp`, and the default `per-type` answer produces six stacks, each owning its own resource group:

```
resources/networking/          → rg-acme-webapp-net-dev
resources/observability/       → rg-acme-webapp-obs-dev
resources/key-vaults/          → rg-acme-webapp-kv-dev
resources/container-registry/  → rg-acme-webapp-acr-dev
resources/storage/             → rg-acme-webapp-st-dev
resources/container-apps/      → rg-acme-webapp-aca-dev
```

Each stack's `main.tf` opens with its own resource group and wires the rest of the domain to it:

```hcl
module "resource_group" {
  source = "../../modules/resource_group"

  organization_name = var.organization_name
  resource          = var.resource
  environment       = var.environment
  location          = var.location
  name_segment      = "kv" # rg_segment from the catalog
  tags              = var.tags
}

module "key_vault" {
  source = "../../modules/key_vault"

  resource_group_name = module.resource_group.resource_group.name
  # ...
}
```

Where a stack reads an **upstream** domain, `data.tf` names that domain's resource group:

```hcl
locals {
  upstream_rg = {
    "observability" = "rg-${var.organization_name}-${var.resource}-obs-${var.environment}"
  }
}

data "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.organization_name}-${var.resource}-${var.environment}"
  resource_group_name = local.upstream_rg["observability"]
}
```

Answer `single` instead and you get a seventh stack, `resources/resource-group/`, owning `rg-acme-webapp-dev`. Every other stack then reads it through one `data "azurerm_resource_group" "this"` block and lists `resource-group` under `upstream_domains`.

## Recorded per stack

Each stack carries a `stack-decision.md`. Two keys hold this decision:

```yaml
resource_group_layout: per-type   # or single — same in every stack of the workload
resource_group_name: rg-acme-webapp-kv-dev
```

A record with **no** `resource_group_layout` key predates the feature and means `single`. Add the key when you next touch that stack; do not change what it says.

## Adding a domain later

Adding a key vault to a `per-type` workload does not mean editing an existing `main.tf`. It means a new `resources/key-vaults/` stack that creates `rg-acme-webapp-kv-dev` and reads what it needs through `data.tf` — one new folder, one new state key, one new pipeline. Under `single` it is the same, except the new stack reads the shared resource group instead of creating one.

## Pipelines

Plan order follows dependency tier: a `data` block fails until its upstream stack has been applied. Under `single`, the `resource-group` stack is tier 1 and runs first. Under `per-type` there is no such job — each stack creates its own resource group as part of its own plan.

---

# Part 2 — Versions

Each skill has **its own version**. A release of one skill is the git tag `<skill>/vX.Y.Z` in [kdcllc/skills](https://github.com/kdcllc/skills), for example `terraform-azure/v1.0.0` or `terraform-azure-pipelines/v1.2.0`. A skill is only released when its own folder changes, so the four Terraform Azure skills can sit at different versions.

## What do I have installed?

Installed skills are file copies with no git context, so the version travels in each `SKILL.md` frontmatter (`metadata.version`), and each skill folder carries its own `CHANGELOG.md`:

```bash
grep -A1 '^metadata:' .claude/skills/terraform-azure/SKILL.md
npx skills ls          # project scope
npx skills ls -g       # user scope
```

## Install forms

| Goal | Command |
| --- | --- |
| **Pin a release** (recommended) | `npx skills add kdcllc/skills#terraform-azure/vX.Y.Z --skill terraform-azure` |
| Default-branch tip (moves without notice) | `npx skills add kdcllc/skills --skill terraform-azure` |
| Preview an unreleased branch | `npx skills add kdcllc/skills#<branch> --skill terraform-azure` |
| A local working copy, uncommitted edits included | `npx skills add /path/to/skills --skill terraform-azure` |
| All four Terraform Azure skills | `--skill terraform-azure terraform-azure-modules terraform-azure-pipelines terraform-azure-upgrade` |
| See what would be installed, without installing | add `--list` |

The ref goes after `#`. `@name` selects a single skill, not a version. A tag pins the whole repository at that commit, so pin each skill with its own tag: run one `npx skills add` per skill when you pin.

The skills link to each other (for example, `terraform-azure` copies pipeline files out of `terraform-azure-pipelines`). Install all four together; installing one on its own leaves those links pointing at a folder that isn't there.

Two things to know about non-tag installs:

- A **branch** install carries whatever `metadata.version` was last released for that skill, so frontmatter cannot tell you that you are on a branch. Track that yourself.
- Unreleased work lives under `## [Unreleased]` in the skill's own `CHANGELOG.md`; released behaviour sits under its own `## [X.Y.Z]` heading. On a branch, read the changelog rather than the frontmatter to know what you got.

Which kind of change bumps MAJOR, MINOR, or PATCH is defined in [CONTRIBUTING.md](https://github.com/kdcllc/skills/blob/master/CONTRIBUTING.md#releases). Changes outside a skill's folder (repo scripts, `.github/`, the README) ship nothing to consumers and get no release of their own.

---

# Part 3 — Updating

## Updating the skills on your workstation

```bash
npx skills update
```

`update` re-downloads from the ref recorded in the lockfile (`skills-lock.json`), so a pinned install **stays on its tag** — that is the point of pinning. To move to a new release, read the target version's entry in that skill's `CHANGELOG.md` first, then re-add with the new tag:

```bash
npx skills add kdcllc/skills#terraform-azure/vX.Y.Z --skill terraform-azure
```

Release notes for every tag are also on the [kdcllc/skills releases page](https://github.com/kdcllc/skills/releases).

`npx skills experimental_install` restores a project's skills from `skills-lock.json` — what you want on a fresh clone or in CI.

## Updating your consumer repo

A new skill version changes what the agent *writes next*; it does not reach into Terraform you already have. When a release carries **Upgrade notes**, work them in this order:

1. **Read `### Upgrade notes`** for the target version in the changelog. Those notes exist only when consumers must act.
2. **Decide per stack**, not per repo. Nothing forces every stack to move at once.
3. **Re-run the validation ladder** — tier 1 (`terraform fmt -check`, `terraform init -backend=false`, `terraform validate`), then tier 2 (`plan`) with credentials. Stop at plan.
4. **Read every plan before applying.** If a plan proposes creating resources you know exist, stop: that is usually a state key or a name that moved, not a real diff. Never let a re-keyed stack apply a create-from-scratch over live infrastructure.

### Resource group layout, specifically

Repos built before this feature are `single`, and **nothing moves**:

- Add `resource_group_layout: single` and `resource_group_name:` to each existing `stack-decision.md`. A record without the key is already read as `single`.
- New workloads default to `per-type`. The agent asks — answer deliberately rather than taking the default out of habit.
- A `resource_group` module copied before this release has no `name_segment` variable, so a `per-type` stack passing one fails until you add it (string, default `""`).
- Do not convert an existing workload between layouts.

## Releasing (maintainers)

In a clone of kdcllc/skills, write the notes under `## [Unreleased]` in the skill's `CHANGELOG.md` and commit them, then run `bash scripts/release-skill.sh <skill> X.Y.Z`. It promotes the notes to `## [X.Y.Z]`, bumps that skill's `metadata.version`, validates the repo, commits, and creates the annotated tag `<skill>/vX.Y.Z`. It never pushes; pushing the tag is the publish event. Never hand-edit versions or tag by hand. Full checklist: [CONTRIBUTING.md](https://github.com/kdcllc/skills/blob/master/CONTRIBUTING.md#releases).
