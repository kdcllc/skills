---
name: terraform-azure
description: >-
  Guides operators through the Terraform Azure operating process — new library
  modules, environment stacks, CI pipelines (Azure DevOps, GitHub Actions,
  GitLab), remote-state bootstrap, and Azure OIDC connections — using Azure CLI
  only and stopping at plan. Use when scaffolding or walking through module,
  stack, pipeline, bootstrap, or connection work in a consumer Azure Terraform
  repository.
license: MIT
metadata:
  version: "1.0.0"
---

# Terraform Azure (`terraform-azure`)

Human operators and agents share one contract: [references/operating-process.md](references/operating-process.md). Layout freeze: [references/ai-conventions.md](references/ai-conventions.md). Resource group layout: [references/resource-group-layout.md](references/resource-group-layout.md). Operator guide (model, versions, updating): [references/using-the-pack.md](references/using-the-pack.md). End-to-end walkthroughs: [references/deep-dive.md](references/deep-dive.md).

**Workstation tools:** Azure CLI (`az`), Terraform **1.15.8**, Git, bash or PowerShell 7. Optional: `gh`, `az devops`, `glab`.

For extra **file-shape** patterns only (not version pins), read sibling skills on demand:

- [../terraform-azure-modules/SKILL.md](../terraform-azure-modules/SKILL.md) — library module layout
- [../terraform-azure-pipelines/SKILL.md](../terraform-azure-pipelines/SKILL.md) — pipeline layout

After writing HCL, run **tier 1** (`terraform fmt -check`, `terraform init -backend=false`, `terraform validate`) in the module or stack directory. Never run a full-library sweep from this skill.

This skill ships templates under [assets/templates/](assets/templates/) and helper scripts under [scripts/](scripts/). Paths below are **relative to this skill folder** unless they name a path in the **consumer** repository (`modules/`, `resources/`, `.github/workflows/`, `pipelines/`).

## Step 0 — Ask which menu item

**Before any scaffolding**, present the five-item menu and ask which path to take:

| # | Menu item | Delivers |
| --- | --- | --- |
| **1** | **New module (interface)** | Reusable library module under `modules/<name>/` |
| **2** | **New stack (class)** | One root module **per domain** under `resources/<domain>/` |
| **3** | **New pipeline** | CI for fmt / validate / plan (ADO + GHA + GitLab) |
| **4** | **Bootstrap state storage** | One-shot remote state RG + storage + container |
| **5** | **Create Azure connections** | OIDC / service connections for CI |

Do not assume a menu choice. Wait for the operator to pick **1–5**, then follow only that section.

---

## Must NOT (binding prohibitions)

This skill and agents using it **must not**:

- Run or instruct **Azure Developer CLI** (`azd`) — including deploy/up workflows, package-manager invocation, or adding it as a documented dependency.
- Run **`terraform apply`** or **`terraform destroy`** — stop at tier 2 (plan). Apply and destroy are for humans or gated CI only.
- Reference host-specific editor extension tool IDs — name documentation tools by role only.
- Inline a second bootstrap implementation — use the checked-in scripts (menu items 4 and 5).
- Create a populated `resources/` tree during skill authoring; templates only unless the operator chose menu item 2 and confirmed paths.
- Author a **mega-stack** — one `main.tf` holding modules from more than one domain-catalog row. One domain per stack, always.
- Wire one stack to another with `terraform_remote_state`, a cross-stack module output, or an upstream ID hardcoded in tfvars. Cross-stack reads are azurerm `data` blocks only.
- Emit the superseded `resources/environments/<env>/<resource>/` layout, or duplicate `.tf` files per environment.
- Use filename **`provider.tf`** — this library standard is **`providers.tf`** only.

---

## Menu 1 — New module (interface)

**Target (consumer repo):** `modules/<snake_name>/` — one primary Azure resource type per folder.

Read [../terraform-azure-modules/SKILL.md](../terraform-azure-modules/SKILL.md) for file-shape details, then follow this section.

### Reuse first

List `modules/` in the **consumer** repository. If a sibling already covers the resource, **update that module** instead of duplicating.

### Files (from this skill's templates)

Copy and adapt from [assets/templates/module/](assets/templates/module/):

