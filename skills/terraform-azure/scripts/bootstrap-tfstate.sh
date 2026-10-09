#!/usr/bin/env bash
set -euo pipefail

# One-time, out-of-band bootstrap for Terraform remote state storage.
# Creates resource group, storage account, and blob container via Azure CLI (`az`).
# Does not run Terraform or manage these resources in state.
#
# Make executable: chmod +x scripts/bootstrap-tfstate.sh
#
# Prerequisites: Azure CLI on PATH; authenticated session (`az login`).

usage() {
  cat <<'EOF'
Usage: bootstrap-tfstate.sh [OPTIONS]

One-time bootstrap of Azure Blob storage for Terraform remote state. Creates the
resource group (if missing), storage account, container, enables blob versioning,
and disables shared-key access on the account. Prints suggested terraform init
-backend-config flags using Entra ID (OIDC + Azure AD auth) — no access keys.

Required:
  -g, --resource-group-name NAME   Resource group for state storage
  -l, --location LOCATION          Azure region (e.g. eastus)

  -s, --storage-account-name NAME  Globally unique storage account name (3–24
                                   lowercase letters and numbers)

Optional:
  -c, --container-name NAME        Blob container name (default: tfstate)
  -r, --resource NAME              Stack resource segment for state key
  -e, --environment ENV            Environment segment for state key
  -h, --help                       Show this help and exit

When --resource and --environment are both set, the printed state key is
tfstate.<resource>.<environment>. Otherwise the example key tfstate.<resource>.<env>
is shown.

Storage account SKU: Standard_LRS. Blob encryption is enabled by default on new
accounts. Shared-key access is disabled via --allow-shared-key-access false.

Examples:
  ./scripts/bootstrap-tfstate.sh \
    --resource-group-name rg-acme-tfstate-prod \
    --location eastus \
    --storage-account-name stacmetfstateprod \
    --container-name tfstate

  ./scripts/bootstrap-tfstate.sh -g rg-acme-tfstate-dev -l westeurope \
    -s stacmetfstatedev -r webapp -e dev
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

RESOURCE_GROUP_NAME=""
LOCATION=""
STORAGE_ACCOUNT_NAME=""
CONTAINER_NAME="tfstate"
RESOURCE=""
ENVIRONMENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g | --resource-group-name)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      RESOURCE_GROUP_NAME="$2"
      shift 2
      ;;
    -l | --location)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      LOCATION="$2"
      shift 2
      ;;
    -s | --storage-account-name)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      STORAGE_ACCOUNT_NAME="$2"
      shift 2
      ;;
    -c | --container-name)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      CONTAINER_NAME="$2"
      shift 2
      ;;
    -r | --resource)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      RESOURCE="$2"
      shift 2
      ;;
    -e | --environment)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      ENVIRONMENT="$2"
      shift 2
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

[[ -n "$RESOURCE_GROUP_NAME" ]] || fail "--resource-group-name is required (use --help)"
[[ -n "$LOCATION" ]] || fail "--location is required (use --help)"
[[ -n "$STORAGE_ACCOUNT_NAME" ]] || fail "--storage-account-name is required (use --help)"

if ! command -v az >/dev/null 2>&1; then
  echo "error: Azure CLI (az) is not installed or not on PATH" >&2
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo "error: Azure CLI is not logged in — run 'az login' and 'az account set'" >&2
  exit 1
fi

if az group show --name "$RESOURCE_GROUP_NAME" >/dev/null 2>&1; then
  echo "Resource group already exists: $RESOURCE_GROUP_NAME"
else
  echo "Creating resource group: $RESOURCE_GROUP_NAME ($LOCATION)"
  az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" >/dev/null
fi

if az storage account show \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" >/dev/null 2>&1; then
  echo "Storage account already exists: $STORAGE_ACCOUNT_NAME"
else
  echo "Creating storage account: $STORAGE_ACCOUNT_NAME (SKU Standard_LRS, shared-key access disabled)"
  az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-shared-key-access false \
    --min-tls-version TLS1_2 >/dev/null
fi

echo "Ensuring shared-key access is disabled on storage account: $STORAGE_ACCOUNT_NAME"
az storage account update \
  --name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --allow-shared-key-access false >/dev/null

echo "Enabling blob versioning on storage account: $STORAGE_ACCOUNT_NAME"
az storage account blob-service-properties update \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --enable-versioning true >/dev/null

if az storage container show \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --auth-mode login >/dev/null 2>&1; then
  echo "Container already exists: $CONTAINER_NAME"
else
  echo "Creating blob container: $CONTAINER_NAME"
  az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --auth-mode login >/dev/null
fi

if [[ -n "$RESOURCE" && -n "$ENVIRONMENT" ]]; then
  STATE_KEY="tfstate.${RESOURCE}.${ENVIRONMENT}"
else
  STATE_KEY="tfstate.<resource>.<env>"
fi

cat <<EOF

Bootstrap complete. Suggested terraform init (Entra ID — no storage account keys):

terraform init \\
  -backend-config="resource_group_name=${RESOURCE_GROUP_NAME}" \\
  -backend-config="storage_account_name=${STORAGE_ACCOUNT_NAME}" \\
  -backend-config="container_name=${CONTAINER_NAME}" \\
  -backend-config="key=${STATE_KEY}" \\
  -backend-config="use_oidc=true" \\
  -backend-config="use_azuread_auth=true"

Grant the CI or operator identity Storage Blob Data Contributor on container
'${CONTAINER_NAME}' before running terraform init with Azure AD auth.
EOF
