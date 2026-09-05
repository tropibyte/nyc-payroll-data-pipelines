/* =====================================================================
   Run against: Azure SQL Database  db_nycpayroll
   Portal path: SQL databases > db_nycpayroll > Query editor (preview)
   Creates the 3 master tables, 2 payroll transaction tables and the
   summary destination table.  Safe to re-run.
   ===================================================================== */

DROP TABLE IF EXISTS [dbo].[NYC_Payroll_EMP_MD];
GO
CREATE TABLE [dbo].[NYC_Payroll_EMP_MD](
    [EmployeeID] [varchar](10) NULL,
    [LastName]   [varchar](20) NULL,
    [FirstName]  [varchar](20) NULL
);
GO

DROP TABLE IF EXISTS [dbo].[NYC_Payroll_TITLE_MD];
GO
CREATE TABLE [dbo].[NYC_Payroll_TITLE_MD](
    [TitleCode]        [varchar](10)  NULL,
    [TitleDescription] [varchar](100) NULL
);
GO

DROP TABLE IF EXISTS [dbo].[NYC_Payroll_AGENCY_MD];
GO
CREATE TABLE [dbo].[NYC_Payroll_AGENCY_MD](
    [AgencyID]   [varchar](10) NULL,
    [AgencyName] [varchar](50) NULL
);
GO

/* 2020 transaction table -- note the column is AgencyID */
DROP TABLE IF EXISTS [dbo].[NYC_Payroll_Data_2020];
GO
CREATE TABLE [dbo].[NYC_Payroll_Data_2020](
    [FiscalYear]            [int]          NULL,
    [PayrollNumber]         [int]          NULL,
    [AgencyID]              [varchar](10)  NULL,
    [AgencyName]            [varchar](50)  NULL,
    [EmployeeID]            [varchar](10)  NULL,
    [LastName]              [varchar](20)  NULL,
    [FirstName]             [varchar](20)  NULL,
    [AgencyStartDate]       [date]         NULL,
    [WorkLocationBorough]   [varchar](50)  NULL,
    [TitleCode]             [varchar](10)  NULL,
    [TitleDescription]      [varchar](100) NULL,
    [LeaveStatusasofJune30] [varchar](50)  NULL,
    [BaseSalary]            [float]        NULL,
    [PayBasis]              [varchar](50)  NULL,
    [RegularHours]          [float]        NULL,
    [RegularGrossPaid]      [float]        NULL,
    [OTHours]               [float]        NULL,
    [TotalOTPaid]           [float]        NULL,
    [TotalOtherPay]         [float]        NULL
);
GO

/* 2021 transaction table -- note the column is AgencyCode, NOT AgencyID */
DROP TABLE IF EXISTS [dbo].[NYC_Payroll_Data_2021];
GO
CREATE TABLE [dbo].[NYC_Payroll_Data_2021](
    [FiscalYear]            [int]          NULL,
    [PayrollNumber]         [int]          NULL,
    [AgencyCode]            [varchar](10)  NULL,
    [AgencyName]            [varchar](50)  NULL,
    [EmployeeID]            [varchar](10)  NULL,
    [LastName]              [varchar](20)  NULL,
    [FirstName]             [varchar](20)  NULL,
    [AgencyStartDate]       [date]         NULL,
    [WorkLocationBorough]   [varchar](50)  NULL,
    [TitleCode]             [varchar](10)  NULL,
    [TitleDescription]      [varchar](100) NULL,
    [LeaveStatusasofJune30] [varchar](50)  NULL,
    [BaseSalary]            [float]        NULL,
    [PayBasis]              [varchar](50)  NULL,
    [RegularHours]          [float]        NULL,
    [RegularGrossPaid]      [float]        NULL,
    [OTHours]               [float]        NULL,
    [TotalOTPaid]           [float]        NULL,
    [TotalOtherPay]         [float]        NULL
);
GO

DROP TABLE IF EXISTS [dbo].[NYC_Payroll_Summary];
GO
CREATE TABLE [dbo].[NYC_Payroll_Summary](
    [FiscalYear] [int]         NULL,
    [AgencyName] [varchar](50) NULL,
    [TotalPaid]  [float]       NULL
);
GO

SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE 'NYC[_]Payroll%'
ORDER BY TABLE_NAME;
GO
