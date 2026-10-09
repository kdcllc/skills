# Terraform Azure operating process

Human operators and the `/terraform-azure` skill share this contract. Later tasks, skills, and agents must not invent a second layout, require Azure Developer CLI, or skip ask-at-create-time questions.

**Layout freeze:** [ai-conventions.md](ai-conventions.md) · **Resource group layout:** [resource-group-layout.md](resource-group-layout.md)

## Workstation tools

| Tool | Required | Notes |
| --- | --- | --- |
| **Azure CLI (`az`)** | Yes | Only Azure command-line this toolkit requires. Authenticate with `az login`; select subscription with `az account set`. |
| **Terraform 1.15.x** | Yes | CI pins the same line. Match library provider bounds (`azurerm` `>= 5.0.0, < 6.0.0`). |
| **Git** | Yes | Version control for modules, stacks, and pipelines. |
| **bash** or **PowerShell 7** | Yes | Run bootstrap scripts and local validation. |
| **`gh`** | Optional | GitHub Actions workflows and OIDC setup. |
| **`az devops`** | Optional | Azure DevOps pipelines and service connections. |
| **GitLab CLI (`glab`)** | Optional | GitLab CI when that host is used. |

**Azure CLI (`az`) only.** Do **not** use Azure Developer CLI (`azd`) for bootstrap, provisioning, pipelines, skills, or developer setup. `azd` must not appear as a dependency, example command, or menu item.

## `/terraform-azure` menu

The skill exposes five entry points. Each follows this document and the validation ladder below.

| Menu item | Delivers | Primary path |
| --- | --- | --- |
| **New module (interface)** | Reusable library module | `modules/<name>/` |
| **New stack (class)** | One root module per domain | `resources/<domain>/` |
| **New pipeline** | CI for fmt / validate / plan / apply | Azure DevOps, GitHub Actions, or GitLab CI templates |
| **Bootstrap state storage** | One-shot out-of-band state RG + storage + container | Checked-in `az` / PowerShell scripts (not Terraform-managed) |
| **Create Azure connections** | Service connections / OIDC for CI | Host-specific (`az devops`, `gh`, GitLab variables) |

Skills and agents may run menu flows through **tier 2 (plan)** only. They never run `terraform apply` or `terraform destroy`.

## Interface vs class

| Term | Meaning | Location |
| --- | --- | --- |
| **Interface (module)** | Reusable Terraform module for one primary Azure resource type | `modules/<name>/` |
| **Class (stack)** | Root module owning **one domain**, consuming library modules via relative `source`, shared across environments | `resources/<domain>/` |

### Interface files (`modules/<name>/`)

Every library module includes:

- `main.tf` — resource definitions
- `variables.tf` — inputs (`organization_name`, `resource`, `environment`, `location`, …)
- `output.tf` or `outputs.tf` — IDs and names for composition
- `providers.tf` — bounded `required_providers` (not `provider.tf`)

Library modules do **not** declare a backend.

### Class files (domain stack)

Every stack includes at minimum:

- `main.tf` — `module` blocks with relative `source`, **for one domain only**
- `data.tf` — azurerm `data` lookups of other domains (omit when `upstream_domains` is empty)
- `variables.tf` — stack inputs including **`location`**
- `providers.tf` — root `provider "azurerm"` with explicit `resource_provider_registrations`
- `backend.tf` — empty `backend "azurerm" {}` (pipeline or CLI injects settings)
- `envs/<env>.tfvars` — one tfvars file per environment, all in a single `envs/` folder

## Stack layout (canonical path)

**One domain per stack.** A stack that provisions a resource group *and* a VNet *and* a key vault is a defect — split it. Map requested resources onto the domain catalog in [ai-conventions.md](ai-conventions.md) before writing files.

In the default **`per-type`** resource group layout the domain's own resource group belongs to that domain's stack — it is the domain's container, not a second domain, and the stack stays single-domain. In the **`single`** layout the tier-1 `resource-group` stack owns the one RG and the others read it. See [resource-group-layout.md](resource-group-layout.md).

Terraform is written **once per domain** and shared by every environment; only tfvars vary:

```
resources/<domain>/
  main.tf            # modules for THIS domain only
  data.tf            # lookups of other domains (omit when there is no upstream)
  variables.tf
  providers.tf
  backend.tf
  stack-decision.md
  envs/
    dev.tfvars
    prod.tfvars
```

Working directory is `resources/<domain>/` for every environment:

```bash
cd resources/networking
terraform plan -var-file=envs/dev.tfvars
```

**Optional region segment** (opt-in — affects the **tfvars filename only**):

