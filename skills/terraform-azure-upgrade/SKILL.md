---
name: terraform-azure-upgrade
description: >-
  Upgrades existing Azure Terraform library modules (and optionally stacks) to
  the current bounded azurerm 5.x schema and Terraform version pins. Use when
  asked to upgrade modules, bump azurerm, fix validate errors after a provider
  major, apply the 5.0 upgrade guide, or migrate skip_provider_registration.
  Does not bulk-rewrite an entire modules/ tree unless the operator lists
  target folders. Never apply.
license: MIT
metadata:
  version: "1.0.0"
---

# Terraform Azure upgrade

Upgrade **existing** `modules/<name>/` folders in the **consumer** repository to the pack’s current pins and to schemas documented on today’s HashiCorp azurerm pages. This skill does **not** create new modules (use [../terraform-azure-modules/SKILL.md](../terraform-azure-modules/SKILL.md)) and does **not** run `terraform apply`.

Layout freeze: [../terraform-azure/references/ai-conventions.md](../terraform-azure/references/ai-conventions.md). Common 5.x argument renames: [reference.md](references/reference.md) — treat that table as **examples**; always confirm against current docs.

## Target pins (do not “latest unbounded”)

| Constraint | Value |
| --- | --- |
| `azurerm` | `>= 5.0.0, < 6.0.0` (or `~> 5.0`) |
| `azapi` (only if required) | `~> 2.0` or `>= 2.0.0, < 3.0.0` |
| Terraform `required_version` | `>= 1.9.0, < 2.0.0` |
| CI Terraform CLI | **1.15.8** — copy from [../terraform-azure-pipelines](../terraform-azure-pipelines/SKILL.md) if bumping pipelines |

Never remove the azurerm **upper** bound to satisfy a child module or AVM. Never vendor AVM as a pin workaround.

## When to use

- Operator names one or more existing modules to upgrade
- `terraform validate` fails after bumping azurerm to 5.x
- `providers.tf` still has unbounded `>= 4.x`, `~> 4.0`, `>= 3.0`, or `skip_provider_registration`
- Stack `provider "azurerm"` is missing `resource_provider_registrations`

Do **not** use this skill to rewrite every folder under `modules/` unless the operator **lists** the targets (or says “all modules under modules/” after seeing the inventory).

## Tools (by role)

- **Query current azurerm provider docs** — resource schema and the [5.0 upgrade guide](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/5.0-upgrade-guide).
- **Search Microsoft Learn** — only for Azure platform behavior (for example soft-delete defaults), not for Terraform argument names.

Do not invent attribute or block names.

## Must NOT

- `terraform apply` or `terraform destroy`
- Azure Developer CLI (`azd`)
- Weaken `azurerm` to allow 4.x or 6.x in the same constraint
- Bulk-edit modules the operator did not include
- Copy stale argument names from memory or from [reference.md](references/reference.md) without checking current docs

## Steps

### 1. Inventory

List `modules/` (and nested module dirs that contain `providers.tf` or `*.tf`). For each candidate record:

- Path
- Current `azurerm` / `azapi` / `required_version` constraints
- Presence of `provider.tf` (wrong name), `skip_provider_registration`, `backend.tf` on a library module

Present the list. Ask which paths to upgrade unless the operator already named them.

### 2. One module at a time

For each agreed path:

1. Read `providers.tf` / `main.tf` / `variables.tf` / outputs.
2. Set pins to the target table. Rename `provider.tf` → `providers.tf` if needed. Remove `backend.tf` from library modules (backends belong on stacks).
3. Query the **current** azurerm resource page for every resource type in the module, plus the 5.0 upgrade guide.
4. Replace removed or renamed arguments/blocks. Keep variable names when only the resource argument renamed (alias in the resource block). If an argument was **removed with no successor**, drop it and the wiring; note the behavior change in the report.
5. Prefer **azurerm**. Use **azapi** only when azurerm cannot represent the resource; comment why.
6. Do not “fix” naming (`organization_name` pattern) unless the operator asked — schema upgrade is the default scope.

### 3. Stacks (optional)

If the operator included a stack under `resources/`:

- Empty `backend "azurerm" {}` stays
- Root `provider "azurerm"` **must** set `resource_provider_registrations` (`"legacy"` default; `"none"` only when RPs are pre-registered)
- **Forbidden:** `skip_provider_registration`

Do not bump stack `location` or rearrange folder layout in this skill. If you encounter a superseded `resources/environments/<env>/<resource>/` tree or a mega-stack mixing several domains, **report it and stop** — restructuring is `terraform-azure` menu 2, not a schema upgrade.

### 4. Validate (tier 1 only)

```bash
terraform fmt -check -diff <module-or-stack-path>
cd <module-or-stack-path> && terraform init -backend=false && terraform validate
```

Fix the **first** validate error, then re-run until that directory is clean or you must stop (undocumented schema, need operator choice). Then the next directory.

Never apply. Optional tier 2 `plan` only if the operator has backend config and asks for it.

### 5. Pipelines (optional)

If CI still pins Terraform 1.8.x / 1.10.x, point at [../terraform-azure-pipelines/SKILL.md](../terraform-azure-pipelines/SKILL.md) and **copy assets** (1.15.8). Do not invent YAML.

### 6. Report

For each upgraded path:

- Old constraint → new constraint
- Arguments/blocks changed (cite the registry URL used)
- Remaining validate errors, if any
- Whether apply is still a human step (always)

## Checklist

- [ ] Inventory shown; targets agreed
- [ ] Each target has `providers.tf` with azurerm `>= 5.0.0, < 6.0.0` and `required_version = ">= 1.9.0, < 2.0.0"`
- [ ] No `skip_provider_registration`; stacks set `resource_provider_registrations`
- [ ] Schema edits match **current** registry docs, not guesswork
- [ ] `terraform fmt` and `init -backend=false && validate` succeeded per finished directory
- [ ] No apply, no `azd`, no unbounded “latest” pin
