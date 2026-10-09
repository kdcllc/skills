# Azure Terraform module reference

Companion to [SKILL.md](../SKILL.md). Read this file when you need an abbreviation, a file template, or a name character-set exception. This is the **single copy** of the abbreviation table for the portable pack.

Canonical resource name:

```
{abbr}-{organization_name}-{resource}-{environment}
```

Do **not** use the superseded pattern `{abbr}-{environment}-{resource}` (for example `kv-${environment}-${resource}`).

For abbreviations missing here, search Microsoft Learn for Azure resource abbreviations (Cloud Adoption Framework resource-abbreviations). Do not treat host-specific doc-tool IDs as part of this pack.

## Azure resource abbreviations

Azure Cloud Adoption Framework abbreviations used when naming resources.

| Resource Type                         | Abbreviation |
| ------------------------------------- | ------------ |
| Resource Group                        | rg           |
| App Service Plan                      | asp          |
| Application Insights                  | ai           |
| AI Search                             | srch         |
| Azure AI services                     | ais          |
| Azure AI Foundry account              | aif          |
| Azure AI Video Indexer                | avi          |
| Azure Machine Learning workspace      | mlw          |
| Azure OpenAI Service                  | oai          |
| Bot service                           | bot          |
| Computer vision                       | cv           |
| Content moderator                     | cm           |
| Content safety                        | cs           |
| Custom vision (prediction)            | cstv         |
| Custom vision (training)              | cstvt        |
| Document intelligence                 | di           |
| Face API                              | face         |
| Health Insights                       | hi           |
| Immersive reader                      | ir           |
| Language service                      | lang         |
| Speech service                        | spch         |
| Translator                            | trsl         |
| Proximity placement group             | ppg          |
| Restore point collection              | rpc          |
| Snapshot                              | snap         |
| Virtual machine                       | vm           |
| Virtual machine scale set             | vmss         |
| Virtual machine maintenance config    | mc           |
| VM storage account                    | stvm         |
| Web app                               | app          |
| AKS cluster                           | aks          |
| AKS system node pool                  | npsystem     |
| AKS user node pool                    | np           |
| Container apps                        | ca           |
| Container apps environment            | cae          |
| Container registry                    | cr           |
| Container instance                    | ci           |
| Service Fabric cluster                | sf           |
| Service Fabric managed cluster        | sfmc         |
| Azure Cosmos DB database              | cosmos       |
| Azure Cosmos DB for Cassandra         | coscas       |
| Azure Cosmos DB for MongoDB           | cosmon       |
| Azure Cosmos DB for NoSQL             | cosno        |
| Azure Cosmos DB for Table             | costab       |
| Azure Cosmos DB for Gremlin           | cosgrm       |
| Azure Cosmos DB PostgreSQL cluster    | cospos       |
| Azure Cache for Redis                 | redis        |
| Azure SQL Database server             | sql          |
| Azure SQL database                    | sqldb        |
| Azure SQL Elastic Job agent           | sqlja        |
| Azure SQL Elastic Pool                | sqlep        |
| MySQL database                        | mysql        |
| PostgreSQL database                   | psql         |
| SQL Server Stretch Database           | sqlstrdb     |
| SQL Managed Instance                  | sqlmi        |
| App Configuration store               | appcs        |
| Maps account                          | map          |
| SignalR                               | sigr         |
| WebPubSub                             | wps          |
| Azure Managed Grafana                 | amg          |
| HDInsight - HBase cluster             | hbase        |
| HDInsight - Kafka cluster             | kafka        |
| HDInsight - Spark cluster             | spark        |
| HDInsight - Storm cluster             | storm        |
| HDInsight - ML Services cluster       | mls          |
| IoT hub                               | iot          |
| Provisioning services                 | provs        |
| Provisioning services certificate     | pcert        |
| Power BI Embedded                     | pbi          |
| Time Series Insights environment      | tsi          |
| Firewall policy                       | afwp         |
| ExpressRoute circuit                  | erc          |
| ExpressRoute direct                   | erd          |
| ExpressRoute gateway                  | ergw         |
| Front Door (Standard/Premium) profile | afd          |
| Front Door endpoint                   | fde          |
| Front Door firewall policy            | fdfp         |
| IP group                              | ipg          |
| Load balancer (internal)              | lbi          |
| Load balancer (external)              | lbe          |
| Load balancer rule                    | rule         |
| Local network gateway                 | lgw          |
| NAT gateway                           | ng           |
| Network interface (NIC)               | nic          |
| Network security perimeter            | nsp          |
| Network security group (NSG)          | nsg          |
| Network Watcher                       | nw           |
| Private Link                          | pl           |
| Private endpoint                      | pep          |
| Public IP address                     | pip          |
| Public IP address prefix              | ippre        |
| Route filter                          | rf           |

## Name character-set exceptions

Keep segment **order** (`abbr`, `organization_name`, `resource`, `environment`) even when Azure rejects hyphens or a length limit.

| Constraint | What to do |
| --- | --- |
| Hyphens not allowed (some storage and compute names) | Drop hyphens; concatenate the same four segments. Comment why. |
| Max length shorter than the hyphenated name | Shorten `resource` first, then `organization_name`; do not drop `organization_name`. |
| Globally unique names (Key Vault, storage, ACR) | Keep the pattern; uniqueness comes from the variable values, not a second naming scheme. |

Never fall back to `{abbr}-{environment}-{resource}`.

## File templates

Match sibling modules in the target repo. Some modules use `output.tf` (singular); others use `outputs.tf`. Always use `providers.tf`. Include `required_version = ">= 1.9.0, < 2.0.0"`.

### `providers.tf`

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

provider "azurerm" {
  features {}
}
```

Add `azapi` only when azurerm cannot represent the resource, with a comment that explains why.

### `variables.tf` (required naming inputs)

```hcl
variable "organization_name" {
  description = "The organization/project/company identifier used in resource naming"
  type        = string
}

variable "resource" {
  description = "Resource identifier used in the name"
  type        = string
}

variable "environment" {
  description = "Deployment environment (for example dev, test, prod)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}
```

Add resource-specific variables after these. Do not hardcode secrets, subscription IDs, or access keys.

### `main.tf` (name only)

```hcl
resource "azurerm_resource_group" "this" {
  name     = "rg-${var.organization_name}-${var.resource}-${var.environment}"
  location = var.location
  tags     = var.tags
}
```

Replace `azurerm_resource_group` and `rg` with the resource type and abbreviation from the table.

The **resource-group module** adds an optional `name_segment` (default `""`) so one module serves both resource group layouts — empty for the single layout, the domain's `rg_segment` for the per-type layout:

```hcl
resource "azurerm_resource_group" "this" {
  name     = join("-", compact(["rg", var.organization_name, var.resource, var.name_segment, var.environment]))
  location = var.location
  tags     = var.tags
}
```

No other module type takes a segment.

### `output.tf`

```hcl
output "kv" {
  value = {
    id = azurerm_key_vault.this.id
  }
}
```

Prefer the Microsoft abbreviation as the output name when siblings do. Inspect the target repo before choosing `output.tf` versus `outputs.tf`.