```
resources/<domain>/envs/<env>.<region>.tfvars
```

**Rejected:** `resources/environments/<env>/<resource>/` (superseded), flat `resources/<resource>/` with no domain meaning, `infra/resources/`, and any layout that duplicates `.tf` per environment.

### Cross-stack references

A stack reads another domain through an azurerm `data` block only. Names are reconstructed from variables the stack already declares, because `var.resource` (the workload) is identical across a workload's domain stacks. In the `per-type` layout the upstream resource lives in the **upstream domain's** resource group:

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

In the `single` layout there is one RG for the workload, read directly:

```hcl
data "azurerm_resource_group" "this" {
  name = "rg-${var.organization_name}-${var.resource}-${var.environment}"
}
```

**Forbidden:** `terraform_remote_state`, cross-stack module outputs, upstream IDs hardcoded in tfvars. If azurerm publishes no data source for a type, its dependents belong in the **same** stack as that resource.

### Relative module `source` (frozen)

Every stack sits at `resources/<domain>/`, so the depth never varies — `envs/` holds tfvars, not `.tf`:

```hcl
module "virtual_network" {
  source = "../../modules/virtual_network"

  organization_name   = var.organization_name
  resource            = var.resource
  environment         = var.environment
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags
}
```

## Ask at create time

When creating a **new stack (class)**, the operator or `/terraform-azure` skill **must ask** before writing files:

