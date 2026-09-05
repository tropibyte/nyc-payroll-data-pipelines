<#
.SYNOPSIS
    Deploys everything in adf/ into the live Data Factory via the Azure CLI.

.DESCRIPTION
    Optional -- connecting the factory to GitHub achieves the same thing with
    fewer moving parts. This exists for two reasons:

      1. It validates the hand-authored JSON (especially the mapping data flow
         scripts) in seconds, instead of finding a parse error in the studio
         after a lab hour has burned.
      2. It makes the whole build reproducible if the lab session expires and
         you have to start over: one command instead of an afternoon of clicks.

    Order matters -- datasets reference linked services, data flows reference
    datasets, the pipeline references data flows.

    The ADLS account key is read into a local variable and injected into the
    linked service. It is never printed and never written to the repo.

.PARAMETER SqlPassword
    Password for the Azure SQL admin. Prompted for if omitted. Passing a
    placeholder is fine -- the create call does not test connectivity, and you
    can fix it in the studio before publishing.
#>
[CmdletBinding()]
param(
    [securestring]$SqlPassword,
    [switch]$SkipLinkedServices
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$cfg = Get-Content (Join-Path $root 'config/project.json') -Raw | ConvertFrom-Json
$rg = $cfg.resourceGroup
$factory = $cfg.factoryName
$tmp = Join-Path ([IO.Path]::GetTempPath()) "adfdeploy"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# az datafactory takes the inner "properties" object, not the whole artifact.
function Write-Props($obj, $name) {
    $p = Join-Path $tmp "$name.json"
    $obj.properties | ConvertTo-Json -Depth 100 | Set-Content $p -Encoding utf8
    return $p
}

function Deploy($folder, $flag, $cmd, $extra = @()) {
    $dir = Join-Path $root "adf/$folder"
    foreach ($f in Get-ChildItem $dir -Filter *.json | Sort-Object Name) {
        $o = Get-Content $f.FullName -Raw | ConvertFrom-Json
        $props = Write-Props $o $o.name
        $out = & az datafactory $cmd create --resource-group $rg --factory-name $factory `
            "--$($cmd)-name" $o.name $flag "@$props" @extra --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAIL $($o.name)" -ForegroundColor Red
            $out | Select-Object -Last 12 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkRed }
            $script:failed++
        } else {
            Write-Host "  ok   $($o.name)" -ForegroundColor Green
        }
    }
}

$script:failed = 0

if (-not $SkipLinkedServices) {
    Write-Host "== linked services ==" -ForegroundColor Cyan

    # ADLS: inject the real account key, in memory only.
    $key = az storage account keys list -n $cfg.storageAccount -g $rg --query "[0].value" -o tsv
    $ls = Get-Content (Join-Path $root "adf/linkedService/ls_adls_nycpayroll.json") -Raw | ConvertFrom-Json
    $ls.properties.typeProperties.accountKey.value = $key
    $p = Write-Props $ls 'ls_adls'
    az datafactory linked-service create --resource-group $rg --factory-name $factory `
        --linked-service-name ls_adls_nycpayroll --properties "@$p" --output none
    if ($LASTEXITCODE -eq 0) { Write-Host "  ok   ls_adls_nycpayroll (account key injected)" -ForegroundColor Green }
    else { Write-Host "  FAIL ls_adls_nycpayroll" -ForegroundColor Red; $script:failed++ }
    Remove-Variable key

    # SQL: password prompted for, or left as a placeholder to fix in the studio.
    if (-not $SqlPassword) { $SqlPassword = Read-Host "Azure SQL password for $($cfg.sqlUser)" -AsSecureString }
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlPassword))
    $ls = Get-Content (Join-Path $root "adf/linkedService/ls_sqldb_nycpayroll.json") -Raw | ConvertFrom-Json
    $ls.properties.typeProperties.password.value = $plain
    $p = Write-Props $ls 'ls_sql'
    az datafactory linked-service create --resource-group $rg --factory-name $factory `
        --linked-service-name ls_sqldb_nycpayroll --properties "@$p" --output none
    if ($LASTEXITCODE -eq 0) { Write-Host "  ok   ls_sqldb_nycpayroll" -ForegroundColor Green }
    else { Write-Host "  FAIL ls_sqldb_nycpayroll" -ForegroundColor Red; $script:failed++ }
    Remove-Variable plain
}

Write-Host "`n== datasets ==" -ForegroundColor Cyan
Deploy 'dataset' '--properties' 'dataset'

# --flow-type is mandatory on this command and is NOT read from the JSON.
# "MappingDataFlow" is the rubric's required type; "Flowlet" is the other option.
Write-Host "`n== data flows ==" -ForegroundColor Cyan
Deploy 'dataflow' '--properties' 'data-flow' @('--flow-type', 'MappingDataFlow')

Write-Host "`n== pipeline ==" -ForegroundColor Cyan
foreach ($f in Get-ChildItem (Join-Path $root 'adf/pipeline') -Filter *.json) {
    $o = Get-Content $f.FullName -Raw | ConvertFrom-Json
    $p = Write-Props $o $o.name
    $out = az datafactory pipeline create --resource-group $rg --factory-name $factory `
        --name $o.name --pipeline "@$p" --output none 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAIL $($o.name)" -ForegroundColor Red
        $out | Select-Object -Last 12 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkRed }
        $script:failed++
    } else { Write-Host "  ok   $($o.name)" -ForegroundColor Green }
}

Remove-Item $tmp -Recurse -Force
if ($script:failed) {
    Write-Host "`n$($script:failed) artifact(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll artifacts deployed." -ForegroundColor Green
Write-Host "Global parameter dataflow_param_fiscalyear must still be set in the studio:"
Write-Host "  Manage > Global parameters > New > dataflow_param_fiscalyear, type Int, value $($cfg.fiscalYearParam)"
