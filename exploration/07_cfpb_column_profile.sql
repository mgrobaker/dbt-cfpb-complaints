-- Column-level profile: null rates and distinct counts, single table scan.
-- Ordered by null_count DESC so drop candidates surface first.

SELECT
  COUNT(*)                                AS total_rows,

  -- Null counts
  COUNTIF(complaint_id IS NULL)           AS complaint_id_nulls,
  COUNTIF(date_received IS NULL)          AS date_received_nulls,
  COUNTIF(date_sent_to_company IS NULL)   AS date_sent_nulls,
  COUNTIF(product IS NULL)                AS product_nulls,
  COUNTIF(subproduct IS NULL)             AS subproduct_nulls,
  COUNTIF(issue IS NULL)                  AS issue_nulls,
  COUNTIF(subissue IS NULL)               AS subissue_nulls,
  COUNTIF(company_name IS NULL)           AS company_name_nulls,
  COUNTIF(state IS NULL)                  AS state_nulls,
  COUNTIF(zip_code IS NULL)               AS zip_code_nulls,
  COUNTIF(tags IS NULL)                   AS tags_nulls,
  COUNTIF(submitted_via IS NULL)          AS submitted_via_nulls,
  COUNTIF(company_response_to_consumer IS NULL) AS company_response_nulls,
  COUNTIF(company_public_response IS NULL) AS company_public_response_nulls,
  COUNTIF(timely_response IS NULL)        AS timely_response_nulls,
  COUNTIF(consumer_disputed IS NULL)      AS consumer_disputed_nulls,
  COUNTIF(consumer_consent_provided IS NULL) AS consumer_consent_nulls,
  COUNTIF(has_narrative = FALSE)          AS no_narrative_count,

  -- Distinct counts
  COUNT(DISTINCT product)                 AS product_distinct,
  COUNT(DISTINCT subproduct)              AS subproduct_distinct,
  COUNT(DISTINCT issue)                   AS issue_distinct,
  COUNT(DISTINCT subissue)                AS subissue_distinct,
  COUNT(DISTINCT company_name)            AS company_name_distinct,
  COUNT(DISTINCT state)                   AS state_distinct,
  COUNT(DISTINCT tags)                    AS tags_distinct,
  COUNT(DISTINCT submitted_via)           AS submitted_via_distinct,
  COUNT(DISTINCT company_response_to_consumer) AS company_response_distinct,
  COUNT(DISTINCT company_public_response) AS company_public_response_distinct,
  COUNT(DISTINCT consumer_consent_provided) AS consumer_consent_distinct,

  -- Date range
  MIN(date_received)                      AS min_date,
  MAX(date_received)                      AS max_date

FROM `dbt-portfolio-493318.raw.cfpb_complaints`;
