-- Company complaint volume: top companies and cumulative coverage analysis.
-- Primary input for sizing and scoping the crosswalk seed.

-- ================================================================
-- Top 50 companies by complaint volume (raw names)
-- Shows the name-normalization mess and sets expectations for FDIC join targets.
-- ================================================================
SELECT
  company_name,
  COUNT(*) AS complaints,
  COUNT(DISTINCT product) AS products_touched,
  MIN(date_received) AS first_seen,
  MAX(date_received) AS last_seen
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
WHERE company_name IS NOT NULL
GROUP BY company_name
ORDER BY complaints DESC
LIMIT 50;

-- ================================================================
-- Cumulative coverage: how many companies needed to reach 85% of volume?
-- Uses company_name_normalized (same expression as stg_cfpb_complaints).
-- ================================================================
WITH normalized AS (
  SELECT
    REGEXP_REPLACE(
      REGEXP_REPLACE(UPPER(TRIM(company_name)), r'\s+', ' '),
      r'[.,;:]+$', ''
    ) AS company_name_normalized
  FROM `raw.cfpb_complaints`
  WHERE date_received BETWEEN '2012-01-01' AND '2022-12-31'
),
counts AS (
  SELECT
    company_name_normalized,
    COUNT(*) AS n
  FROM normalized
  GROUP BY company_name_normalized
),
ranked AS (
  SELECT
    company_name_normalized,
    n,
    ROW_NUMBER() OVER (ORDER BY n DESC) AS rnk,
    SUM(n) OVER () AS total_n,
    SUM(n) OVER (ORDER BY n DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_n
  FROM counts
)

SELECT
  rnk,
  company_name_normalized,
  n,
  ROUND(100 * n / total_n, 3) AS pct,
  ROUND(100 * cum_n / total_n, 2) AS cum_pct
FROM ranked
WHERE rnk <= 100
ORDER BY rnk;

-- ================================================================
-- Pick top entities besides the credit bureaus
-- ================================================================
WITH normalized AS (
  SELECT
    REGEXP_REPLACE(
      REGEXP_REPLACE(UPPER(TRIM(company_name)), r'\s+', ' '),
      r'[.,;:]+$', ''
    ) AS company_name_normalized
  FROM `raw.cfpb_complaints`
  WHERE date_received BETWEEN '2012-01-01' AND '2022-12-31'
),
counts AS (
  SELECT
    company_name_normalized,
    COUNT(*) AS n
  FROM normalized
  GROUP BY company_name_normalized
),
credit_bureaus AS (
  SELECT company_name_normalized FROM counts
  WHERE company_name_normalized IN (
    'EQUIFAX, INC', 
    'TRANSUNION INTERMEDIATE HOLDINGS, INC',
    'EXPERIAN INFORMATION SOLUTIONS INC'
  )
),
bank_counts AS (
  SELECT c.company_name_normalized, c.n
  FROM counts c
  LEFT JOIN credit_bureaus cb USING (company_name_normalized)
  WHERE cb.company_name_normalized IS NULL
),
totals AS (
  SELECT SUM(n) AS total_all FROM counts
),
ranked AS (
  SELECT
    bc.company_name_normalized,
    bc.n,
    ROW_NUMBER() OVER (ORDER BY bc.n DESC) AS rnk,
    SUM(bc.n) OVER () AS total_banks,
    t.total_all,
    SUM(bc.n) OVER (ORDER BY bc.n DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_n_banks
  FROM bank_counts bc
  CROSS JOIN totals t
)

SELECT
  rnk,
  company_name_normalized,
  n                                                         AS complaints,
  ROUND(100 * n / total_all, 2)                            AS pct_of_all,
  ROUND(100 * n / total_banks, 2)                          AS pct_of_banks,
  ROUND(100 * cum_n_banks / total_all, 2)                  AS cum_pct_of_all,
  ROUND(100 * cum_n_banks / total_banks, 2)                AS cum_pct_of_banks
FROM ranked
WHERE rnk <= 30
ORDER BY rnk;
