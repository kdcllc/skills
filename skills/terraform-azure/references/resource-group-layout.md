# Resource group layout

How a workload's Azure resources are grouped into resource groups. The operator picks one of two layouts when the first stack for a workload is created; every later stack for that workload **must use the same layout**, because downstream stacks reconstruct upstream resource-group names from it.

Companion documents: [ai-conventions.md](ai-conventions.md) (layout freeze) and [operating-process.md](operating-process.md) (menu, create-time questions, decision record).

## The two layouts

| Layout | Meaning | Resource group name | Who creates it |
| --- | --- | --- | --- |
| **`per-type`** (default) | One resource group per **domain**: all key vaults in one RG, all container apps and their environments in one RG, all storage accounts in one RG, and so on | `rg-{organization_name}-{resource}-{rg_segment}-{environment}` — `rg-acme-webapp-kv-dev` | **Each domain stack owns its RG** through `module "resource_group"` in its own `main.tf`. There is no `resource-group` stack. |
| **`single`** | Every resource of the workload in **one** RG | `rg-{organization_name}-{resource}-{environment}` — `rg-acme-webapp-dev` | The tier-1 **`resource-group`** stack. Every other stack reads it with `data "azurerm_resource_group" "this"`. |

Default to **`per-type`** unless the operator explicitly picks `single`. Record the answer in every `stack-decision.md` for the workload (`resource_group_layout`).

Both layouts are **per workload**: `{resource}` (the workload, e.g. `webapp`) stays in the RG name and stays constant across the workload's stacks. That is what keeps the cross-stack data-block rule working unchanged.

## Domain catalog `rg_segment`

The `per-type` RG name carries the domain through a short segment. The segment is fixed per catalog row so that any stack can derive any other stack's RG name:

| Tier | Domain folder | `rg_segment` |
| --- | --- | --- |
| 1 | `resource-group` | — (`single` layout only; no RG of its own in `per-type`) |
| 2 | `networking` | `net` |
| 2 | `identity` | `id` |
| 2 | `observability` | `obs` |
| 3 | `key-vaults` | `kv` |
| 3 | `container-registry` | `acr` |
| 3 | `storage` | `st` |
| 3 | `databases` | `db` |
| 4 | `container-apps` | `aca` |
| 4 | `app-services` | `app` |

Operators who add a catalog row **must** add an `rg_segment` for it (lowercase, 2–4 characters, unique in the catalog) and record it where the row is added.

## Naming rule

The canonical pattern is unchanged:

```
{resource-type}-{organization_name}-{resource}-{environment}
```

`rg_segment` is an **optional segment of that one pattern**, inserted before `{environment}`, exactly as `-{region}` is an optional suffix after it. It is not a second naming scheme. With both options chosen: `rg-acme-webapp-kv-dev-eastus`.

The resource group is the **only** resource whose name carries the domain. Key vaults, storage accounts, container apps and everything else keep `{abbr}-{organization_name}-{resource}-{environment}` in both layouts — `kv-acme-webapp-dev`, never `kv-acme-webapp-kv-dev`.

## `per-type` stack shape

The domain stack opens with the resource-group module and hands its name to the domain's other modules:

```hcl
# resources/key-vaults/main.tf
module "resource_group" {
  source = "../../modules/resource_group"

  organization_name = var.organization_name
  resource          = var.resource
  environment       = var.environment
  location          = var.location
  name_segment      = "kv" # rg_segment for this domain (catalog)
  tags              = var.tags
}

module "key_vault" {
  source = "../../modules/key_vault"

  organization_name   = var.organization_name
  resource            = var.resource
  environment         = var.environment
  location            = var.location
  resource_group_name = module.resource_group.resource_group.name
  tags                = var.tags
}
```

This is still **one domain per stack**: the resource group is the container for the domain's resources, not a second domain. `upstream_domains` in `stack-decision.md` lists only the domains read through `data.tf`.

Upstream resources live in the **upstream domain's** RG, so `data.tf` reconstructs that RG's name from the upstream row's `rg_segment`:

```hcl
# resources/key-vaults/data.tf
locals {
  # upstream domain -> the resource group that domain owns. Quote the keys —
  # domain names with hyphens ("key-vaults") are not bare HCL identifiers.
  upstream_rg = {
    "observability" = "rg-${var.organization_name}-${var.resource}-obs-${var.environment}"
  }
}

data "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.organization_name}-${var.resource}-${var.environment}"
  resource_group_name = local.upstream_rg["observability"]
}
```

A stack with no upstream domain (for example `networking` at tier 2 in `per-type`) has **no `data.tf`** and `upstream_domains: []`.

Worked example — the request "a resource group, VNet, container apps, ACR, key vault, storage and Log Analytics" in `per-type` becomes **six** stacks, each owning its RG:

```
resources/networking/           rg-acme-webapp-net-dev
resources/observability/        rg-acme-webapp-obs-dev
resources/key-vaults/           rg-acme-webapp-kv-dev
resources/container-registry/   rg-acme-webapp-acr-dev
resources/storage/              rg-acme-webapp-st-dev
resources/container-apps/       rg-acme-webapp-aca-dev
```

## `single` stack shape

The v2.0.0 shape. The tier-1 `resource-group` stack owns `rg-acme-webapp-dev`; every other stack reads it:

```hcl
# resources/key-vaults/data.tf
data "azurerm_resource_group" "this" {
  name = "rg-${var.organization_name}-${var.resource}-${var.environment}"
}

data "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.organization_name}-${var.resource}-${var.environment}"
  resource_group_name = data.azurerm_resource_group.this.name
}
```

Module blocks take `resource_group_name = data.azurerm_resource_group.this.name`. The same request becomes **seven** stacks: the six above plus `resources/resource-group/` at tier 1, and every other stack lists `resource-group` in `upstream_domains`.

## Resource-group module

The `resource_group` library module accepts an optional `name_segment` (default `""`). An empty segment yields the `single` name, so one module serves both layouts:

```hcl
resource "azurerm_resource_group" "this" {
  name     = join("-", compact(["rg", var.organization_name, var.resource, var.name_segment, var.environment]))
  location = var.location
  tags     = var.tags
}
```

Only the resource-group module declares `name_segment`. Other module types do not take a segment.

## Decision record keys

Every `stack-decision.md` carries:

| Key | Value |
| --- | --- |
| `resource_group_layout` | `per-type` or `single` — identical in every stack of the workload |
| `resource_group_name` | The RG this stack **owns** (`per-type`) or **reads** (`single`), e.g. `rg-acme-webapp-kv-dev` |

A record **without** `resource_group_layout` is a v2.0.0 record and means `single` — that is the only shape the pack produced before this key existed. Add the key explicitly when touching such a stack; do not change its layout.

## Pipelines

Plan order follows dependency tier in both layouts. In `single`, the `resource-group` stack is tier 1 and runs first. In `per-type` there is no `resource-group` job; tier-2 stacks are the first jobs, and each stack's plan creates its own RG.

## Switching layouts

Converting an existing workload between layouts means moving live Azure resources between resource groups and re-keying state. That is out of scope for this skill: do **not** author a conversion, and do **not** change `resource_group_layout` in an existing record. Point the operator at a human-reviewed, plan-only Azure resource move instead.
