# Submission map — rubric criterion → artifact

| Rubric criterion | Where it is satisfied |
|---|---|
| Linked Service of type `AzureBlobFS` | [`adf/linkedService/ls_adls_nycpayroll.json`](../adf/linkedService/ls_adls_nycpayroll.json) |
| Linked Service of type `AzureSqlDatabase` | [`adf/linkedService/ls_sqldb_nycpayroll.json`](../adf/linkedService/ls_sqldb_nycpayroll.json) |
| Datasets of type `AzureBlobFSLocation` for AgencyMaster, TitleMaster, EmpMaster, nycpayroll_2020, nycpayroll_2021 | `adf/dataset/ds_adls_*.json` (6 files, including the `dirstaging` sink) |
| Datasets of type `AzureSqlTable` for payroll, agency, employee, title tables | `adf/dataset/ds_sql_*.json` (6 files) |
| `MappingDataFlow` with a union producing `TotalPaid = RegularGrossPaid + TotalOTPaid + TotalOtherPay`, sourced from Azure SQL DB tables | [`adf/dataflow/dataflow_summary.json`](../adf/dataflow/dataflow_summary.json) |
| `MappingDataFlow` objects moving data Data Lake → Azure SQL DB, and SQL DB → staging directory + summary table | `dataflow_agency`, `dataflow_emp`, `dataflow_title`, `dataflow_payroll2020`, `dataflow_payroll2021`, `dataflow_summary` |
| Pipeline with `ExecuteDataFlow` activities | [`adf/pipeline/pl_nyc_payroll.json`](../adf/pipeline/pl_nyc_payroll.json) — 6 activities |
| Screenshot of a successful pipeline execution | `screenshots/17-pipeline-run-success.png`, `screenshots/18-activity-runs-success.png` |
| Data verified in Gen2 storage, SQL DB table, Synapse external table | `screenshots/20-adls-dirstaging.png`, `screenshots/19-sqldb-summary-query.png`, `screenshots/21-synapse-summary-query.png`; queries in [`sql/04_verification_queries.sql`](../sql/04_verification_queries.sql) |

## Notes for the reviewer

**Global parameter.** `dataflow_param_fiscalyear` is declared in
`adf/factory/<factory>.json` and bound in the pipeline's Execute Data Flow
activity as `@pipeline().globalParameters.dataflow_param_fiscalyear`, which the
`dataflow_summary` Filter consumes as
`toInteger(FiscalYear) >= $dataflow_param_fiscalyear`.

**Synapse sink.** Dedicated SQL pools are disabled in the current lab, so the
pipeline's second aggregate sink writes to `dirstaging` in ADLS Gen2 and Synapse
reads it through a serverless external table
(`sql/03_synapse_external_table.sql`) rather than an ADF Synapse sink. This is
the CETAS-era approach the updated project instructions call for.

**Authentication, and why it does not match the course screenshots.** The lab
subscription denies `Microsoft.Authorization/roleAssignments/write`, which rules
out granting any managed identity an Azure RBAC role. That forced two choices:

* `ls_adls_nycpayroll` uses an **account key** rather than managed identity.
* `ls_sqldb_nycpayroll` uses the factory's **system-assigned managed identity**
  with no username or password at all. A contained database user
  (`sql/05_grant_adf_managed_identity.sql`) is a *database*-level grant, not an
  Azure role assignment, so it works despite that restriction. The linked
  service is still Version 1.0 — the "Legacy" the instructions call for, which
  the current studio labels 1.0 against 2.0 (Recommended).
* The Synapse external data source carries **no credential**, falling back to
  Entra pass-through as the querying user, who holds `Storage Blob Data Owner`
  on the resource group.

Nothing secret is stored in this repository.

**Two runs appear in Monitor.** The first (`6b08e4b7…`, Failed) died in all
three master-load activities with *"Only one valid authentication should be used
for ls_sqldb_nycpayroll. SQLAuthentication is invalid. One of user/password is
missing."* The cause was not the pipeline: `az datafactory linked-service
create` rewrites a `SecureString` password into an empty `AzureKeyVaultSecret`,
so the service stored a username with no password. Switching that linked service
to managed identity removed the credential from the equation entirely. The
second run (`606b0f20…`, Succeeded, 7m 24s) is the one the screenshots document.

**Verification.** The expected results were computed directly from the source
CSVs before the pipeline existed: **25 summary rows totalling 35,709,510.43**.
The pipeline produced 25 rows totalling 35,709,510.5 (float rounding), matching
in both Azure SQL DB and the Synapse external table. The course-distributed CSVs each contain one
out-of-range row as shipped — `FiscalYear` 1998 in `nycpayroll_2020.csv`, 1999 in
`nycpayroll_2021.csv`. These are in the original data, not added here; the files
under `data/` are byte-identical to the ones in the course download.
`22-fiscalyear-filter-proof.png` shows both rows present in the raw tables and
neither in the summary, which is what proves `dataflow_param_fiscalyear`
actually fired.
