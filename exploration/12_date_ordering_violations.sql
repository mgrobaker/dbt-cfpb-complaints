-- Investigate complaints where date_sent_to_company < date_received.
-- 7,036 rows flagged by assert_complaint_dates_ordered test (~0.2% of 3.2M).
-- Questions: how large is the offset? clustered in time? specific companies?

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
/*
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
*/
