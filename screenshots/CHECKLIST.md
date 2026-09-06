# Proof-of-work screenshots

All captured. `scripts/capture_checklist.ps1` walks this list and saves each
shot under the right filename; `scripts/capture_screen.ps1` grabs a single one.

## Step 1 — infrastructure

- [x] `01-adls-dirpayrollfiles.png` — Storage browser showing `dirpayrollfiles`
      with AgencyMaster.csv, EmpMaster.csv, TitleMaster.csv, nycpayroll_2021.csv
- [x] `02-adls-dirhistoryfiles.png` — `dirhistoryfiles` with nycpayroll_2020.csv
- [x] `03-sqldb-tables.png` — Query editor result of the
      `INFORMATION_SCHEMA.TABLES` select at the end of
      `sql/01_sqldb_create_tables.sql` (six `NYC_Payroll*` tables)
- [x] `04-synapse-external-table.png` — Synapse `udacity` database, object
      explorer showing `dbo.NYC_Payroll_Summary` under External Tables

## Step 2 — linked services

- [x] `05-linkedservices-list.png` — Manage → Linked services, both entries
      listed after successful creation (this is the capture the step asks for)
- [x] `06-linkedservice-sql-legacy.png` — `ls_sqldb_nycpayroll` edit blade.
      The studio labels the versions **1.0** and **2.0 (Recommended)**; 1.0 is
      the "Legacy" the project instructions mean, and it is the one selected.
      Authentication is System-assigned managed identity, so there is no
      password field -- see docs/SUBMISSION.md for why.
- [x] `07-linkedservice-adls.png` — `ls_adls_nycpayroll`, account-key auth

"Save configs of Linked Services" is already satisfied by
`adf/linkedService/*.json` in this repo.

## Step 3 — datasets

- [x] `08-datasets-list.png` — Author pane with all 12 datasets expanded
- [x] `09-dataset-preview.png` — Preview data on `ds_adls_payroll2021` showing
      parsed rows

## Step 4 — load data flows

- [x] `10-dataflows-list.png` — Author pane with all 6 data flows
- [x] `11-dataflow-payroll2020.png` — canvas: source → cast → sink

## Step 5 — aggregate data flow

- [x] `12-dataflow-summary-canvas.png` — full canvas: two sources, two selects,
      union, filter, derived column, aggregate, select, two sinks
- [x] `13-dataflow-summary-filter.png` — the Filter expression
      `toInteger(FiscalYear) >= $dataflow_param_fiscalyear`
- [x] `14-dataflow-summary-aggregate.png` — Aggregate settings, group by
      `FiscalYear`, `AgencyName`
- [x] `14b-dataflow-summary-aggregates-expression.png` — the Aggregates tab of
      the same step, showing `TotalPaid = sum(TotalPaid)`

## Steps 6–7 — pipeline and run

- [x] `15-pipeline-canvas.png` — `pl_nyc_payroll` showing the 3 → 2 → 1
      dependency fan
- [x] `16-global-parameter.png` — Manage → Global parameters →
      `dataflow_param_fiscalyear`, and the Execute Data Flow activity binding
      `@pipeline().globalParameters.dataflow_param_fiscalyear`
- [x] `17-pipeline-run-success.png` — **Monitor → Pipeline runs**, status
      Succeeded
- [x] `18-activity-runs-success.png` — the run's activity list, all six data
      flow activities green

## Step 8 — data verification

- [x] `19-sqldb-summary-query.png` — `SELECT * FROM dbo.NYC_Payroll_Summary`
- [x] `20-adls-dirstaging.png` — Storage browser showing the files the pipeline
      wrote into `dirstaging`
- [x] `21-synapse-summary-query.png` — the same select against the Synapse
      external table
- [x] `22-fiscalyear-filter-proof.png` *(optional, strong)* — the query showing
      the source data's own `FiscalYear` 1998 and 1999 rows present in the raw
      payroll tables and absent from the summary

## Step 9 — GitHub

- [x] `23-git-configuration.png` — Manage → Git configuration, repo and
      root folder `/adf`
- [x] `24-github-repo.png` — the repo showing the published `adf/` tree
