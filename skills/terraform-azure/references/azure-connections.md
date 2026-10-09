# Azure connections for Terraform CI

Wire GitHub Actions, Azure DevOps, or GitLab CI to Azure using **Entra ID workload identity federation** (OIDC). This toolkit uses **Azure CLI (`az`) only** — not Azure Developer CLI. Do not use Azure Developer CLI for bootstrap, connections, or pipelines.

**Related:** [Operating process](operating-process.md) (menu item **Create Azure connections**) · [Bootstrap state storage](../scripts/bootstrap-tfstate.sh)

## Overview

| Phase | Who | Azure roles |
| --- | --- | --- |
| **Bootstrap** (one-time) | Platform admin with `az login` | **Contributor** on the subscription or state resource group, plus permission to create role assignments (e.g. **User Access Administrator** or **Owner**) to create the state RG, storage account, container, and grant CI access |
| **Ongoing CI** | Pipeline service principal (federated) | **Storage Blob Data Contributor** on the **state blob container** (not the whole subscription). **Least-privilege** roles on the target subscription or resource group for resources Terraform manages (often **Contributor** on a workload RG, not on the state RG) |

State backends must use Entra ID auth: set `use_oidc = true` **and** `use_azuread_auth = true` at `terraform init`. Do not use storage account keys or SAS tokens for production state (SEC-002).

## What `az` does vs host UI

| Step | `az` (scripts) | Manual in host UI / host CLI |
| --- | --- | --- |
| Entra app registration | `scripts/create-azure-oidc.sh` / `.ps1` (GitHub/GitLab); ADO: `az ad app create` first (see ADO section) | — |
| Service principal | Same as above (`az ad sp create` for ADO step 2) | — |
| Federated credential (OIDC trust) | Same scripts (GitHub/GitLab); ADO requires **Issuer** and **Subject identifier** copied from ADO draft | — |
| Storage Blob Data Contributor on state container | Script with `--assign-state-role`, or run printed `az role assignment create` | — |
| Workload RBAC (target RG/subscription) | `az role assignment create` (operator choice) | — |
| **Azure DevOps** draft ARM service connection | `az ad app create` + `az ad sp create`; tenant/subscription from `az account show` | **Project Settings → Service connections → New → Azure Resource Manager → Workload identity federation (manual)** — enter app ID, tenant, subscription; copy **Issuer** and **Subject identifier**; **Keep as draft** |
| **Azure DevOps** federated credential + finish connection | Script with `--ado-issuer` / `--ado-subject` from ADO draft | Return to draft → **Finish setup** → **Verify and save** |
| **GitHub** repository / environment secrets | Scripts output values | **Settings → Secrets and variables → Actions** (repo or **environment** secrets): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` |
| **GitLab** CI variables | `scripts/create-azure-oidc.sh` prints `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | **Settings → CI/CD → Variables**: `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` (same three values); enable **OIDC** / federated identity in `.gitlab-ci.yml` (`id_tokens`) |

Optional host CLIs (not required by this toolkit): `gh` (GitHub), `az devops` (Azure DevOps), `glab` (GitLab).

## Scripts

Bash and PowerShell wrappers share the same parameters:

```bash
chmod +x scripts/create-azure-oidc.sh
./scripts/create-azure-oidc.sh --help
```

```powershell
./scripts/create-azure-oidc.ps1 -Host github -GitHubOrg myorg -GitHubRepo myrepo -GitHubEnvironment prod
```

**Prerequisites:** `az` on PATH; `az login`; `az account set` to the target subscription.

**Required:** `--host` / `-Host` — `github`, `ado`, or `gitlab`.

### Host-specific parameters

| Host | Required parameters | Federated credential subject (created by script) |
| --- | --- | --- |
| **GitHub** | `--github-org`, `--github-repo`, `--github-environment` | `repo:ORG/REPO:environment:ENV` |
| **Azure DevOps** | `--ado-org`, `--ado-project`, `--ado-service-connection`, `--ado-issuer`, `--ado-subject` | Issuer and subject **copied from ADO draft** (Microsoft Entra issuer; not the deprecated `vstoken.dev.azure.com` URL) |
| **GitLab** | `--gitlab-project-path` (e.g. `group/project`) | `project_path:PATH:ref_type:TYPE:ref:REF` (defaults: `branch`, `main`) |

