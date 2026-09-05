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
    [switch]$SkipUpload
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

# -------------------------------------------------------------------- sql ---
if (-not $SkipSql) {
    Write-Host "`n== Azure SQL: $sqlServer / $sqlDb ==" -ForegroundColor Cyan
    $found = az sql server list -g $rg --query "[?name=='$sqlServer'].name" -o tsv
    if (-not $found) {
        Write-Host "Choose an admin password for the SQL server."
        Write-Host "It is read straight into the az command and never written to disk." -ForegroundColor DarkGray
        $sec = Read-Host "SQL admin password for '$sqlUser'" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

        az sql server create --name $sqlServer --resource-group $rg --location $loc `
            --admin-user $sqlUser --admin-password $plain --output none
        Remove-Variable plain
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

Write-Host "`nDone. Next:" -ForegroundColor Green
Write-Host "  1. Run sql/01_sqldb_create_tables.sql in the portal Query editor."
Write-Host "  2. python scripts/build_adf.py   (after filling config/project.json)"
Write-Host "  3. Connect the factory to GitHub, root folder /adf, BEFORE building anything by hand."
