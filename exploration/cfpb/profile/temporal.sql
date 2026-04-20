-- Temporal patterns: year-over-year profile and complaint resolution time.

-- ================================================================
-- Year-over-year: volume, disputed fill rate, narrative rate, public response rate
-- Use to decide date filter bounds for staging (2011 stub, 2023 partial year).
-- Watch for: consumer_disputed fill collapses ~2017; has_narrative jumps ~2015.
-- ================================================================
SELECT
  EXTRACT(YEAR FROM date_received) AS year,
  COUNT(*) AS complaints,
  COUNT(DISTINCT company_name) AS distinct_companies,
  COUNTIF(consumer_disputed IS NOT NULL) AS disputed_known,
  SAFE_DIVIDE(COUNTIF(consumer_disputed IS NOT NULL), COUNT(*)) AS disputed_fill_rate,
  COUNTIF(has_narrative) AS with_narrative,
  SAFE_DIVIDE(COUNTIF(has_narrative), COUNT(*)) AS narrative_rate,
  COUNTIF(company_public_response IS NOT NULL) AS public_response_count,
  SAFE_DIVIDE(COUNTIF(company_public_response IS NOT NULL), COUNT(*)) AS public_response_rate
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
GROUP BY year
ORDER BY year;

-- ================================================================
-- Resolution time: percentile distribution of days_to_resolution by era
-- Informs the days_to_resolution derived column in fct_complaints.
-- ================================================================
WITH base AS (
  SELECT
    DATE_DIFF(date_sent_to_company, date_received, DAY) AS days_to_resolution,
    CASE
      WHEN date_received < '2015-01-01' THEN 'pre_2015'
      WHEN date_received < '2020-01-01' THEN '2015_2019'
      ELSE '2020_plus'
    END AS era
  FROM `raw.cfpb_complaints`
  WHERE date_received BETWEEN '2012-01-01' AND '2022-12-31'
    AND date_sent_to_company IS NOT NULL
)

SELECT
  era,
  COUNT(*) AS n,
  COUNTIF(days_to_resolution < 0) AS n_negative,
  COUNTIF(days_to_resolution = 0) AS n_zero,
  MIN(days_to_resolution) AS min_days,
  APPROX_QUANTILES(days_to_resolution, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(days_to_resolution, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(days_to_resolution, 100)[OFFSET(99)] AS p99,
  MAX(days_to_resolution) AS max_days,
  AVG(days_to_resolution) AS mean_days
FROM base
GROUP BY era
ORDER BY era;
