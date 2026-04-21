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
-- (queries omitted for brevity — see original exploration)

-- ================================================================
-- 5e: Suffix-strip fuzzy match — CFPB crosswalk banks vs FDIC top_holder
-- Strips common legal suffixes from both sides before matching.
-- Run after 5b to see which crosswalk fdic_top_holder values resolve cleanly
-- and which CFPB bank names have no FDIC candidate.
--
-- Approach: strip suffixes → exact match on stripped form.
-- For any unmatched row, fall back to first-token LIKE scan (5f).
-- ================================================================
WITH suffix_strip AS (
  -- Common legal suffixes to remove from both sides before matching
  SELECT
    top_holder                                                                           AS fdic_raw,
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(UPPER(TRIM(top_holder)),
                r',?\s*(INC\.?|INCORPORATED)$', ''),
              r',?\s*(LLC\.?|L\.L\.C\.?)$', ''),
            r',?\s*(CORP\.?|CORPORATION)$', ''),
          r',?\s*(N\.?A\.?|NATIONAL ASSOCIATION)$', ''),
        r',?\s*(&\s*CO\.?|AND\s+CO\.?|AND\s+COMPANY)$', ''),
      r',?\s*(HOLDINGS?|FINANCIAL|BANCORP|BANCSHARES?)$', ''))                          AS fdic_stripped,
    SUM(total_assets) OVER (PARTITION BY top_holder)                                    AS combined_assets
  FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
  WHERE top_holder IS NOT NULL
),

cfpb_banks AS (
  -- Bank-category rows from the crosswalk seed that have an fdic_top_holder
  -- Update this list as the crosswalk grows
  SELECT raw_company_name, canonical_name, fdic_top_holder
  FROM UNNEST([
    STRUCT('JPMORGAN CHASE & CO.'             AS raw_company_name, 'JPMorgan Chase'       AS canonical_name, 'JPMORGAN CHASE & CO'           AS fdic_top_holder),
    STRUCT('BANK OF AMERICA NATIONAL ASSOCIATION', 'Bank of America',                       'BANK OF AMERICA CORP'),
    STRUCT('WELLS FARGO & COMPANY',               'Wells Fargo',                            'WELLS FARGO & CO'),
    STRUCT('CITIBANK NA',                          'Citibank',                               'CITIGROUP INC'),
    STRUCT('CAPITAL ONE FINANCIAL CORPORATION',    'Capital One',                            'CAPITAL ONE FINANCIAL CORP'),
    STRUCT('SYNCHRONY FINANCIAL',                  'Synchrony Financial',                    NULL),
    STRUCT('ALLY FINANCIAL INC.',                  'Ally Financial',                         'ALLY FINANCIAL INC'),
    STRUCT('SANTANDER CONSUMER USA INC.',          'Santander Consumer USA',                 'SANTANDER HOLDINGS USA INC'),
    STRUCT('AMERICAN EXPRESS COMPANY',             'American Express',                       'AMERICAN EXPRESS CO'),
    STRUCT('DISCOVER BANK',                        'Discover',                               'DISCOVER FINANCIAL SERVICES'),
    STRUCT('USAA FEDERAL SAVINGS BANK',            'USAA',                                   'USAA'),
    STRUCT('SUNTRUST BANK',                        'Truist',                                 'SUNTRUST BANKS INC'),
    STRUCT('BB&T FINANCIAL',                       'Truist',                                 'BB&T CORP')
  ])
),

cfpb_stripped AS (
  SELECT
    raw_company_name,
    canonical_name,
    fdic_top_holder                                                                      AS crosswalk_fdic_top_holder,
    TRIM(REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              REGEXP_REPLACE(UPPER(TRIM(fdic_top_holder)),
                r',?\s*(INC\.?|INCORPORATED)$', ''),
              r',?\s*(LLC\.?|L\.L\.C\.?)$', ''),
            r',?\s*(CORP\.?|CORPORATION)$', ''),
          r',?\s*(N\.?A\.?|NATIONAL ASSOCIATION)$', ''),
        r',?\s*(&\s*CO\.?|AND\s+CO\.?|AND\s+COMPANY)$', ''),
      r',?\s*(HOLDINGS?|FINANCIAL|BANCORP|BANCSHARES?)$', ''))                          AS cfpb_stripped
  FROM cfpb_banks
  WHERE fdic_top_holder IS NOT NULL
)

SELECT
  cs.canonical_name,
  cs.crosswalk_fdic_top_holder,
  ss.fdic_raw                                                                            AS fdic_top_holder_matched,
  ROUND(ss.combined_assets / 1e9, 1)                                                    AS combined_assets_bn,
  cs.cfpb_stripped,
  ss.fdic_stripped,
  cs.cfpb_stripped = ss.fdic_stripped                                                    AS exact_strip_match
FROM cfpb_stripped cs
LEFT JOIN (SELECT DISTINCT fdic_raw, fdic_stripped, combined_assets FROM suffix_strip) ss
  ON cs.cfpb_stripped = ss.fdic_stripped
ORDER BY cs.canonical_name;

-- ================================================================
-- 5f: First-token LIKE scan — find FDIC candidates for CFPB names with no 5e match
-- Use for any row where 5e returns no fdic_top_holder_matched.
-- Noisy — review manually. Replace <FIRST_TOKEN> with the company's primary word.
-- Example: for Synchrony Financial with no fdic_top_holder, run:
--   WHERE UPPER(top_holder) LIKE '%SYNCHRONY%'
-- ================================================================
SELECT
  top_holder,
  institution_name,
  SUM(total_assets) AS combined_assets,
  COUNT(*) AS charters
FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
WHERE UPPER(top_holder) LIKE '%SYNCHRONY%'  -- replace token per company
   OR UPPER(institution_name) LIKE '%SYNCHRONY%'
GROUP BY top_holder, institution_name
ORDER BY combined_assets DESC NULLS LAST
LIMIT 20;
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
