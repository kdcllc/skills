# Deep dive: using the Terraform Azure skills

This walkthrough is a full pass through the four Terraform Azure skills (`terraform-azure`, `terraform-azure-modules`, `terraform-azure-pipelines`, `terraform-azure-upgrade`) in a **consumer** Azure Terraform repository. You do **not** run this inside the [kdcllc/skills](https://github.com/kdcllc/skills) repo. Install the skills, then work in an empty (or existing) Terraform repo.

Three scenarios:

1. [Minimal stack](#scenario-a-minimal-resource-group-stack) — resource group, remote state, OIDC, GitHub Actions plan (`webapp`).
2. [Microsoft Foundry chat on Container Apps](#scenario-b-microsoft-foundry-chat-on-container-apps) — Foundry account, project, model deployment, and a Container App that hosts a chat UI (`chat`).
3. [Upgrade existing modules](#scenario-c-upgrade-existing-modules) — inventory, bounded azurerm 5.x pins, current HashiCorp schema, stop at validate.

All three use org `acme`, environment `dev`, region `eastus` unless noted. Apply remains a human or gated CI step. Skills never run `azd` or `terraform apply` / `destroy`.

## Install in the consumer repo

From the consumer repository:

```bash
npx skills add kdcllc/skills --skill terraform-azure --skill terraform-azure-modules \
  --skill terraform-azure-pipelines --skill terraform-azure-upgrade
```

Or one skill:

```bash
npx skills add kdcllc/skills --skill terraform-azure-upgrade
```

The agent then has `terraform-azure` (operator menu **1–6**), plus the three specialist skills. Workstation: Azure CLI (`az`), Terraform **1.15.8**, Git, bash or PowerShell 7.

---

# Scenario A: minimal resource-group stack

Goal: one library module (`resource_group`), one stack (`webapp` in `dev`), remote state, GitHub OIDC, a plan-only workflow.

## A1. Menu 1 — new module

Ask the agent for **terraform-azure menu 1**. It copies templates into:

```
modules/resource_group/
  providers.tf
  main.tf
  variables.tf
  outputs.tf
```

Pins: `azurerm >= 5.0.0, < 6.0.0`, `required_version = ">= 1.9.0, < 2.0.0"`. Resource names use `{abbr}-{organization_name}-{resource}-{environment}` (example: `rg-acme-webapp-dev`). No `backend.tf` on the module. Query **current** azurerm docs for `azurerm_resource_group`.

Tier 1 in that folder: `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`.

## A2. Menu 4 — bootstrap state

From the **installed** `terraform-azure` skill folder (not a git clone of kdcllc/skills):

```bash
./scripts/bootstrap-tfstate.sh \
  --resource-group-name rg-acme-tfstate-dev \
  --location eastus \
  --storage-account-name stacmetfstatedev \
  --container-name tfstate \
  --resource webapp \
  --environment dev
```

This uses Azure CLI only. Record the printed `terraform init -backend-config` flags in the host secret store. Never commit keys or a populated backend-config file.

## A3. Menu 5 — GitHub OIDC

```bash
./scripts/create-azure-oidc.sh --host github \
  --github-org acme --github-repo infra --github-environment dev \
  --state-resource-group rg-acme-tfstate-dev \
  --state-storage-account stacmetfstatedev \
  --assign-state-role
```

Store client / tenant / subscription IDs in GitHub Environment secrets. Follow the skill’s azure-connections reference.

## A4. Menu 2 — new stack

Ask domains, environments (`dev`), location `eastus`, workload `webapp`, and the resource group layout. This scenario answers **`single`** — the only Azure resource in scope *is* the resource group, so it maps to one domain-catalog row, `resource-group`, tier 1:

```
resources/resource-group/
  providers.tf    # resource_provider_registrations = "legacy"
  backend.tf      # empty backend "azurerm" {}
  main.tf         # resource-group modules only
  variables.tf
  stack-decision.md
  envs/
    dev.tfvars
```

No `data.tf` — tier 1 has no upstream domain to read.

Module source is relative and fixed: `source = "../../modules/resource_group"`. **`location` is always** on the stack and in every module block. State key is `tfstate.webapp.resource-group.dev`. `stack-decision.md` records `resource_group_layout: single` and `resource_group_name: rg-acme-webapp-dev`; every later stack for `webapp` must repeat that layout.

Adding a VNet later does **not** mean editing this `main.tf`. It means creating `resources/networking/` with its own `data.tf` that looks the resource group up by name.

Had the operator taken the default **`per-type`** layout instead, there would be no `resources/resource-group/` at all: each domain stack would create its own `rg-acme-webapp-<rg_segment>-dev`. See `references/resource-group-layout.md` in the skill.

## A5. Menu 3 — pipeline

Copy **terraform-azure-pipelines** assets (Terraform **1.15.8**, Entra backend: `use_oidc=true`, `use_azuread_auth=true`). On GitHub that is `tf-deploy-base.yaml` once plus a `terraform-<domain>.yaml` per stack. Point `working_directory` at `resources/resource-group` and `tfvars_file` at `envs/dev.tfvars`. One workflow per domain stack. Default action is plan, not apply.

`terraform fmt -check -recursive` runs before init and **fails the job** — unformatted Terraform never reaches plan.

Every generated workflow also offers **destroy**, gated by a `confirm_destroy` checkbox on the dispatch form. Choosing `destroy` without ticking it fails on the workflow's first step, before checkout and before Azure login. For a human approval step on top of that, add a GitHub Environment with required reviewers to the job — the skills copy YAML, they cannot create protection rules.

### Scenario A — what “done” looks like

- Module and stack pass tier 1 (`fmt` / `init -backend=false` / `validate`).
- Stack `plan` works locally or in CI with OIDC + Entra backend auth.
- The stack holds **one domain**; a second domain would be a second folder.
- No `azd`, no apply from the agent, no secrets in git, no `provider.tf`, no superseded `resources/environments/` layout.

Azure (from scripts, not from Terraform): `rg-acme-tfstate-dev`, storage account, container `tfstate`.

---

# Scenario B: Microsoft Foundry chat on Container Apps

Acme wants a **chat application** in `dev`: a Container App serves the UI/API, and [Microsoft Foundry](https://learn.microsoft.com/azure/foundry/tutorials/quickstart-create-foundry-resources) hosts the model. Azure Container Apps integrates with Foundry for this pattern ([AI integration with Azure Container Apps](https://learn.microsoft.com/azure/container-apps/ai-integration)).

This is still the same pack: menu **1** once per resource type, then menu **2** once **per domain**, then menus **3–5** as in Scenario A. Do not invent a mega-module that owns Foundry plus Container Apps plus ACR — and do not collapse those domains into one stack either.

Ground every resource in **current** azurerm registry pages and Microsoft Learn. If azurerm cannot represent the Foundry **account** or **project**, use **azapi** with a comment that says why. Do not put API keys in tfvars; the chat app authenticates with **managed identity**.

## B1. One module per type

Create (or reuse) library modules under `modules/`, one primary Azure type each, for example:

| Module | Typical resource |
| --- | --- |
| `resource_group` | `azurerm_resource_group` |
| `log_analytics_workspace` | `azurerm_log_analytics_workspace` |
| `container_registry` | `azurerm_container_registry` |
| `user_assigned_identity` | `azurerm_user_assigned_identity` |
| `ai_foundry` / Foundry account | azurerm if documented; otherwise azapi + why-comment |
| `ai_foundry_project` | same rule |
| `cognitive_deployment` (or current Foundry deployment type) | query current docs for the model deployment resource |
| `container_app_environment` | `azurerm_container_app_environment` |
| `container_app` | `azurerm_container_app` |

Each module gets `providers.tf` with azurerm `>= 5.0.0, < 6.0.0`. Naming uses `organization_name` (example: `cae-acme-chat-dev`). Never apply from the skill.

## B2. One stack per domain

This scenario takes the default **`per-type`** resource group layout, so those nine module types map onto **five** domain-catalog rows — five stacks, not one `chat` folder, and no `resource-group` stack. Each stack creates its own RG with `module "resource_group"` and its catalog `rg_segment`:

| Tier | Stack | Owns RG | Modules it owns |
| --- | --- | --- | --- |
| 2 | `resources/identity/` | `rg-acme-chat-id-dev` | `resource_group`, `user_assigned_identity`, role assignments |
| 2 | `resources/observability/` | `rg-acme-chat-obs-dev` | `resource_group`, `log_analytics_workspace` |
| 3 | `resources/container-registry/` | `rg-acme-chat-acr-dev` | `resource_group`, `container_registry` |
| 3 | `resources/ai-foundry/` | `rg-acme-chat-aif-dev` | `resource_group`, Foundry account, project, model deployment (new catalog row) |
| 4 | `resources/container-apps/` | `rg-acme-chat-aca-dev` | `resource_group`, `container_app_environment`, `container_app` |

`ai-foundry` is not in the shipped catalog — add it as a row, with its own `rg_segment` (`aif`), rather than folding Foundry into `container-apps`.

Every stack sets `resource = "chat"` in its tfvars, so each derives the others' names — including which RG an upstream resource sits in. `container-apps/data.tf` reads its upstreams:

```hcl
locals {
  # keys are domain folder names — quote them, hyphens are not bare identifiers
  upstream_rg = {
    "container-registry" = "rg-${var.organization_name}-${var.resource}-acr-${var.environment}"
  }
}

data "azurerm_container_registry" "this" {
  name                = "cr${var.organization_name}${var.resource}${var.environment}"
  resource_group_name = local.upstream_rg["container-registry"]
}
```

Wire modules with relative `source` (`../../modules/<name>`). Pass `location = "eastus"` into every module block.

**Watch the no-exceptions rule.** If azurerm exposes no data source for the Foundry project, the resources that depend on it move into `resources/ai-foundry/` — do **not** add `terraform_remote_state`. Role assignments granting the Container App's identity Foundry access belong in whichever stack can see both sides through data blocks; query **current** Learn docs for the built-in role, do not hard-code a guess.

## B3. Pipelines and secrets

Same as A3–A5, with `--resource chat` on bootstrap, and **one pipeline job per domain stack** — `working_directory` = `resources/<domain>`, state key `tfstate.chat.<domain>.dev`. Order jobs by tier so `data` blocks resolve. Image name / ACR login can come from tfvars or CI; **no Foundry API keys**.

### Scenario B — what “done” looks like

- Nine (or fewer, if some types already exist) modules validate independently.
- **Six** domain stacks validate independently, each with its own state key.
- No stack's `main.tf` contains modules from two catalog rows.
- Cross-stack wiring is `data` blocks only — no `terraform_remote_state`, no cross-stack outputs.
- Chat Container App has no API-key variables; identity is the credential.
- azapi appears only where azurerm cannot represent Foundry account/project, with a why-comment.

---

# Scenario C: upgrade existing modules

Use this when the consumer **already has** `modules/` written against azurerm 3.x / 4.x, mixed pins, `provider.tf`, `skip_provider_registration`, or validate errors after someone bumped azurerm to 5.x.

**Skill:** `terraform-azure-upgrade` (or **terraform-azure menu 6**). Do **not** use `terraform-azure-modules` for a provider major — that skill is for new modules and in-place feature/naming edits.

## What the upgrade skill will not do

- Silently rewrite every folder under `modules/` unless you **list** targets (or say “all modules under modules/” after seeing the inventory).
- Pin `azurerm` to unbounded `latest` or drop the `< 6.0.0` ceiling.
- Vendor or bump Azure Verified Modules (AVM) to dodge the parent constraint.
- Run `terraform apply` or `terraform destroy`.
- “Fix” naming (`organization_name` pattern) unless you ask — default scope is **pins + schema**.

## C1. Invoke it

In the consumer repo (skills already installed):

> Upgrade our existing Terraform Azure modules to azurerm 5.x. Start with an inventory; I will pick which folders.

Or pick the menu:

> terraform-azure — item 6.

The agent must follow `skills/terraform-azure-upgrade/SKILL.md` after install (path varies by host: often `.agents/skills/terraform-azure-upgrade/` or `.claude/skills/…`).

## C2. Read the inventory, then name targets

The skill’s first step is a table, for example:

| Path | Current azurerm | Notes |
| --- | --- | --- |
| `modules/key_vault` | `~> 3.0` | `enable_rbac_authorization`; `provider.tf` |
| `modules/storage_account/blob` | `>= 4.0.0` | `storage_container_name` |
| `modules/resource_group` | `>= 5.0.0, < 6.0.0` | already on target pins |

You then choose:

- **One folder** — default, lowest risk. Example: `modules/key_vault`.
- **An explicit list** — `modules/key_vault` and `modules/storage_account/blob`.
- **All under `modules/`** — only after you have seen the inventory and said so.

Until you answer, the agent must not edit HCL.

## C3. What happens inside one folder

For each agreed path the agent:

1. Sets `providers.tf` (renames `provider.tf` if needed) to:

   ```hcl
   terraform {
     required_version = ">= 1.9.0, < 2.0.0"
     required_providers {
       azurerm = {
         source  = "hashicorp/azurerm"
         version = ">= 5.0.0, < 6.0.0"
       }
     }
   }
   ```

2. Removes `backend.tf` from **library** modules (backends belong on stacks).
3. Opens the **current** [azurerm 5.0 upgrade guide](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/5.0-upgrade-guide) and the **current** registry page for every resource type in that folder. The upgrade skill’s [reference](../../terraform-azure-upgrade/references/reference.md) is a set of **examples** (Key Vault `rbac_authorization_enabled`, diagnostic `enabled_metric`, blob `storage_container_id`, and so on). If the live docs disagree, **docs win**.
4. Replaces removed arguments. Keeps your variable names when only the resource argument renamed (alias in the resource block). Drops arguments that have **no successor** (example historically: `soft_delete_enabled` on Recovery Services vault) and reports the behavior change.
5. Runs **only in that directory**:

   ```bash
   terraform fmt -check -diff .
   terraform init -backend=false
   terraform validate
   ```

6. Fixes the **first** remaining validate error, then the next, until the directory is clean or it must stop (undocumented schema, needs your choice). Then the next agreed folder.

Example Key Vault rename (confirm on the live resource page before copying):

```hcl
# 4.x
enable_rbac_authorization = var.enable_rbac_authorization

# 5.x — argument renamed; variable may stay
rbac_authorization_enabled = var.enable_rbac_authorization
```

## C4. Stacks (only if you include them)

If you also name a stack such as `resources/networking`:

- Keep empty `backend "azurerm" {}`.
- On the **root** provider, set `resource_provider_registrations` (`"legacy"` unless RPs are pre-registered — then `"none"`).
- Delete `skip_provider_registration` (removed in 5.x). azurerm 5.x registers **none** by default; `"legacy"` is how stacks keep 4.x-like first-plan RP registration.

Do not ask the upgrade skill to rearrange `resources/` or to invent `location`. If it finds a superseded `resources/environments/` tree or a mega-stack mixing domains, it reports and stops — restructuring is `terraform-azure` menu 2.

## C5. Pipelines (optional)

If workflows still pin Terraform 1.8.x / 1.10.x, say so. The agent copies **terraform-azure-pipelines** assets (1.15.8) instead of rewriting YAML from memory.

## C6. Read the report, then you apply

The skill ends with a per-path report:

- Old constraint → new constraint
- Arguments/blocks changed, with the registry URL used
- Remaining validate errors (fail closed — do not mark those folders done)
- Reminder that **apply is still yours** (or gated CI)

Then you (or a gated pipeline) run `plan` against a real stack that consumes the upgraded module, and apply when you accept the plan. State may show in-place updates or replacements depending on the schema change (for example blob identity moving to `storage_container_id`). Review that plan yourself.

## C7. Worked prompt sequence

Copy-paste this in the consumer repo after install:

1. `Upgrade existing Azure Terraform modules. Inventory modules/ and show pins and skip_provider_registration. Do not edit yet.`
2. After the table: `Upgrade only modules/key_vault. Query current azurerm 5.x docs. Stop at validate. Do not apply.`
3. If validate is green: `Upgrade modules/storage_account/blob the same way.`
4. When a stack still fails plan: `Include resources/networking: set resource_provider_registrations, remove skip_provider_registration. Still no apply.`

Bulk only when you mean it:

> Inventory looked right. Upgrade **all** modules under `modules/`, one directory at a time, fail closed on validate, report leftovers. Do not apply.

## C8. When to stop and escalate

Stop the skill and ask a human when:

- Current docs do not document a replacement for a removed argument you still need.
- A child AVM pin conflicts with `azurerm >= 5.0.0, < 6.0.0` — **do not** weaken the parent bound; rewrite to first-party azurerm or leave that module unupgraded in the report.
- Foundry / preview resources still need azapi — allowed only with a why-comment, same as Scenario B.

### Scenario C — what “done” looks like

- Every **agreed** module directory has `providers.tf` with azurerm `>= 5.0.0, < 6.0.0` and `required_version = ">= 1.9.0, < 2.0.0"`.
- `terraform init -backend=false && terraform validate` succeeded in those directories.
- Remaining failures are listed, not hidden.
- No apply, no `azd`, no unbounded provider pin, no unnamed bulk rewrite.