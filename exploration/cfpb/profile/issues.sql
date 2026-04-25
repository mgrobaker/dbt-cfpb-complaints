-- Issue taxonomy exploration: distribution of the 165 distinct issue values,
-- and how they cluster by product. Drives the bucketing decision for
-- issue_category (mart-improvements-plan A1).
--
-- Run statements one at a time.

-- ================================================================
-- 1) Issue distribution with cumulative coverage.
-- Goal: see how many top issues cover ~80% of volume and what
-- semantic clusters they form.
-- ================================================================
WITH issue_counts AS (
  SELECT
    issue,
    COUNT(*) AS complaints
  FROM `dbt-portfolio-493318.raw.cfpb_complaints`
  GROUP BY issue
),
ranked AS (
  SELECT
    issue,
    complaints,
    ROW_NUMBER() OVER (ORDER BY complaints DESC) AS rnk,
    SUM(complaints) OVER () AS total_complaints,
    SUM(complaints) OVER (ORDER BY complaints DESC ROWS UNBOUNDED PRECEDING) AS cumulative
  FROM issue_counts
)
SELECT
  rnk,
  issue,
  complaints,
  ROUND(100 * complaints / total_complaints, 2) AS pct,
  ROUND(100 * cumulative / total_complaints, 2) AS cumulative_pct
FROM ranked
ORDER BY rnk;

-- ================================================================
-- 2) Issue × product_category cross-tab (top issues only).
-- Goal: detect whether the same issue string appears across product
-- categories (e.g., "Improper use of your report" only in credit_reporting,
-- vs. "Managing the loan or lease" spanning auto + student).
-- This informs whether bucketing should be product-conditional.
-- Limited to issues with >= 10K complaints to keep result tight.
-- ================================================================
-- WITH big_issues AS (
--   SELECT issue
--   FROM `dbt-portfolio-493318.raw.cfpb_complaints`
--   GROUP BY issue
--   HAVING COUNT(*) >= 10000
-- )
-- SELECT
--   c.product,
--   c.issue,
--   COUNT(*) AS complaints
-- FROM `dbt-portfolio-493318.raw.cfpb_complaints` c
-- JOIN big_issues b USING (issue)
-- GROUP BY c.product, c.issue
-- ORDER BY complaints DESC;