| File | Template |
| --- | --- |
| `main.tf` | `assets/templates/module/main.tf.tmpl` |
| `variables.tf` | `assets/templates/module/variables.tf.tmpl` (must include `organization_name`) |
| `outputs.tf` or `output.tf` | `assets/templates/module/outputs.tf.tmpl` — match sibling modules in the consumer repo |
| `providers.tf` | `assets/templates/module/providers.tf.tmpl` |

**Required conventions:**

- **`providers.tf`** with `azurerm` `>= 5.0.0, < 6.0.0` and `required_version = ">= 1.9.0, < 2.0.0"`.
- **`organization_name`** variable on every library module.
- **No** `provider.tf` filename.
- **No** `backend.tf` on library modules.
- **No** `resource_provider_registrations` on library modules — that belongs on domain stacks only.

### Naming

Canonical pattern (one pattern only):

```
{resource-type}-{organization_name}-{resource}-{environment}
```

Example: `rg-acme-webapp-dev` (`rg` = resource-type abbreviation).

Use placeholders like `acme` in examples — never real org names, subscription IDs, or keys.

### Validation (tier 1)

```bash
terraform fmt -check -diff modules/<name>
cd modules/<name> && terraform init -backend=false && terraform validate
```

---

## Menu 2 — New stack (class)

**Target (consumer repo):** one root module **per domain**, consuming library modules via relative `source`, written once and reused across environments.

### Rule 0 — decompose before you write

An operator asking for "a resource group, VNet, container apps, ACR, key vault, storage and Log Analytics" is asking for **six or seven stacks (by layout), not one file**. Before creating anything:

1. Map every requested Azure resource onto exactly one row of the **domain catalog** below.
2. Create one stack folder per distinct domain.
3. Wire lower-tier domains into higher-tier ones with `data` blocks (Rule 2).

**Never** emit a single `main.tf` holding modules from more than one domain. If you catch yourself adding a second domain's module to an existing stack, stop and create that domain's own folder instead.

#### Domain catalog

Tier is dependency order — a stack may read from **lower** tiers only.

| Tier | Domain folder | `rg_segment` | Typical Azure resources |
| --- | --- | --- | --- |
| 1 | `resource-group` | — (`single` only) | resource group |
| 2 | `networking` | `net` | virtual network, subnets, NSGs, private DNS zones, private endpoints |
| 2 | `identity` | `id` | user-assigned managed identities, role assignments |
| 2 | `observability` | `obs` | Log Analytics workspace, Application Insights |
| 3 | `key-vaults` | `kv` | key vault, key vault secrets |
| 3 | `container-registry` | `acr` | container registry |
| 3 | `storage` | `st` | storage accounts, blob containers |
| 3 | `databases` | `db` | SQL, PostgreSQL, Cosmos DB |
| 4 | `container-apps` | `aca` | Container Apps environment, container apps |
| 4 | `app-services` | `app` | service plans, web apps, function apps |

Operators may add rows, and a new row needs an `rg_segment`. Do **not** invent a folder name when a row already covers the resource, and do **not** merge two rows into one stack.

Worked example — the request above in the default `per-type` layout becomes six stacks, each owning `rg-acme-webapp-<rg_segment>-dev`:

```
resources/networking/           (tier 2)
resources/observability/        (tier 2)
resources/key-vaults/           (tier 3)
resources/container-registry/   (tier 3)
resources/storage/              (tier 3)
resources/container-apps/       (tier 4)
```

The `single` layout adds `resources/resource-group/` (tier 1), which owns the workload's one RG.

### Rule 1 — directory layout

`.tf` is written **once per domain**; only tfvars vary per environment.

```
resources/<domain>/
  main.tf            # modules for THIS domain only
  data.tf            # lookups of other domains (omit for tier 1)
  variables.tf
  providers.tf
  backend.tf
  stack-decision.md
  envs/
    dev.tfvars
    prod.tfvars
```

Working directory is `resources/<domain>/` for every environment.

**Rejected:** `resources/environments/<env>/<resource>/` (superseded), `infra/resources/`, and any layout that duplicates `.tf` per environment.

**Module `source` (frozen — one row):** `source = "../../modules/<name>"`.

### Rule 2 — cross-stack reads are data blocks only

A stack reads another domain through an azurerm `data` block. Because naming is deterministic and `var.resource` is identical across a workload's stacks, the downstream stack **reconstructs** the upstream name from variables it already has:

