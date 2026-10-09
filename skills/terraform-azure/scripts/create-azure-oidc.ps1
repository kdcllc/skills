#Requires -Version 7.0
<#
.SYNOPSIS
  Create Entra ID app + federated credential for CI OIDC (GitHub, ADO, GitLab).

.DESCRIPTION
  Creates or reuses an Entra ID application registration, service principal, and
  federated credential for secret-less CI authentication. Optionally assigns or prints
  Storage Blob Data Contributor on a Terraform state blob container.

  Uses Azure CLI (az) only. Does not create client secrets.

.PARAMETER Host
  CI host: github, ado, or gitlab (required).

.PARAMETER SubscriptionId
  Target subscription ID. Default: current az account.

.PARAMETER AppDisplayName
  Entra application display name. Default: generated from host parameters.

.PARAMETER GitHubOrg
  GitHub organization or user (required when Host is github).

.PARAMETER GitHubRepo
  GitHub repository name (required when Host is github).

.PARAMETER GitHubEnvironment
  GitHub environment name for OIDC subject (required when Host is github).

.PARAMETER AdoOrg
  Azure DevOps organization name (required when Host is ado).

.PARAMETER AdoProject
  Azure DevOps project name (required when Host is ado).

.PARAMETER AdoServiceConnection
  Planned ARM service connection name (required when Host is ado).

.PARAMETER AdoIssuer
  Issuer URL copied from the ADO draft service connection (required when Host is ado).

.PARAMETER AdoSubject
  Subject identifier copied from the ADO draft service connection (required when Host is ado).

.PARAMETER GitLabProjectPath
  GitLab project path, e.g. group/subgroup/project (required when Host is gitlab).

.PARAMETER GitLabRefType
  branch, tag, or environment. Default: branch.

.PARAMETER GitLabRef
  Branch/tag name or environment name. Default: main.

.PARAMETER GitLabIssuerUrl
  GitLab OIDC issuer URL. Default: https://gitlab.com

.PARAMETER StateResourceGroup
  Resource group containing the state storage account.

.PARAMETER StateStorageAccount
  State storage account name.

.PARAMETER StateContainerName
  State blob container name. Default: tfstate.

.PARAMETER AssignStateRole
  Run Storage Blob Data Contributor assignment. Default: print exact az command.

.EXAMPLE
  ./scripts/create-azure-oidc.ps1 -Host github `
    -GitHubOrg myorg -GitHubRepo myrepo -GitHubEnvironment prod `
    -StateResourceGroup rg-acme-tfstate-prod -StateStorageAccount stacmetfstateprod

