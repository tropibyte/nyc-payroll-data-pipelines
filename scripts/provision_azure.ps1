<#
.SYNOPSIS
    Creates the ADLS Gen2 account + folders, uploads the five CSVs, and
    (optionally) creates the Azure SQL server and db_nycpayroll database.

.DESCRIPTION
    Everything here mirrors the portal clicks in project Step 1, but from the
    CLI it takes about two minutes instead of twenty -- which matters because
    the Udacity lab session is time-boxed and its resources are deleted when
    the session expires.

    One real advantage of the CLI path: `az storage account create` does NOT
    turn on blob soft delete or change feed, whereas the portal wizard does.
    Those two features are what produce the notorious linked-service error
    "EndpointUnsupportedAccountFeatures: This endpoint does not support
    BlobStorageEvents or SoftDelete".

.PARAMETER SkipSql
    Only do storage + upload.

.EXAMPLE
    az login                      # you type the lab credentials, not a script
    az account show
    ./scripts/provision_azure.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipSql,
    [switch]$SkipUpload,
    [switch]$SkipSynapse
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cfg = Get-Content (Join-Path $root 'config/project.json') -Raw | ConvertFrom-Json

$rg        = $cfg.resourceGroup
$loc       = $cfg.location
$account   = $cfg.storageAccount
$container = $cfg.storageContainer
$sqlServer = $cfg.sqlServer
$sqlDb     = $cfg.sqlDatabase
$sqlUser   = $cfg.sqlUser

if ($rg -like '*CHANGE-ME*') {
    throw "Set resourceGroup in config/project.json to the lab-provided resource group first. List them with: az group list -o table"
}

Write-Host "== signed-in account ==" -ForegroundColor Cyan
az account show --query "{user:user.name, subscription:name}" -o table
if ($LASTEXITCODE -ne 0) { throw "Not logged in. Run 'az login' first." }

