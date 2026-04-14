-- Top 50 companies by complaint volume
-- Useful for seeing the name-normalization mess (same company appearing multiple ways)
-- and for sanity-checking the FDIC join target list.

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
