/* =====================================================================
   Run against: Azure SQL Database  db_nycpayroll
   Connect as the server's Microsoft Entra admin (scripts/run_sql.py does
   this with the token from your az login).

   Gives the Data Factory's system-assigned managed identity a contained
   database user, so the linked service needs no password at all.

   Why this instead of SQL authentication:

     * `az datafactory linked-service create` mangles a SecureString password
       into an empty AzureKeyVaultSecret, and the data flow then fails with
       "Only one valid authentication should be used for ls_sqldb_nycpayroll.
       SQLAuthentication is invalid. One of user/password is missing."
     * A contained database user is a DATABASE-level grant, not an Azure RBAC
       role assignment, so it works even though this lab denies
       Microsoft.Authorization/roleAssignments/write.
     * Nothing secret ends up in the repo, the linked service, or a prompt.

   The user name must be the factory's name, which is also its managed
   identity's display name.
   ===================================================================== */

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'adf-nycpayroll-tarie-n')
    CREATE USER [adf-nycpayroll-tarie-n] FROM EXTERNAL PROVIDER;
GO

ALTER ROLE db_datareader ADD MEMBER [adf-nycpayroll-tarie-n];
GO
ALTER ROLE db_datawriter ADD MEMBER [adf-nycpayroll-tarie-n];
GO
-- Needed for the sinks that truncate their target table before loading.
ALTER ROLE db_ddladmin ADD MEMBER [adf-nycpayroll-tarie-n];
GO

SELECT dp.name       AS principal,
       dp.type_desc  AS principal_type,
       r.name        AS role_name
FROM sys.database_principals dp
LEFT JOIN sys.database_role_members drm ON drm.member_principal_id = dp.principal_id
LEFT JOIN sys.database_principals r     ON r.principal_id = drm.role_principal_id
WHERE dp.name = 'adf-nycpayroll-tarie-n';
GO
