# NYC Payroll Data Integration — Azure Data Factory

Udacity *Data Engineering with Azure* — Data Pipelines project.

Loads NYC payroll master and transaction files from **Azure Data Lake Storage
Gen2** into **Azure SQL Database**, aggregates total pay by agency and fiscal
year, and lands the result in both a SQL summary table and a Data Lake staging
directory that a **Synapse Analytics** serverless external table reads in place.

```
ADLS Gen2                      Azure SQL DB                 ADLS Gen2
dirpayrollfiles/  ──dataflow──▶ NYC_Payroll_AGENCY_MD
  AgencyMaster.csv              NYC_Payroll_EMP_MD
  EmpMaster.csv                 NYC_Payroll_TITLE_MD
  TitleMaster.csv               NYC_Payroll_Data_2021 ─┐
  nycpayroll_2021.csv                                  ├─▶ union ─▶ filter
dirhistoryfiles/                NYC_Payroll_Data_2020 ─┘    (fiscal year)
  nycpayroll_2020.csv                                            │
                                                                 ▼
                                NYC_Payroll_Summary  ◀── aggregate ──▶ dirstaging/
                                                                          │
                                                       Synapse serverless │
                                                       external table ────┘
```

## Layout

| Path | What |
|---|---|
| `config/project.json` | Your Azure resource names. Everything else is generated from this. |
| `data/` | The five project CSVs, already split into the two upload folders. |
| `sql/` | DDL for Azure SQL DB, DDL for the Synapse external table, verification queries. |
| `scripts/provision_azure.ps1` | Creates the storage account + folders, uploads the CSVs, creates the SQL server and database. |
| `scripts/build_adf.py` | Generates `adf/` — 22 Data Factory artifacts — from `config/project.json`. |
| `adf/` | The Data Factory Git tree. Point ADF's repo root folder here. |
| `screenshots/` | Drop your proof-of-work captures here; `CHECKLIST.md` names each one. |

## Runbook

The lab session is time-boxed and **everything you create is deleted when it
expires**, so work through this in one sitting. Budget 3–4 hours.

### 0. Names

Edit `config/project.json`. One Azure rule the project instructions gloss over:
a **storage account name allows only lowercase letters and digits, 3–24
characters** — `adlsnycpayroll-tarie-n` is not a legal account name. Use the
squashed form for the account and the hyphenated form for the container, which
does allow hyphens:

```json
"storageAccount":   "adlsnycpayrolltarien",
"storageContainer": "adlsnycpayroll-tarie-n"
```

Find the lab's resource group first:

```bash
az login
az group list -o table
```

### 1. Storage, data, SQL database

```bash
pwsh ./scripts/provision_azure.ps1
```

This creates the ADLS Gen2 account with hierarchical namespace on, secure
transfer required, shared key access on, and Entra-default portal
authorization; creates `dirpayrollfiles`, `dirhistoryfiles`, `dirstaging`;
uploads the five CSVs; then creates the Basic-tier SQL server and
`db_nycpayroll` with both firewall rules. It prompts for the SQL admin
password and never writes it anywhere.

> Doing this from the CLI also sidesteps the most common failure in this
> project. The portal's storage wizard switches on blob **soft delete** and
> **change feed** by default, and an ADLS Gen2 linked service then fails with
> `EndpointUnsupportedAccountFeatures: This endpoint does not support
> BlobStorageEvents or SoftDelete`. `az storage account create` leaves both
> off.

Then run **`sql/01_sqldb_create_tables.sql`** in the portal:
*SQL databases → db_nycpayroll → Query editor (preview)*.

### 2. Generate the Data Factory artifacts

```bash
python scripts/build_adf.py
```

Writes `adf/` (2 linked services, 12 datasets, 6 data flows, 1 pipeline,
1 factory file with the global parameter) and a filled-in copy of the Synapse
DDL to `sql/rendered/`.

### 3. Connect the factory to GitHub — do this *first*, not last

The project instructions put Git integration at Step 9. Do it at **Step 3**
instead. In Git mode every Save writes JSON to the repo, so your work survives
the lab teardown and you never have to rebuild it to satisfy the submission
requirement. Connecting at the end means re-publishing everything against a
clock that may have already run out.

*Data Factory Studio → Manage → Git configuration → Configure*

| Field | Value |
|---|---|
| Repository type | GitHub |
| Repository name | this repo |
| Collaboration branch | `main` |
| **Root folder** | `/adf` |
| Import existing resources | **No** (the artifacts are already in the branch) |

Reload the studio. All 22 objects appear in the Author pane.

### 4. Two things you must finish by hand

**a. The SQL password.** Secrets are deliberately not in the repo.
Open `ls_sqldb_nycpayroll` → type the password → **Test connection** →
confirm **Version** reads `Legacy`. The current (non-legacy) version of the
Azure SQL linked service breaks mapping data flows with
`MissingRequiredPropertyException: server is a required property`.

**b. Storage authentication.** `ls_adls_nycpayroll` ships in account-key form,
with the key itself left as a placeholder. Open it in the studio, set
Authentication type to **Account key**, and pick the storage account **from the
Azure subscription** rather than pasting anything — the studio resolves the key
through ARM, so it never has to be typed or committed.

Managed identity is the nicer design and `build_adf.py` still writes that
variant to `adf-optional/linkedService/ls_adls_nycpayroll.managedIdentity.json`,
but it does not work in this lab — see below.

Then **Test connection** on both, and **Publish**.

### 5. Synapse

