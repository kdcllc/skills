---
domain: networking
resource: webapp
environments:
  - dev
  - prod
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
  - ../../modules/subnet
upstream_domains: []
---
# Stack decision record

One record per **domain stack**. `domain` must be a row from the domain catalog in
[ai-conventions.md](../../references/ai-conventions.md); a record listing two domains means the
stack needs splitting.

`resource_group_layout` is `per-type` (default — this stack owns `resource_group_name`) or
`single` (the tier-1 `resource-group` stack owns it and this stack reads it). It is chosen once
per workload and must be identical in every stack of that workload. See
[resource-group-layout.md](../../references/resource-group-layout.md). In the `single` layout the
example above would drop `../../modules/resource_group`, set `resource_group_name` to
`rg-acme-webapp-dev`, and list `- resource-group` under `upstream_domains`.

`upstream_domains` lists the lower-tier domains this stack reads through `data.tf`.
Every entry must correspond to an azurerm `data` block — never `terraform_remote_state`,
never a cross-stack module output, never a hardcoded ID in tfvars.

Human-readable notes about subscription choice, region-in-key, and pipeline wiring go below.
Do not store storage account keys, SAS tokens, or client secrets in this file.
