-- Staging validation: confirms staging transformations are correct.
-- Run against dbt_dev.stg_cfpb_complaints after every dbt run that touches staging.

-- ================================================================
-- zip_code_is_valid: distribution check
-- Expected: vast majority valid_true. Small tail of invalid (corrupted inputs).
-- NULL = zip not provided in source; false = present but not a clean 5-digit code.
-- ================================================================
SELECT
  zip_code_is_valid,
  COUNT(*)                                        AS n,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM `dbt-portfolio-493318.dbt_dev.stg_cfpb_complaints`
GROUP BY zip_code_is_valid
ORDER BY n DESC;

-- Spot-check: confirm invalid zips look like known bad patterns (not clean digits).
SELECT
  zip_code,
  COUNT(*) AS n
FROM `dbt-portfolio-493318.dbt_dev.stg_cfpb_complaints`
WHERE zip_code_is_valid = false
GROUP BY zip_code
ORDER BY n DESC
LIMIT 50;

-- ================================================================
-- not-provided sentinel: company_public_response and consumer_consent_provided
-- Confirms NULL → 'not-provided' mapping applied; no residual NULLs.
-- ================================================================
SELECT
  COALESCE(company_public_response, '(null)')    AS company_public_response,
  COUNT(*)                                        AS n
FROM `dbt-portfolio-493318.dbt_dev.stg_cfpb_complaints`
GROUP BY company_public_response
ORDER BY n DESC;

SELECT
  COALESCE(consumer_consent_provided, '(null)')  AS consumer_consent_provided,
  COUNT(*)                                        AS n
FROM `dbt-portfolio-493318.dbt_dev.stg_cfpb_complaints`
GROUP BY consumer_consent_provided
ORDER BY n DESC;
