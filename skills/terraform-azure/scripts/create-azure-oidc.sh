#!/usr/bin/env bash
set -euo pipefail

# Create (or reuse) an Entra ID application and federated credential for CI OIDC.
# Supports GitHub Actions, Azure DevOps, and GitLab. Uses Azure CLI (az) only.
#
# Make executable: chmod +x scripts/create-azure-oidc.sh
#
# Prerequisites: Azure CLI on PATH; authenticated session (`az login`).

usage() {
  cat <<'EOF'
Usage: create-azure-oidc.sh [OPTIONS]

Creates or reuses an Entra ID app registration, service principal, and federated
credential for secret-less CI authentication to Azure. Optionally assigns (or prints)
Storage Blob Data Contributor on a Terraform state blob container.

Required:
  --host HOST                    CI host: github, ado, or gitlab

Host-specific (required when --host matches):

  GitHub (--host github):
    --github-org ORG
    --github-repo REPO
    --github-environment ENV     GitHub environment name (OIDC subject)

  Azure DevOps (--host ado):
    --ado-org ORG
    --ado-project PROJECT
    --ado-service-connection NAME
                                 Planned ARM service connection name
    --ado-issuer ISSUER           Issuer URL copied from ADO draft service connection
    --ado-subject SUBJECT         Subject identifier copied from ADO draft service connection

  GitLab (--host gitlab):
    --gitlab-project-path PATH   Project path, e.g. group/subgroup/project
    --gitlab-ref-type TYPE       branch, tag, or environment (default: branch)
    --gitlab-ref REF             Branch/tag name or environment name (default: main)

Optional:
  -s, --subscription-id ID       Target subscription (default: current az account)
  -n, --app-display-name NAME    Entra app display name
  --gitlab-issuer-url URL        GitLab OIDC issuer (default: https://gitlab.com)
  -g, --state-resource-group RG  State storage resource group
  -a, --state-storage-account SA State storage account name
  -c, --state-container-name CN  State blob container (default: tfstate)
  --assign-state-role            Run Storage Blob Data Contributor assignment
                                 (default: print exact az role assignment create)
  -h, --help                     Show this help and exit

Examples:
  ./scripts/create-azure-oidc.sh --host github \
    --github-org myorg --github-repo myrepo --github-environment prod \
    -g rg-acme-tfstate-prod -a stacmetfstateprod

  ./scripts/create-azure-oidc.sh --host ado \
    --ado-org myorg --ado-project myproject --ado-service-connection terraform-prod \
    --ado-issuer 'https://login.microsoftonline.com/<tenant-id>/v2.0' \
    --ado-subject 'sc://myorg/myproject/terraform-prod' \
    --assign-state-role -g rg-acme-tfstate-prod -a stacmetfstateprod

  ./scripts/create-azure-oidc.sh --host gitlab \
    --gitlab-project-path mygroup/myrepo --gitlab-ref-type branch --gitlab-ref main
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

HOST=""
SUBSCRIPTION_ID=""
APP_DISPLAY_NAME=""
GITHUB_ORG=""
GITHUB_REPO=""
GITHUB_ENVIRONMENT=""
ADO_ORG=""
ADO_PROJECT=""
ADO_SERVICE_CONNECTION=""
ADO_ISSUER=""
ADO_SUBJECT=""
GITLAB_PROJECT_PATH=""
GITLAB_REF_TYPE="branch"
GITLAB_REF="main"
GITLAB_ISSUER_URL="https://gitlab.com"
STATE_RESOURCE_GROUP=""
STATE_STORAGE_ACCOUNT=""
STATE_CONTAINER_NAME="tfstate"
ASSIGN_STATE_ROLE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      HOST="$2"
      shift 2
      ;;
    -s | --subscription-id)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      SUBSCRIPTION_ID="$2"
      shift 2
      ;;
    -n | --app-display-name)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      APP_DISPLAY_NAME="$2"
      shift 2
      ;;
    --github-org)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      GITHUB_ORG="$2"
      shift 2
      ;;
    --github-repo)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      GITHUB_REPO="$2"
      shift 2
      ;;
    --github-environment)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      GITHUB_ENVIRONMENT="$2"
      shift 2
      ;;
    --ado-org)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      ADO_ORG="$2"
      shift 2
      ;;
    --ado-project)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      ADO_PROJECT="$2"
      shift 2
      ;;
    --ado-service-connection)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      ADO_SERVICE_CONNECTION="$2"
      shift 2
      ;;
    --ado-issuer)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      ADO_ISSUER="$2"
      shift 2
      ;;
    --ado-subject)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      ADO_SUBJECT="$2"
      shift 2
      ;;
    --gitlab-project-path)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      GITLAB_PROJECT_PATH="$2"
      shift 2
      ;;
    --gitlab-ref-type)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      GITLAB_REF_TYPE="$2"
      shift 2
      ;;
    --gitlab-ref)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      GITLAB_REF="$2"
      shift 2
      ;;
    --gitlab-issuer-url)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      GITLAB_ISSUER_URL="$2"
      shift 2
      ;;
    -g | --state-resource-group)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      STATE_RESOURCE_GROUP="$2"
      shift 2
      ;;
    -a | --state-storage-account)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      STATE_STORAGE_ACCOUNT="$2"
      shift 2
      ;;
    -c | --state-container-name)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      STATE_CONTAINER_NAME="$2"
      shift 2
      ;;
    --assign-state-role)
      ASSIGN_STATE_ROLE=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1 (use --help)"
      ;;
  esac
