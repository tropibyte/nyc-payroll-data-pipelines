# Proof-of-work screenshots

Save each capture in this folder using the filename given. Take them **as you
go** — the lab session expires and the resources disappear with it.

## Step 1 — infrastructure

- [ ] `01-adls-dirpayrollfiles.png` — Storage browser showing `dirpayrollfiles`
      with AgencyMaster.csv, EmpMaster.csv, TitleMaster.csv, nycpayroll_2021.csv
- [ ] `02-adls-dirhistoryfiles.png` — `dirhistoryfiles` with nycpayroll_2020.csv
- [ ] `03-sqldb-tables.png` — Query editor result of the
      `INFORMATION_SCHEMA.TABLES` select at the end of
      `sql/01_sqldb_create_tables.sql` (six `NYC_Payroll*` tables)
- [ ] `04-synapse-external-table.png` — Synapse `udacity` database, object
      explorer showing `dbo.NYC_Payroll_Summary` under External Tables

## Step 2 — linked services  *(not in the numbered instructions, but the rubric grades it)*

- [ ] `05-linkedservice-adls.png` — `ls_adls_nycpayroll`, connection successful
- [ ] `06-linkedservice-sql.png` — `ls_sqldb_nycpayroll`, connection successful,
      Version = **Legacy**

## Step 3 — datasets

- [ ] `07-datasets-list.png` — Author pane with all 12 datasets expanded
- [ ] `08-dataset-preview.png` — Preview data on `ds_adls_payroll2021` showing
      parsed rows

## Step 4 — load data flows

- [ ] `09-dataflows-list.png` — Author pane with all 6 data flows
- [ ] `10-dataflow-payroll2020.png` — canvas: source → cast → sink

## Step 5 — aggregate data flow

- [ ] `11-dataflow-summary-canvas.png` — full canvas: two sources, two selects,
      union, filter, derived column, aggregate, select, two sinks
- [ ] `12-dataflow-summary-filter.png` — the Filter expression
      `toInteger(FiscalYear) >= $dataflow_param_fiscalyear`
- [ ] `13-dataflow-summary-aggregate.png` — group by + `sum(TotalPaid)`

## Steps 6–7 — pipeline and run

- [ ] `14-pipeline-canvas.png` — `pl_nyc_payroll` showing the 3 → 2 → 1
      dependency fan
- [ ] `15-global-parameter.png` — Manage → Global parameters →
      `dataflow_param_fiscalyear`, and the Execute Data Flow activity binding
      `@pipeline().globalParameters.dataflow_param_fiscalyear`
- [ ] `16-pipeline-run-success.png` — **Monitor → Pipeline runs**, status
      Succeeded
- [ ] `17-activity-runs-success.png` — the run's activity list, all six data
      flow activities green

## Step 8 — data verification

- [ ] `18-sqldb-summary-query.png` — `SELECT * FROM dbo.NYC_Payroll_Summary`
- [ ] `19-adls-dirstaging.png` — Storage browser showing the files the pipeline
      wrote into `dirstaging`
- [ ] `20-synapse-summary-query.png` — the same select against the Synapse
      external table
- [ ] `21-fiscalyear-filter-proof.png` *(optional, strong)* — the query showing
      the planted `FiscalYear = 1999` row present in `NYC_Payroll_Data_2021`
      and absent from the summary

## Step 9 — GitHub

- [ ] `22-git-configuration.png` — Manage → Git configuration, repo and
      root folder `/adf`
- [ ] `23-github-repo.png` — the repo showing the published `adf/` tree
