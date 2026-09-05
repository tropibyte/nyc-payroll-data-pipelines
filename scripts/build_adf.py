#!/usr/bin/env python3
"""
Generate the Azure Data Factory artifact tree (adf/) from config/project.json.

ADF's GitHub integration reads and writes a fixed folder layout underneath a
"root folder" you nominate when you connect the factory to the repo:

    adf/
      factory/         global parameters
      linkedService/   connections
      dataset/         views over files and tables
      dataflow/        MappingDataFlow definitions
      pipeline/        orchestration

Point ADF at root folder "/adf" and everything here shows up in the studio.

Run:  python scripts/build_adf.py
Also renders sql/03_synapse_external_table.sql -> sql/rendered/.
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / "config" / "project.json").read_text(encoding="utf-8"))

ACCOUNT = CFG["storageAccount"]
CONTAINER = CFG["storageContainer"]
SQL_SERVER = CFG["sqlServer"]
SQL_DB = CFG["sqlDatabase"]
SQL_USER = CFG["sqlUser"]
FACTORY = CFG["factoryName"]
FY_PARAM = int(CFG.get("fiscalYearParam", 2020))

LS_ADLS = "ls_adls_nycpayroll"
LS_SQL = "ls_sqldb_nycpayroll"

OUT = ROOT / "adf"


# --------------------------------------------------------------------------
# column definitions
# --------------------------------------------------------------------------
# (name, sql_type, dataflow_type).  2020 has AgencyID, 2021 has AgencyCode --
# that difference is real and is why the summary flow needs a Select before
# the Union.
def payroll_cols(agency_col):
    return [
        ("FiscalYear", "int", "integer"),
        ("PayrollNumber", "int", "integer"),
        (agency_col, "varchar", "string"),
        ("AgencyName", "varchar", "string"),
        ("EmployeeID", "varchar", "string"),
        ("LastName", "varchar", "string"),
        ("FirstName", "varchar", "string"),
        ("AgencyStartDate", "date", "date"),
        ("WorkLocationBorough", "varchar", "string"),
        ("TitleCode", "varchar", "string"),
        ("TitleDescription", "varchar", "string"),
        ("LeaveStatusasofJune30", "varchar", "string"),
        ("BaseSalary", "float", "double"),
        ("PayBasis", "varchar", "string"),
        ("RegularHours", "float", "double"),
        ("RegularGrossPaid", "float", "double"),
        ("OTHours", "float", "double"),
        ("TotalOTPaid", "float", "double"),
        ("TotalOtherPay", "float", "double"),
    ]


COLS_2020 = payroll_cols("AgencyID")
COLS_2021 = payroll_cols("AgencyCode")
COLS_AGENCY = [("AgencyID", "varchar", "string"), ("AgencyName", "varchar", "string")]
COLS_EMP = [
    ("EmployeeID", "varchar", "string"),
    ("LastName", "varchar", "string"),
    ("FirstName", "varchar", "string"),
]
COLS_TITLE = [
    ("TitleCode", "varchar", "string"),
    ("TitleDescription", "varchar", "string"),
]
COLS_SUMMARY = [
    ("FiscalYear", "int", "integer"),
    ("AgencyName", "varchar", "string"),
    ("TotalPaid", "float", "double"),
]

# Numeric / date columns that arrive from CSV as text and must be cast before
# they land in a typed SQL column.  AgencyStartDate is 9/12/2016 style.
CASTS = {
    "FiscalYear": "toInteger(FiscalYear)",
    "PayrollNumber": "toInteger(PayrollNumber)",
    "AgencyStartDate": "toDate(AgencyStartDate, 'M/d/yyyy')",
    "BaseSalary": "toFloat(BaseSalary)",
    "RegularHours": "toFloat(RegularHours)",
    "RegularGrossPaid": "toFloat(RegularGrossPaid)",
    "OTHours": "toFloat(OTHours)",
    "TotalOTPaid": "toFloat(TotalOTPaid)",
    "TotalOtherPay": "toFloat(TotalOtherPay)",
}


def write(folder, name, obj):
    d = OUT / folder
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{name}.json").write_text(
        json.dumps(obj, indent=4) + "\n", encoding="utf-8"
    )


# --------------------------------------------------------------------------
# linked services
# --------------------------------------------------------------------------
def adls_linked_service(auth):
    """Two interchangeable shapes for the same connection.

    managedIdentity  no secret anywhere, but the factory's managed identity
                     needs "Storage Blob Data Contributor" on the storage
                     account -- a role assignment some lab tenants block.
    accountKey       always works, but the key is a secret: it is written as
                     an empty SecureString here and typed into the portal.
    """
    props = {
        "annotations": [],
        "type": "AzureBlobFS",
        "typeProperties": {"url": f"https://{ACCOUNT}.dfs.core.windows.net"}
    }
    if auth == "accountKey":
        props["typeProperties"]["accountKey"] = {
            "type": "SecureString",
            "value": "PASTE-THE-STORAGE-ACCOUNT-KEY-IN-THE-PORTAL"
        }
    return {"name": LS_ADLS, "properties": props}


def linked_services():
    primary = CFG.get("adlsAuth", "managedIdentity")
    if primary not in ("managedIdentity", "accountKey"):
        raise SystemExit(f"adlsAuth must be managedIdentity or accountKey, got {primary!r}")
    alternate = "accountKey" if primary == "managedIdentity" else "managedIdentity"

    write("linkedService", LS_ADLS, adls_linked_service(primary))

    # The other form, parked outside the ADF root folder so the studio ignores
    # it.  To swap: copy it over adf/linkedService/ls_adls_nycpayroll.json, or
    # flip "adlsAuth" in config/project.json and re-run this script.
    d = ROOT / "adf-optional" / "linkedService"
    d.mkdir(parents=True, exist_ok=True)
    for stale in d.glob(f"{LS_ADLS}.*.json"):
        stale.unlink()
    (d / f"{LS_ADLS}.{alternate}.json").write_text(
        json.dumps(adls_linked_service(alternate), indent=4) + "\n", encoding="utf-8"
    )

    # The connectionString form IS the "Legacy" version of the Azure SQL linked
    # service.  The current/recommended version (discrete server / database /
    # authenticationType properties) breaks mapping data flows with
    # "MissingRequiredPropertyException: server is a required property".
    # No explicit "version" property here -- omitting it is what every legacy
    # linked service looks like, and a wrong literal would fail validation.
    # Confirm the portal's Version dropdown reads "Legacy" after import.
    #
    # Authentication, sqlAuth in config/project.json:
    #
    #   managedIdentity  (default) no credential in the connection string at
    #                    all, so the factory authenticates as its own managed
    #                    identity.  Requires the contained database user from
    #                    sql/05_grant_adf_managed_identity.sql.  Nothing secret
    #                    exists to leak, and it sidesteps a real bug: `az
    #                    datafactory linked-service create` rewrites a
    #                    SecureString password into an empty
    #                    AzureKeyVaultSecret, after which every data flow fails
    #                    with "SQLAuthentication is invalid. One of
    #                    user/password is missing."
    #
    #   sqlLogin         classic user + password.  Deploy this one through the
    #                    REST API (scripts/deploy_adf.ps1 does) or type the
    #                    password into the studio -- do not rely on the CLI
    #                    extension to carry it.
    sql_auth = CFG.get("sqlAuth", "managedIdentity")
    base = (
        "Integrated Security=False;Encrypt=True;Connection Timeout=30;"
        f"Data Source={SQL_SERVER}.database.windows.net;"
        f"Initial Catalog={SQL_DB}"
    )
    type_props = {"connectionString": base}
    if sql_auth == "sqlLogin":
        type_props["connectionString"] = f"{base};User ID={SQL_USER}"
        type_props["password"] = {
            "type": "SecureString",
            "value": "TYPE-THE-PASSWORD-IN-THE-PORTAL",
        }
    elif sql_auth != "managedIdentity":
        raise SystemExit(f"sqlAuth must be managedIdentity or sqlLogin, got {sql_auth!r}")

    write("linkedService", LS_SQL, {
        "name": LS_SQL,
        "properties": {
            "annotations": [],
            "type": "AzureSqlDatabase",
            "typeProperties": type_props
        }
    })


# --------------------------------------------------------------------------
# datasets
# --------------------------------------------------------------------------
def adls_dataset(name, folder, filename, cols, header=True):
    props = {
        "linkedServiceName": {
            "referenceName": LS_ADLS, "type": "LinkedServiceReference"
        },
        "annotations": [],
        "type": "DelimitedText",
        "typeProperties": {
            "location": {
                "type": "AzureBlobFSLocation",
                "folderPath": folder,
                "fileSystem": CONTAINER
            },
            "columnDelimiter": ",",
            "escapeChar": "\\",
            "firstRowAsHeader": header,
            "quoteChar": "\""
        },
        "schema": [{"name": c, "type": "String"} for c, _, _ in cols]
    }
    if filename:
        props["typeProperties"]["location"]["fileName"] = filename
    write("dataset", name, {"name": name, "properties": props})


def sql_dataset(name, table, cols):
    write("dataset", name, {
        "name": name,
        "properties": {
            "linkedServiceName": {
                "referenceName": LS_SQL, "type": "LinkedServiceReference"
            },
            "annotations": [],
            "type": "AzureSqlTable",
            "schema": [{"name": c, "type": t} for c, t, _ in cols],
            "typeProperties": {"schema": "dbo", "table": table}
        }
    })


def datasets():
    adls_dataset("ds_adls_agency", "dirpayrollfiles", "AgencyMaster.csv", COLS_AGENCY)
    adls_dataset("ds_adls_emp", "dirpayrollfiles", "EmpMaster.csv", COLS_EMP)
    adls_dataset("ds_adls_title", "dirpayrollfiles", "TitleMaster.csv", COLS_TITLE)
    adls_dataset("ds_adls_payroll2021", "dirpayrollfiles", "nycpayroll_2021.csv", COLS_2021)
    # 2020 is the historical file and lives in a different directory
    adls_dataset("ds_adls_payroll2020", "dirhistoryfiles", "nycpayroll_2020.csv", COLS_2020)

    # Staging sink.  firstRowAsHeader is FALSE on purpose: the Synapse external
    # file format has no FIRST_ROW option, so a header row would be read as data
    # and blow up the int conversion on FiscalYear.
    adls_dataset("ds_adls_staging", "dirstaging", None, COLS_SUMMARY, header=False)

    sql_dataset("ds_sql_agency", "NYC_Payroll_AGENCY_MD", COLS_AGENCY)
    sql_dataset("ds_sql_emp", "NYC_Payroll_EMP_MD", COLS_EMP)
    sql_dataset("ds_sql_title", "NYC_Payroll_TITLE_MD", COLS_TITLE)
    sql_dataset("ds_sql_payroll2020", "NYC_Payroll_Data_2020", COLS_2020)
    sql_dataset("ds_sql_payroll2021", "NYC_Payroll_Data_2021", COLS_2021)
    sql_dataset("ds_sql_summary", "NYC_Payroll_Summary", COLS_SUMMARY)


# --------------------------------------------------------------------------
# data flow script fragments
# --------------------------------------------------------------------------
def src_file(cols, name):
    proj = ",\n".join(f"\t\t{c} as string" for c, _, _ in cols)
    return (
        f"source(output(\n{proj}\n\t),\n"
        "\tallowSchemaDrift: true,\n"
        "\tvalidateSchema: false,\n"
        "\tignoreNoFilesFound: false) ~> " + name
    )


def src_table(cols, name):
    proj = ",\n".join(f"\t\t{c} as {t}" for c, _, t in cols)
    return (
        f"source(output(\n{proj}\n\t),\n"
        "\tallowSchemaDrift: true,\n"
        "\tvalidateSchema: false,\n"
        "\tisolationLevel: 'READ_UNCOMMITTED',\n"
        "\tformat: 'table') ~> " + name
    )


def sink_table(upstream, name):
    return (
        f"{upstream} sink(allowSchemaDrift: true,\n"
        "\tvalidateSchema: false,\n"
        "\tdeletable:false,\n"
        "\tinsertable:true,\n"
        "\tupdateable:false,\n"
        "\tupsertable:false,\n"
        "\ttruncate:true,\n"
        "\tformat: 'table',\n"
        "\tskipDuplicateMapInputs: true,\n"
        "\tskipDuplicateMapOutputs: true,\n"
        "\terrorHandlingOption: 'stopOnFirstError') ~> " + name
    )


def sink_file(upstream, name):
    # truncate:true == the sink's "Clear the folder" checkbox
    return (
        f"{upstream} sink(allowSchemaDrift: true,\n"
        "\tvalidateSchema: false,\n"
        "\tumask: 0022,\n"
        "\tpreCommands: [],\n"
        "\tpostCommands: [],\n"
        "\ttruncate: true,\n"
        "\tskipDuplicateMapInputs: true,\n"
        "\tskipDuplicateMapOutputs: true) ~> " + name
    )


def dataflow(name, sources, sinks, transformations, lines):
    write("dataflow", name, {
        "name": name,
        "properties": {
            "type": "MappingDataFlow",
            "typeProperties": {
                "sources": [
                    {"dataset": {"referenceName": ds, "type": "DatasetReference"},
                     "name": n}
                    for n, ds in sources
                ],
                "sinks": [
                    {"dataset": {"referenceName": ds, "type": "DatasetReference"},
                     "name": n}
                    for n, ds in sinks
                ],
                "transformations": [{"name": t} for t in transformations],
                "scriptLines": "\n".join(lines).split("\n")
            }
        }
    })


def simple_load(name, src_ds, sink_ds, cols, src_name, sink_name):
    """CSV in Data Lake -> table in Azure SQL DB, no transformation."""
    dataflow(
        name,
        [(src_name, src_ds)],
        [(sink_name, sink_ds)],
        [],
        [src_file(cols, src_name), sink_table(src_name, sink_name)],
    )


def cast_load(name, src_ds, sink_ds, cols, src_name, cast_name, sink_name):
    """CSV -> typed cast -> table.  Needed for the payroll files, whose
    numeric and date columns arrive as text."""
    casts = ",\n".join(
        f"\t\t{c} = {CASTS[c]}" for c, _, _ in cols if c in CASTS
    )
    derive = f"{src_name} derive(\n{casts}) ~> {cast_name}"
    dataflow(
        name,
        [(src_name, src_ds)],
        [(sink_name, sink_ds)],
        [cast_name],
        [src_file(cols, src_name), derive, sink_table(cast_name, sink_name)],
    )


def summary_dataflow():
    """The aggregate flow: union 2020 + 2021 from SQL, filter by fiscal year
    parameter, derive TotalPaid, aggregate by agency and year, land in both
    the SQL summary table and the Data Lake staging directory."""
    keep = ["FiscalYear", "AgencyName", "RegularGrossPaid", "TotalOTPaid", "TotalOtherPay"]
    sel = ",\n".join(f"\t\t{c}" for c in keep)

    lines = [
        "parameters{",
        f"\tdataflow_param_fiscalyear as integer ({FY_PARAM})",
        "}",
        src_table(COLS_2020, "srcSql2020"),
        src_table(COLS_2021, "srcSql2021"),
        # Select on both sides drops AgencyID / AgencyCode so the union lines
        # up by name -- this is the fix for "AgencyID column not found in 2021".
        f"srcSql2020 select(mapColumn(\n{sel}\n\t),\n"
        "\tskipDuplicateMapInputs: true,\n"
        "\tskipDuplicateMapOutputs: true) ~> sel2020",
        f"srcSql2021 select(mapColumn(\n{sel}\n\t),\n"
        "\tskipDuplicateMapInputs: true,\n"
        "\tskipDuplicateMapOutputs: true) ~> sel2021",
        "sel2020, sel2021 union(byName: true)~> unionPayroll",
        "unionPayroll filter(toInteger(FiscalYear) >= $dataflow_param_fiscalyear) ~> filterFiscalYear",
        "filterFiscalYear derive(TotalPaid = RegularGrossPaid + TotalOTPaid + TotalOtherPay) ~> deriveTotalPaid",
        "deriveTotalPaid aggregate(groupBy(FiscalYear,\n"
        "\t\tAgencyName),\n"
        "\tTotalPaid = sum(TotalPaid)) ~> aggTotalPaid",
        # Explicit column order so the headerless staging CSV matches the
        # Synapse external table definition exactly.
        "aggTotalPaid select(mapColumn(\n"
        "\t\tFiscalYear,\n"
        "\t\tAgencyName,\n"
        "\t\tTotalPaid\n"
        "\t),\n"
        "\tskipDuplicateMapInputs: true,\n"
        "\tskipDuplicateMapOutputs: true) ~> selSummary",
        sink_table("selSummary", "sinkSummaryTable"),
        sink_file("selSummary", "sinkSummaryStaging"),
    ]

    dataflow(
        "dataflow_summary",
        [("srcSql2020", "ds_sql_payroll2020"), ("srcSql2021", "ds_sql_payroll2021")],
        [("sinkSummaryTable", "ds_sql_summary"), ("sinkSummaryStaging", "ds_adls_staging")],
        ["sel2020", "sel2021", "unionPayroll", "filterFiscalYear",
         "deriveTotalPaid", "aggTotalPaid", "selSummary"],
        lines,
    )


def dataflows():
    simple_load("dataflow_agency", "ds_adls_agency", "ds_sql_agency",
                COLS_AGENCY, "srcAgencyFile", "sinkAgencyTable")
    simple_load("dataflow_emp", "ds_adls_emp", "ds_sql_emp",
                COLS_EMP, "srcEmpFile", "sinkEmpTable")
    simple_load("dataflow_title", "ds_adls_title", "ds_sql_title",
                COLS_TITLE, "srcTitleFile", "sinkTitleTable")
    cast_load("dataflow_payroll2020", "ds_adls_payroll2020", "ds_sql_payroll2020",
              COLS_2020, "srcPayroll2020File", "castPayroll2020", "sinkPayroll2020Table")
    cast_load("dataflow_payroll2021", "ds_adls_payroll2021", "ds_sql_payroll2021",
              COLS_2021, "srcPayroll2021File", "castPayroll2021", "sinkPayroll2021Table")
    summary_dataflow()


# --------------------------------------------------------------------------
# pipeline
# --------------------------------------------------------------------------
def activity(name, flow, depends, params=None):
    a = {
        "name": name,
        "type": "ExecuteDataFlow",
        "dependsOn": [
            {"activity": d, "dependencyConditions": ["Succeeded"]} for d in depends
        ],
        "policy": {
            "timeout": "0.12:00:00",
            "retry": 0,
            "retryIntervalInSeconds": 30,
            "secureOutput": False,
            "secureInput": False
        },
        "userProperties": [],
        "typeProperties": {
            "dataflow": {"referenceName": flow, "type": "DataFlowReference"},
            "compute": {"coreCount": 8, "computeType": "General"},
            "traceLevel": "Fine"
        }
    }
    if params:
        a["typeProperties"]["dataflow"]["parameters"] = params
    return a


def pipeline():
    masters = ["Load Agency Master", "Load Employee Master", "Load Title Master"]
    write("pipeline", "pl_nyc_payroll", {
        "name": "pl_nyc_payroll",
        "properties": {
            "description": (
                "Loads NYC payroll master and transaction files from ADLS Gen2 "
                "into Azure SQL DB, then aggregates 2020 + 2021 spend by agency "
                "and fiscal year into the SQL summary table and the dirstaging "
                "directory that the Synapse external table reads."
            ),
            "activities": [
                activity("Load Agency Master", "dataflow_agency", []),
                activity("Load Employee Master", "dataflow_emp", []),
                activity("Load Title Master", "dataflow_title", []),
                activity("Load Payroll 2020", "dataflow_payroll2020", masters),
                activity("Load Payroll 2021", "dataflow_payroll2021", masters),
                activity(
                    "Aggregate Payroll Summary", "dataflow_summary",
                    ["Load Payroll 2020", "Load Payroll 2021"],
                    params={
                        "dataflow_param_fiscalyear": {
                            "value": "@pipeline().globalParameters.dataflow_param_fiscalyear",
                            "type": "Expression"
                        }
                    }
                ),
            ],
            "annotations": []
        }
    })


def factory():
    write("factory", FACTORY, {
        "name": FACTORY,
        "properties": {
            "globalParameters": {
                "dataflow_param_fiscalyear": {"type": "Int", "value": FY_PARAM}
            }
        }
    })


def render_sql():
    src = ROOT / "sql" / "03_synapse_external_table.sql"
    dst = ROOT / "sql" / "rendered"
    dst.mkdir(exist_ok=True)
    text = (src.read_text(encoding="utf-8")
            .replace("__STORAGE_CONTAINER__", CONTAINER)
            .replace("__STORAGE_ACCOUNT__", ACCOUNT))
    (dst / src.name).write_text(text, encoding="utf-8")


def main():
    if "CHANGE-ME" in json.dumps(CFG):
        print("warning: config/project.json still has CHANGE-ME placeholders",
              file=sys.stderr)
    linked_services()
    datasets()
    dataflows()
    pipeline()
    factory()
    render_sql()
    n = sum(1 for _ in OUT.rglob("*.json"))
    print(f"wrote {n} ADF artifacts to {OUT}")
    print(f"rendered sql/rendered/03_synapse_external_table.sql")


if __name__ == "__main__":
    main()
