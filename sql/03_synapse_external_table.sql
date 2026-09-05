/* =====================================================================
   Run against: Synapse Built-in (serverless) SQL pool, database 'udacity'

   Replace the two __PLACEHOLDER__ tokens below, or run
     python scripts/build_adf.py
   which writes a filled-in copy to sql/rendered/03_synapse_external_table.sql

   A serverless pool cannot be a Data Factory sink, so the pipeline writes the
   aggregate to  <container>/dirstaging  in ADLS Gen2 and this external table
   reads those files in place.

   AUTHENTICATION
   The external data source below deliberately has NO credential. In a
   serverless SQL pool that means Microsoft Entra pass-through: the storage
   call is made as whoever is running the query. The Udacity lab account
   already holds "Storage Blob Data Owner" on the resource group, so this
   just works -- and it is the only clean option here, because the lab denies
   Microsoft.Authorization/roleAssignments/write, so you cannot grant the
   Synapse workspace's managed identity access to the payroll storage account.

   If you ever need a credential (a different tenant, or a caller without a
   storage role), use the SAS block at the bottom of this file instead.
   ===================================================================== */

-- 1. File format.  There is no FIRST_ROW option here, so the staging files
--    must be written WITHOUT a header row.  The ADF sink dataset
--    ds_adls_staging sets firstRowAsHeader = false for exactly this reason.
--    If you let ADF write headers, this table fails with
--    "Error converting data type NVARCHAR to INT" on the word 'FiscalYear'.
IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'SynapseDelimitedTextFormat')
    CREATE EXTERNAL FILE FORMAT [SynapseDelimitedTextFormat]
    WITH ( FORMAT_TYPE = DELIMITEDTEXT,
           FORMAT_OPTIONS (
               FIELD_TERMINATOR = ',',
               STRING_DELIMITER = '"',
               USE_TYPE_DEFAULT = FALSE
           ));
GO

-- 2. Data source over the payroll container, no credential -> Entra pass-through.
IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'ds_nycpayroll_staging')
    CREATE EXTERNAL DATA SOURCE [ds_nycpayroll_staging]
    WITH ( LOCATION = 'abfss://__STORAGE_CONTAINER__@__STORAGE_ACCOUNT__.dfs.core.windows.net' );
GO

-- 3. The external table required by the rubric.
DROP EXTERNAL TABLE [dbo].[NYC_Payroll_Summary];
GO
CREATE EXTERNAL TABLE [dbo].[NYC_Payroll_Summary](
    [FiscalYear] [int]         NULL,
    [AgencyName] [varchar](50) NULL,
    [TotalPaid]  [float]       NULL
)
WITH (
    LOCATION    = 'dirstaging/',
    DATA_SOURCE = [ds_nycpayroll_staging],
    FILE_FORMAT = [SynapseDelimitedTextFormat]
);
GO

SELECT * FROM [dbo].[NYC_Payroll_Summary] ORDER BY FiscalYear, TotalPaid DESC;
GO


/* ---------------------------------------------------------------------
   FALLBACK: shared access signature, if pass-through is ever unavailable.
   Generate the SAS with:
     az storage container generate-sas --account-name __STORAGE_ACCOUNT__ \
        --name __STORAGE_CONTAINER__ --permissions rl --expiry <yyyy-mm-dd> \
        --auth-mode login --as-user -o tsv
   Then drop the objects above and run:

   CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<a strong local key>';
   GO
   CREATE DATABASE SCOPED CREDENTIAL [cred_nycpayroll]
   WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
        SECRET   = '<sas token, no leading ?>';
   GO
   CREATE EXTERNAL DATA SOURCE [ds_nycpayroll_staging]
   WITH ( LOCATION   = 'abfss://__STORAGE_CONTAINER__@__STORAGE_ACCOUNT__.dfs.core.windows.net',
          CREDENTIAL = [cred_nycpayroll] );
   GO

   Managed identity is NOT an option in this lab: granting the Synapse
   workspace MI a storage role needs roleAssignments/write, which the lab's
   Spektra custom role does not include.
   --------------------------------------------------------------------- */
