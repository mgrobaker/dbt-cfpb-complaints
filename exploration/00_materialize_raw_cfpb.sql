-- ONE-TIME SETUP: Materialize CFPB data into your project, dropping the narrative column.
-- Consumer complaint narratives are ~90% of the 2.3 GB table size.
-- All subsequent exploration queries run against this table for near-zero cost.
--
-- Cost: ~2.3 GB (one time). After this, exploration queries scan <200 MB each.
-- Run once, then use `dbt-portfolio-493318.raw.cfpb_complaints` everywhere.
--
-- NOTE: We keep the narrative column NULL-checked row count in 01_cfpb_summary.sql
-- so we know fill rate, but we don't store the text itself here.
-- If you ever want narratives for NLP/text work, go back to the public table.

CREATE OR REPLACE TABLE `dbt-portfolio-493318.raw.cfpb_complaints` AS
SELECT
  complaint_id,
  date_received,
  date_sent_to_company,
  product,
  subproduct,
  issue,
  subissue,
  company_name,
  state,
  zip_code,
  tags,
  submitted_via,
  company_response_to_consumer,
  company_public_response,
  timely_response,
  consumer_disputed,
  consumer_consent_provided,
  -- Narrative presence flag (not the text itself)
  (consumer_complaint_narrative IS NOT NULL) AS has_narrative
FROM `bigquery-public-data.cfpb_complaints.complaint_database`;
