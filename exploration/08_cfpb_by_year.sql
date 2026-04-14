-- Row distribution by year, with field-coverage context.
-- Use to decide whether to date-filter rows in staging.
--
-- Watch for:
--   * Early years (2011-2013) may be thin — possibly drop
--   * consumer_disputed fill rate collapses ~2017 (CFPB stopped asking)
--   * has_narrative rate changes over time (consent policy changes)

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