Optional: `--gitlab-issuer-url` (default `https://gitlab.com` for GitLab.com; set your instance URL for self-hosted).

### State container RBAC

When bootstrap has already created the state storage account and container (see `scripts/bootstrap-tfstate.sh`), pass:

- `--state-resource-group` / `-StateResourceGroup`
- `--state-storage-account` / `-StateStorageAccount`
- `--state-container-name` / `-StateContainerName` (default: `tfstate`)

Without `--assign-state-role` / `-AssignStateRole`, the script prints the exact:

```bash
az role assignment create \
  --assignee-object-id <SP_OBJECT_ID> \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<SUB>/resourceGroups/<RG>/providers/Microsoft.Storage/storageAccounts/<SA>/blobServices/default/containers/<CONTAINER>"
```

With `--assign-state-role`, the script runs that assignment (idempotent if already present).

**Secrets:** Scripts use **secret-less federation only** — they do not create or print client secrets. If you ever create a client secret manually (not recommended), store it only in a password manager or the host’s secret store — **never in git**.

## Azure DevOps (ARM service connection, OIDC)

Follow the [manual workload identity federation flow](https://learn.microsoft.com/azure/devops/pipelines/release/configure-workload-identity?view=azure-devops#set-a-workload-identity-service-connection) (app registration path). Azure DevOps generates the **Issuer** and **Subject identifier**; do not guess or hardcode them. New connections use the Microsoft Entra issuer (for example `https://login.microsoftonline.com/<tenant-id>/v2.0`), not the deprecated `https://vstoken.dev.azure.com` issuer.

1. **Plan** the service connection name (e.g. `terraform-prod`). It must match `--ado-service-connection`.
2. **Create Entra app + service principal** with `az` (no federated credential yet):

   ```bash
   ADO_ORG=myorg
   ADO_PROJECT=myproject
   APP_NAME="tf-oidc-ado-${ADO_ORG}-${ADO_PROJECT}"
   APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
   az ad sp create --id "$APP_ID"
   TENANT_ID="$(az account show --query tenantId -o tsv)"
   SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
   echo "AZURE_CLIENT_ID=$APP_ID"
   echo "AZURE_TENANT_ID=$TENANT_ID"
   echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
   ```

3. **Manual (ADO UI):** Project → **Pipelines** → **Service connections** → **New service connection** → **Azure Resource Manager** → **App registration or Managed identity (manual)** → **Workload identity federation**.
   - **Service connection name:** same as `--ado-service-connection`
   - **Application (client) ID:** `AZURE_CLIENT_ID` from step 2
   - **Directory (tenant) ID:** `AZURE_TENANT_ID` from `az account show`
   - **Subscription Id** / **Subscription Name:** target subscription from `az account show`
   - Copy the generated **Issuer** and **Subject identifier**
   - Select **Keep as draft** (required until the federated credential exists in Entra)

4. **Create the federated credential** (and optional state RBAC) with the ADO-copied values:

   ```bash
   ./scripts/create-azure-oidc.sh --host ado \
     --ado-org myorg --ado-project myproject \
     --ado-service-connection terraform-prod \
     --ado-issuer '<Issuer from ADO draft>' \
     --ado-subject '<Subject identifier from ADO draft>' \
     -g rg-acme-tfstate-prod -a stacmetfstateprod --assign-state-role
   ```

   PowerShell equivalent: `-AdoIssuer` and `-AdoSubject` with the same values. The script reuses the Entra app from step 2 (matching display name) and adds the federated credential via `az ad app federated-credential create`.

5. **Manual (ADO UI):** Return to the draft service connection → **Finish setup** → **Verify and save**.

6. Grant the service principal **least-privilege** on the workload subscription or resource group (e.g. Contributor on `rg-acme-webapp-prod`, not on the tfstate RG unless required).

Pipeline templates use the service connection name; backend init uses OIDC + Azure AD auth flags from the operating process.

## GitHub Actions (OIDC)

1. Create a **GitHub environment** (e.g. `prod`) if using environment-scoped OIDC.
2. Run the script:

   ```bash
   ./scripts/create-azure-oidc.sh --host github \
     --github-org myorg --github-repo myrepo --github-environment prod \
     -g rg-acme-tfstate-prod -a stacmetfstateprod
   ```

3. **Manual (GitHub UI):** Repository or environment → **Settings → Secrets and variables → Actions** → add:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
4. Workflow must request OIDC (`permissions: id-token: write`) and use `azure/login` (or equivalent) with those secrets. Copy the GitHub workflow assets from the sibling `terraform-azure-pipelines` skill (`assets/tf-deploy-base.yaml` once, `assets/examples/terraform-domain.yaml` per domain) into the consumer `.github/workflows/` directory.
5. `tf-deploy-base.yaml` runs as a single job with no `environment:` key, so its OIDC subject is the branch or pull request — `repo:<org>/<repo>:ref:refs/heads/<branch>` and `repo:<org>/<repo>:pull_request`. `create-azure-oidc.sh --host github` creates an **environment-scoped** subject (`repo:<org>/<repo>:environment:<env>`) instead, so either add a branch/PR federated credential alongside it, or add `environment: <env>` to the workflow job to match. A subject mismatch surfaces as `AADSTS700213` at the `azure/login` step.

Grant workload RBAC separately on the target subscription or RG.

## GitLab CI (OIDC / federated identity)

1. Run the script:

   ```bash
   ./scripts/create-azure-oidc.sh --host gitlab \
     --gitlab-project-path mygroup/myrepo \
     --gitlab-ref-type branch --gitlab-ref main \
     -g rg-acme-tfstate-dev -a stacmetfstatedev --assign-state-role
   ```

   For GitLab environments, use `--gitlab-ref-type environment --gitlab-ref production`.

2. **Manual (GitLab UI):** **Settings → CI/CD → Variables** (masked, protected as appropriate). `scripts/create-azure-oidc.sh` prints `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`; map those into GitLab as:
   - `ARM_CLIENT_ID`
   - `ARM_TENANT_ID`
   - `ARM_SUBSCRIPTION_ID`

3. **Manual (`.gitlab-ci.yml`):** declare OIDC token and pass to Azure login, e.g.:

   ```yaml
   id_tokens:
     GITLAB_OIDC_TOKEN:
       aud: api://AzureADTokenExchange
   ```

   The `aud` value must match the federated credential **audiences** (`api://AzureADTokenExchange` — [Entra recommendation](https://learn.microsoft.com/entra/workload-id/workload-identity-federation-considerations#general-federated-identity-credential-considerations)). Set `--gitlab-issuer-url` to your GitLab instance URL when self-hosted (issuer only; audience stays `api://AzureADTokenExchange`). Copy `assets/gitlab-ci-terraform-template.yml` from the sibling `terraform-azure-pipelines` skill for backend `-backend-config` injection and validate/plan/apply stages; that template does **not** declare `id_tokens` — operators must add the snippet above.

## Role summary

| Role | Scope | When |
| --- | --- | --- |
| Contributor (+ role assignment rights) | Subscription or state RG | **Bootstrap only** — create state RG, storage account, container (`bootstrap-tfstate.sh`) |
| **Storage Blob Data Contributor** | **State blob container** | **Every CI run** that reads/writes remote state with Azure AD auth |
| Contributor / custom (least privilege) | Workload subscription or RG | Terraform plan/apply against application resources |

## Verification checklist

1. `az account show` returns the intended subscription.
2. Entra app + federated credential exist (`az ad app federated-credential list --id <APP_ID>`).
3. State container has **Storage Blob Data Contributor** for the CI principal.
4. Host secrets/variables or ADO service connection match script output.
5. `terraform init` with `use_oidc=true` and `use_azuread_auth=true` succeeds in CI (tier 2 plan).

## Troubleshooting

- **Login / federation failed:** Confirm federated credential **issuer** and **subject** match the host (GitHub environment name, ADO service connection name, GitLab project path/ref).
- **State access denied:** Confirm role on the **container** scope, not only the storage account. Shared-key access should remain disabled on the state account.
- **Missing `az` or session:** Scripts exit non-zero with usage or login instructions — run `az login` and `az account set`.
