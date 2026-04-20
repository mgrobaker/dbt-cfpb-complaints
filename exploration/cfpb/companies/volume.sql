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
-- Target: top ~50 companies ≈ 85% of all complaints.
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
