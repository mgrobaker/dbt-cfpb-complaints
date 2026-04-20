-- Company data quality: name variant analysis, response field values, timely response rates.

-- ================================================================
-- Name variant distribution and alphabetical list
-- Pass 1 shows the long-tail; Pass 2 is the full alphabetical dump for
-- spreadsheet review — sort by name to spot near-duplicates clustering together.
-- ================================================================

-- Pass 1: long-tail distribution by complaint bucket
SELECT
  CASE
    WHEN complaints = 1              THEN '1'
    WHEN complaints BETWEEN 2 AND 5  THEN '2-5'
    WHEN complaints BETWEEN 6 AND 20 THEN '6-20'
    WHEN complaints BETWEEN 21 AND 100  THEN '21-100'
    WHEN complaints BETWEEN 101 AND 1000 THEN '101-1000'
    ELSE '1001+'
  END                           AS complaint_bucket,
  COUNT(*)                      AS company_count,
  SUM(complaints)               AS total_complaints
FROM (
  SELECT company_name, COUNT(*) AS complaints
  FROM `dbt-portfolio-493318.raw.cfpb_complaints`
  GROUP BY company_name
)
GROUP BY complaint_bucket
ORDER BY MIN(complaints);

-- Pass 2: full list alphabetical (run separately — returns all 6,694 rows)
-- Scan for: same root word, different casing/punctuation/suffix (Inc. vs Inc vs INC),
-- known rebrands (SunTrust / Truist), parent vs subsidiary naming.
SELECT
  company_name,
  COUNT(*)                    AS complaints,
  MIN(date_received)          AS first_seen,
  MAX(date_received)          AS last_seen,
  COUNT(DISTINCT product)     AS products
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
GROUP BY company_name
ORDER BY company_name;

-- ================================================================
-- Response field distinct values and fill rates
-- Decides whether company_response_to_consumer, company_public_response,
-- consumer_consent_provided need accepted_values tests or staging normalization.
-- Single scan with UNION ALL — conditional aggregation over three fields.
-- ================================================================
WITH base AS (
  SELECT
    company_response_to_consumer,
    company_public_response,
    consumer_consent_provided
  FROM `raw.cfpb_complaints`
)

SELECT 'company_response_to_consumer' AS field, company_response_to_consumer AS value, COUNT(*) AS n
FROM base GROUP BY value
UNION ALL
SELECT 'company_public_response', company_public_response, COUNT(*) FROM base GROUP BY company_public_response
UNION ALL
SELECT 'consumer_consent_provided', consumer_consent_provided, COUNT(*) FROM base GROUP BY consumer_consent_provided
ORDER BY field, n DESC;

-- ================================================================
-- Timely response rate by company (top companies, ≥1000 complaints)
-- Future mart input; sanity-checks that timely_response is populated throughout.
-- ================================================================
WITH normalized AS (
  SELECT
    REGEXP_REPLACE(
      REGEXP_REPLACE(UPPER(TRIM(company_name)), r'\s+', ' '),
      r'[.,;:]+$', ''
    ) AS company_name_normalized,
    timely_response
  FROM `raw.cfpb_complaints`
  WHERE date_received BETWEEN '2012-01-01' AND '2022-12-31'
)

SELECT
  company_name_normalized,
  COUNT(*) AS n_complaints,
  COUNTIF(timely_response IS NULL) AS n_null,
  COUNTIF(timely_response = TRUE) AS n_timely,
  COUNTIF(timely_response = FALSE) AS n_not_timely,
  SAFE_DIVIDE(COUNTIF(timely_response = TRUE), COUNTIF(timely_response IS NOT NULL)) AS timely_rate
FROM normalized
GROUP BY company_name_normalized
HAVING n_complaints >= 1000
ORDER BY n_complaints DESC
LIMIT 100;
