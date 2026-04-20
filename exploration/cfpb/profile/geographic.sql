-- Complaint counts by state — validate accepted_values test list before wiring it up.
-- Expected ~60 values: 50 states + DC + territories (PR VI GU AS MP) +
-- military APO codes (AE AP AA). Anything else is a DQ flag.

SELECT
  state,
  COUNT(*)                  AS complaints,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total,
  MIN(date_received)        AS first_seen,
  MAX(date_received)        AS last_seen
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
GROUP BY state
ORDER BY state;
-- Null rows (state IS NULL) will appear as a blank entry — check that count.
-- Flag any 2-char code that is not in the expected set for accepted_values test.
