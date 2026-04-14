-- Eyeball 20 rows to see real data shape and mess
-- Narrative truncated so output is readable

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
  has_narrative
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
ORDER BY date_received DESC
LIMIT 20;
