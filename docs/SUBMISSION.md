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
| Screenshot of a successful pipeline execution | `screenshots/16-pipeline-run-success.png`, `screenshots/17-activity-runs-success.png` |
| Data verified in Gen2 storage, SQL DB table, Synapse external table | `screenshots/18-…`, `19-…`, `20-…`; queries in [`sql/04_verification_queries.sql`](../sql/04_verification_queries.sql) |

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

**Secrets.** The SQL linked service ships with a placeholder SecureString; the
password is entered in the Data Factory portal and stored by the service, never
in this repository.