# ---------------------------------------------------------------- storage ---
Write-Host "`n== storage account $account ==" -ForegroundColor Cyan
$exists = az storage account check-name --name $account --query nameAvailable -o tsv
if ($exists -eq 'true') {
    az storage account create `
        --name $account --resource-group $rg --location $loc `
        --sku Standard_LRS --kind StorageV2 `
        --enable-hierarchical-namespace true `
        --https-only true `
        --allow-blob-public-access true `
        --allow-shared-key-access true `
        --default-action Allow `
        --min-tls-version TLS1_2 `
        --output none
    Write-Host "created." -ForegroundColor Green
} else {
    Write-Host "already exists, reusing." -ForegroundColor Yellow
}

# "Default to Microsoft Entra authorization in the Azure portal" has no
# parameter on `az storage account create/update` in CLI 2.82.  It only changes
# which auth the portal's Storage browser defaults to -- nothing in this
# pipeline depends on it -- so set it by hand if you want the checkbox ticked:
#   Storage account > Settings > Configuration > Default to Microsoft Entra
#   authorization in the Azure portal > Enabled
Write-Host "note: set 'Default to Microsoft Entra authorization' in the portal (no CLI flag)." -ForegroundColor DarkGray

# Data-plane access.  The Udacity lab pre-grants the odl_user account
# "Storage Blob Data Owner" at the resource group scope, which is what makes
# --auth-mode login work below.  It also DENIES
# Microsoft.Authorization/roleAssignments/write, so do not try to grant roles
# here -- that is why config/project.json uses adlsAuth = accountKey.
$myRoles = az role assignment list --all `
    --assignee (az ad signed-in-user show --query id -o tsv 2>$null) `
    --query "[?contains(roleDefinitionName,'Storage Blob Data')].roleDefinitionName" -o tsv 2>$null
if ($myRoles) {
    Write-Host "data-plane access via: $($myRoles -join ', ')"
} else {
    Write-Host "WARNING: no Storage Blob Data role found; uploads may fall back to key auth." -ForegroundColor Yellow
}

Write-Host "`n== container $container + directories ==" -ForegroundColor Cyan
az storage fs create --name $container --account-name $account --auth-mode login --output none 2>$null
foreach ($d in 'dirpayrollfiles', 'dirhistoryfiles', 'dirstaging') {
    az storage fs directory create --name $d --file-system $container `
        --account-name $account --auth-mode login --output none 2>$null
    Write-Host "  $d"
}

# ----------------------------------------------------------------- upload ---
if (-not $SkipUpload) {
    Write-Host "`n== uploading CSVs ==" -ForegroundColor Cyan
    $map = @{
        'dirpayrollfiles' = 'data/dirpayrollfiles'
        'dirhistoryfiles' = 'data/dirhistoryfiles'
    }
    foreach ($dest in $map.Keys) {
        Get-ChildItem (Join-Path $root $map[$dest]) -Filter *.csv | ForEach-Object {
            az storage fs file upload `
                --source $_.FullName `
                --path "$dest/$($_.Name)" `
                --file-system $container --account-name $account `
                --auth-mode login --overwrite true --output none
            Write-Host "  $dest/$($_.Name)"
        }
    }
    Write-Host "`n== listing ==" -ForegroundColor Cyan
    az storage fs file list --file-system $container --account-name $account `
        --auth-mode login --query "[].{path:name, bytes:contentLength}" -o table
}

# One password serves both the SQL server and the Synapse workspace admin.
# Read once, held only in this process, never written to disk or the repo.
$adminPassword = $null
function Get-AdminPassword {
    if ($script:adminPassword) { return $script:adminPassword }
    Write-Host "`nChoose an admin password (used for both the SQL server and the"
    Write-Host "Synapse workspace). You will retype it into the Data Factory linked"
    Write-Host "service later, so pick something you will remember." -ForegroundColor DarkGray
    Write-Host "Azure requires 8+ chars with three of: upper, lower, digit, symbol." -ForegroundColor DarkGray
    $sec = Read-Host "admin password for '$sqlUser'" -AsSecureString
    $script:adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    return $script:adminPassword
}

# -------------------------------------------------------------------- sql ---
if (-not $SkipSql) {
    Write-Host "`n== Azure SQL: $sqlServer / $sqlDb ==" -ForegroundColor Cyan
    $found = az sql server list -g $rg --query "[?name=='$sqlServer'].name" -o tsv
    if (-not $found) {
        az sql server create --name $sqlServer --resource-group $rg --location $loc `
            --admin-user $sqlUser --admin-password (Get-AdminPassword) --output none
        Write-Host "created." -ForegroundColor Green
    } else {
        Write-Host "server already exists, reusing." -ForegroundColor Yellow
    }

    # "Allow Azure services and resources to access this server"
    az sql server firewall-rule create -g $rg -s $sqlServer -n AllowAllAzureIPs `
        --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 --output none 2>$null
    # "Add current client IP address"
    $myIp = (Invoke-RestMethod 'https://api.ipify.org?format=json').ip
    az sql server firewall-rule create -g $rg -s $sqlServer -n ClientIp `
        --start-ip-address $myIp --end-ip-address $myIp --output none 2>$null
    Write-Host "firewall: Azure services + $myIp"

    $dbFound = az sql db list -g $rg -s $sqlServer --query "[?name=='$sqlDb'].name" -o tsv
    if (-not $dbFound) {
        # Basic / 5 DTU / 2 GB -- the tier the project asks for, ~$5/month
        az sql db create -g $rg -s $sqlServer -n $sqlDb `
            --edition Basic --capacity 5 --max-size 2GB --output none
        Write-Host "database created." -ForegroundColor Green
    } else {
        Write-Host "database already exists, reusing." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------- synapse ---
if (-not $SkipSynapse) {
    $synWs = $cfg.synapseWorkspace
    # The project asks for a NEW Data Lake Gen2 + file system dedicated to the
    # Synapse workspace, separate from the payroll data lake.
    $synAcct = ($synWs -replace '[^a-z0-9]', '')
    if ($synAcct.Length -gt 24) { $synAcct = $synAcct.Substring(0, 24) }
    $synFs = 'synfs'

    Write-Host "`n== Synapse workspace: $synWs ==" -ForegroundColor Cyan
    $wsFound = az synapse workspace list -g $rg --query "[?name=='$synWs'].name" -o tsv 2>$null
    if (-not $wsFound) {
        $acctFree = az storage account check-name --name $synAcct --query nameAvailable -o tsv
        if ($acctFree -eq 'true') {
            az storage account create --name $synAcct --resource-group $rg --location $loc `
                --sku Standard_LRS --kind StorageV2 --enable-hierarchical-namespace true `
                --https-only true --min-tls-version TLS1_2 --output none
            Write-Host "  storage $synAcct created."
        }
        az storage fs create --name $synFs --account-name $synAcct --auth-mode login --output none 2>$null
        Write-Host "  file system $synFs ready."

        Write-Host "  creating workspace (this takes several minutes)..." -ForegroundColor DarkGray
        az synapse workspace create --name $synWs --resource-group $rg --location $loc `
            --storage-account $synAcct --file-system $synFs `
            --sql-admin-login-user $sqlUser --sql-admin-login-password (Get-AdminPassword) `
            --output none
        Write-Host "  created." -ForegroundColor Green
    } else {
        Write-Host "workspace already exists, reusing." -ForegroundColor Yellow
    }

    # Synapse Studio needs your IP allowed before it will run SQL scripts.
    if (-not $myIp) { $myIp = (Invoke-RestMethod 'https://api.ipify.org?format=json').ip }
    az synapse workspace firewall-rule create --name AllowAll --workspace-name $synWs `
        --resource-group $rg --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255 `
        --output none 2>$null
    az synapse workspace firewall-rule create --name ClientIp --workspace-name $synWs `
        --resource-group $rg --start-ip-address $myIp --end-ip-address $myIp `
        --output none 2>$null
    Write-Host "firewall: client IP $myIp allowed"
}

if ($adminPassword) { Remove-Variable adminPassword -Scope Script }

Write-Host "`nDone. Next:" -ForegroundColor Green
Write-Host "  1. Run sql/01_sqldb_create_tables.sql in the portal Query editor."
Write-Host "  2. pwsh ./scripts/deploy_adf.ps1   (pushes all 22 artifacts into the factory)"
Write-Host "  3. Connect the factory to GitHub, root folder /adf."
