#Requires -Version 7.0
<#
.SYNOPSIS
  One-time bootstrap of Azure Blob storage for Terraform remote state.

.DESCRIPTION
  Out-of-band creation of the state resource group, storage account, and blob
  container using Azure CLI (az). Enables blob versioning and disables shared-key
  access on the storage account. Prints suggested terraform init -backend-config
  flags for Entra ID (OIDC + Azure AD auth) without storage account keys.

  This is a one-time bootstrap — do not manage these resources in Terraform state.

.PARAMETER ResourceGroupName
  Resource group name for state storage (required).

.PARAMETER Location
  Azure region, e.g. eastus (required).

.PARAMETER StorageAccountName
  Globally unique storage account name, 3–24 lowercase letters and numbers (required).

.PARAMETER ContainerName
  Blob container name. Default: tfstate.

.PARAMETER Resource
  Optional stack resource segment for the printed state key.

.PARAMETER Environment
  Optional environment segment for the printed state key. When both Resource and
  Environment are set, the key is tfstate.<resource>.<environment>; otherwise the
  example tfstate.<resource>.<env> is shown.

.EXAMPLE
  ./scripts/bootstrap-tfstate.ps1 `
    -ResourceGroupName rg-acme-tfstate-prod `
    -Location eastus `
    -StorageAccountName stacmetfstateprod

.EXAMPLE
  ./scripts/bootstrap-tfstate.ps1 -ResourceGroupName rg-acme-tfstate-dev `
    -Location westeurope -StorageAccountName stacmetfstatedev `
    -Resource webapp -Environment dev

.NOTES
  Prerequisites: Azure CLI (az) on PATH; authenticated session (az login).
  Storage SKU: Standard_LRS. Blob encryption is enabled by default. Shared-key
  access is disabled with --allow-shared-key-access false.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $ResourceGroupName,

  [Parameter(Mandatory = $true)]
  [string] $Location,

  [Parameter(Mandatory = $true)]
  [string] $StorageAccountName,

  [Parameter(Mandatory = $false)]
  [string] $ContainerName = 'tfstate',

  [Parameter(Mandatory = $false)]
  [string] $Resource,

  [Parameter(Mandatory = $false)]
  [string] $Environment
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Write-Error 'error: Azure CLI (az) is not installed or not on PATH'
  exit 1
}

az account show *>$null
if ($LASTEXITCODE -ne 0) {
  Write-Error 'error: Azure CLI is not logged in — run ''az login'' and ''az account set'''
  exit 1
}

$rgShow = az group show --name $ResourceGroupName 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "Resource group already exists: $ResourceGroupName"
} else {
  Write-Host "Creating resource group: $ResourceGroupName ($Location)"
  az group create --name $ResourceGroupName --location $Location | Out-Null
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$saShow = az storage account show `
  --name $StorageAccountName `
  --resource-group $ResourceGroupName 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "Storage account already exists: $StorageAccountName"
} else {
  Write-Host "Creating storage account: $StorageAccountName (SKU Standard_LRS, shared-key access disabled)"
  az storage account create `
    --name $StorageAccountName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --sku Standard_LRS `
    --kind StorageV2 `
    --allow-shared-key-access false `
    --min-tls-version TLS1_2 | Out-Null
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Ensuring shared-key access is disabled on storage account: $StorageAccountName"
az storage account update `
  --name $StorageAccountName `
  --resource-group $ResourceGroupName `
  --allow-shared-key-access false | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Enabling blob versioning on storage account: $StorageAccountName"
az storage account blob-service-properties update `
  --resource-group $ResourceGroupName `
  --account-name $StorageAccountName `
  --enable-versioning true | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$containerShow = az storage container show `
  --name $ContainerName `
  --account-name $StorageAccountName `
  --auth-mode login 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host "Container already exists: $ContainerName"
} else {
  Write-Host "Creating blob container: $ContainerName"
  az storage container create `
    --name $ContainerName `
    --account-name $StorageAccountName `
    --auth-mode login | Out-Null
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($Resource -and $Environment) {
  $stateKey = "tfstate.$Resource.$Environment"
} else {
  $stateKey = 'tfstate.<resource>.<env>'
}

Write-Output @"

Bootstrap complete. Suggested terraform init (Entra ID — no storage account keys):

terraform init \
  -backend-config="resource_group_name=$ResourceGroupName" \
  -backend-config="storage_account_name=$StorageAccountName" \
  -backend-config="container_name=$ContainerName" \
  -backend-config="key=$stateKey" \
  -backend-config="use_oidc=true" \
  -backend-config="use_azuread_auth=true"

Grant the CI or operator identity Storage Blob Data Contributor on container
'$ContainerName' before running terraform init with Azure AD auth.
"@