1. **Domains** — which Azure resources are in scope, so each maps to exactly one domain-catalog row (and therefore one stack).
2. **Environments** — e.g. `dev`, `test`, `prod` (one `envs/<env>.tfvars` file each).
3. **Azure region (location)** — e.g. `eastus`, `westeurope` (Azure location string).
4. **Subscription** — current `az account show` subscription, or another subscription/tenant ID the stack will target.
5. **Region in layout** — whether `<region>` appears in the tfvars filename, the resource name, the state key, several, or none.
6. **Resource group layout** — `per-type` (**default**: one RG per domain, `rg-acme-webapp-kv-dev`, owned by that domain's stack) or `single` (one RG for the workload, `rg-acme-webapp-dev`, owned by the tier-1 `resource-group` stack). Chosen once per workload and identical in every stack of that workload. Details: [resource-group-layout.md](resource-group-layout.md).

**location is always** a stack variable (`variables.tf`) and **is always** passed into every module block, even when region appears nowhere else. Modules never infer region from path alone.

Record answers in **`stack-decision.md`** inside each domain stack (see below).

## Naming and state keys

Default Azure resource name pattern:

```
{resource-type}-{organization_name}-{resource}-{environment}
```

`{resource-type}` is the Azure CAF abbreviation (`rg`, `kv`, `aca`, …). Example: `rg-acme-webapp-dev`.

`{resource}` is the **workload** and is identical across every domain stack for that workload. The domain lives in the folder and the state key, never in the resource name — `kv-acme-webapp-dev`, not `kv-acme-key-vaults-dev`. Holding it constant is what lets any stack derive another stack's names in `data.tf`.

If the operator chooses **region-in-name**, append `-{region}` as an **allowed suffix of the same pattern** (Azure-legal, lowercase), e.g. `rg-acme-webapp-dev-eastus`. This is not a second naming scheme.

In the **`per-type`** resource group layout the resource group inserts the domain's `rg_segment` before `{environment}` — `rg-acme-webapp-kv-dev` — as an **allowed segment of the same pattern**. Only the resource group takes a segment; the key vaults inside it are still `kv-acme-webapp-dev`. With both options: `rg-acme-webapp-kv-dev-eastus`.

Default remote state blob key:

```
tfstate.{resource}.{domain}.{environment}
```

Example: `tfstate.webapp.networking.dev`. If **region-in-key** is chosen, append `.{region}`: `tfstate.webapp.networking.dev.eastus`.

One state file per domain per environment. The working directory is shared across environments; the injected backend key is what separates them.

## Root provider: `resource_provider_registrations`

Domain-stack `provider "azurerm"` **must** set `resource_provider_registrations` explicitly. On azurerm 5.x, provider registration no longer happens implicitly.

- **Templates / first-time stacks:** default to `"legacy"` so a non-expert first `plan` behaves like azurerm 4.x.
- **Production / pre-registered subscriptions:** use `"none"` when a platform team has already registered required resource providers.

**Forbidden:** `skip_provider_registration` (removed in azurerm 5.x).

```hcl
provider "azurerm" {
  features {}

  resource_provider_registrations = "legacy" # or "none" when RPs are pre-registered
}
```

## Stack decision record

Each domain stack includes **`stack-decision.md`** in its working directory. Required keys (YAML front matter or equivalent structured block):

| Key | Description |
| --- | --- |
| `domain` | Exactly one domain-catalog row (`networking`, `key-vaults`, …). Two domains means the stack needs splitting. |
| `resource` | Workload segment used in resource names (`webapp`) |
| `environments` | List of environments with a file in `envs/` |
| `region` | Azure region slug if used in path/name/key; empty if not |
| `location` | Azure location string always used as stack variable |
| `subscription_id` | Target subscription GUID — use placeholder `00000000-0000-0000-0000-000000000000`, not a real secret |
| `region_in_path` | `true` / `false` — `envs/<env>.<region>.tfvars` filename |
| `region_in_name` | `true` / `false` — `-{region}` suffix on resource names |
| `region_in_key` | `true` / `false` — `.{region}` suffix on state keys |
| `resource_group_layout` | `per-type` (default) or `single`. Identical in every stack of the workload. A record without this key is a v2.0.0 record and means `single`. |
| `resource_group_name` | The resource group this stack **owns** (`per-type`) or **reads** (`single`), e.g. `rg-acme-webapp-net-dev` |
| `working_directory` | Repo-relative stack root, e.g. `resources/networking` |
| `tfvars` | Map of environment to tfvars path, e.g. `dev: envs/dev.tfvars` (relative to `working_directory`) |
| `state_keys` | Map of environment to blob key, e.g. `dev: tfstate.webapp.networking.dev` |
| `module_sources` | Relative paths consumed, e.g. `../../modules/virtual_network` |
| `upstream_domains` | Lower-tier domains read through `data.tf`; each needs a matching `data` block |

Do **not** store storage account keys, SAS tokens, or client secrets in this file.

Example:

```yaml
---
domain: networking
resource: webapp
environments: [dev, prod]
region: eastus
location: eastus
subscription_id: "00000000-0000-0000-0000-000000000000"
region_in_path: false
region_in_name: false
region_in_key: false
resource_group_layout: per-type
resource_group_name: rg-acme-webapp-net-dev
working_directory: resources/networking
tfvars:
  dev: envs/dev.tfvars
  prod: envs/prod.tfvars
state_keys:
  dev: tfstate.webapp.networking.dev
  prod: tfstate.webapp.networking.prod
module_sources:
  - ../../modules/resource_group
  - ../../modules/virtual_network
upstream_domains: []
---
# Stack decision record — human-readable notes optional below.
```

## Validation ladder

Run checks in order. Stop on first failure.

| Tier | Who | Commands / scope |
| --- | --- | --- |
| **1 — Offline** | Humans, skills, CI | `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`, `terraform test` with `mock_provider` when tests exist. Optional static scan (TFLint / Trivy / Checkov). No Azure credentials required. |
| **2 — Plan** | Humans, skills, CI | `terraform init` with injected backend config, then `terraform plan`. Requires authenticated Azure access. On azurerm 5.x, optional enhanced / preflight validation at plan time. |
| **3 — Apply** | Humans or gated CI only | `terraform apply` behind manual approval. **Skills and unattended agents never apply or destroy.** |

Portable skills and `/terraform-azure` stop at tier 2.

### Library check (consumer modules)

In the consumer repository, run tier 1 on each module or stack you just authored (`terraform fmt -check`, `terraform init -backend=false`, `terraform validate`). No Azure credentials, `az`, or `azd` are involved. Include this check in tier 1 before tier 2.

## Backend (reminder)

Stacks use an empty backend block; pipelines inject storage settings at init:

```hcl
terraform {
  backend "azurerm" {}
}
```

Bootstrap the state storage account **out of band** with Azure CLI (`az`) — see **Bootstrap state storage** menu item. Never commit real account names, keys, or populated backend-config files.

## Quick checklist

1. Pick a menu item (module, stack, pipeline, bootstrap, connections).
2. For stacks: map every requested resource onto the **domain catalog** first — one stack per domain, never a mega-stack.
3. Ask domains, environments, location, subscription, and region-in-path/name/key; write `stack-decision.md` per domain.
4. Use canonical path `resources/<domain>/` with `.tf` written once and one `envs/<env>.tfvars` per environment.
5. Set `source = "../../modules/<name>"`.
6. Read other domains with azurerm `data` blocks only — no `terraform_remote_state`, no cross-stack module outputs.
7. Declare `location` on the stack and pass it into every module.
8. State key is `tfstate.{resource}.{domain}.{environment}`.
9. Set `resource_provider_registrations` on root `provider "azurerm"`.
10. Run tier 1, then tier 2 — lower tiers before higher; leave tier 3 to humans or approved CI.
