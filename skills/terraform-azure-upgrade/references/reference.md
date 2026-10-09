# Azure Terraform upgrade reference

Companion to [SKILL.md](../SKILL.md). **Examples** of azurerm **5.0** removals and replacements seen on HashiCorp’s [5.0 upgrade guide](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/5.0-upgrade-guide). Before editing HCL, open the **current** resource page — names below can change in later 5.x minors.

Do not treat this table as a closed mapping. If docs disagree with a row, follow the docs.

## Pins

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

Library modules: `provider "azurerm" { features {} }` only — no `resource_provider_registrations` (that is a **stack** setting).

Stacks:

```hcl
provider "azurerm" {
  features {}
  resource_provider_registrations = "legacy" # or "none" if RPs are pre-registered
}
```

## Example 5.0 schema moves

Confirm each against the live registry page before applying.

| Area | Typical 4.x / pre-5.0 | Typical 5.x replacement |
| --- | --- | --- |
| Monitor diagnostic metrics | dynamic `"metric"` with `category` + `enabled` | `enabled_metric` with `category` only |
| Cosmos DB account | `local_authentication_disabled` | `local_authentication_enabled` (invert the boolean if keeping the old variable) |
| Front Door custom domain TLS | `tls.minimum_tls_version` | `tls.minimum_version` |
| Key Vault | `enable_rbac_authorization` | required `rbac_authorization_enabled` |
| Recovery Services vault | `soft_delete_enabled` | **removed** — drop argument; do not invent a successor on this resource |
| Service Bus network rules | nested `ip_rules { ip_mask, action }` | `ip_rules` as list of CIDR strings |
| Storage blob | `storage_account_name` + `storage_container_name` | required `storage_container_id` |
| Provider | `skip_provider_registration` | **removed** — use `resource_provider_registrations` on the **stack** provider |

Provider registration: azurerm 5.x registers **none** by default. Stacks that need 4.x-like first-plan behavior set `resource_provider_registrations = "legacy"`.

## Process reminder

1. Inventory → agree targets.
2. Pins, then schema, then `fmt` / `init -backend=false` / `validate`.
3. Next validate error in the **same** directory is still that module’s job.
4. Never apply from this skill.
