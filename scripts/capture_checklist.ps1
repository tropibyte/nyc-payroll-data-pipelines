<#
.SYNOPSIS
    Walk the submission screenshot checklist, capturing each screen to
    screenshots/ with the right filename.

.DESCRIPTION
    Prints one instruction at a time. You navigate the browser to that screen,
    come back, press Enter, and the window is captured under the filename the
    checklist expects. Press S to skip one, Q to stop.

    Beats capturing by hand: no save dialogs, no renaming, no wondering which
    of twenty PNGs was the aggregate data flow.

    The capture targets the browser window's rectangle, so whatever tab is
    visible in that window is what gets saved -- keep the screen you want in
    front before pressing Enter.

.PARAMETER Only
    Capture just the entries whose filename matches this wildcard, e.g. -Only '1*'

.EXAMPLE
    ./scripts/capture_checklist.ps1
    ./scripts/capture_checklist.ps1 -Only '2*'
#>
[CmdletBinding()]
param(
    [string]$Only = '*',
    [string]$ProcessName = 'chrome',
    [string]$TitleMatch = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$capture = Join-Path $PSScriptRoot 'capture_screen.ps1'

# filename, where to go, what the reviewer should be able to see in the shot
$shots = @(
    @{ n = '01-adls-dirpayrollfiles'; where = 'Portal > Storage account adlsnycpayrolltarien > Containers > adlsnycpayroll-tarie-n > dirpayrollfiles';
       see = 'AgencyMaster.csv, EmpMaster.csv, TitleMaster.csv, nycpayroll_2021.csv' }
    @{ n = '02-adls-dirhistoryfiles'; where = 'same container > dirhistoryfiles';
       see = 'nycpayroll_2020.csv' }
    @{ n = '03-sqldb-tables'; where = 'Portal > SQL databases > db_nycpayroll > Query editor, run the SELECT at the end of sql/01_sqldb_create_tables.sql';
       see = 'six NYC_Payroll* tables' }
    @{ n = '04-synapse-external-table'; where = 'Synapse Studio > Data > Workspace > udacity > External tables';
       see = 'dbo.NYC_Payroll_Summary' }
    @{ n = '05-linkedservices-list'; where = 'ADF Studio > Manage > Linked services';
       see = 'ls_adls_nycpayroll and ls_sqldb_nycpayroll' }
    @{ n = '06-linkedservice-sql-legacy'; where = 'ADF Studio > Manage > Linked services > ls_sqldb_nycpayroll (open it)';
       see = 'Version = Legacy' }
    @{ n = '07-linkedservice-adls'; where = 'ADF Studio > Manage > Linked services > ls_adls_nycpayroll (open it)';
       see = 'the ADLS Gen2 connection' }
    @{ n = '08-datasets-list'; where = 'ADF Studio > Author > Datasets (expand)';
       see = 'all 12 datasets' }
    @{ n = '09-dataset-preview'; where = 'ADF Studio > Author > ds_adls_payroll2021 > Preview data';
       see = 'parsed rows of payroll data' }
    @{ n = '10-dataflows-list'; where = 'ADF Studio > Author > Data flows (expand)';
       see = 'all 6 data flows' }
    @{ n = '11-dataflow-payroll2020'; where = 'ADF Studio > Author > dataflow_payroll2020';
       see = 'source -> cast -> sink' }
    @{ n = '12-dataflow-summary-canvas'; where = 'ADF Studio > Author > dataflow_summary';
       see = 'two sources, two selects, union, filter, derived column, aggregate, select, two sinks' }
    @{ n = '13-dataflow-summary-filter'; where = 'same flow, click the filterFiscalYear step';
       see = 'toInteger(FiscalYear) >= $dataflow_param_fiscalyear' }
    @{ n = '14-dataflow-summary-aggregate'; where = 'same flow, click the aggTotalPaid step';
       see = 'group by FiscalYear, AgencyName and sum(TotalPaid)' }
    @{ n = '15-pipeline-canvas'; where = 'ADF Studio > Author > pl_nyc_payroll';
       see = 'the 3 -> 2 -> 1 dependency fan' }
    @{ n = '16-global-parameter'; where = 'ADF Studio > Manage > Global parameters';
       see = 'dataflow_param_fiscalyear = 2020' }
    @{ n = '17-pipeline-run-success'; where = 'ADF Studio > Monitor > Pipeline runs';
       see = 'pl_nyc_payroll, status Succeeded' }
    @{ n = '18-activity-runs-success'; where = 'click into that run';
       see = 'all six activities Succeeded' }
    @{ n = '19-sqldb-summary-query'; where = 'Portal > db_nycpayroll > Query editor: SELECT * FROM dbo.NYC_Payroll_Summary ORDER BY FiscalYear, TotalPaid DESC';
       see = '25 rows' }
    @{ n = '20-adls-dirstaging'; where = 'Portal > container > dirstaging';
       see = 'the part-*.csv files the pipeline wrote' }
    @{ n = '21-synapse-summary-query'; where = 'Synapse Studio > new SQL script on udacity: SELECT * FROM dbo.NYC_Payroll_Summary ORDER BY FiscalYear, TotalPaid DESC';
       see = 'the same 25 rows' }
    @{ n = '22-fiscalyear-filter-proof'; where = 'Query editor: the FY 1998 / 1999 check from sql/04_verification_queries.sql';
       see = '1, 1, 0' }
    @{ n = '23-git-configuration'; where = 'ADF Studio > Manage > Git configuration';
       see = 'repo nyc-payroll-data-pipelines, branch main, root folder /adf' }
    @{ n = '24-github-repo'; where = 'github.com/tropibyte/nyc-payroll-data-pipelines/tree/main/adf';
       see = 'the published artifact folders' }
)

$todo = $shots | Where-Object { $_.n -like $Only }
Write-Host "$($todo.Count) screenshot(s) to capture. Enter = capture, S = skip, Q = quit.`n" -ForegroundColor Cyan

$done = 0; $skipped = 0
foreach ($s in $todo) {
    $existing = Test-Path (Join-Path $root "screenshots/$($s.n).png")
    $mark = if ($existing) { ' [already captured]' } else { '' }
    Write-Host "`n--- $($s.n)$mark" -ForegroundColor Yellow
    Write-Host "    go to : $($s.where)"
    Write-Host "    show  : $($s.see)" -ForegroundColor DarkGray
    $k = Read-Host "    Enter to capture, S to skip, Q to quit"
    if ($k -match '^[Qq]') { break }
    if ($k -match '^[Ss]') { $skipped++; continue }
    try {
        # TitleMatch defaults to '' so any window of $ProcessName matches --
        # shot 24 is on github.com, whose title has no "Azure" in it.
        $splat = @{ Name = $s.n; ProcessName = $ProcessName; TitleMatch = $TitleMatch }
        & $capture @splat
        $done++
    } catch {
        Write-Host "    capture failed: $_" -ForegroundColor Red
    }
}

Write-Host "`n$done captured, $skipped skipped." -ForegroundColor Green
$have = (Get-ChildItem (Join-Path $root 'screenshots') -Filter *.png -ErrorAction SilentlyContinue).Count
Write-Host "screenshots/ now holds $have PNG(s) of $($shots.Count)."
