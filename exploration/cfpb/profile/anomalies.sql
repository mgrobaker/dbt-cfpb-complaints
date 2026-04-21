-- Data quality anomalies: date ordering violations, tags field, zip validity.
-- Findings documented in staging/_models.yml column descriptions and exploration/README.md.

-- ================================================================
-- Date ordering violations: date_sent_to_company < date_received
-- 7,036 rows (~0.2%) flagged by assert_complaint_dates_ordered test.
-- Finding: all exactly 1 day early, all 2012-01-22 to 2014-04-26 — systematic
-- artifact from CFPB's early intake system. Rows kept; test set to severity: warn.
-- Queries run against stg_cfpb_complaints (already filtered to 2012-2022).
-- ================================================================
SELECT
  DATE_DIFF(date_received, date_sent_to_company, DAY)  AS days_early,
  COUNT(*)                                              AS complaints,
  MIN(date_received)                                    AS earliest,
  MAX(date_received)                                    AS latest
FROM `dbt-portfolio-493318.dbt_dev.stg_cfpb_complaints`
WHERE date_sent_to_company < date_received
GROUP BY days_early
ORDER BY days_early DESC;

-- Follow-up: are these concentrated in specific companies or years?
SELECT
  EXTRACT(YEAR FROM date_received)                     AS year,
  company_name,
  COUNT(*)                                             AS violations,
  AVG(DATE_DIFF(date_received, date_sent_to_company, DAY)) AS avg_days_early
FROM `dbt-portfolio-493318.dbt_dev.stg_cfpb_complaints`
WHERE date_sent_to_company < date_received
GROUP BY year, company_name
ORDER BY violations DESC
LIMIT 30;

-- ================================================================
-- date_sent_to_company null check by response status
-- Confirms whether the not_null test on date_sent_to_company is safe.
-- 'In progress' complaints (103K rows) may not have been forwarded to the company yet —
-- if so, date_sent_to_company would be null and the test would fail.
-- Expected: zero nulls across all response values.
-- ================================================================
SELECT
  COALESCE(company_response_to_consumer, '(null)') AS response,
  COUNT(*)                                          AS n_total,
  COUNTIF(date_sent_to_company IS NULL)             AS n_null_sent_date
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
GROUP BY response
HAVING COUNTIF(date_sent_to_company IS NULL) > 0
    OR response = 'In progress'
ORDER BY n_null_sent_date DESC;

-- ================================================================
-- Tags: distinct values and co-occurrence
-- Confirms parse strategy for tags_is_servicemember / tags_is_older_american flags.
-- 88.9% null — field only populated for special populations.
-- ================================================================
SELECT
  tags,
  COUNT(*) AS n,
  COUNTIF(tags LIKE '%Servicemember%') AS n_servicemember,
  COUNTIF(tags LIKE '%Older American%') AS n_older_american,
  COUNTIF(tags LIKE '%Servicemember%' AND tags LIKE '%Older American%') AS n_both
FROM `raw.cfpb_complaints`
GROUP BY tags
ORDER BY n DESC;

-- ================================================================
-- Zip code validity: masked values (XXXXX), 4-digit, nulls, other patterns
-- Sets the staging rule for zip_code_is_valid flag.
-- ================================================================
SELECT
  COUNT(*) AS n_total,
  COUNTIF(zip_code IS NULL) AS n_null,
  COUNTIF(zip_code = '') AS n_empty,
  COUNTIF(REGEXP_CONTAINS(zip_code, r'^\d{5}$')) AS n_valid_5digit,
  COUNTIF(REGEXP_CONTAINS(zip_code, r'^\d{4}$')) AS n_4digit,
  COUNTIF(REGEXP_CONTAINS(zip_code, r'X')) AS n_contains_x,
  COUNTIF(zip_code = 'XXXXX') AS n_fully_masked,
  COUNTIF(REGEXP_CONTAINS(zip_code, r'^\d{3}XX$')) AS n_partially_masked_3,
  COUNTIF(NOT REGEXP_CONTAINS(zip_code, r'^[0-9X]{5}$') AND zip_code IS NOT NULL AND zip_code != '') AS n_other_weird
FROM `raw.cfpb_complaints`;