done

[[ -n "$HOST" ]] || fail "--host is required (github, ado, or gitlab; use --help)"

case "$HOST" in
  github)
    [[ -n "$GITHUB_ORG" ]] || fail "--github-org is required when --host github"
    [[ -n "$GITHUB_REPO" ]] || fail "--github-repo is required when --host github"
    [[ -n "$GITHUB_ENVIRONMENT" ]] || fail "--github-environment is required when --host github"
    ;;
  ado)
    [[ -n "$ADO_ORG" ]] || fail "--ado-org is required when --host ado"
    [[ -n "$ADO_PROJECT" ]] || fail "--ado-project is required when --host ado"
    [[ -n "$ADO_SERVICE_CONNECTION" ]] || fail "--ado-service-connection is required when --host ado"
    [[ -n "$ADO_ISSUER" ]] || fail "--ado-issuer is required when --host ado (copy from ADO draft service connection)"
    [[ -n "$ADO_SUBJECT" ]] || fail "--ado-subject is required when --host ado (copy from ADO draft service connection)"
    ;;
  gitlab)
    [[ -n "$GITLAB_PROJECT_PATH" ]] || fail "--gitlab-project-path is required when --host gitlab"
    case "$GITLAB_REF_TYPE" in
      branch | tag | environment) ;;
      *) fail "--gitlab-ref-type must be branch, tag, or environment" ;;
    esac
    ;;
  *)
    fail "--host must be github, ado, or gitlab (use --help)"
    ;;
esac

if [[ -n "$STATE_RESOURCE_GROUP" || -n "$STATE_STORAGE_ACCOUNT" ]]; then
  [[ -n "$STATE_RESOURCE_GROUP" && -n "$STATE_STORAGE_ACCOUNT" ]] || \
    fail "both --state-resource-group and --state-storage-account are required for state RBAC"
fi

if ! command -v az >/dev/null 2>&1; then
  echo "error: Azure CLI (az) is not installed or not on PATH" >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "error: Azure CLI is not logged in — run 'az login' and 'az account set'" >&2
  exit 1
fi

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
fi

TENANT_ID="$(az account show --query tenantId -o tsv)"

if [[ -z "$APP_DISPLAY_NAME" ]]; then
  case "$HOST" in
    github) APP_DISPLAY_NAME="tf-oidc-github-${GITHUB_ORG}-${GITHUB_REPO}" ;;
    ado) APP_DISPLAY_NAME="tf-oidc-ado-${ADO_ORG}-${ADO_PROJECT}" ;;
    gitlab)
      slug="${GITLAB_PROJECT_PATH//\//-}"
      APP_DISPLAY_NAME="tf-oidc-gitlab-${slug}"
      ;;
  esac
fi

echo "Using subscription: $SUBSCRIPTION_ID"
echo "Using tenant: $TENANT_ID"
echo "Entra app display name: $APP_DISPLAY_NAME"