```hcl
# resources/key-vaults/data.tf — per-type: read the UPSTREAM domain's RG
locals {
  upstream_rg = {
    "observability" = "rg-${var.organization_name}-${var.resource}-obs-${var.environment}"
  }
}

# single: data "azurerm_resource_group" "this" { name = "rg-${var.organization_name}-${var.resource}-${var.environment}" }
```

**Forbidden:** `terraform_remote_state`, cross-stack module outputs, and upstream IDs hardcoded into tfvars. If azurerm publishes no data source for a type, its dependents belong in the **same** stack as that resource — that is the only merge this skill allows.

Stack `outputs.tf` is optional, for humans and CI logs only — never a cross-stack contract.

### Resource group layout

| Layout | Resource group | Owner |
| --- | --- | --- |
| **`per-type`** (default) | One per domain — `rg-acme-webapp-kv-dev` | The domain's own stack, `module "resource_group"` with `name_segment` = catalog `rg_segment`. No `resource-group` stack. |
| **`single`** | One per workload — `rg-acme-webapp-dev` | Tier-1 `resource-group` stack; others read it with a `data` block. |

Chosen **once per workload** and identical in every stack of that workload. A stack owning its RG in `per-type` is still one domain. Full rules and HCL: [references/resource-group-layout.md](references/resource-group-layout.md).

### Ask at create time (required)

Before writing files, ask:

1. **Domains** — which resources are in scope, so they can be mapped to catalog rows.
2. **Environments** — e.g. `dev`, `test`, `prod` (one `envs/<env>.tfvars` file each).
3. **Azure region (location)** — e.g. `eastus`, `westeurope`.
4. **Subscription** — current `az account show` subscription, or another subscription ID.
5. **Region in layout** — whether `<region>` appears in the **tfvars filename**, the **resource name**, the **state key**, several, or none.
6. **Resource group layout** — `per-type` (**default**, one RG per domain) or `single` (one RG per workload). Same answer for every stack of the workload.

**location is always** a stack variable in `variables.tf` and **is always** passed into every `module` block, even when region appears nowhere else. Modules never infer region from path alone.

Region-in-path affects only the tfvars filename (`resources/<domain>/envs/<env>.<region>.tfvars`). Module `source` depth never changes.

### Naming

`var.resource` is the **workload** (`webapp`), identical in every domain stack for that workload. The domain lives in the folder and state key, never in the resource name:

- Correct: `kv-acme-webapp-dev`, `vnet-acme-webapp-dev`
- Wrong: `kv-acme-key-vaults-dev`
- Only exception — the RG in the `per-type` layout: `rg-acme-webapp-kv-dev`

### State keys

```
tfstate.{resource}.{domain}.{environment}
```

Example: `tfstate.webapp.networking.dev`. Append `.{region}` when region-in-key is chosen. One state file per domain per environment.

### Stack files (from this skill's templates)

Copy and adapt from [assets/templates/stack/](assets/templates/stack/), once per domain:

| File | Template |
| --- | --- |
| `main.tf` | `assets/templates/stack/main.tf.tmpl` — one domain's modules only |
| `data.tf` | `assets/templates/stack/data.tf.tmpl` — omit when `upstream_domains` is empty |
| `variables.tf` | `assets/templates/stack/variables.tf.tmpl` — **must** declare `location` |
| `providers.tf` | `assets/templates/stack/providers.tf.tmpl` — sets `resource_provider_registrations = "legacy"` |
| `backend.tf` | `assets/templates/stack/backend.tf.tmpl` — empty `backend "azurerm" {}` |
| `envs/<env>.tfvars` | `assets/templates/stack/dev.tfvars.tmpl` — one per environment, all in `envs/` |

### Stack decision record

Write **`stack-decision.md`** in each domain stack using [assets/templates/stack-decision.md](assets/templates/stack-decision.md). Required keys: `domain`, `resource`, `environments`, `region`, `location`, `subscription_id`, `region_in_path`, `region_in_name`, `region_in_key`, `resource_group_layout`, `resource_group_name`, `working_directory`, `tfvars`, `state_keys`, `module_sources`, `upstream_domains`.

