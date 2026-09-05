/* =====================================================================
   Run against: Synapse Built-in (serverless) SQL pool, database 'udacity'

   Replace the two __PLACEHOLDER__ tokens below, or run
     python scripts/render_adf.py
   which writes a filled-in copy to sql/rendered/03_synapse_external_table.sql

   A serverless pool cannot be a Data Factory sink, so the pipeline writes
   the aggregate to  <container>/dirstaging  in ADLS Gen2 and this external
   table reads those files in place (the CETAS-era approach the project
   instructions point you to now that dedicated pools are disabled).
   ===================================================================== */

-- 1. Master key -- required before a database-scoped credential can exist.
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Udacity!Nyc#Payroll2026';
GO

-- 2. Credential.  Passwordless: use the Synapse workspace managed identity.
--    Requires the workspace MI to hold "Storage Blob Data Contributor" on the
--    ADLS Gen2 account (Storage account > Access Control (IAM) > Add role
--    assignment > Managed identity > Synapse workspace).
--    If you would rather not touch IAM, swap this for a SAS credential:
--      CREATE DATABASE SCOPED CREDENTIAL [cred_nycpayroll]
--      WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = '<sas-token-no-leading-?>';
IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'cred_nycpayroll')
    CREATE DATABASE SCOPED CREDENTIAL [cred_nycpayroll]
    WITH IDENTITY = 'Managed Identity';
GO

-- 3. File format.  NOTE: there is no FIRST_ROW option here, so the staging
--    files must be written WITHOUT a header row.  The ADF sink dataset
--    ds_adls_staging sets firstRowAsHeader = false for exactly this reason.
--    If you let ADF write headers instead, this table fails with
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

-- 4. Data source pointing at the payroll container.
IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'ds_nycpayroll_staging')
    CREATE EXTERNAL DATA SOURCE [ds_nycpayroll_staging]
    WITH ( LOCATION   = 'abfss://__STORAGE_CONTAINER__@__STORAGE_ACCOUNT__.dfs.core.windows.net',
           CREDENTIAL = [cred_nycpayroll]
         );
GO

-- 5. The external table required by the rubric.
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
