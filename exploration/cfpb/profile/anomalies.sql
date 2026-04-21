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
-- Zip code validity: pattern breakdown.
-- Sets the staging rule for zip_code_is_valid flag.
-- Tags query moved to cfpb/profile/tags.sql — not an anomaly.
-- ================================================================

-- Pattern summary — CASE avoids double-counting across categories.
-- Run against staging (not raw) — raw zip_code is float-formatted (e.g. '30349.0'),
-- a BigQuery CSV import artifact. Staging strips the .0 and LPADs to 5 digits.
-- Querying staging gives the cleaned shape that the zip_code_is_valid flag should reflect.
SELECT
  CASE
    WHEN zip_code IS NULL                                  THEN 'null'
    WHEN zip_code = ''                                     THEN 'empty_string'
    WHEN REGEXP_CONTAINS(zip_code, r'^\d{5}$')            THEN 'valid_5digit'
    WHEN REGEXP_CONTAINS(zip_code, r'^\d{4}$')            THEN '4digit_leading_zero_dropped'
    WHEN REGEXP_CONTAINS(zip_code, r'^[0-9X]{5}$')        THEN 'masked_5char'
    WHEN REGEXP_CONTAINS(zip_code, r'^\d{5}-\d{4}$')      THEN 'zip_plus4_dash'
    WHEN REGEXP_CONTAINS(zip_code, r'^\d{9}$')            THEN 'zip_plus4_nodash'
    ELSE                                                        'other'
  END    AS zip_pattern,
  COUNT(*) AS n
FROM `dbt-portfolio-493318.dbt_dev.stg_cfpb_complaints`
GROUP BY zip_pattern
ORDER BY n DESC;

-- Drill into non-null, non-valid-5digit values on staging data.
SELECT
  zip_code,
  LENGTH(zip_code) AS zip_len,
  COUNT(*)         AS n
FROM `dbt-portfolio-493318.dbt_dev.stg_cfpb_complaints`
WHERE zip_code IS NOT NULL
  AND zip_code != ''
  AND NOT REGEXP_CONTAINS(zip_code, r'^\d{5}$')
GROUP BY zip_code, zip_len
ORDER BY n DESC
LIMIT 100;