`domain` must be a single catalog row — two domains in one record means the stack needs splitting. Every `upstream_domains` entry must have a matching `data` block in `data.tf`.

Do **not** store storage account keys, SAS tokens, or client secrets in this file.

### Root provider

Stack `providers.tf` **must** set `resource_provider_registrations` explicitly (default `"legacy"` in template). Use `"none"` only when a platform team has pre-registered providers. **Forbidden:** `skip_provider_registration`.

### Validation

Run per domain stack. Tier 1 (no Azure credentials):

```bash
terraform fmt -check -diff resources/<domain>
cd resources/<domain> && terraform init -backend=false && terraform validate
```

Tier 2 (plan only — requires `az login`):

```bash
cd resources/<domain>
terraform init \
  -backend-config=resource_group_name=<RG> \
  -backend-config=storage_account_name=<SA> \
  -backend-config=container_name=tfstate \
  -backend-config=key=<state_key for this domain+env> \
  -backend-config=use_oidc=true \
  -backend-config=use_azuread_auth=true
terraform plan -var-file=envs/<env>.tfvars
```

Plan tier-1 domains before higher tiers — a `data` block fails until the upstream stack has been applied by a human or gated CI. A downstream plan that fails on a missing data source is expected, not a defect; report it and stop.

Stop at plan. Do not apply or destroy.

---

## Menu 3 — New pipeline

Read [../terraform-azure-pipelines/SKILL.md](../terraform-azure-pipelines/SKILL.md) and **copy assets** from that sibling skill into the consumer repo. Do not invent YAML; do not copy older Terraform pins.

Wire CI **per domain stack** — each domain gets its own pipeline (or its own caller job) because each has its own working directory and its own state key. Do not wire seven domains into one job.

Read values from that stack's **`stack-decision.md`**:

- `working_directory` → pipeline working directory (`resources/<domain>`)
- `state_keys.<env>` → backend blob key
- `tfvars.<env>` → tfvars parameter (`envs/<env>.tfvars`)

Trigger paths should watch `resources/<domain>/**` so an unrelated domain's change does not run every plan.

**Terraform CLI pin:** **1.15.8**.

### Azure DevOps

Copy `../terraform-azure-pipelines/assets/azure-pipelines.yaml` to `pipelines/azure_dev_ops/shared/azure-pipelines.yaml` in the consumer repo. Copy `../terraform-azure-pipelines/assets/examples/dev-azure-pipelines.yaml` as a starting wrapper under `pipelines/azure_dev_ops/<env>/`.

Parameterize from the decision record. Use placeholder names like `acme` — never real subscription IDs or keys in committed YAML.

### GitHub Actions

Copy `../terraform-azure-pipelines/assets/tf-deploy-base.yaml` once to `.github/workflows/tf-deploy-base.yaml`, then copy `../terraform-azure-pipelines/assets/examples/terraform-domain.yaml` **per domain** to `.github/workflows/terraform-<domain>.yaml`. One caller per domain stack, one shared base:

```
.github/workflows/
  tf-deploy-base.yaml
  terraform-resource-group.yaml
  terraform-networking.yaml
  terraform-key-vaults.yaml
```

Caller workflow example:

```yaml
name: Terraform Networking

on:
  pull_request:
    paths:
      - 'resources/networking/**'
  workflow_dispatch:
    inputs:
      terraform_action:
        type: choice
        options: [plan, apply, destroy]
        default: plan
      confirm_destroy:
        description: '⚠️ DESTROY: tick to confirm teardown'
        type: boolean
        default: false
      environment:
        type: choice
        options: [dev, prod]
        default: dev

jobs:
  terraform:
    uses: ./.github/workflows/tf-deploy-base.yaml
    with:
      working_directory: resources/networking
      tfvars_file: envs/${{ inputs.environment || 'dev' }}.tfvars
      terraform_action: ${{ inputs.terraform_action || 'plan' }}
      environment: ${{ inputs.environment || 'dev' }}
      backend_state_key: tfstate.webapp.networking.${{ inputs.environment || 'dev' }}
      confirm_destroy: ${{ inputs.confirm_destroy || false }}
    secrets: inherit
```

Default `terraform_action` is **plan**. Apply is opt-in only — this skill never triggers apply. Destroy is offered but requires the `confirm_destroy` checkbox in addition to picking `destroy`; the run fails on its first step, before checkout and Azure login, if the box is unticked.