.EXAMPLE
  ./scripts/create-azure-oidc.ps1 -Host ado `
    -AdoOrg myorg -AdoProject myproject -AdoServiceConnection terraform-prod `
    -AdoIssuer 'https://login.microsoftonline.com/<tenant-id>/v2.0' `
    -AdoSubject 'sc://myorg/myproject/terraform-prod' `
    -AssignStateRole -StateResourceGroup rg-acme-tfstate-prod `
    -StateStorageAccount stacmetfstateprod

.NOTES
  Prerequisites: Azure CLI (az) on PATH; authenticated session (az login).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [Alias('Host')]
  [ValidateSet('github', 'ado', 'gitlab')]
  [string] $CiHost,

  [Parameter(Mandatory = $false)]
  [string] $SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string] $AppDisplayName,

  [Parameter(Mandatory = $false)]
  [string] $GitHubOrg,

  [Parameter(Mandatory = $false)]
  [string] $GitHubRepo,

  [Parameter(Mandatory = $false)]
  [string] $GitHubEnvironment,

  [Parameter(Mandatory = $false)]
  [string] $AdoOrg,

  [Parameter(Mandatory = $false)]
  [string] $AdoProject,

  [Parameter(Mandatory = $false)]
  [string] $AdoServiceConnection,

  [Parameter(Mandatory = $false)]
  [string] $AdoIssuer,

  [Parameter(Mandatory = $false)]
  [string] $AdoSubject,

  [Parameter(Mandatory = $false)]
  [string] $GitLabProjectPath,

  [Parameter(Mandatory = $false)]
  [ValidateSet('branch', 'tag', 'environment')]
  [string] $GitLabRefType = 'branch',

  [Parameter(Mandatory = $false)]
  [string] $GitLabRef = 'main',

  [Parameter(Mandatory = $false)]
  [string] $GitLabIssuerUrl = 'https://gitlab.com',

  [Parameter(Mandatory = $false)]
  [string] $StateResourceGroup,

  [Parameter(Mandatory = $false)]
  [string] $StateStorageAccount,

  [Parameter(Mandatory = $false)]
  [string] $StateContainerName = 'tfstate',

  [Parameter(Mandatory = $false)]
  [switch] $AssignStateRole
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
  @'
Usage: create-azure-oidc.ps1 -Host github|ado|gitlab [OPTIONS]

See ./scripts/create-azure-oidc.sh --help for full parameter documentation.
'@ | Write-Output
}

switch ($CiHost) {
  'github' {
    if (-not $GitHubOrg -or -not $GitHubRepo -or -not $GitHubEnvironment) {
      Show-Usage
      Write-Error 'error: -GitHubOrg, -GitHubRepo, and -GitHubEnvironment are required when -Host is github'
      exit 1
    }
  }
  'ado' {
    if (-not $AdoOrg -or -not $AdoProject -or -not $AdoServiceConnection) {
      Show-Usage
      Write-Error 'error: -AdoOrg, -AdoProject, and -AdoServiceConnection are required when -Host is ado'
      exit 1
    }
    if (-not $AdoIssuer) {
      Show-Usage
      Write-Error 'error: -AdoIssuer is required when -Host is ado (copy from ADO draft service connection)'
      exit 1
    }
    if (-not $AdoSubject) {
      Show-Usage
      Write-Error 'error: -AdoSubject is required when -Host is ado (copy from ADO draft service connection)'
      exit 1
    }
  }
  'gitlab' {
    if (-not $GitLabProjectPath) {
      Show-Usage
      Write-Error 'error: -GitLabProjectPath is required when -Host is gitlab'
      exit 1
    }
  }
}

if (($StateResourceGroup -or $StateStorageAccount) -and (-not $StateResourceGroup -or -not $StateStorageAccount)) {
  Write-Error 'error: both -StateResourceGroup and -StateStorageAccount are required for state RBAC'
  exit 1
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  Write-Error 'error: Azure CLI (az) is not installed or not on PATH'
  exit 1
}

az account show *>$null
if ($LASTEXITCODE -ne 0) {
  Write-Error 'error: Azure CLI is not logged in — run ''az login'' and ''az account set'''
  exit 1
}

if (-not $SubscriptionId) {
  $SubscriptionId = az account show --query id -o tsv
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$tenantId = az account show --query tenantId -o tsv
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $AppDisplayName) {
  switch ($CiHost) {
    'github' { $AppDisplayName = "tf-oidc-github-$GitHubOrg-$GitHubRepo" }
    'ado' { $AppDisplayName = "tf-oidc-ado-$AdoOrg-$AdoProject" }
    'gitlab' {
      $slug = $GitLabProjectPath -replace '/', '-'
      $AppDisplayName = "tf-oidc-gitlab-$slug"
    }
  }
}

Write-Host "Using subscription: $SubscriptionId"
Write-Host "Using tenant: $tenantId"
Write-Host "Entra app display name: $AppDisplayName"

$existingAppId = az ad app list --display-name $AppDisplayName --query "[0].appId" -o tsv 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAppId -and $existingAppId -ne 'null') {
  $appId = $existingAppId
  Write-Host "Reusing existing Entra application: $appId"
} else {
  Write-Host "Creating Entra application: $AppDisplayName"
  $appId = az ad app create --display-name $AppDisplayName --query appId -o tsv
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$spObjectId = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or -not $spObjectId -or $spObjectId -eq 'null') {
  Write-Host "Creating service principal for app: $appId"
  $spObjectId = az ad sp create --id $appId --query id -o tsv
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
  Write-Host "Reusing existing service principal: $spObjectId"
}

switch ($CiHost) {
  'github' {
    $fedName = "github-$GitHubOrg-$GitHubRepo-$GitHubEnvironment"
    $fedIssuer = 'https://token.actions.githubusercontent.com'
    $fedSubject = "repo:${GitHubOrg}/${GitHubRepo}:environment:${GitHubEnvironment}"
  }
  'ado' {
    $fedName = "ado-$AdoOrg-$AdoProject-$AdoServiceConnection"
    $fedIssuer = $AdoIssuer
    $fedSubject = $AdoSubject
  }
  'gitlab' {
    $slug = $GitLabProjectPath -replace '/', '-'
    $fedName = "gitlab-$slug-$GitLabRefType-$GitLabRef"
    $fedIssuer = $GitLabIssuerUrl
    $fedSubject = "project_path:${GitLabProjectPath}:ref_type:${GitLabRefType}:ref:${GitLabRef}"
  }
}

$fedName = ($fedName -replace '[^a-zA-Z0-9_-]', '-')

$existingFed = az ad app federated-credential list --id $appId --query "[?name=='$fedName'].name" -o tsv 2>$null
if ($LASTEXITCODE -eq 0 -and $existingFed) {
  Write-Host "Reusing existing federated credential: $fedName"
} else {
  Write-Host "Creating federated credential: $fedName"
  Write-Host "  issuer:  $fedIssuer"
  Write-Host "  subject: $fedSubject"
  $fedParams = @{
    name      = $fedName
    issuer    = $fedIssuer
    subject   = $fedSubject
    audiences = @('api://AzureADTokenExchange')
  } | ConvertTo-Json -Compress
  az ad app federated-credential create --id $appId --parameters $fedParams | Out-Null
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($StateResourceGroup -and $StateStorageAccount) {
  $stateScope = "/subscriptions/$SubscriptionId/resourceGroups/$StateResourceGroup/providers/Microsoft.Storage/storageAccounts/$StateStorageAccount/blobServices/default/containers/$StateContainerName"
  $roleAssignCmd = @(
    'az', 'role', 'assignment', 'create',
    '--assignee-object-id', $spObjectId,
    '--assignee-principal-type', 'ServicePrincipal',
    '--role', 'Storage Blob Data Contributor',
    '--scope', $stateScope
  )

  if ($AssignStateRole) {
    Write-Host 'Assigning Storage Blob Data Contributor on state container scope'
    $existingAssignment = az role assignment list `
      --assignee-object-id $spObjectId `
      --scope $stateScope `
      --role 'Storage Blob Data Contributor' `
      --query '[0].id' -o tsv 2>$null
    if ($LASTEXITCODE -eq 0 -and $existingAssignment) {
      Write-Host "Role assignment already exists on container: $StateContainerName"
    } else {
      az role assignment create `
        --assignee-object-id $spObjectId `
        --assignee-principal-type ServicePrincipal `
        --role 'Storage Blob Data Contributor' `
        --scope $stateScope | Out-Null
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      Write-Host 'Role assignment created.'
    }
  } else {
    Write-Output ''
    Write-Output 'Run this command to grant state container access (Storage Blob Data Contributor):'
    Write-Output ('  ' + ($roleAssignCmd -join ' '))
  }
}

Write-Output @"

OIDC setup complete (secret-less federation — no client secret created).

Pipeline / host values:
  AZURE_CLIENT_ID=$appId
  AZURE_TENANT_ID=$tenantId
  AZURE_SUBSCRIPTION_ID=$SubscriptionId

Next: complete host-specific steps in references/azure-connections.md (service connection,
GitHub environment secrets, or GitLab CI variables). Never commit client secrets to git.
"@
