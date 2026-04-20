-- FDIC active banks exploration: top holders, join hypothesis test against CFPB names.
-- Key finding: FDIC `top_holder` matches CFPB's parent-corp naming better than institution_name.
-- Run each block separately.

-- ================================================================
-- 5a: FDIC top 50 institutions by assets — institution_name vs top_holder comparison
-- ================================================================
SELECT
  institution_name,
  top_holder,
  fdic_certificate_number,
  state,
  city,
  total_assets
FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
ORDER BY total_assets DESC NULLS LAST
LIMIT 50;

-- ================================================================
-- 5b: Distinct top_holder names — how many unique parent corps, combined assets
-- ================================================================
SELECT
  top_holder,
  COUNT(*) AS subsidiaries,
  SUM(total_assets) AS combined_assets
FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
WHERE top_holder IS NOT NULL
GROUP BY top_holder
ORDER BY combined_assets DESC NULLS LAST
LIMIT 50;

-- ================================================================
-- 5c: Direct join test — CFPB company_name vs FDIC top_holder (uppercase-normalized)
-- Hypothesis: top_holder matches CFPB parent-corp names better than institution_name.
-- ================================================================
WITH cfpb AS (
  SELECT
    company_name,
    UPPER(TRIM(company_name)) AS company_name_norm,
    COUNT(*) AS complaints
  FROM `dbt-portfolio-493318.raw.cfpb_complaints`
  WHERE company_name IS NOT NULL
  GROUP BY company_name
),
fdic_holders AS (
  SELECT DISTINCT UPPER(TRIM(top_holder)) AS top_holder_norm
  FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
  WHERE top_holder IS NOT NULL
),
fdic_insts AS (
  SELECT DISTINCT UPPER(TRIM(institution_name)) AS institution_name_norm
  FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
)
SELECT
  COUNT(*)                                                       AS distinct_cfpb_companies,
  SUM(complaints)                                                AS total_complaints,
  COUNTIF(h.top_holder_norm IS NOT NULL)                         AS matched_via_top_holder,
  SUM(IF(h.top_holder_norm IS NOT NULL, complaints, 0))          AS complaints_matched_top_holder,
  COUNTIF(i.institution_name_norm IS NOT NULL)                   AS matched_via_institution,
  SUM(IF(i.institution_name_norm IS NOT NULL, complaints, 0))    AS complaints_matched_institution,
  COUNTIF(h.top_holder_norm IS NOT NULL OR i.institution_name_norm IS NOT NULL) AS matched_either,
  SUM(IF(h.top_holder_norm IS NOT NULL OR i.institution_name_norm IS NOT NULL, complaints, 0)) AS complaints_matched_either
FROM cfpb c
LEFT JOIN fdic_holders h ON c.company_name_norm = h.top_holder_norm
LEFT JOIN fdic_insts   i ON c.company_name_norm = i.institution_name_norm;

-- ================================================================
-- 5d: Top CFPB companies still unmatched after both joins
-- Uncomment to run after 5c confirms top_holder is the right grain.
-- ================================================================
-- WITH fdic_all AS (
--   SELECT DISTINCT UPPER(TRIM(top_holder)) AS norm
--   FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean` WHERE top_holder IS NOT NULL
--   UNION DISTINCT
--   SELECT DISTINCT UPPER(TRIM(institution_name))
--   FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
-- )
-- SELECT
--   c.company_name,
--   COUNT(*) AS complaints
-- FROM `dbt-portfolio-493318.raw.cfpb_complaints` c
-- LEFT JOIN fdic_all f ON UPPER(TRIM(c.company_name)) = f.norm
-- WHERE f.norm IS NULL AND c.company_name IS NOT NULL
-- GROUP BY c.company_name
-- ORDER BY complaints DESC
-- LIMIT 50;