Create the workspace (with its own new ADLS Gen2 filesystem — Azure allows one
Synapse workspace per lab account). Dedicated SQL pools are disabled in the
lab, so use the **Built-in** serverless pool:

1. `sql/02_synapse_create_database.sql` against `master` → creates `udacity`.
2. Refresh the database dropdown, select `udacity`.
3. `sql/rendered/03_synapse_external_table.sql` → master key, credential, file
   format, data source, external table.

The Synapse workspace's managed identity also needs **Storage Blob Data
Contributor** on the payroll storage account, or swap the credential for a SAS
token (the alternative is commented into the script).

> **Header trap.** The external file format has no `FIRST_ROW` option, so the
> staging files must have no header row. `ds_adls_staging` sets
> `firstRowAsHeader: false` for exactly this reason. If you rebuild that
> dataset by hand and leave headers on, the external table fails converting
> the literal string `FiscalYear` to `int`.

### 6. Run and verify

*Author → `pl_nyc_payroll` → Add trigger → Trigger now*, then watch
**Monitor → Pipeline runs**. Six activities: three master loads in parallel,
then the two payroll loads, then the aggregate.

Verify with `sql/04_verification_queries.sql`. Expected row counts:

| Table | Rows |
|---|---|
| `NYC_Payroll_AGENCY_MD` | 153 |
| `NYC_Payroll_EMP_MD` | 1000 |
| `NYC_Payroll_TITLE_MD` | 1446 |
| `NYC_Payroll_Data_2020` | 100 |
| `NYC_Payroll_Data_2021` | 101 |
| `NYC_Payroll_Summary` | **25**, summing to **35,709,510.43** |

Those last two numbers were computed directly from the source CSVs, so they are
an exact check on the whole pipeline rather than a smell test.

Each payroll file ships with one planted out-of-range row — `FiscalYear` **1998**
in `nycpayroll_2020.csv`, **1999** in `nycpayroll_2021.csv`. Both must land in
the raw tables and neither may appear in the summary; that is the check that the
`dataflow_param_fiscalyear` filter actually fired. The verification script tests
it explicitly.

## What the Udacity lab actually permits

Measured against the live lab account rather than guessed at. The subscription
grants two Spektra custom roles plus `Storage Blob Data Owner` on the resource
group, which adds up to:

| | |
|---|---|
| Create storage, SQL, Synapse, Data Factory | **yes** — `Microsoft.Storage/*`, `Microsoft.Sql/servers/*`, `Microsoft.Synapse/workspaces/*`, `Microsoft.DataFactory/factories/*` |
| Read/write blobs as yourself | **yes** — `Storage Blob Data Owner` on the resource group |
| Assign RBAC roles | **no** — `Microsoft.Authorization/*/read` only. `roleAssignments/write` returns `AuthorizationFailed`. |
| Synapse dedicated SQL pool | **no** — `workspaces/sqlPools/*` is in `notActions` |
| Synapse Spark pool | **no** — `workspaces/bigDataPools/*` is in `notActions` |
| Custom integration runtimes | **no** — `factories/integrationruntimes/*` is in `notActions`; the built-in AutoResolve IR still runs the data flows |

Two consequences drive real design choices here:

1. **No role assignment means no managed identity anywhere.** Data Factory
   reaches storage by account key, and the Synapse external data source carries
   no credential at all, falling back to Entra pass-through as the querying
   user — who already holds `Storage Blob Data Owner`. Both are the *only*
   working options, not preferences.
2. **No dedicated pool** is why the aggregate lands in `dirstaging` and Synapse
   reads it through an external table rather than an ADF Synapse sink.

## Design notes

**`AgencyID` vs `AgencyCode`.** The 2020 file and table use `AgencyID`; the
2021 file and table use `AgencyCode`. `dataflow_summary` puts a Select on each
source that projects down to the five columns the aggregate needs, which
removes the mismatched column before the union — cleaner than renaming, and it
is why `union(byName: true)` is safe here.

**Explicit casts.** The CSV sources are all string-typed. `dataflow_payroll2020`
and `dataflow_payroll2021` carry a Derived Column that casts the numerics and
parses `AgencyStartDate` with `toDate(..., 'M/d/yyyy')` — the file has
`9/12/2016`, not an ISO date, and implicit conversion into a `date` column is
not reliable.

**Column order into staging.** An Aggregate emits group-by columns first, so a
final Select pins the order to `FiscalYear, AgencyName, TotalPaid` to match the
external table. The SQL sink maps by name and does not care; the headerless CSV
very much does.

**Truncating sinks.** Every SQL sink has `truncate: true`, not just the summary
one. The pipeline is then idempotent — re-running it does not double the row
counts, which matters when you are iterating against a clock.

## If a data flow shows a parse error

The `adf/dataflow/*.json` files are hand-authored data flow script, and ADF's
script dialect is version-sensitive. If the studio flags a transformation, open
that data flow, fix it on the canvas (every construct here has a UI equivalent
— Source, Select, Union, Filter, Derived Column, Aggregate, Sink), and save.
Git mode writes the corrected JSON straight back to this repo. Nothing is lost
and the submission artifact stays correct.

## Cost and teardown

Basic SQL DB is about $5/month; the factory bills per data flow run
(~$0.30/hour of cluster time, 8-core General purpose, with a few minutes of
startup per activity). Synapse serverless bills per TB scanned — negligible
here. The lab deletes everything on expiry, but if you are on your own
subscription:

```bash
az group delete --name <resource-group> --yes --no-wait
```