EXISTING_APP_ID="$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)"
if [[ -n "$EXISTING_APP_ID" && "$EXISTING_APP_ID" != "null" ]]; then
  APP_ID="$EXISTING_APP_ID"
  echo "Reusing existing Entra application: $APP_ID"
else
  echo "Creating Entra application: $APP_DISPLAY_NAME"
  APP_ID="$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)"
fi

SP_OBJECT_ID="$(az ad sp list --filter "appId eq '$APP_ID'" --query "[0].id" -o tsv 2>/dev/null || true)"
if [[ -z "$SP_OBJECT_ID" || "$SP_OBJECT_ID" == "null" ]]; then
  echo "Creating service principal for app: $APP_ID"
  SP_OBJECT_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
else
  echo "Reusing existing service principal: $SP_OBJECT_ID"
fi

case "$HOST" in
  github)
    FED_NAME="github-${GITHUB_ORG}-${GITHUB_REPO}-${GITHUB_ENVIRONMENT}"
    FED_ISSUER="https://token.actions.githubusercontent.com"
    FED_SUBJECT="repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${GITHUB_ENVIRONMENT}"
    ;;
  ado)
    FED_NAME="ado-${ADO_ORG}-${ADO_PROJECT}-${ADO_SERVICE_CONNECTION}"
    FED_ISSUER="$ADO_ISSUER"
    FED_SUBJECT="$ADO_SUBJECT"
    ;;
  gitlab)
    slug="${GITLAB_PROJECT_PATH//\//-}"
    FED_NAME="gitlab-${slug}-${GITLAB_REF_TYPE}-${GITLAB_REF}"
    FED_ISSUER="$GITLAB_ISSUER_URL"
    FED_SUBJECT="project_path:${GITLAB_PROJECT_PATH}:ref_type:${GITLAB_REF_TYPE}:ref:${GITLAB_REF}"
    ;;
esac

FED_NAME="${FED_NAME//[^a-zA-Z0-9_-]/-}"

EXISTING_FED="$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='${FED_NAME}'].name" -o tsv 2>/dev/null || true)"
if [[ -n "$EXISTING_FED" ]]; then
  echo "Reusing existing federated credential: $FED_NAME"
else
  echo "Creating federated credential: $FED_NAME"
  echo "  issuer:  $FED_ISSUER"
  echo "  subject: $FED_SUBJECT"
  az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters "{\"name\":\"${FED_NAME}\",\"issuer\":\"${FED_ISSUER}\",\"subject\":\"${FED_SUBJECT}\",\"audiences\":[\"api://AzureADTokenExchange\"]}" \
    >/dev/null
fi

if [[ -n "$STATE_RESOURCE_GROUP" && -n "$STATE_STORAGE_ACCOUNT" ]]; then
  STATE_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${STATE_RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STATE_STORAGE_ACCOUNT}/blobServices/default/containers/${STATE_CONTAINER_NAME}"
  ROLE_ASSIGN_CMD=(az role assignment create
    --assignee-object-id "$SP_OBJECT_ID"
    --assignee-principal-type ServicePrincipal
    --role "Storage Blob Data Contributor"
    --scope "$STATE_SCOPE")

  if [[ "$ASSIGN_STATE_ROLE" == true ]]; then
    echo "Assigning Storage Blob Data Contributor on state container scope"
    if az role assignment list \
      --assignee-object-id "$SP_OBJECT_ID" \
      --scope "$STATE_SCOPE" \
      --role "Storage Blob Data Contributor" \
      --query "[0].id" -o tsv 2>/dev/null | grep -q .; then
      echo "Role assignment already exists on container: $STATE_CONTAINER_NAME"
    else
      "${ROLE_ASSIGN_CMD[@]}" >/dev/null
      echo "Role assignment created."
    fi
  else
    echo
    echo "Run this command to grant state container access (Storage Blob Data Contributor):"
    printf '  %q' "${ROLE_ASSIGN_CMD[@]}"
    echo
  fi
fi

cat <<EOF

OIDC setup complete (secret-less federation — no client secret created).

Pipeline / host values:
  AZURE_CLIENT_ID=$APP_ID
  AZURE_TENANT_ID=$TENANT_ID
  AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID

Next: complete host-specific steps in references/azure-connections.md (service connection,
GitHub environment secrets, or GitLab CI variables). Never commit client secrets to git.
EOF