`terraform fmt -check -recursive` runs before init and **fails the job**. Never soften it with `continue-on-error`.

Backend storage settings come from repository/environment **variables** (`TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`), not hardcoded in workflows.

### GitLab CI

Copy `../terraform-azure-pipelines/assets/gitlab-ci-terraform-template.yml` to `.gitlab/pipelines/gitlab-ci-terraform-template.yml`. Pin image `hashicorp/terraform:1.15.8`.

Set from the decision record and CI/CD variables:

```yaml
variables:
  TF_ROOT: "resources/networking"
  TFVARS_FILE: "envs/dev.tfvars"
  TFSTATE_KEY: "tfstate.webapp.networking.dev"
```

Backend init flags must include `use_oidc=true` and `use_azuread_auth=true`. Never commit account names, keys, or subscription IDs.

### Pipeline validation

Confirm fmt, init, validate, and plan stages reference the decision-record paths. Do not run apply from this skill.

---

## Menu 4 — Bootstrap state storage

**Do not inline bootstrap logic.** Run or instruct the script in **this skill folder**:

```bash
chmod +x scripts/bootstrap-tfstate.sh
./scripts/bootstrap-tfstate.sh --help
```

```powershell
./scripts/bootstrap-tfstate.ps1 -Help
```

**Prerequisites:** `az` on PATH; `az login`; `az account set` to the target subscription.

Example (placeholders):

```bash
./scripts/bootstrap-tfstate.sh \
  --resource-group-name rg-acme-tfstate-dev \
  --location eastus \
  --storage-account-name stacmetfstatedev \
  --container-name tfstate \
  --resource webapp \
  --environment dev
```

The script creates RG, storage account, and container out of band and prints suggested `terraform init -backend-config` flags with Entra ID auth — no access keys.

Record printed values in host secrets/variables for pipelines; never commit keys or populated backend-config files.

---

## Menu 5 — Create Azure connections

**Do not reimplement OIDC setup.** Run or instruct the script in **this skill folder**:

```bash
chmod +x scripts/create-azure-oidc.sh
./scripts/create-azure-oidc.sh --help
```

```powershell
./scripts/create-azure-oidc.ps1 -Help
```

Follow the runbook: [references/azure-connections.md](references/azure-connections.md).

**Prerequisites:** `az login`; bootstrap complete when assigning state-container RBAC.

### Host summary

| Host | Script `--host` | Notes |
| --- | --- | --- |
| **GitHub Actions** | `github` | `--github-org`, `--github-repo`, `--github-environment` |
| **Azure DevOps** | `ado` | Draft ARM service connection in ADO UI first; copy **Issuer** and **Subject identifier** into `--ado-issuer` / `--ado-subject` |
| **GitLab** | `gitlab` | `--gitlab-project-path` |

Pass state container details when bootstrap exists:

```bash
./scripts/create-azure-oidc.sh --host github \
  --github-org myorg --github-repo myrepo --github-environment prod \
  --state-resource-group rg-acme-tfstate-prod \
  --state-storage-account stacmetfstateprod \
  --assign-state-role
```

Store output client/tenant/subscription IDs in the host secret store — never in git.

---

## Quick checklist

1. Ask which menu item (**1–5**).
2. **Module:** `modules/<name>/`, templates in this skill, `providers.tf`, `organization_name`, no backend.
3. **Stack:** map resources to the **domain catalog** first — one stack per domain, never a mega-stack. Ask domains, environments, location, subscription, region-in-path/name/key. `.tf` once at `resources/<domain>/`, tfvars at `envs/<env>.tfvars`. Cross-domain reads are `data` blocks only. `source = "../../modules/<name>"`. Write `stack-decision.md` per domain.
4. **Pipeline:** one per domain stack; copy sibling `terraform-azure-pipelines` assets; parameterize from decision record; Terraform **1.15.8**.
5. **Bootstrap:** `scripts/bootstrap-tfstate.sh` or `.ps1` in this skill folder.
6. **Connections:** `scripts/create-azure-oidc.sh` or `.ps1` + [references/azure-connections.md](references/azure-connections.md).
7. Validate tier 1, then tier 2 (plan). **Never apply or destroy.**
