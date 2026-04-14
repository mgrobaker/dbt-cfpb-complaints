-- Product / subproduct / issue / subissue distribution
-- Confirms the taxonomy shape for dimensional modeling.

-- 4a: products × subproducts
SELECT
  product,
  subproduct,
  COUNT(*) AS complaints
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
GROUP BY product, subproduct
ORDER BY complaints DESC;

-- 4b: issues × subissues  (run separately)
-- SELECT
--   issue,
--   subissue,
--   COUNT(*) AS complaints
-- FROM `dbt-portfolio-493318.raw.cfpb_complaints`
-- GROUP BY issue, subissue
-- ORDER BY complaints DESC;
