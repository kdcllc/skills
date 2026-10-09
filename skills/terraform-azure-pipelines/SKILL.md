---
name: terraform-azure-pipelines
description: >-
  Creates Terraform CI pipelines that fmt, validate, and plan Azure
  infrastructure with GitHub Actions reusable workflow_call workflows, Azure
  DevOps templates, or GitLab CI, using OIDC and parameterized backends, with a
  mandatory failing fmt check and a confirmation-gated destroy option in every
  action dropdown. Use when creating a pipeline, adding Terraform CI, GitHub
  Actions, Azure DevOps, plan jobs, a gated destroy or teardown workflow, or
  OIDC for azurerm state.
license: MIT
metadata:
  version: "1.0.0"
---

# Terraform Azure pipelines

Author a **fmt → validate → plan** CI path for Azure Terraform in the **consumer** repository. Default action is **plan**. Apply is **opt-in and parameterized, never the default**, on every host. **`fmt -check` always fails the job**, and **destroy is always available behind a confirmation input** — see [Format check is mandatory](#format-check-is-mandatory) and [Destroy policy](#destroy-policy-all-hosts).

**Copy YAML from [assets/](assets/).** Do not invent a second template and do not copy older Terraform pins. The assets pin Terraform **1.15.8** and Entra backend auth (`use_oidc=true`, `use_azuread_auth=true`).

Layout freeze: [../terraform-azure/references/ai-conventions.md](../terraform-azure/references/ai-conventions.md). Search Microsoft Learn for GitHub Actions Azure login (OIDC) and Azure Pipelines Terraform tasks. Query HashiCorp Terraform docs for `fmt`, `validate`, `plan`, and `-backend-config`. Name documentation tools by **role** only.

## When to use

- Creating or updating a pipeline that runs Terraform CI for an environment stack
- Adding GitHub Actions, Azure DevOps, or (optionally) GitLab jobs that plan Azure Terraform
- Wiring OIDC to Azure so init/plan can reach remote state without inline credentials

Do not use this skill to run `terraform apply` locally, to rewrite reusable modules under `modules/`, or to embed cloud secrets in YAML.

## Stack path and backend

Stacks are **one root module per domain**, with `.tf` written once and all per-environment tfvars in a single `envs/` folder:

```
resources/<domain>/
  main.tf
  data.tf
  envs/
    dev.tfvars
    prod.tfvars
```

Do not use `resources/environments/<env>/<resource>/` (superseded) or `infra/resources/`.

**One pipeline (or one caller job) per domain stack.** Each domain has its own working directory and its own state key, so they cannot share a job. Scope trigger paths to `resources/<domain>/**` so an unrelated domain's change does not replan everything.

**Plan order follows dependency tier.** A `data` block in a higher-tier stack fails until the lower-tier stack has been applied. Order jobs tier 1 → tier 2 → tier 3 → tier 4, and treat a missing-data failure in an unapplied environment as expected, not as a pipeline defect. In the `single` resource group layout the `resource-group` stack is tier 1 and runs first; the default `per-type` layout has no such job, because each stack creates its own resource group.

Point `working_directory` / `workingDirectory` at `resources/<domain>`, and the tfvars parameter at `envs/<env>.tfvars` (relative to the working directory). Keep `backend.tf` empty so the pipeline injects storage settings:

```hcl
terraform {
  backend "azurerm" {}
}
```

Never put resource-group names, storage-account names, access keys, SAS tokens, or subscription IDs in the Terraform. Pass backend settings at init with `-backend-config=` or host variables/secrets.

## Apply policy (all hosts)

| Rule | Portable default |
| --- | --- |
| Default `terraform_action` / `terraformAction` | `plan` |
| `terraform fmt` or `fmt -check` | Required; **must fail the job** (no `continue-on-error`) |
| `terraform validate` | Required after init |
| `terraform plan` | Required |
| `terraform apply` | Only when the caller **explicitly** asks (`apply`); gated by input/parameter/condition or a manual stage |
| `terraform destroy` | Always offered in the action list, never the default, always behind a **confirmation input** (below) |

Do not copy an always-apply template as the portable default.

## Format check is mandatory

Every pipeline you generate runs `terraform fmt -check -recursive` **before init**, and it **fails the job**. No `continue-on-error`, no `allow_failure`, no advisory warning. A host template that has no format step is incomplete — add one; do not ship the pipeline without it.

The failure message must tell the operator the fix: run `terraform fmt -recursive` and commit the result.

## Destroy policy (all hosts)

Every generated pipeline **offers destroy** in its action dropdown — an operator should never have to hand-edit CI or run a teardown from a laptop. Destroy is never reachable by one dropdown pick alone: it requires a **separate confirmation input** the operator sets *in addition to* choosing `destroy`, and the run fails fast if that input is unset.

| Host | Confirmation | Fails at |
| --- | --- | --- |
| GitHub Actions | `confirm_destroy` boolean input | First step, before checkout and Azure login |
| Azure DevOps | `confirmDestroy` boolean parameter | First step, before Terraform installs |
| GitLab | `CONFIRM_DESTROY` must equal `DESTROY` | First script line of `terraform_destroy` |

A destroy run always plans with `terraform plan -destroy -out=…` and then applies **that saved plan** — the teardown is never a fresh plan, so the log shows exactly what was deleted.

The confirmation input is the only gate wired by default. For a human approval step on top of it, use the host's own approval machinery — a GitHub Environment with required reviewers, an Azure DevOps environment check or `ManualValidation@0`, a GitLab protected environment — rather than building one into the template.

## Secrets

- **Never** embed ARM access keys, SAS tokens, client secrets, or subscription/tenant ID **literals** in YAML or tfvars committed to the repo.
- GitHub: `permissions.id-token: write` plus repository/environment **secrets** (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) and OIDC (`ARM_USE_OIDC`).
- Azure DevOps: pass the **service connection name as a parameter**, not a hardcoded org/project string.
- Backend location (resource group, storage account, container, state key) comes from **parameters, variables, or secrets** — never hardcoded account names in the playbook.

## GitHub Actions (`workflow_call`)

**Default layout: one `terraform-<domain>.yaml` per domain stack, all calling one shared `tf-deploy-base.yaml`.** That is the shape to generate unless the consumer asks otherwise:

```
.github/workflows/
  tf-deploy-base.yaml            reusable runner (workflow_call only)
  terraform-resource-group.yaml  tier 1 (single RG layout only)
  terraform-networking.yaml      tier 2
  terraform-key-vaults.yaml      one file per domain, named for the domain
  terraform-container-apps.yaml
```

Copy these files into the consumer repo:

| Skill asset | Consumer path |
| --- | --- |
| [assets/tf-deploy-base.yaml](assets/tf-deploy-base.yaml) | `.github/workflows/tf-deploy-base.yaml` |
| [assets/examples/terraform-domain.yaml](assets/examples/terraform-domain.yaml) | `.github/workflows/terraform-<domain>.yaml` — **once per domain** |
| [assets/terraform-stack.yaml](assets/terraform-stack.yaml) | `.github/workflows/terraform-stack.yaml` — optional generic caller for ad-hoc runs |

Per-domain callers pin their own `working_directory`, `backend_state_key`, and trigger paths, so a dispatch form asks only for action / confirm / environment and nothing is retyped at teardown time. Only `tf-deploy-base.yaml` carries the Terraform logic — do not fork it per domain.

The reusable job uses `on: workflow_call`. Default action is `plan`. `fmt -check` is a hard failure. Configure `TFSTATE_*` as GitHub **variables** (or secrets); do not inline those values in the workflow file.

### Per-domain caller

```yaml
name: Terraform Networking

on:
  pull_request:
    paths:
      - 'resources/networking/**'
      - '.github/workflows/tf-deploy-base.yaml'
  workflow_dispatch:
    inputs:
      terraform_action:
        description: Terraform action
        type: choice
        options: [plan, apply, destroy]
        default: plan
      confirm_destroy:
        description: '⚠️ DESTROY: tick to confirm teardown (required when action = destroy)'
        type: boolean
        default: false
      environment:
        description: Environment
        type: choice
        options: [dev, prod]
        default: dev

permissions:
  id-token: write
  contents: read

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

On `pull_request` the `inputs` context is empty, so `|| 'plan'` keeps apply and destroy off and `|| false` leaves the destroy confirmation unset — a PR can only ever plan. Read every value from `inputs`, **not** `github.event.inputs`: the latter returns the *string* `"false"` for an unticked checkbox, which is truthy and would defeat the confirmation.

The base workflow runs as a single job with no `environment:` key, so plan, apply, and destroy all authenticate from the branch or `pull_request` OIDC subject. To require reviewers for production apply, add `environment: <env>` to the job in your copy of `tf-deploy-base.yaml` and a matching `repo:<org>/<repo>:environment:<env>` federated credential — the plan-on-PR subject is still needed alongside it.

## Azure DevOps (shared template)

Copy [assets/azure-pipelines.yaml](assets/azure-pipelines.yaml) to `pipelines/azure_dev_ops/shared/azure-pipelines.yaml`. Copy [assets/examples/dev-azure-pipelines.yaml](assets/examples/dev-azure-pipelines.yaml) to `pipelines/azure_dev_ops/<env>/` and fill service-connection / state-storage **parameters at queue time**.

Parameters: service connection, state key, `workingDirectory`, `tfvarsFile`, plus backend resource group / storage / container. **No hardcoded org or project names.** TerraformInstaller pin is **1.15.8**. Apply remains in the shared template but production should use an approval gate; default caller action is plan.

Step expansion is compile-time on `terraformAction`: the destroy-confirmation check and the execute task only exist in the compiled YAML when the action calls for them. `terraform fmt -check -recursive` runs as a script step right after `TerraformInstaller@1` and fails the job — the Terraform task has no `fmt` command, so this step is how the policy is met on this host.

Plan saves `-out=tfplan`; the execute step runs `command: apply` with `commandOptions: tfplan` for **both** apply and destroy — applying a destroy plan *is* the destroy. No `-var-file` there: Terraform rejects it alongside a plan file.

### Environment pipeline (extends template)

```yaml
trigger: none

parameters:
  - name: resource
    type: string
  - name: domain
    type: string
  - name: workingDirectory
    type: string
  - name: serviceConnection
    type: string
  - name: stateResourceGroup
    type: string
  - name: stateStorageAccount
    type: string
  - name: terraformAction
    type: string
    default: plan
    values:
      - plan
      - apply
      - destroy
  - name: confirmDestroy
    type: boolean
    default: false

extends:
  template: /pipelines/azure_dev_ops/shared/azure-pipelines.yaml
  parameters:
    backendServiceArm: ${{ parameters.serviceConnection }}
    backendAzureRmResourceGroupName: ${{ parameters.stateResourceGroup }}
    backendAzureRmStorageAccountName: ${{ parameters.stateStorageAccount }}
    backendAzureRmContainerName: tfstate
    backendAzureRmKey: tfstate.${{ parameters.resource }}.${{ parameters.domain }}.dev
    workingDirectory: ${{ parameters.workingDirectory }}
    tfvarsFile: envs/dev.tfvars
    terraformAction: ${{ parameters.terraformAction }}
    confirmDestroy: ${{ parameters.confirmDestroy }}
```

## GitLab (optional third host)

If the consumer uses GitLab, copy [assets/gitlab-ci-terraform-template.yml](assets/gitlab-ci-terraform-template.yml) to `.gitlab/pipelines/gitlab-ci-terraform-template.yml`. Image is `hashicorp/terraform:1.15.8`. Parameterize `TF_ROOT` as `resources/<domain>/` and the var-file as `envs/<env>.tfvars`. `terraform_validate` runs `fmt -check -recursive` with no `allow_failure`. Apply is manual on `main`; `terraform_destroy` is manual and refuses to run unless `CONFIRM_DESTROY=DESTROY`. Do **not** add a new GitLab file unless the consumer asked for GitLab.

## Agent checklist

1. Confirm the stack path `resources/<domain>/` (one job per domain) and empty `backend "azurerm" {}`. State key is `tfstate.{resource}.{domain}.{environment}`; tfvars is `envs/<env>.tfvars`.
2. **Copy assets** from this skill into the consumer repo (do not rewrite YAML from memory).
3. Choose host: GitHub Actions reusable `workflow_call`, or Azure DevOps `extends` template (GitLab only if asked).
4. GitHub: one `terraform-<domain>.yaml` per domain from `assets/examples/terraform-domain.yaml`, plus a single shared `tf-deploy-base.yaml`.
5. Wire OIDC or a service-connection **parameter**; no key/SAS/subscription literals.
6. Parameterize backend `-backend-config` / template inputs from variables or parameters.
7. Add `terraform fmt -check -recursive` before init on **every** host and let it **fail the job** — no `continue-on-error`, no `allow_failure`. If the host template has no format step, add one.
8. Require `validate` after init, then `plan`.
9. Default action `plan`; apply only when the caller sets `apply`.
10. Offer `destroy` in every action list, behind a confirmation input that is separate from the action itself and fails the run before any credential is used.
11. Do not run `terraform apply` or `terraform destroy` from the agent session.
