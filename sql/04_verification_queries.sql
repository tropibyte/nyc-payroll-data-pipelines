/* =====================================================================
   Post-pipeline verification.  Screenshot the results of these.
   ===================================================================== */

-- ---------- Azure SQL DB: db_nycpayroll ----------

-- Row counts loaded by the five load dataflows
SELECT 'AGENCY_MD' AS TableName, COUNT(*) AS [Rows] FROM dbo.NYC_Payroll_AGENCY_MD
UNION ALL SELECT 'EMP_MD',    COUNT(*) FROM dbo.NYC_Payroll_EMP_MD
UNION ALL SELECT 'TITLE_MD',  COUNT(*) FROM dbo.NYC_Payroll_TITLE_MD
UNION ALL SELECT 'Data_2020', COUNT(*) FROM dbo.NYC_Payroll_Data_2020
UNION ALL SELECT 'Data_2021', COUNT(*) FROM dbo.NYC_Payroll_Data_2021
UNION ALL SELECT 'Summary',   COUNT(*) FROM dbo.NYC_Payroll_Summary;
-- Expected: 153, 1000, 1446, 100, 101, 25

-- The rubric screenshot: summary table contents
SELECT FiscalYear, AgencyName, TotalPaid
FROM dbo.NYC_Payroll_Summary
ORDER BY FiscalYear, TotalPaid DESC;

-- Independently computed from the source CSVs: 25 rows totalling 35,709,510.43
SELECT COUNT(*) AS SummaryRows, ROUND(SUM(TotalPaid), 2) AS GrandTotal
FROM dbo.NYC_Payroll_Summary;

-- Proof the fiscal-year filter worked.  As distributed by the course, each
-- payroll file already contains one out-of-range row: FiscalYear 1998 in
-- nycpayroll_2020.csv and 1999 in nycpayroll_2021.csv.  Both must be PRESENT in
-- the raw tables and ABSENT from the summary when dataflow_param_fiscalyear
-- = 2020.
SELECT 'raw 2020 table, FY 1998' AS Src, COUNT(*) AS [Rows]
FROM dbo.NYC_Payroll_Data_2020 WHERE FiscalYear = 1998
UNION ALL
SELECT 'raw 2021 table, FY 1999', COUNT(*)
FROM dbo.NYC_Payroll_Data_2021 WHERE FiscalYear = 1999
UNION ALL
SELECT 'summary, any FY < 2020', COUNT(*)
FROM dbo.NYC_Payroll_Summary WHERE FiscalYear < 2020;
-- Expected: 1, 1, 0

-- Overtime share of spend -- the business question the project is asking
SELECT FiscalYear,
       SUM(TotalOTPaid)                                    AS OvertimePaid,
       SUM(RegularGrossPaid + TotalOTPaid + TotalOtherPay) AS TotalPaid,
       100.0 * SUM(TotalOTPaid)
             / NULLIF(SUM(RegularGrossPaid + TotalOTPaid + TotalOtherPay), 0) AS PctOvertime
FROM (
    SELECT FiscalYear, RegularGrossPaid, TotalOTPaid, TotalOtherPay FROM dbo.NYC_Payroll_Data_2020
    UNION ALL
    SELECT FiscalYear, RegularGrossPaid, TotalOTPaid, TotalOtherPay FROM dbo.NYC_Payroll_Data_2021
) x
WHERE FiscalYear >= 2020
GROUP BY FiscalYear
ORDER BY FiscalYear;


-- ---------- Synapse serverless SQL pool: database 'udacity' ----------

SELECT * FROM dbo.NYC_Payroll_Summary ORDER BY FiscalYear, TotalPaid DESC;

SELECT COUNT(*) AS RowsInExternalTable, SUM(TotalPaid) AS GrandTotal
FROM dbo.NYC_Payroll_Summary;
