-- Product taxonomy exploration: distributions and narrative rate over time.

-- ================================================================
-- Product × subproduct distribution (raw taxonomy, pre-normalization)
-- Run 4a to see the taxonomy mess that drives product_normalized in staging.
-- 4b (issues × subissues) runs separately — large result set.
-- ================================================================

-- 4a: products × subproducts
SELECT
  product,
  subproduct,
  COUNT(*) AS complaints
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
GROUP BY product, subproduct
ORDER BY complaints DESC;

-- 4b: issues × subissues (run separately — returns ~1,500 rows)
-- SELECT
--   issue,
--   subissue,
--   COUNT(*) AS complaints
-- FROM `dbt-portfolio-493318.raw.cfpb_complaints`
-- GROUP BY issue, subissue
-- ORDER BY complaints DESC;

-- ================================================================
-- Narrative rate by product × year (post-June 2015 only)
-- CFPB launched consumer narratives with opt-in consent in June 2015.
-- Shows which products drive narrative availability.
-- ================================================================
SELECT
  EXTRACT(YEAR FROM date_received) AS year,
  product,
  COUNT(*) AS n_complaints,
  COUNTIF(has_narrative) AS n_with_narrative,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(has_narrative), COUNT(*)), 2) AS narrative_rate_pct
FROM `raw.cfpb_complaints`
WHERE date_received >= '2015-06-01'
  AND date_received <= '2022-12-31'
GROUP BY year, product
ORDER BY year, n_complaints DESC;
