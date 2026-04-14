-- CFPB complaint_database: overall shape, cardinality, fill rates
-- Scans the full table (~2.3 GB). Run once.

SELECT
  COUNT(*)                                              AS total_rows,
  COUNT(DISTINCT company_name)                          AS distinct_companies,
  COUNT(DISTINCT product)                               AS distinct_products,
  COUNT(DISTINCT subproduct)                            AS distinct_subproducts,
  COUNT(DISTINCT issue)                                 AS distinct_issues,
  COUNT(DISTINCT subissue)                              AS distinct_subissues,
  COUNT(DISTINCT state)                                 AS distinct_states,
  COUNTIF(has_narrative = TRUE)                         AS has_narrative,
  COUNTIF(consumer_disputed IS NOT NULL)                AS has_disputed,
  COUNTIF(date_sent_to_company IS NOT NULL)             AS has_sent_date,
  COUNTIF(company_public_response IS NOT NULL)          AS has_public_response,
  COUNTIF(tags IS NOT NULL)                             AS has_tags,
  MIN(date_received)                                    AS min_date,
  MAX(date_received)                                    AS max_date
FROM `dbt-portfolio-493318.raw.cfpb_complaints`;
